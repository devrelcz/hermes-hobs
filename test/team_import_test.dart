import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/api/team_catalog.dart';
import 'package:hobs/l10n/strings_cs.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/state/team_import.dart';
import 'package:hobs/ui/hob_avatar.dart';
import 'package:hobs/ui/hobs_screen.dart';
import 'package:hobs/ui/team_catalog_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credentials_test.dart' show settle, waitFor;
import 'fake_hermes_server.dart';

final _root = Uri.parse('https://cdn.example/catalog@v1/');

Map<String, dynamic> _member(
  String key, {
  String? handle,
  List<Map<String, dynamic>> jobs = const [],
  List<String> prefer = const [],
}) => {
  'key': key,
  'handle': handle ?? key,
  'title': {'en': 'The $key', 'cs': 'Ten $key'},
  'description': {'en': '$key work', 'cs': 'práce $key'},
  'face': {'shape': 'blobatar:$key:round'},
  'soul': {'en': 'souls/$key.en.md', 'cs': 'souls/$key.cs.md'},
  if (prefer.isNotEmpty) 'model': {'prefer': prefer},
  'jobs': jobs,
};

Map<String, dynamic> _team({List<Map<String, dynamic>>? members}) => {
  'schema': 1,
  'id': 'dev-team',
  'version': '1.0.0',
  'name': {'en': 'Dev team', 'cs': 'Vývojový tým'},
  'summary': {'en': 'Builds things', 'cs': 'Staví věci'},
  'folder': {'en': 'Dev', 'cs': 'Vývoj'},
  'group': {
    'create': true,
    'name': {'en': 'Dev chat', 'cs': 'Vývoj chat'},
  },
  'members':
      members ??
      [
        _member(
          'cto',
          jobs: [
            {
              'name': {'en': 'Weekly plan', 'cs': 'Týdenní plán'},
              'schedule': '0 8 * * 1',
              'prompt': {
                'en': 'Plan with {{@analyst}}.',
                'cs': 'Naplánuj s {{@analyst}}.',
              },
              'continuity': true,
            },
          ],
          prefer: ['anthropic/claude-opus-5-5', 'nous/hermes-4-pro'],
        ),
        _member('analyst'),
        _member('dev'),
      ],
};

/// A catalog served from memory: the index, [team] and SOULs that name
/// their teammates.
Map<Uri, String> _files({Map<String, dynamic>? team}) {
  final t = team ?? _team();
  return {
    _root.resolve('index.json'): jsonEncode({
      'schema': 1,
      'teams': [
        {
          'id': 'dev-team',
          'version': '1.0.0',
          'path': 'teams/dev-team/team.json',
          'cover': 'teams/dev-team/cover.webp',
          'name': t['name'],
          'summary': t['summary'],
          'members': (t['members'] as List).length,
          'faces': [for (final m in t['members'] as List) m['face']],
        },
        // A team for a newer app's format is still listed by a newer index
        // entry with a bad path: left out, not fatal.
        {'id': 'bad', 'path': '../evil.json', 'name': 'Bad'},
      ],
    }),
    _root.resolve('teams/dev-team/team.json'): jsonEncode(t),
    for (final m in t['members'] as List)
      for (final lang in ['en', 'cs'])
        _root.resolve('teams/dev-team/souls/${m['key']}.$lang.md'):
            '# ${m['key']} ($lang)\nAsk {{@cto}} and {{@analyst}}.\n',
  };
}

