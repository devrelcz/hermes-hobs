import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/group_models.dart';
import 'package:hobs/api/hermes_rpc.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/l10n/strings_cs.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/state/chat_controller.dart';
import 'package:hobs/state/notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'biometric_lock_test.dart' show FakeBiometrics;
import 'credentials_test.dart' show settle, waitFor;
import 'fake_hermes_server.dart';

class Shown {
  Shown(this.key, this.title, this.body, this.blocking);

  /// [NotifyTarget.key]: `hob:<name>` or `group:<room id>`.
  final String key;
  final String title;
  final String body;
  final bool blocking;

  @override
  String toString() => '$key: $title / $body';
}

/// Records what the app would show instead of calling the plugin.
class FakeNotifier implements Notifier {
  final shown = <Shown>[];
  final cleared = <String>[];
  final _taps = StreamController<String>.broadcast();
  String? launchedFor;
  bool grant = true;
  int permissionAsks = 0;

  void tap(String payload) => _taps.add(payload);

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> init() async => launchedFor;

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return grant;
  }

  @override
  Future<bool?> permitted() async => grant;

  @override
  Future<void> show({
    required String key,
    required String title,
    required String body,
    required bool blocking,
  }) async => shown.add(Shown(key, title, body, blocking));

  @override
  Future<void> clear(String key) async => cleared.add(key);
}

class FakeBackgroundTime extends BackgroundTime {
  int begins = 0;
  int ends = 0;
  bool held = false;

  @override
  Future<void> begin() async {
    if (held) return;
    held = true;
    begins++;
  }

  @override
  Future<void> end() async {
    if (!held) return;
    held = false;
    ends++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late FakeHermesServer server;
  late FakeNotifier notifier;
  late FakeBackgroundTime background;

  setUp(() async {
    server = FakeHermesServer();
    await server.start();
    notifier = FakeNotifier();
    background = FakeBackgroundTime();
    Strings.current = const StringsCs();
  });

  tearDown(() => server.stop());

  Future<AppState> signedIn({
    bool lock = false,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'server_url': server.baseUrl.toString(),
      'username': 'u',
      'biometric_lock': lock,
      'auto_login': true,
      ...prefs,
    });
    FlutterSecureStorage.setMockInitialValues({'password': 'p'});
    final app = AppState(
      biometrics: FakeBiometrics(),
      notifier: notifier,
      backgroundTime: background,
    );
    await app.init();
    await settle(app);
    return app;
  }

  /// Opens the cto chat the way the hob list does, then leaves it.
  Future<ChatController> openChat(AppState app, {bool leave = true}) async {
    final hob = app.hobs.firstWhere((b) => b.name == 'cto');
    app.setOpenHob(hob.name);
    final chat = app.chatFor(hob);
    await waitFor(() => chat.ready);
    if (leave) app.setOpenHob(null);
    return chat;
  }

  test('a reply finished in the background notifies with a preview', () async {
    final app = await signedIn();
    final chat = await openChat(app, leave: false);

    await chat.send('ahoj');
    expect(notifier.permissionAsks, 1, reason: 'asked on the first prompt');
    app.onAppHidden();
    await waitFor(() => !chat.busy);
    await waitFor(() => notifier.shown.isNotEmpty);

    final n = notifier.shown.single;
    expect(n.key, 'hob:cto');
    expect(n.title, 'CTO');
    expect(n.body, 'Ahoj, svete!');
    expect(n.blocking, isFalse);

    // A second prompt does not ask again.
    await chat.send('znovu');
    await waitFor(() => !chat.busy);
    expect(notifier.permissionAsks, 1);
    app.dispose();
  });

