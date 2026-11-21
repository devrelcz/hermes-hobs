import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/ui/hob_avatar.dart';
import 'package:hobs/ui/hob_detail_screen.dart';
import 'package:hobs/ui/hobs_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credentials_test.dart' show settle;
import 'fake_hermes_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('screen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    final cto = Hob(
      name: 'dev-cto',
      displayName: 'CTO',
      description: 'Vede vývoj',
      shape: 'circle',
      color: '#F0997B',
      meta: const {'title': 'CTO', 'shape': 'circle'},
    );

    /// Opens the profile on top of a page, the way the chat header does.
    Future<void> openProfile(WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: AppState()..hobs = [cto],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => HobDetailScreen.open(context, cto),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('the list opens the chat, never the profile', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: AppState()..hobs = [cto],
          child: const MaterialApp(home: HobsScreen()),
        ),
      );
      expect(find.byType(HobAvatar), findsOneWidget);
      expect(find.byTooltip('Upravit profil: CTO'), findsNothing);
    });

    testWidgets('the profile shows what the roster knows', (tester) async {
      await openProfile(tester);

      expect(find.byType(HobDetailScreen), findsOneWidget);
      expect(find.text('Profil Hobíka'), findsOneWidget);
      expect(find.text('@dev-cto'), findsOneWidget);
      await tester.dragUntilVisible(
        find.widgetWithText(TextField, 'Vede vývoj'),
        find.byType(ListView).last,
        const Offset(0, -150),
      );
      expect(find.widgetWithText(TextField, 'Vede vývoj'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'CTO'), findsOneWidget);
      // Offline: the model cannot be read, the rest stays editable.
      await tester.dragUntilVisible(
        find.textContaining('SOUL.md se nepodařilo'),
        find.byType(ListView).last,
        const Offset(0, -150),
      );
      expect(find.textContaining('SOUL.md se nepodařilo'), findsOneWidget);
    });

    testWidgets('save wakes up on an edit, closing asks first', (tester) async {
      await openProfile(tester);
      FilledButton save() =>
          tester.widget(find.widgetWithText(FilledButton, 'Uložit'));
      expect(save().onPressed, isNull);

      await tester.tap(find.byTooltip('hexagon'));
      await tester.pump();
      expect(save().onPressed, isNotNull);
      final preview = tester.widget<HobAvatar>(find.byType(HobAvatar).first);
      expect(preview.face!.shape, 'hexagon');

      // A generated face keeps its seed when the silhouette changes.
      await tester.tap(find.byTooltip('Obličej: sun'));
      await tester.pump();
      final blob = tester.widget<HobAvatar>(find.byType(HobAvatar).first);
      expect((blob.face!.blobSeed, blob.face!.blobKind), ('dev-cto', 'sun'));
      expect(find.text('Barva'), findsNothing);

      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text('Zahodit neuložené změny?'), findsOneWidget);
      await tester.tap(find.text('Zahodit'));
      await tester.pumpAndSettle();
      expect(find.byType(HobDetailScreen), findsNothing);
    });
  });

  group('saving', () {
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

    Map<String, dynamic> meta() =>
        (server.roster[0]['ui_meta'] as Map)['hermes-bots']
            as Map<String, dynamic>;

    test('appearance keeps the rest of the metadata', () async {
      await app.saveHobAppearance(
        app.hobNamed('cto')!,
        title: ' Šéf ',
        shape: 'hexagon',
        color: null,
      );
      expect(meta(), {
        'title': 'Šéf',
        'sectionId': 's1',
        'sectionName': 'Vibee.one',
        'pinned': true,
        'shape': 'hexagon',
        'custom': true,
      });

      await app.refreshHobs(silent: true);
      expect(app.hobNamed('cto')!.displayName, 'Šéf');
    });

    test('a stale revision is reread and retried', () async {
      await app.renameSection('section:s1', 'Klienti');
      final stale = app.hobNamed('cto')!;
      // Another client edits the hob: the app's copy is now one revision old.
      meta()['pinned'] = false;
      (server.roster[0]['ui_meta_revisions'] as Map)['hermes-bots'] = 7;
      server.configures.clear();

      await app.saveHobAppearance(
        stale,
        title: 'CTO',
        shape: stale.shape,
        color: '#000000',
      );
      expect(server.configures.length, 2);
      expect(meta()['pinned'], false);
      expect(meta()['color'], '#000000');
    });

    test('description goes through the profile command', () async {
      await app.saveHobDescription(app.hobNamed('cto')!, ' Vede vývoj ');
      expect(server.cliCalls, [
        ['profile', 'describe', 'cto', '--text', 'Vede vývoj'],
      ]);
      await app.refreshHobs(silent: true);
      expect(app.hobNamed('cto')!.description, 'Vede vývoj');
    });

    test('model is read, switched, confirmed and unset', () async {
      final hob = app.hobNamed('cto')!;
      final now = await app.hobSetup(hob);
      expect((now.provider, now.model), ('nous', 'hermes-4'));
      final providers = await app.modelProviders();
      expect(providers.map((p) => p.label), [
        'Nous (nous)',
        'Codex (openai-codex)',
      ]);
      expect(providers.last.models, ['gpt-6.2-sol']);

      expect(
        await app.saveHobModel(
          hob,
          provider: 'openai-codex',
          model: 'gpt-6.2-sol',
        ),
        isNull,
      );
      expect(server.profileModel['default'], 'gpt-6.2-sol');

      // An expensive model is not switched until the user confirms.
      expect(
        await app.saveHobModel(hob, provider: 'nous', model: 'hermes-4-pro'),
        'Pricey.',
      );
      expect(server.profileModel['default'], 'gpt-6.2-sol');
      await app.saveHobModel(
        hob,
        provider: 'nous',
        model: 'hermes-4-pro',
        confirmed: true,
      );
      expect(server.profileModel['default'], 'hermes-4-pro');

      await app.saveHobModel(hob, provider: '', model: '');
      expect(server.cliCalls.last, [
        '--profile',
        'cto',
        'config',
        'unset',
        'model',
      ]);
    });

    test('SOUL.md is read and replaced', () async {
      final hob = app.hobNamed('cto')!;
      expect((await app.hobSetup(hob)).soul, '# CTO\n\nVede vývoj.\n');

      await app.saveHobSoul(hob, '# CTO\n\nVede vývoj a testy.\n');
      expect(server.configures.last, {
        'name': 'cto',
        'soul': '# CTO\n\nVede vývoj a testy.',
      });
      expect((await app.hobSetup(hob)).soul, '# CTO\n\nVede vývoj a testy.');
    });
  });
}
