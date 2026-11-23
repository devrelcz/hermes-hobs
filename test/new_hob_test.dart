import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/group_models.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/ui/hobs_screen.dart';
import 'package:hobs/ui/new_hob_screen.dart';
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

    test('is made free when the name is taken', () {
      final app = AppState()
        ..hobs = [
          Hob(name: 'cto', displayName: 'CTO'),
          Hob(name: 'cto-2', displayName: 'CTO 2'),
          Hob(name: 'hob', displayName: 'Hob'),
        ];
      expect(app.freeHobNameFor(''), '');
      expect(app.freeHobNameFor('Účetní Péťa'), 'ucetni-peta');
      expect(app.freeHobNameFor('CTO'), 'cto-3');
      expect(app.freeHobNameFor('Default'), 'default-2');
      expect(app.freeHobNameFor('🤖'), 'hob-2');
      final long = app.freeHobNameFor('a' * 80);
      expect(long.length, 64);
      expect(AppState.hobNamePattern.hasMatch(long), isTrue);
    });

    test("a Hob's group chats are the rooms it sits in", () {
      GroupMember seat(String p) =>
          GroupMember(memberId: p, handle: p, profile: p);
      final app = AppState()
        ..groups = [
          GroupRoom(
            roomId: 'a',
            name: 'Launch',
            members: [seat('cto'), seat('qa')],
          ),
          GroupRoom(
            roomId: 'b',
            name: 'Ops',
            members: [seat('ops'), seat('qa')],
          ),
        ];
      final cto = Hob(name: 'cto', displayName: 'CTO');
      final qa = Hob(name: 'qa', displayName: 'QA');
      expect(app.groupsOf(cto).map((r) => r.roomId), ['a']);
      expect(app.groupsOf(qa).map((r) => r.roomId), ['a', 'b']);
      expect(app.groupsOf(Hob(name: 'x', displayName: 'X')), isEmpty);
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

    test('a duplicate clones the Hob under the next free name', () async {
      final cto = app.hobNamed('cto')!;
      final copy = await app.duplicateHob(cto);
      final create = server.profileCreates.single;
      expect(create['name'], 'cto-2');
      expect(create['clone_from'], 'cto');
      final row = server.roster.firstWhere((r) => r['name'] == 'cto-2');
      final meta = (row['ui_meta'] as Map)['hermes-bots'] as Map;
      expect(meta['title'], 'CTO (kopie)');
      expect(meta['color'], cto.meta['color']);
      expect(meta['sectionId'], cto.meta['sectionId']);
      expect(copy.name, 'cto-2');
      expect(copy.displayName, 'CTO (kopie)');

      // The next copy takes the next free name.
      await app.duplicateHob(cto);
      expect(server.profileCreates.last['name'], 'cto-3');
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

  group('page', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    final cto = Hob(name: 'cto', displayName: 'CTO');

    Future<void> openPage(WidgetTester tester) async {
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

    testWidgets('an empty list invites the first Hob', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: AppState(),
          child: const MaterialApp(home: HobsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Zatím tu není žádný Hobík'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Nový Hobík'));
      await tester.pumpAndSettle();
      expect(find.byType(NewHobScreen), findsOneWidget);
    });

    testWidgets('the list offers a new Hob', (tester) async {
      await openPage(tester);
      expect(find.text('Nový Hobík'), findsWidgets);
      expect(create(tester).onPressed, isNull);
    });

    testWidgets('the handle is made up until edited', (tester) async {
      await openPage(tester);
      final name = find.widgetWithText(TextField, 'Jméno');
      final handle = find.widgetWithText(TextField, 'Identifikátor');
      expect(handle, findsNothing);

      await tester.enterText(name, 'Účetní Péťa');
      await tester.pump();
      expect(find.text('@ucetni-peta'), findsOne);
      expect(create(tester).onPressed, isNotNull);

      // Taken: a free one is picked instead of blocking.
      await tester.enterText(name, 'CTO');
      await tester.pumpAndSettle();
      expect(find.text('@cto-2'), findsOne);
      expect(create(tester).onPressed, isNotNull);

      await tester.tap(find.byTooltip('Upravit identifikátor'));
      await tester.pump();
      expect(tester.widget<TextField>(handle).controller!.text, 'cto-2');
      expect(tester.widget<TextField>(handle).focusNode!.hasFocus, isTrue);

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

    testWidgets('a refused create keeps the page open', (tester) async {
      await openPage(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Jméno'), 'Péťa');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Vytvořit'));
      await tester.pumpAndSettle();
      // Offline: no gateway to create it on.
      expect(find.byType(NewHobScreen), findsOneWidget);
      expect(
        find.text(
          'Hobíka se nepodařilo vytvořit: Aplikace není připojená k serveru.',
        ),
        findsOne,
      );
    });

    testWidgets('closing a filled sheet asks first', (tester) async {
      await openPage(tester);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.byType(NewHobScreen), findsNothing);

      await tester.tap(find.byTooltip('Nový Hobík'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Jméno'), 'Péťa');
      await tester.pump();
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text('Zahodit neuložené změny?'), findsOne);
      await tester.tap(find.text('Zahodit'));
      await tester.pumpAndSettle();
      expect(find.byType(NewHobScreen), findsNothing);
    });
  });
}