  test('approval.request (canonical event) notifies while backgrounded and '
      'the reconnect snapshot does not repeat it', () async {
    server
      ..canonical = true
      ..askApproval = true;
    final app = await signedIn();
    final chat = await openChat(app, leave: false);
    app.onAppHidden();
    expect(background.begins, 0, reason: 'nothing streaming yet');

    unawaited(chat.send('ls'));
    await waitFor(() => chat.approval != null);
    await waitFor(() => notifier.shown.isNotEmpty);
    final n = notifier.shown.single;
    expect(n.title, 'CTO');
    expect(n.body, Strings.current.notifyApproval('ls /'));
    expect(n.blocking, isTrue);

    // The socket drops; the resume snapshot still lists the prompt.
    server.pendingPrompts = [
      {
        'prompt_id': 'p-approval',
        'kind': 'approval',
        'command': 'ls /',
        'choices': ['once', 'deny'],
      },
    ];
    final resumes = server.resumed.length;
    await server.dropConnections();
    await waitFor(() => server.resumed.length > resumes);
    await waitFor(() => chat.approval != null);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(notifier.shown, hasLength(1), reason: 'no duplicate on replay');
    app.dispose();
  });

  test('legacy approval server request notifies and keeps iOS time for the '
      'running turn', () async {
    server.askApproval = true;
    final app = await signedIn();
    final chat = await openChat(app);

    unawaited(chat.send('ls'));
    await waitFor(() => chat.busy);
    app.onAppHidden();
    expect(background.begins, 1, reason: 'a reply is still streaming');

    await waitFor(() => chat.approval != null);
    await waitFor(() => notifier.shown.isNotEmpty);
    expect(notifier.shown.single.body, Strings.current.notifyApproval('ls /'));

    chat.answerApproval('once');
    await waitFor(() => !chat.busy);
    await waitFor(() => notifier.shown.length == 2);
    expect(notifier.shown.last.body, 'Ahoj, svete!');
    expect(background.ends, 1, reason: 'released once the turn ended');

    // The next turn's request reuses the id (the fake server always sends
    // `srq-approval`, a real one may restart its count on a new socket):
    // it is a new prompt and must notify again.
    server.approvalAnswer = Completer();
    unawaited(chat.send('ls'));
    await waitFor(() => chat.approval != null);
    await waitFor(() => notifier.shown.length == 3);
    expect(notifier.shown.last.blocking, isTrue);
    chat.answerApproval('once');
    await waitFor(() => !chat.busy);
    app.dispose();
  });

