import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/group_attachments.dart';
import 'package:hobs/api/group_models.dart';
import 'package:hobs/api/hermes_rpc.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/l10n/strings_cs.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/state/group_chat_controller.dart';
import 'package:hobs/ui/attachments_ui.dart';
import 'package:hobs/ui/hobs_screen.dart';
import 'package:hobs/ui/group_chat_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credentials_test.dart' show settle, waitFor;
import 'fake_hermes_server.dart';

class _GroupFilePicker extends AttachmentPickers {
  @override
  Future<List<XFile>> files() async => [
    XFile.fromData(Uint8List.fromList([65]), path: 'notes.txt'),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('attachment manifests reject unsafe names and omit extra fields', () {
    final manifest = {
      'attachment_id': 'att_${'a' * 32}',
      'kind': 'file',
      'name': 'poznámky.txt',
      'mime': 'text/plain',
      'size': 12,
    };
    expect(
      GroupAttachment.fromJson({...manifest, 'extra': 'ignored'})?.toJson(),
      manifest,
    );
    expect(
      GroupAttachment.fromJson({...manifest, 'name': '../private.txt'}),
      isNull,
    );
    expect(
      GroupAttachment.fromJson({
        ...manifest,
        'size': maxGroupAttachmentBytes + 1,
      }),
      isNull,
    );
  });

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

    test(
      'a room attachment round trips and is scoped to its own event',
      () async {
        final members = [app.hobNamed('cto')!, app.hobNamed('posta')!];
        final chat = app.groupChatFor(await app.createGroup(members));
        final other = app.groupChatFor(await app.createGroup(members));
        await waitFor(() => !chat.loading && !other.loading);
        expect(chat.canUploadAttachments, isTrue);
        expect(chat.canDownloadAttachments, isTrue);

        final bytes = Uint8List.fromList(utf8.encode('review notes'));
        chat.draft.addFile(bytes, 'notes.txt');
        await waitFor(() => chat.draft.ready);
        final file = chat.draft.items.single.uploaded!.groupAttachment!;
        final upload = lastCall(groupAttachmentUpload);
        expect(upload['profile'], 'default');
        expect(upload['room_id'], chat.roomId);
        expect(upload['kind'], 'file');
        expect(base64Decode(upload['data_base64']), bytes);

        await expectLater(
          chat.attachmentApi.download('not-committed', file),
          throwsA(isA<RpcException>()),
        );
        expect(await chat.send('', attachments: [file]), isTrue);
        await waitFor(() => chat.log.isNotEmpty);
        final event = chat.log.first;
        expect(event.text, isEmpty);
        expect(event.attachments.single.toJson(), file.toJson());
        expect(lastCall('groups.send')['payload']['attachments'], [
          file.toJson(),
        ]);
        expect(await chat.attachmentApi.download(event.eventId, file), bytes);
        await expectLater(
          other.attachmentApi.download(event.eventId, file),
          throwsA(isA<RpcException>()),
        );
      },
    );

    test('a rejected file message can retry with the same event ID', () async {
      final chat = app.groupChatFor(
        await app.createGroup([app.hobNamed('cto')!, app.hobNamed('posta')!]),
      );
      await waitFor(() => !chat.loading);
      final bytes = Uint8List.fromList(utf8.encode('%PDF-1.7'));
      chat.draft.addFile(bytes, 'brief.pdf');
      await waitFor(() => chat.draft.ready);
      final file = chat.draft.items.single.uploaded!.groupAttachment!;
      expect(file.kind, 'pdf');

      server.rejectNextGroupSend = true;
      expect(await chat.send('Read this', attachments: [file]), isFalse);
      expect(chat.sendError, isNotNull);
      expect(chat.log, isEmpty);
      final attempted = lastCall('groups.send');

      expect(await chat.send('Read this', attachments: [file]), isTrue);
      expect(lastCall('groups.send'), attempted);
      await waitFor(() => chat.log.isNotEmpty);
      expect(chat.log.where((event) => event.isUserMessage), hasLength(1));
    });

    test('text chat works when the gateway has no room file methods', () async {
      server.groupAttachmentsEnabled = false;
      final chat = app.groupChatFor(
        await app.createGroup([app.hobNamed('cto')!, app.hobNamed('posta')!]),
      );
      await waitFor(() => !chat.loading);
      expect(chat.canUploadAttachments, isFalse);
      expect(chat.canDownloadAttachments, isFalse);
      expect(await chat.send('Hello'), isTrue);
      await waitFor(() => chat.log.isNotEmpty);
      expect(chat.log.first.text, 'Hello');
    });

    testWidgets('group composer shows a file before and after sending', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final chat = (await tester.runAsync(() async {
        final room = await app.createGroup([
          app.hobNamed('cto')!,
          app.hobNamed('posta')!,
        ]);
        final c = app.groupChatFor(room);
        await waitFor(() => !c.loading);
        return c;
      }))!;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(home: GroupChatScreen(room: chat.room)),
        ),
      );
      final attach = find.byIcon(Icons.add_circle_outline);
      final send = find.byIcon(Icons.arrow_upward);
      final input = find.byKey(const ValueKey('group-input'));
      final hint = find.text(const StringsCs().groupMessageHint);
      expect(tester.getSize(hint).height, greaterThan(30));
      expect(
        tester.getCenter(attach).dy,
        closeTo(tester.getCenter(input).dy, 0.5),
      );
      expect(
        tester.getCenter(send).dy,
        closeTo(tester.getCenter(input).dy, 0.5),
      );
      final original = AttachmentPickers.current;
      AttachmentPickers.current = _GroupFilePicker();
      addTearDown(() => AttachmentPickers.current = original);
      await tester.tap(find.byKey(const ValueKey('attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(const StringsCs().chooseFiles));
      await tester.pump();
      for (
        var attempt = 0;
        attempt < 100 && (chat.draft.isEmpty || !chat.draft.ready);
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(chat.draft.ready, isTrue);
      await tester.pump();
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('Pošta'), findsOneWidget);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(find.text('Pošta'), findsNothing);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(
        find.byTooltip(const StringsCs().send).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      tester.view.resetViewInsets();
      await tester.pump();
      expect(find.text('Pošta'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip(const StringsCs().send));
        await waitFor(
          () => chat.log.any((event) => event.attachments.isNotEmpty),
        );
      });
      await tester.pump();
      expect(chat.draft.isEmpty, isTrue);
      expect(find.widgetWithText(ActionChip, 'notes.txt'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
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
