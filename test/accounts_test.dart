import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/hermes_rpc.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/l10n/strings_cs.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/state/credentials_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'biometric_lock_test.dart' show FakeBiometrics;
import 'credentials_test.dart' show settle;
import 'fake_hermes_server.dart';
import 'notifications_test.dart' show FakeNotifier, FakeBackgroundTime;

/// Several Hermes servers, each under its own name; only the active one is
/// connected.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late FakeHermesServer home;
  late FakeHermesServer work;
  late FakeNotifier notifier;

  setUp(() async {
    home = FakeHermesServer();
    work = FakeHermesServer();
    await home.start();
    await work.start();
    notifier = FakeNotifier();
    Strings.current = const StringsCs();
  });

  tearDown(() async {
    await home.stop();
    await work.stop();
  });

  AppState newApp(CredentialsStore store) => AppState(
    store: store,
    biometrics: FakeBiometrics(kind: null),
    notifier: notifier,
    backgroundTime: FakeBackgroundTime(),
  );

  /// The app as it was before accounts: one sign-in under the bare keys.
  Future<(AppState, CredentialsStore)> legacySignedIn() async {
    SharedPreferences.setMockInitialValues({
      'server_url': home.baseUrl.toString(),
      'username': 'u',
    });
    FlutterSecureStorage.setMockInitialValues({'password': 'p'});
    final store = CredentialsStore();
    final app = newApp(store);
    await app.init();
    await settle(app);
    return (app, store);
  }

  test('the existing sign-in becomes the first account as it is', () async {
    final (app, store) = await legacySignedIn();
    expect(app.phase, AuthPhase.signedIn);
    expect(app.accounts, hasLength(1));
    final first = app.accounts.single;
    expect(first.id, '');
    expect(first.serverUrl, home.baseUrl.toString());
    expect(first.username, 'u');
    expect(first.label, home.baseUrl.host);
    // Still under the original keys: nothing had to move.
    expect(await store.password(), 'p');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('accounts'), isNotNull);
    app.dispose();
  });

  test('adding a server signs in there and keeps the first one', () async {
    final (app, store) = await legacySignedIn();
    await app.addAccount(
      name: 'Práce',
      color: accountColors[1],
      serverUrl: work.baseUrl.toString(),
      username: 'u',
      password: 'p',
    );
    await settle(app);
    expect(app.accounts.map((a) => a.label), [home.baseUrl.host, 'Práce']);
    final added = app.accounts.last;
    expect(added.id, isNotEmpty);
    expect(app.activeId, added.id);
    expect(app.serverUrl, work.baseUrl.toString());
    expect(app.connection, ConnectionStatus.connected);
    expect(notifier.clearedAll, 1, reason: 'old notifications would mislead');
    // Each account keeps its own secrets.
    expect(await store.password(account: ''), 'p');
    expect(await store.password(account: added.id), 'p');
    expect(await store.cookies(account: ''), isNotEmpty);
    expect(await store.cookies(account: added.id), isNotEmpty);

    // Back to the first: its session cookies still work, no new password
    // sign-in.
    final logins = home.passwordLogins;
    await app.switchAccount('');
    await settle(app);
    expect(app.phase, AuthPhase.signedIn);
    expect(app.serverUrl, home.baseUrl.toString());
    expect(home.passwordLogins, logins);

    // The choice survives a restart.
    await app.switchAccount(added.id);
    await settle(app);
    final again = newApp(store);
    await again.init();
    await settle(again);
    expect(again.activeId, added.id);
    expect(again.serverUrl, work.baseUrl.toString());
    app.dispose();
    again.dispose();
  });

  test('a wrong password saves nothing and leaves the session up', () async {
    final (app, _) = await legacySignedIn();
    await expectLater(
      app.addAccount(
        name: 'Práce',
        color: accountColors[1],
        serverUrl: work.baseUrl.toString(),
        username: 'u',
        password: 'wrong',
      ),
      throwsA(isA<Exception>()),
    );
    expect(app.accounts, hasLength(1));
    expect(app.activeId, '');
    expect(app.phase, AuthPhase.signedIn);
    expect(app.connection, ConnectionStatus.connected);
    expect(app.hobs, isNotEmpty);
    expect(notifier.clearedAll, 0);
    app.dispose();
  });

  test('the login form adds a new server as its own account', () async {
    final (app, _) = await legacySignedIn();
    await app.logout();
    await app.login(
      serverUrl: work.baseUrl.toString(),
      username: 'u',
      password: 'p',
    );
    await settle(app);
    expect(app.accounts, hasLength(2));
    expect(app.activeAccount!.serverUrl, work.baseUrl.toString());
    // Signing in to a saved server again does not duplicate it.
    await app.logout();
    await app.login(
      serverUrl: '${home.baseUrl}/',
      username: 'u',
      password: 'p',
    );
    await settle(app);
    expect(app.accounts, hasLength(2));
    expect(app.activeId, '');
    app.dispose();
  });

  test('picking a signed-out account signs it in with its password', () async {
    final (app, _) = await legacySignedIn();
    await app.addAccount(
      name: 'Práce',
      color: accountColors[1],
      serverUrl: work.baseUrl.toString(),
      username: 'u',
      password: 'p',
    );
    await settle(app);
    final workId = app.activeId;
    await app.logout();
    expect(app.phase, AuthPhase.signedOut);
    // From the login list: the signed-out account has no session left but
    // keeps its password, and picking it is asking to sign in.
    final logins = work.passwordLogins;
    await app.switchAccount(workId, showLoading: false);
    await settle(app);
    expect(app.phase, AuthPhase.signedIn);
    expect(work.passwordLogins, logins + 1);
    // The other one still has its session.
    await app.switchAccount('', showLoading: false);
    await settle(app);
    expect(app.serverUrl, home.baseUrl.toString());
    app.dispose();
  });

  test('renaming, recoloring and reordering are kept', () async {
    final (app, store) = await legacySignedIn();
    await app.addAccount(
      name: 'Práce',
      color: accountColors[1],
      serverUrl: work.baseUrl.toString(),
      username: 'u',
      password: 'p',
    );
    await settle(app);
    await app.updateAccount('', name: 'Doma', color: accountColors[3]);
    await app.reorderAccounts(1, 0);
    final again = newApp(store);
    await again.init();
    await settle(again);
    expect(again.accounts.map((a) => a.label), ['Práce', 'Doma']);
    expect(again.accountById('')!.color, accountColors[3]);
    app.dispose();
    again.dispose();
  });

  test('a new password is kept only when the server takes it', () async {
    final (app, store) = await legacySignedIn();
    await expectLater(
      app.setAccountPassword('', 'wrong'),
      throwsA(isA<Exception>()),
    );
    expect(await store.password(account: ''), 'p');
    await app.setAccountPassword('', 'p');
    expect(app.savedPassword, 'p');
    app.dispose();
  });

  test('removing accounts forgets their secrets on this device', () async {
    final (app, store) = await legacySignedIn();
    await app.addAccount(
      name: 'Práce',
      color: accountColors[1],
      serverUrl: work.baseUrl.toString(),
      username: 'u',
      password: 'p',
    );
    await settle(app);
    final workId = app.activeId;

    // A waiting account goes quietly.
    await app.switchAccount('');
    await settle(app);
    await app.removeAccount(workId);
    expect(app.accounts.map((a) => a.id), ['']);
    expect(await store.password(account: workId), isNull);
    expect(await store.cookies(account: workId), isEmpty);
    expect(app.phase, AuthPhase.signedIn);

    // The last one leaves an empty login form.
    await app.removeAccount('');
    expect(app.accounts, isEmpty);
    expect(app.phase, AuthPhase.signedOut);
    expect(app.serverUrl, isEmpty);
    expect(await store.password(account: ''), isNull);
    app.dispose();
  });

  test('removing the active account moves to the next one', () async {
    final (app, _) = await legacySignedIn();
    await app.addAccount(
      name: 'Práce',
      color: accountColors[1],
      serverUrl: work.baseUrl.toString(),
      username: 'u',
      password: 'p',
    );
    await settle(app);
    final workId = app.activeId;
    await app.removeAccount(workId);
    await settle(app);
    expect(app.activeId, '');
    expect(app.phase, AuthPhase.signedIn);
    expect(app.serverUrl, home.baseUrl.toString());
    app.dispose();
  });
}
