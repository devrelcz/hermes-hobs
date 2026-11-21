import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/demo/demo_hermes.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/l10n/strings_cs.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/state/credentials_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'biometric_lock_test.dart' show FakeBiometrics;
import 'credentials_test.dart' show settle;
import 'notifications_test.dart' show FakeNotifier, FakeBackgroundTime;

/// Demo mode: the app signs in to the demo server built into it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    Strings.current = const StringsCs();
  });

  AppState newApp() => AppState(
    store: CredentialsStore(),
    biometrics: FakeBiometrics(kind: null),
    notifier: FakeNotifier(),
    backgroundTime: FakeBackgroundTime(),
  );

  test('the demo signs in as an account with the demo Hobs', () async {
    final app = newApp();
    await app.init();
    expect(app.phase, AuthPhase.signedOut);

    await app.tryDemo();
    await settle(app);
    expect(app.phase, AuthPhase.signedIn);
    final demo = app.accounts.single;
    expect(demo.serverUrl, DemoHermes.url);
    expect(demo.label, 'Demo');
    expect(
      app.hobs.map((h) => h.name),
      containsAll(['research', 'mail', 'ops', 'writer']),
    );
    app.dispose();
  });

  test('the saved demo account opens again after a restart', () async {
    final first = newApp();
    await first.init();
    await first.tryDemo();
    await settle(first);
    first.dispose();

    final again = newApp();
    await again.init();
    await settle(again);
    expect(again.phase, AuthPhase.signedIn);
    expect(again.hobs, isNotEmpty);
    again.dispose();
  });

  test('trying the demo twice keeps one demo account', () async {
    final app = newApp();
    await app.init();
    await app.tryDemo();
    await settle(app);
    await app.tryDemo();
    await settle(app);
    expect(app.accounts, hasLength(1));
    app.dispose();
  });
}