  test(
    'the chat on screen does not notify; another hob\'s chat does',
    () async {
      final app = await signedIn();
      final chat = await openChat(app, leave: false);

      await chat.send('ahoj');
      await waitFor(() => !chat.busy);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifier.shown, isEmpty, reason: 'user is looking at it');

      // Still in the foreground, but looking at another hob.
      app.setOpenHob('default');
      await chat.send('znovu');
      await waitFor(() => !chat.busy);
      await waitFor(() => notifier.shown.length == 1);

      // Back to the cto chat: its notification goes away.
      notifier.cleared.clear();
      app.setOpenHob('cto');
      expect(notifier.cleared, ['hob:cto']);
      app.dispose();
    },
  );

  test('a request id reused after a reconnect notifies again', () async {
    server.askApproval = true;
    final app = await signedIn();
    final chat = await openChat(app);
    app.onAppHidden();

    unawaited(chat.send('ls'));
    await waitFor(() => notifier.shown.length == 1);

    // The socket drops before anyone answers; the turn is gone with it.
    final resumes = server.resumed.length;
    await server.dropConnections();
    await waitFor(() => server.resumed.length > resumes);
    await waitFor(() => !chat.busy);

    // The next turn's request arrives with the same id on the new socket.
    server.approvalAnswer = Completer();
    unawaited(chat.send('ls'));
    await waitFor(() => notifier.shown.where((n) => n.blocking).length == 2);
    chat.answerApproval('once');
    await waitFor(() => !chat.busy);
    app.dispose();
  });

  test('history replay on reconnect does not notify', () async {
    server.replayCompleteOnResume = true;
    final app = await signedIn();
    final chat = await openChat(app);
    expect(chat.messages, isNotEmpty);
    app.onAppHidden();

    final resumes = server.resumed.length;
    await server.dropConnections();
    await waitFor(() => server.resumed.length > resumes);
    await waitFor(() => app.connection == ConnectionStatus.connected);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(notifier.shown, isEmpty);
    app.dispose();
  });

  test('turned off in settings: nothing shows', () async {
    final app = await signedIn(prefs: {'notifications': false});
    expect(app.notificationsEnabled, isFalse);
    final chat = await openChat(app);
    app.onAppHidden();
    await chat.send('ahoj');
    await waitFor(() => !chat.busy);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifier.shown, isEmpty);
    expect(notifier.permissionAsks, 0);

    notifier.grant = false;
    await app.setNotificationsEnabled(true);
    expect(app.notificationsEnabled, isTrue);
    expect(app.notificationsBlocked, isTrue);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool('notifications'), isTrue);
    app.dispose();
  });

  test('a tapped notification opens the chat only after unlocking', () async {
    notifier.launchedFor = 'cto';
    final app = await signedIn(lock: true);
    expect(app.locked, isTrue);
    expect(app.pendingChat, 'cto');
    expect(app.takePendingChat(), isNull, reason: 'the lock comes first');

    await app.unlock();
    expect(app.takePendingChat()?.name, 'cto');
    expect(app.pendingChat, isNull);

    // A tap while running.
    notifier.tap('cto');
    await waitFor(() => app.pendingChat == 'cto');
    expect(app.takePendingChat()?.name, 'cto');

    // A hob that no longer exists is dropped.
    notifier.tap('gone');
    await waitFor(() => app.pendingChat == 'gone');
    expect(app.takePendingChat(), isNull);
    expect(app.pendingChat, isNull);
    app.dispose();
  });

  for (final canonical in [true, false]) {
    test('a Hob whose chat was never opened notifies an approval and a '
        'finished reply while backgrounded '
        '(${canonical ? 'canonical' : 'legacy'})', () async {
      server
        ..canonical = canonical
        ..history = [
          ...server.history,
          for (var i = 0; i < 50; i++) {'role': 'user', 'text': 'stara $i'},
        ];
      final app = await signedIn();
      // Watched without its history: the payload stays small.
      await waitFor(() => app.watchedHobs.contains('cto'));
      await waitFor(() => server.resumed.contains('botchat-tip'));
      final watch = server.resumeParams.singleWhere(
        (p) => p['session_id'] == 'botchat-tip',
      );
      expect(watch['omit_messages'], isTrue);
      expect(watch['profile'], 'cto');
      expect(app.watchedHobs, {'cto'}, reason: 'only Hobs with a Bot Chat');
      expect(
        server.calls.where((c) => c['method'] == 'model.options'),
        isEmpty,
        reason: 'a watcher skips the model reads',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(notifier.shown, isEmpty, reason: 'attaching alerts nothing');

      app.onAppHidden();
      unawaited(server.externalTurn('botchat-tip', approval: true));
      await waitFor(() => notifier.shown.isNotEmpty);
      final ask = notifier.shown.single;
      expect(ask.key, 'hob:cto');
      expect(ask.title, 'CTO');
      expect(ask.body, Strings.current.notifyApproval('rm -rf build'));
      expect(ask.blocking, isTrue);
      expect(background.begins, 0, reason: 'it ran before going away');

      server.approvalAnswer.complete({'choice': 'once'});
      await waitFor(() => notifier.shown.length == 2);
      final done = notifier.shown.last;
      expect(done.key, 'hob:cto');
      expect(done.body, 'Hotovo z dashboardu.');
      expect(done.blocking, isFalse);
      expect(notifier.permissionAsks, 0, reason: 'asked on a prompt only');

      // The socket drops and the watcher re-attaches: nothing repeats.
      server.replayCompleteOnResume = true;
      final resumes = server.resumed.length;
      await server.dropConnections();
      await waitFor(() => server.resumed.length > resumes);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(notifier.shown, hasLength(2));
      app.dispose();
    });
  }

  test(
    'opening a watched Hob loads its history and does not alert again',
    () async {
      final app = await signedIn();
      await waitFor(() => server.resumed.contains('botchat-tip'));
      app.onAppHidden();
      await server.externalTurn('botchat-tip');
      await waitFor(() => notifier.shown.length == 1);

      // The user taps it.
      app.onAppResumed();
      notifier.tap('hob:cto');
      await waitFor(() => app.pendingChat == 'cto');
      final hob = app.takePendingChat()!;
      app.setOpenHob(hob.name);
      expect(notifier.cleared, contains('hob:cto'));
      final chat = app.chatFor(hob);
      await waitFor(() => chat.ready && chat.messages.isNotEmpty);
      expect(chat.watchOnly, isFalse);
      expect(app.watchedHobs, isEmpty);
      expect(server.resumeParams.last['omit_messages'], isNull);
      expect(chat.messages.last.text, 'Monitoring sverim Analytikovi.');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(notifier.shown, hasLength(1));
      app.dispose();
    },
  );

  test('turning notifications off stops watching, on starts again', () async {
    final app = await signedIn();
    await waitFor(() => app.watchedHobs.contains('cto'));
    await app.setNotificationsEnabled(false);
    expect(app.watchedHobs, isEmpty);
    await server.externalTurn('botchat-tip');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(notifier.shown, isEmpty);

    await app.setNotificationsEnabled(true);
    expect(app.watchedHobs, {'cto'});
    app.dispose();
  });

  group('group chats', () {
    void addRoom(String id, {String name = 'Porada'}) {
      server.rooms[id] = {
        'room_id': id,
        'name': name,
        'members': [
          GroupMember.localSeat('cto'),
          GroupMember.localSeat('posta'),
        ],
        'authority_epoch': 1,
        'created_at': 1795205794,
        'updated_at': 1795205794,
      };
      server.roomLogs[id] = [];
    }

    setUp(() {
      server.roster.add({
        'name': 'posta',
        'ui_meta': {
          'hermes-bots': {'title': 'Pošta'},
        },
      });
    });

    test('a member message notifies while the group is not on screen, not '
        'when it is, and never twice', () async {
      addRoom('r1');
      final app = await signedIn();
      await waitFor(() => app.groups.isNotEmpty);

      // Another client's round: the app has never opened this group.
      server.postMemberMessage('r1', 'cto', '**Mám** hotovo.');
      await waitFor(() => notifier.shown.isNotEmpty);
      final n = notifier.shown.single;
      expect(n.key, 'group:r1');
      expect(n.title, 'Porada');
      expect(n.body, 'CTO: Mám hotovo.');
      expect(n.blocking, isFalse);

      // Replays: a reconnect, another groups.changed, a roster refresh.
      await server.dropConnections();
      await waitFor(() => app.connection == ConnectionStatus.connected);
      server.announceRoom('r1');
      await app.refreshGroups();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notifier.shown, hasLength(1), reason: 'nothing new');

      // Opened: its notification goes away and its messages stay quiet.
      final room = app.groupById('r1')!;
      final chat = app.groupChatFor(room);
      app.setOpenGroup('r1');
      expect(notifier.cleared, contains('group:r1'));
      await waitFor(() => !chat.loading);
      server.postMemberMessage('r1', 'posta', 'Vidím to.');
      await waitFor(() => chat.lastSeq == 2);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(notifier.shown, hasLength(1), reason: 'the user is looking');

      // The first message the user sends asks for the permission.
      await chat.send('díky');
      expect(notifier.permissionAsks, 1);
      await waitFor(() => chat.lastSeq == 8);
      expect(notifier.shown, hasLength(1));

      // In the background the open group notifies again.
      app.onAppHidden();
      server.postMemberMessage('r1', 'posta', 'Ještě jedna věc.');
      await waitFor(() => notifier.shown.length == 2);
      expect(notifier.shown.last.body, 'Pošta: Ještě jedna věc.');

      // Its log replays after a reconnect: nothing repeats.
      await server.dropConnections();
      await waitFor(() => app.connection == ConnectionStatus.connected);
      await chat.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notifier.shown, hasLength(2));
      app.dispose();
    });

    test('a pending approval in a group notifies once', () async {
      addRoom('r1');
      final app = await signedIn();
      await waitFor(() => app.groups.isNotEmpty);
      app.onAppHidden();

      server.groupPendingActions = [
        {
          'kind': 'approval',
          'member_id': 'cto',
          'task_id': 't1',
          'execution_generation': 1,
          'request_id': 'q1',
          'approval': {
            'command': 'ls /',
            'choices': ['once', 'deny'],
          },
        },
      ];
      server.announceRoom('r1');
      await waitFor(() => notifier.shown.isNotEmpty);
      final n = notifier.shown.single;
      expect(n.key, 'group:r1');
      expect(n.body, 'CTO: ${Strings.current.notifyApproval('ls /')}');
      expect(n.blocking, isTrue);

      server.announceRoom('r1');
      await waitFor(() => server.groupStateCalls.length >= 2);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(notifier.shown, hasLength(1));
      app.dispose();
    });

    test('turned off in settings: groups stay quiet', () async {
      addRoom('r1');
      final app = await signedIn(prefs: {'notifications': false});
      await waitFor(() => app.groups.isNotEmpty);
      server.postMemberMessage('r1', 'cto', 'Ahoj.');
      await waitFor(() => app.groupById('r1')?.latestSeq == 1);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(notifier.shown, isEmpty);
      expect(server.groupStateCalls, isEmpty, reason: 'no peeking');

      // What came while they were off is not news when they come back on.
      await app.setNotificationsEnabled(true);
      await app.refreshGroups();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(notifier.shown, isEmpty);
      app.dispose();
    });

    test(
      'a tapped group notification opens the group only after unlocking',
      () async {
        addRoom('r1');
        notifier.launchedFor = 'group:r1';
        final app = await signedIn(lock: true);
        expect(app.pendingGroup, 'r1');
        expect(app.pendingChat, isNull);
        expect(app.takePendingGroup(), isNull, reason: 'the lock comes first');

        await app.unlock();
        await waitFor(() => app.groups.isNotEmpty);
        expect(app.takePendingGroup()?.roomId, 'r1');
        expect(app.pendingGroup, isNull);

        // A tap while running; a Hob tap replaces a waiting group.
        notifier.tap('group:r1');
        await waitFor(() => app.pendingGroup == 'r1');
        notifier.tap('hob:cto');
        await waitFor(() => app.pendingChat == 'cto');
        expect(app.pendingGroup, isNull);
        expect(app.takePendingChat()?.name, 'cto');

        // A group that is gone is dropped.
        notifier.tap('group:gone');
        await waitFor(() => app.pendingGroup == 'gone');
        expect(app.takePendingGroup(), isNull);
        expect(app.pendingGroup, isNull);
        app.dispose();
      },
    );
  });

  test('notification preview flattens markdown and shortens', () {
    expect(notificationPreview('**Hotovo**\n\n- a\n- b'), 'Hotovo - a - b');
    expect(notificationPreview('[odkaz](https://x.cz) ok'), 'odkaz ok');
    final long = notificationPreview('x' * 300);
    expect(long.length, 140);
    expect(long.endsWith('…'), isTrue);
    expect(notificationId('hob:cto'), notificationId('hob:cto'));
    expect(notificationId('hob:cto'), isNot(notificationId('hob:default')));
    // A Hob keeps the id its notifications had before the `hob:` prefix.
    expect(notificationId('hob:cto'), notificationId('cto'));
    expect(notificationId('group:cto'), isNot(notificationId('hob:cto')));
    expect(NotifyTarget.parse('cto'), const NotifyTarget.hob('cto'));
    expect(NotifyTarget.parse('hob:cto'), const NotifyTarget.hob('cto'));
    expect(NotifyTarget.parse('group:r1'), const NotifyTarget.group('r1'));
    expect(NotifyTarget.parse('group:'), isNull);
  });
}
