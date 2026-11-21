import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/ui/hobs_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credentials_test.dart' show settle;
import 'fake_hermes_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('handle', () {
    test('follows the name without accents and spaces', () {
      expect(AppState.hobNameFor('Účetní Péťa'), 'ucetni-peta');
      expect(AppState.hobNameFor('  Dev  CTO!! '), 'dev-cto');
      expect(AppState.hobNameFor('žluťoučký_kůň'), 'zlutoucky_kun');
      expect(AppState.hobNameFor('🤖'), '');
      expect(AppState.hobNameFor('a' * 80).length, 64);
    });

    test('is checked against the server rule', () {
      expect(AppState.hobNamePattern.hasMatch('ucetni-peta'), isTrue);
      expect(AppState.hobNamePattern.hasMatch('-peta'), isFalse);
      expect(AppState.hobNamePattern.hasMatch('Peta'), isFalse);
    });
  });

  group('creating', () {
    late FakeHermesServer server;
    late AppState app;

    setUp(() async {
      HttpOverrides.global = null;
      server = FakeHermesServer();
      await server.start();
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      app = AppState();
      await app.login(
        serverUrl: server.baseUrl.toString(),
        username: 'u',
        password: 'p',
      );
      await settle(app);
    });

    tearDown(() async {
      app.dispose();
      await server.stop();
    });

    test('clones the default profile and stores the look', () async {
      final hob = await app.createHob(
        name: 'ucetni-peta',
        title: ' Účetní Péťa ',
        description: ' Hlídá faktury ',
        shape: 'blobatar:abc',
      );

      final create = server.profileCreates.single;
      expect(create['name'], 'ucetni-peta');
      expect(create['description'], 'Hlídá faktury');
      expect(create['clone_from'], 'default');
      expect(create['share_auth'], isTrue);
      expect(create['soul'], startsWith('# Účetní Péťa\n'));
      expect(create['soul'], contains('**Mission:** Hlídá faktury'));
      expect(create['soul'], contains('(profile `ucetni-peta`)'));

      final row = server.roster.firstWhere((r) => r['name'] == 'ucetni-peta');
      final meta = (row['ui_meta'] as Map)['hermes-bots'] as Map;
      expect(meta['title'], 'Účetní Péťa');
      expect(meta['shape'], 'blobatar:abc');

      expect(hob.displayName, 'Účetní Péťa');
      expect(app.hobNamed('ucetni-peta'), isNotNull);
      expect(app.hobNameTaken('ucetni-peta'), isTrue);
    });

    test('a taken name fails with the server message', () async {
      await expectLater(
        app.createHob(name: 'cto'),
        throwsA(
          predicate<Object>(
            (e) => AppState.describeError(e).contains('already'),
          ),
        ),
      );
    });
  });

  group('dialog', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    final cto = Hob(name: 'cto', displayName: 'CTO');

    Future<void> openDialog(WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: AppState()..hobs = [cto],
          child: const MaterialApp(home: HobsScreen()),
        ),
      );
      await tester.tap(find.byTooltip('Nový Hobík'));
      await tester.pumpAndSettle();
    }

    FilledButton create(WidgetTester tester) =>
        tester.widget(find.widgetWithText(FilledButton, 'Vytvořit'));

    testWidgets('the list offers a new Hob', (tester) async {
      await openDialog(tester);
      expect(find.text('Nový Hobík'), findsWidgets);
      expect(create(tester).onPressed, isNull);
    });

    testWidgets('the handle follows the name until edited', (tester) async {
      await openDialog(tester);
      final name = find.widgetWithText(TextField, 'Jméno');
      final handle = find.widgetWithText(TextField, 'Identifikátor');

      await tester.enterText(name, 'Účetní Péťa');
      await tester.pump();
      expect(tester.widget<TextField>(handle).controller!.text, 'ucetni-peta');
      expect(create(tester).onPressed, isNotNull);

      await tester.enterText(handle, 'cto');
      await tester.pump();
      expect(find.text('Tenhle identifikátor už má jiný Hobík.'), findsOne);
      expect(create(tester).onPressed, isNull);

      await tester.enterText(name, 'Někdo jiný');
      await tester.pump();
      expect(tester.widget<TextField>(handle).controller!.text, 'cto');

      await tester.enterText(handle, 'Bad Name');
      await tester.pump();
      expect(find.textContaining('Jen malá písmena'), findsOne);
      expect(create(tester).onPressed, isNull);
    });

    testWidgets('a refused create keeps the dialog open', (tester) async {
      await openDialog(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Jméno'), 'Péťa');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Vytvořit'));
      await tester.pumpAndSettle();
      // Offline: no gateway to create it on.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Hobíka se nepodařilo vytvořit'), findsOne);
    });
  });
}
