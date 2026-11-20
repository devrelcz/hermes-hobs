import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
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
  Shown(this.hob, this.title, this.body, this.blocking);

  final String hob;
  final String title;
  final String body;
  final bool blocking;

  @override
  String toString() => '$hob: $title / $body';
}

/// Records what the app would show instead of calling the plugin.
class FakeNotifier implements Notifier {
  final shown = <Shown>[];
  final cleared = <String>[];
  final _taps = StreamController<String>.broadcast();
  String? launchedFor;
  bool grant = true;
  int permissionAsks = 0;

  void tap(String hob) => _taps.add(hob);

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
    required String hob,
    required String title,
    required String body,
    required bool blocking,
  }) async => shown.add(Shown(hob, title, body, blocking));

  @override
  Future<void> clear(String hob) async => cleared.add(hob);
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
    expect(n.hob, 'cto');
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
    await server.dropSockets();
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
      expect(notifier.cleared, ['cto']);
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
    await server.dropSockets();
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
    await server.dropSockets();
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

  test('notification preview flattens markdown and shortens', () {
    expect(notificationPreview('**Hotovo**\n\n- a\n- b'), 'Hotovo - a - b');
    expect(notificationPreview('[odkaz](https://x.cz) ok'), 'odkaz ok');
    final long = notificationPreview('x' * 300);
    expect(long.length, 140);
    expect(long.endsWith('…'), isTrue);
    expect(notificationId('cto'), notificationId('cto'));
    expect(notificationId('cto'), isNot(notificationId('default')));
  });
}
