import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/group_models.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/l10n/strings_cs.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/state/group_chat_controller.dart';
import 'package:hobs/ui/hobs_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credentials_test.dart' show settle, waitFor;
import 'fake_hermes_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('flow', () {
    late FakeHermesServer server;
    late AppState app;

    setUp(() async {
      HttpOverrides.global = null;
      server = FakeHermesServer();
      server.roster.add({
        'name': 'posta',
        'ui_meta': {
          'hermes-bots': {'title': 'Pošta'},
        },
      });
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
      await waitFor(() => app.groupsSupported != null);
    });

    tearDown(() async {
      app.dispose();
      await server.stop();
    });

    Map<String, dynamic> lastCall(String method) =>
        server.calls.lastWhere((c) => c['method'] == method)['params'];

    test('create, talk, rename and disband a group chat', () async {
      expect(app.groupsSupported, isTrue);
      expect(app.seatableProfiles, containsAll(['cto', 'posta']));
      expect(app.groups, isEmpty);

      final members = [app.hobNamed('cto')!, app.hobNamed('posta')!];
      final room = await app.createGroup(members);
      expect(room.name, 'CTO, Pošta');
      final create = lastCall('groups.create');
      expect(create['profile'], 'default');
      expect(create['members'], [
        {
          'member_id': 'cto',
          'profile': 'cto',
          'handle': 'cto',
          'target': {'kind': 'local', 'profile': 'cto'},
        },
        {
          'member_id': 'posta',
          'profile': 'posta',
          'handle': 'posta',
          'target': {'kind': 'local', 'profile': 'posta'},
        },
      ]);
      // A second group of the same Hobs gets its own name.
      expect(app.groupNameFor(members), 'CTO, Pošta (2)');

      final chat = app.groupChatFor(room);
      app.setOpenGroup(room.roomId);
      await waitFor(() => !chat.loading);
      expect(chat.log, isEmpty);

      server.groupHold = Completer();
      await chat.send('@cto ahoj');
      final sent = lastCall('groups.send');
      expect(sent['payload']['text'], '@cto ahoj');
      expect(sent['payload']['thread_id'], sent['event_id']);
      await waitFor(() => chat.stateOf('cto') == MemberState.working);
      expect(chat.toolOf('cto'), 'web_search');
      expect(chat.busy, isTrue);

      server.groupHold!.complete();
      await waitFor(() => chat.lastSeq == 6);
      await waitFor(() => !chat.busy);
      expect(chat.pendingText, isNull);
      expect(chat.stateOf('cto'), MemberState.replied);
      expect(chat.stateOf('posta'), MemberState.replied);
      expect(chat.log.where((e) => e.isMemberMessage).map((e) => e.text), [
        'Ahoj od cto',
        'Ahoj od posta',
      ]);
      expect(chat.preview, 'Ahoj od posta');
      // The open room counts as read.
      expect(app.isGroupUnread(app.groupById(room.roomId)!), isFalse);

      await chat.rename('Porada');
      expect(chat.room.name, 'Porada');
      await waitFor(() => app.groupById(room.roomId)?.name == 'Porada');

      await chat.disband();
      expect(chat.disbanded, isTrue);
      app.forgetGroup(room.roomId);
      expect(app.groups, isEmpty);
      expect(server.rooms, isEmpty);
    });

    test('gateway preserves URLs in group messages', () async {
      const url = 'https://example.org/a%20b?next=%2Fdocs&lang=cs#intro';
      const question = 'Podívej se na ($url).';
      const answer = '[Návod]($url)';
      server.memberReply = (_) => answer;
      final room = await app.createGroup([
        app.hobNamed('cto')!,
        app.hobNamed('posta')!,
      ]);
      final chat = app.groupChatFor(room);
      app.setOpenGroup(room.roomId);
      await waitFor(() => !chat.loading);

      await chat.send(question);
      await waitFor(() => chat.lastSeq == 6);

      expect(lastCall('groups.send')['payload']['text'], question);
      expect(chat.log.map((event) => event.text), contains(question));
      expect(
        chat.log
            .where((event) => event.isMemberMessage)
            .map((event) => event.text),
        [answer, answer],
      );
    });

    test('a gateway without group chats hides them', () async {
      final s2 = FakeHermesServer()..groupsEnabled = false;
      await s2.start();
      final other = AppState();
      await other.login(
        serverUrl: s2.baseUrl.toString(),
        username: 'u',
        password: 'p',
      );
      await settle(other);
      await waitFor(() => other.groupsSupported != null);
      expect(other.groupsSupported, isFalse);
      expect(other.groups, isEmpty);
      other.dispose();
      await s2.stop();
    });
  });

  group('screen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('the list shows group chats in their own folder', (
      tester,
    ) async {
      final app = AppState()
        ..hobs = [
          Hob(name: 'cto', displayName: 'CTO'),
          Hob(name: 'posta', displayName: 'Pošta'),
        ]
        ..groupsSupported = true
        ..groups = [
          const GroupRoom(
            roomId: 'r1',
            name: 'Porada',
            members: [
              GroupMember(memberId: 'cto', handle: 'cto', profile: 'cto'),
              GroupMember(memberId: 'posta', handle: 'posta', profile: 'posta'),
            ],
          ),
        ];
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: const MaterialApp(home: HobsScreen()),
        ),
      );
      const s = StringsCs();
      expect(find.text(s.groupChats), findsOneWidget);
      expect(find.text('Porada'), findsOneWidget);
      expect(find.text('2 Hobíci · CTO, Pošta'), findsOneWidget);
      await tester.tap(find.byTooltip(s.create));
      await tester.pumpAndSettle();
      expect(find.text(s.newHob), findsOneWidget);
      expect(find.text(s.newGroupChat), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      app.setQuery('nic');
      await tester.pump();
      expect(find.text('Porada'), findsNothing);
      app.setQuery('pošta');
      await tester.pump();
      expect(find.text('Porada'), findsOneWidget);
    });
  });
}
