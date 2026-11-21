import 'dart:io';

import 'package:flutter/gestures.dart';
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

  group('writes', () {
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

    Map<String, dynamic> meta(String name) =>
        (server.roster.firstWhere((r) => r['name'] == name)['ui_meta']
                as Map)['hermes-bots']
            as Map<String, dynamic>;

    Hob hob(String name) => app.hobNamed(name)!;

    const cto = {
      'title': 'CTO',
      'sectionId': 's1',
      'sectionName': 'Vibee.one',
      'pinned': true,
      'color': '#F0997B',
      'shape': 'circle',
    };

    test('delete removes the hob on the server and from the list', () async {
      final name = server.roster
          .map((r) => r['name'] as String)
          .firstWhere((n) => n != 'default');
      await app.deleteHob(hob(name));
      expect(server.deletedProfiles, [name]);
      expect(app.hobNamed(name), isNull);
      expect(server.roster.any((r) => r['name'] == name), isFalse);
    });

    test('a refused delete keeps the hob', () async {
      final name = server.roster
          .map((r) => r['name'] as String)
          .firstWhere((n) => n != 'default');
      server.refuseDelete = true;
      await expectLater(app.deleteHob(hob(name)), throwsA(anything));
      expect(app.hobNamed(name), isNotNull);
    });

    test('pin and unpin send the whole block back', () async {
      await app.setHobPinned(hob('default'), true);
      expect(meta('default'), {'pinned': true});
      expect(hob('default').pinned, isTrue);

      await app.setHobPinned(hob('cto'), false);
      expect(meta('cto'), {...cto, 'pinned': false});
      expect(hob('cto').pinned, isFalse);
    });

    test('pinned hobs sort first, like the dashboard', () async {
      app.hobs = [
        Hob(name: 'old', displayName: 'old', pinned: true),
        Hob(
          name: 'new',
          displayName: 'new',
          canonical: SessionSummary(id: 'x', lastActive: DateTime.now()),
        ),
      ];
      expect(app.sections.single.hobs.map((b) => b.name), ['old', 'new']);
    });

    test('hide and unhide move the hob between the lists', () async {
      expect(app.hiddenHobs.map((b) => b.name), ['ghost']);

      await app.setHobHidden(hob('cto'), true);
      expect(meta('cto'), {...cto, 'hidden': true});
      expect(app.hobs.map((b) => b.name), ['default']);
      expect(app.hiddenHobs.map((b) => b.name), ['cto', 'ghost']);

      await app.setHobHidden(hob('ghost'), false);
      expect(meta('ghost'), {'hidden': false});
      expect(app.hobs.map((b) => b.name), contains('ghost'));
      expect(app.hiddenHobs.map((b) => b.name), ['cto']);
    });

    test('move to an existing folder, a new one, and out', () async {
      expect(app.folders, [(id: 's1', name: 'Vibee.one')]);

      await app.moveHobToFolder(hob('default'), 's1', 'Vibee.one');
      expect(meta('default'), {'sectionId': 's1', 'sectionName': 'Vibee.one'});
      expect(app.sections.single.hobs.map((b) => b.name), ['cto', 'default']);

      await app.moveHobToNewFolder(hob('cto'), '  Klienti ');
      final id = meta('cto')['sectionId'] as String;
      expect(id, matches(RegExp(r'^sec-[0-9a-z]+-[0-9a-z]{5}$')));
      expect(meta('cto'), {...cto, 'sectionId': id, 'sectionName': 'Klienti'});
      expect(app.folders.map((f) => f.name), ['Klienti', 'Vibee.one']);

      await app.moveHobToFolder(hob('cto'), null, null);
      expect(meta('cto'), {...cto, 'sectionId': null, 'sectionName': null});
      expect(hob('cto').sectionId, isNull);
    });

    test('a stale revision is reread and retried once', () async {
      server.roster[0]['ui_meta_revisions'] = {'hermes-bots': 3};
      await app.refreshHobs();
      // Another client edits the hob: the app's copy is now stale.
      meta('cto')['color'] = '#000000';
      (server.roster[0]['ui_meta_revisions'] as Map)['hermes-bots'] = 7;

      await app.setHobPinned(hob('cto'), false);

      final writes = server.configures.where((c) => c['name'] == 'cto');
      expect(writes.map((c) => c['ui_meta_expected_revisions']), [
        {'hermes-bots': 3},
        {'hermes-bots': 7},
      ]);
      expect(meta('cto'), {...cto, 'color': '#000000', 'pinned': false});
    });

    test('shows the change at once and puts it back on a refusal', () async {
      server.refuseMeta.add('default');
      final write = app.setHobHidden(hob('default'), true);
      expect(app.hobs.map((b) => b.name), isNot(contains('default')));
      expect(app.hiddenHobs.map((b) => b.name), contains('default'));

      await expectLater(write, throwsA(isA<StateError>()));
      expect(server.configures.where((c) => c['name'] == 'default').length, 2);
      expect(app.hobs.map((b) => b.name), contains('default'));
      expect(hob('default').hidden, isFalse);
    });
  });

  group('menu', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    // Offline: every write fails, so each action ends rolled back.
    AppState offline() => AppState()
      ..hobs = [
        Hob(
          name: 'cto',
          displayName: 'CTO',
          sectionId: 's1',
          sectionName: 'Vibee.one',
        ),
        Hob(name: 'dev', displayName: 'Dev'),
      ];

    Future<void> pump(WidgetTester tester, AppState app, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: const MaterialApp(home: HobsScreen()),
        ),
      );
    }

    testWidgets('long-press opens a popover on phones too', (tester) async {
      final app = offline();
      await pump(tester, app, const Size(400, 800));

      await tester.longPress(find.text('CTO'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Připnout'), findsOneWidget);
      expect(find.text('Skrýt'), findsOneWidget);
      expect(find.text('Přesunout do složky'), findsOneWidget);
      expect(find.text('Smazat'), findsOneWidget);

      await tester.tap(find.text('Přesunout do složky'));
      await tester.pumpAndSettle();
      expect(find.text('Vibee.one'), findsWidgets);
      expect(find.text('Vyjmout ze složky'), findsOneWidget);
      await tester.tap(find.text('Nová složka…'));
      await tester.pumpAndSettle();
      expect(find.text('Nová složka'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Klienti');
      await tester.tap(find.text('Vytvořit'));
      await tester.pumpAndSettle();
      // Not connected: the write fails, the hob stays put, a snackbar says so.
      expect(
        find.text('Změnu se nepodařilo uložit. Zkuste to znovu.'),
        findsOneWidget,
      );
      expect(app.hobNamed('cto')!.sectionName, 'Vibee.one');
    });

    testWidgets('delete asks in a sheet and keeps the hob when refused', (
      tester,
    ) async {
      final app = offline();
      await pump(tester, app, const Size(400, 800));

      await tester.longPress(find.text('Dev'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Smazat'));
      await tester.pumpAndSettle();
      expect(find.text('Smazat Hobíka Dev?'), findsOneWidget);

      // Backing out deletes nothing.
      await tester.tap(find.text('Zrušit'));
      await tester.pumpAndSettle();
      expect(find.text('Smazat Hobíka Dev?'), findsNothing);
      expect(app.hobNamed('dev'), isNotNull);

      await tester.longPress(find.text('Dev'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Smazat'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Smazat'));
      await tester.pumpAndSettle();
      // Offline: the server never saw it, the hob stays.
      expect(
        find.text(
          'Hobíka se nepodařilo smazat: Aplikace není připojená k serveru.',
        ),
        findsOneWidget,
      );
      expect(app.hobNamed('dev'), isNotNull);
    });

    testWidgets('right-click opens a popup menu', (tester) async {
      final app = offline();
      await pump(tester, app, const Size(1200, 800));

      await tester.tap(find.text('Dev'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(PopupMenuItem<Object?>), findsNothing);
      expect(find.text('Skrýt'), findsOneWidget);

      await tester.tap(find.text('Skrýt'));
      await tester.pumpAndSettle();
      // Once across the split view, not once in each pane.
      expect(
        find.text('Změnu se nepodařilo uložit. Zkuste to znovu.'),
        findsOneWidget,
      );
      expect(app.hobNamed('dev')!.hidden, isFalse);
    });

    testWidgets('hidden hobs wait in a closed group', (tester) async {
      final app = offline()
        ..hiddenHobsForTest = [
          Hob(name: 'ghost', displayName: 'Ghost', hidden: true),
        ];
      await pump(tester, app, const Size(400, 800));
      expect(find.text('Skrytí Hobíci'), findsOneWidget);
      expect(find.text('Ghost'), findsNothing);

      await tester.tap(find.text('Skrytí Hobíci'));
      await tester.pumpAndSettle();
      expect(find.text('Ghost'), findsOneWidget);

      await tester.longPress(find.text('Ghost'));
      await tester.pumpAndSettle();
      expect(find.text('Zobrazit v seznamu'), findsOneWidget);
      expect(find.text('Skrýt'), findsNothing);
    });
  });
}