TeamCatalogClient _client(Map<Uri, String> files, {List<Uri>? log}) =>
    TeamCatalogClient(
      root: _root,
      fetch: (uri) async {
        log?.add(uri);
        final body = files[uri];
        if (body == null) throw TeamCatalogException('404 $uri');
        return body;
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('catalog', () {
    test('text falls back to English, then to any language', () {
      expect(const LocalText({'en': 'Hi', 'cs': 'Ahoj'}).pick('cs'), 'Ahoj');
      expect(const LocalText({'en': 'Hi'}).pick('cs'), 'Hi');
      expect(const LocalText({'de': 'Hallo'}).pick('cs'), 'Hallo');
      expect(LocalText.empty.pick('cs'), '');
    });

    test('a team the app cannot import is refused', () {
      expect(TeamSpec.fromJson(_team()), isNotNull);
      expect(TeamSpec.fromJson({..._team(), 'schema': 2}), isNull);
      expect(TeamSpec.fromJson(_team(members: [_member('solo')])), isNull);
      expect(
        TeamSpec.fromJson(
          _team(members: [for (var i = 0; i < 7; i++) _member('m$i')]),
        ),
        isNull,
      );
      expect(
        TeamSpec.fromJson(
          _team(
            members: [
              _member('a', handle: 'same'),
              _member('b', handle: 'same'),
            ],
          ),
        ),
        isNull,
      );
      // A member with a handle the server would refuse is dropped.
      expect(
        TeamSpec.fromJson(
          _team(
            members: [
              _member('a'),
              _member('b'),
              _member('c', handle: 'default'),
              _member('d', handle: 'Bad Name'),
            ],
          ),
        )!.members.map((m) => m.key),
        ['a', 'b'],
      );
    });

    test('reads the index and a team with SOULs in the language', () async {
      final log = <Uri>[];
      final client = _client(_files(), log: log);
      final cards = await client.fetchIndex();
      expect(cards.map((c) => c.id), ['dev-team']);
      expect(cards.single.members, 3);
      expect(cards.single.faces.first.shape, 'blobatar:cto:round');
      expect(
        client.coverOf(cards.single),
        _root.resolve('teams/dev-team/cover.webp'),
      );
      expect(log, [_root.resolve('index.json')]);

      final team = await client.fetchTeam(cards.single, 'cs');
      expect(team.members.first.soul, startsWith('# cto (cs)'));
      expect(team.members.first.jobs.single.continuity, isTrue);
      expect(
        log,
        contains(_root.resolve('teams/dev-team/souls/analyst.cs.md')),
      );
    });

    test('the official catalog is HobCrew', () {
      expect(TeamCatalogClient.defaultRoot.host, 'hobcrew.com');
      expect(TeamCatalogClient().root, TeamCatalogClient.defaultRoot);
    });

    test('an unknown catalog format is an error', () async {
      final client = _client({
        _root.resolve('index.json'): jsonEncode({'schema': 9, 'teams': []}),
      });
      await expectLater(
        client.fetchIndex(),
        throwsA(isA<TeamCatalogException>()),
      );
    });
  });

  group('import', () {
    late FakeHermesServer server;
    late AppState app;

    setUp(() async {
      HttpOverrides.global = null;
      server = FakeHermesServer();
      await server.start();
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      app = AppState()..teamCatalog = _client(_files());
      await app.login(
        serverUrl: server.baseUrl.toString(),
        username: 'u',
        password: 'p',
      );
      await settle(app);
      await waitFor(() => app.groupsSupported != null);
    });

    tearDown(() async {
      app.dispose();
      await server.stop();
    });

    Future<TeamPlan> plan() async {
      final card = (await app.teamCatalog.fetchIndex()).single;
      final team = await app.teamCatalog.fetchTeam(card, 'cs');
      return TeamPlan.make(app, team, lang: 'cs');
    }

    Map<String, dynamic> uiMeta(String name) => Map<String, dynamic>.from(
      server.roster.firstWhere((r) => r['name'] == name)['ui_meta'] as Map,
    );

    test('plans free handles, the model offered and one folder', () async {
      final p = await plan();
      // The server already has a cto.
      expect(p.members.map((m) => m.handle), ['cto-2', 'analyst', 'dev']);
      expect(p.members.first.provider, 'nous');
      expect(p.members.first.model, 'hermes-4-pro');
      expect(p.members[1].model, isNull);
      expect(p.folderName, 'Vývoj');
      expect(p.folderId, startsWith('sec-'));
      expect(p.groupName, 'Vývoj chat');
      expect(p.soulOf(p.members[1]), contains('Ask @cto-2 and @analyst.'));
    });

    test('creates the Hobs, their jobs switched off, and the group', () async {
      final p = await plan();
      final import = TeamImport(app, p);
      expect(await import.run(), isTrue);
      expect(import.finished, isTrue);
      expect(import.created, ['cto-2', 'analyst', 'dev']);

      final creates = server.profileCreates;
      expect(creates.map((c) => c['name']), ['cto-2', 'analyst', 'dev']);
      expect(creates.first['clone_from'], 'default');
      expect(creates.first['share_auth'], isTrue);
      expect(creates.first['provider'], 'nous');
      expect(creates.first['model'], 'hermes-4-pro');
      expect(creates[1].containsKey('model'), isFalse);
      expect(creates[1]['description'], 'práce analyst');
      expect(creates[1]['soul'], '# analyst (cs)\nAsk @cto-2 and @analyst.');

      final folders = <Object?>{};
      for (final name in import.created) {
        final meta = uiMeta(name);
        final bots = meta['hermes-bots'] as Map;
        folders.add(bots['sectionId']);
        expect(bots['sectionName'], 'Vývoj');
        expect(bots['shape'], startsWith('blobatar:'));
        expect(meta[AppState.teamMetaKey], containsPair('id', 'dev-team'));
      }
      expect(folders, hasLength(1));
      expect((uiMeta('cto-2')['hermes-bots'] as Map)['title'], 'Ten cto');
      expect(uiMeta('dev')[AppState.teamMetaKey]['key'], 'dev');

      final job = server.cronAdds.single;
      expect(job['name'], '[bot:cto-2] Týdenní plán');
      expect(job['profile'], 'cto-2');
      expect(job['prompt'], 'Naplánuj s @analyst.');
      expect(job['deliver'], 'bot-chat');
      expect(job['continuity'], isTrue);
      expect(server.cronActions, ['pause ${server.cronJobs.last['id']}']);
      expect(server.cronJobs.last['enabled'], isFalse);

      final room = import.room!;
      expect(room.name, 'Vývoj chat');
      expect(room.members.map((m) => m.profile), ['cto-2', 'analyst', 'dev']);
      expect(app.hobNamed('analyst')?.sectionName, 'Vývoj');
    });

    test('a failed step stops; running again finishes the rest', () async {
      server.refuseCreate.add('analyst');
      final import = TeamImport(app, await plan());
      expect(await import.run(), isFalse);
      expect(import.failed, isTrue);
      expect(import.created, ['cto-2']);
      expect(import.steps[1].state, TeamStepState.failed);
      expect(import.steps[2].state, TeamStepState.pending);
      expect(AppState.describeError(import.error!), contains('Disk full'));

      expect(await import.run(), isTrue);
      expect(import.created, ['cto-2', 'analyst', 'dev']);
      // cto-2 was not created twice.
      expect(
        server.profileCreates.where((c) => c['name'] == 'cto-2'),
        hasLength(1),
      );
      expect(import.room, isNotNull);
    });

    test('rolling back deletes the Hobs created so far', () async {
      server.refuseCreate.add('dev');
      final import = TeamImport(app, await plan());
      expect(await import.run(), isFalse);
      await import.rollback();
      expect(server.deletedProfiles, ['cto-2', 'analyst']);
      expect(import.created, isEmpty);
      expect(import.rolledBack, isTrue);
      expect(await import.run(), isFalse);
    });

    test('without group chats the team gets no group step', () async {
      app.groupsSupported = false;
      final p = await plan();
      expect(p.groupName, isNull);
      final import = TeamImport(app, p);
      expect(
        import.steps.map((s) => s.kind),
        isNot(contains(TeamStepKind.group)),
      );
    });

    test('an existing folder of the same name is reused', () async {
      final p = await TeamPlan.make(
        app,
        TeamSpec.fromJson({
          ..._team(),
          'folder': {'en': 'Vibee.one'},
        })!,
        lang: 'cs',
      );
      expect(p.folderId, 's1');
    });
  });

  group('screen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('"+" adds a team and opens its group chat', (tester) async {
      SharedPreferences.setMockInitialValues({'welcomeSeen': true});
      // Tall enough that a team's whole page is built.
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      HttpOverrides.global = null;
      FlutterSecureStorage.setMockInitialValues({});
      final server = FakeHermesServer();
      final app = AppState()..teamCatalog = _client(_files());
      await tester.runAsync(() async {
        await server.start();
        await app.login(
          serverUrl: server.baseUrl.toString(),
          username: 'u',
          password: 'p',
        );
        await settle(app);
        await waitFor(() => app.groupsSupported != null);
      });
      addTearDown(() => tester.runAsync(server.stop));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: const MaterialApp(home: HobsScreen()),
        ),
      );
      await tester.pump();
      const s = StringsCs();

      Future<void> settleAsync(bool Function() done) async {
        for (var i = 0; i < 100 && !done(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump(const Duration(milliseconds: 500));
      }

      await tester.tap(find.byTooltip(s.create));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.newTeam));
      await settleAsync(() => find.text('Vývojový tým').evaluate().isNotEmpty);
      await tester.tap(find.text('Vývojový tým'));
      await settleAsync(
        () => find.text(s.teamFolder('Vývoj')).evaluate().isNotEmpty,
      );
      await tester.tap(find.widgetWithText(FilledButton, s.addTeam));
      await settleAsync(() => server.rooms.isNotEmpty);
      await settleAsync(
        () => find.byType(TeamCatalogScreen).evaluate().isEmpty,
      );

      expect(find.byType(TeamCatalogScreen), findsNothing);
      expect(find.text(s.teamReady('Vývojový tým')), findsOneWidget);
      expect(app.openGroup, server.rooms.keys.single);
      expect(app.hobNamed('analyst')?.sectionName, 'Vývoj');

      // Stop the app's timers (the toast, the group chat's polling).
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('lists the teams and shows a team before adding it', (
      tester,
    ) async {
      // Tall enough that a team's whole page is built.
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = AppState()
        ..hobs = [Hob(name: 'cto', displayName: 'CTO')]
        ..groupsSupported = true
        ..teamCatalog = _client(_files());
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: const MaterialApp(home: Scaffold(body: TeamCatalogScreen())),
        ),
      );
      await tester.pumpAndSettle();
      const s = StringsCs();
      expect(find.text(s.teamsTitle), findsOneWidget);
      expect(find.text(s.teamsSection), findsOneWidget);
      expect(find.text(s.teamsIntro), findsOneWidget);
      expect(find.text('Vývojový tým'), findsOneWidget);
      // The count is in the row's label; the faces show it.
      expect(find.bySemanticsLabel(RegExp('3 Hobíci')), findsOneWidget);
      expect(find.byType(HobAvatar), findsNWidgets(3));
      // The picture cannot be fetched here: a placeholder stands in.
      expect(find.byIcon(Icons.groups_outlined), findsWidgets);
      expect(find.byType(Image), findsOneWidget);

      await tester.tap(find.text('Vývojový tým'));
      await tester.pumpAndSettle();
      expect(find.text(s.teamFolder('Vývoj')), findsOneWidget);
      expect(find.text(s.teamGroup('Vývoj chat')), findsOneWidget);
      expect(find.text(s.teamReviewNote), findsOneWidget);
      expect(find.text('Ten cto'), findsOneWidget);
      expect(find.textContaining('@cto-2'), findsOneWidget);
      expect(find.text(s.teamJobsOff), findsOneWidget);

      await tester.tap(find.text('Ten cto'));
      await tester.pumpAndSettle();
      expect(find.text(s.teamHandleTaken('cto')), findsOneWidget);
      expect(find.text('Naplánuj s @analyst.'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(s.teamsSection), findsOneWidget);
    });

    testWidgets('five teams fit a narrow phone without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final files = _files();
      final index = jsonDecode(files[_root.resolve('index.json')]!) as Map;
      final card = (index['teams'] as List).first as Map;
      index['teams'] = [
        for (var i = 0; i < 5; i++)
          {
            ...card,
            'id': 'team-$i',
            'name': {'en': 'A team with a rather long name number $i'},
            'members': 6,
            'faces': [for (var j = 0; j < 6; j++) card['faces'][j % 3]],
          },
      ];
      files[_root.resolve('index.json')] = jsonEncode(index);
      final app = AppState()..teamCatalog = _client(files);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: const MaterialApp(home: Scaffold(body: TeamCatalogScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // All five rows are on the first screen.
      for (var i = 0; i < 5; i++) {
        expect(
          find.text('A team with a rather long name number $i'),
          findsOneWidget,
        );
      }
      final last = tester.getRect(
        find.text('A team with a rather long name number 4'),
      );
      expect(last.bottom, lessThan(800));
    });

    testWidgets('a catalog that fails to load offers a retry', (tester) async {
      final app = AppState()..teamCatalog = _client({});
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: const MaterialApp(home: Scaffold(body: TeamCatalogScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Katalog týmů se nepodařilo načíst'),
        findsOne,
      );
      expect(find.text(const StringsCs().retry), findsOne);
    });
  });
}
