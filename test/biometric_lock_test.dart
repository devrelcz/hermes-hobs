import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/state/biometrics.dart';
import 'package:hobs/state/credentials_store.dart';
import 'package:hobs/ui/login_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credentials_test.dart' show settle, waitFor;
import 'fake_hermes_server.dart';

/// A device with Face ID whose answer the test decides.
class FakeBiometrics extends Biometrics {
  FakeBiometrics({this.kind = BiometricKind.faceId});

  BiometricKind? kind;
  BiometricFailure? nextFailure;
  int prompts = 0;

  @override
  Future<BiometricKind?> available() async => kind;

  @override
  Future<void> authenticate(String reason) async {
    prompts++;
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw BiometricException(failure);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late FakeHermesServer server;

  setUp(() async {
    server = FakeHermesServer();
    await server.start();
  });

  tearDown(() => server.stop());

  void seed({bool lock = false, bool autoLogin = true}) {
    SharedPreferences.setMockInitialValues({
      'server_url': server.baseUrl.toString(),
      'username': 'u',
      'biometric_lock': lock,
      'auto_login': autoLogin,
    });
    FlutterSecureStorage.setMockInitialValues({'password': 'p'});
  }

  test('the lock is off until turned on', () async {
    seed();
    final app = AppState(biometrics: FakeBiometrics());
    await app.init();
    expect(app.phase, AuthPhase.signedIn);
    expect(app.locked, isFalse);
    expect(app.biometricKind, BiometricKind.faceId);
    await settle(app);
    app.dispose();
  });

  test('turning the lock on needs a successful prompt', () async {
    seed();
    final bio = FakeBiometrics();
    final store = CredentialsStore();
    final app = AppState(store: store, biometrics: bio);
    await app.init();
    await settle(app);

    bio.nextFailure = BiometricFailure.failed;
    await expectLater(
      app.setBiometricLock(true),
      throwsA(isA<BiometricException>()),
    );
    expect(app.biometricLock, isFalse);
    expect(await store.biometricLock(), isFalse);

    await app.setBiometricLock(true);
    expect(app.biometricLock, isTrue);
    expect(await store.biometricLock(), isTrue);
    expect(app.locked, isFalse, reason: 'the user just proved who they are');

    final prompts = bio.prompts;
    await app.setBiometricLock(false);
    expect(bio.prompts, prompts, reason: 'turning it off asks nothing');
    expect(await store.biometricLock(), isFalse);
    app.dispose();
  });

  test('with the lock on, startup stays locked until verified', () async {
    seed(lock: true);
    final bio = FakeBiometrics();
    final app = AppState(biometrics: bio);
    await app.init();
    expect(app.phase, AuthPhase.signedIn);
    expect(app.locked, isTrue);

    bio.nextFailure = BiometricFailure.cancelled;
    await expectLater(app.unlock(), throwsA(isA<BiometricException>()));
    expect(app.locked, isTrue);

    await app.unlock();
    expect(app.locked, isFalse);
    await settle(app);
    app.dispose();
  });

  test(
    'coming back after a while locks again, a quick switch does not',
    () async {
      seed(lock: true);
      final app = AppState(biometrics: FakeBiometrics());
      await app.init();
      await app.unlock();
      await settle(app);

      app.onAppHidden();
      app.onAppResumed();
      expect(app.locked, isFalse);

      app.relockAfter = Duration.zero;
      app.onAppHidden();
      app.onAppResumed();
      expect(app.locked, isTrue);
      // Resuming refreshes the roster; let it land before disposing.
      await waitFor(() => !app.loadingHobs);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await settle(app);
      app.dispose();
    },
  );

  test('signed out with the lock on, the biometric signs back in', () async {
    seed(lock: true, autoLogin: false);
    final bio = FakeBiometrics();
    final app = AppState(biometrics: bio);
    await app.init();
    expect(app.phase, AuthPhase.signedOut);
    expect(app.canBiometricSignIn, isTrue);

    bio.nextFailure = BiometricFailure.failed;
    await expectLater(
      app.biometricSignIn(),
      throwsA(isA<BiometricException>()),
    );
    expect(app.phase, AuthPhase.signedOut);

    await app.biometricSignIn();
    expect(app.phase, AuthPhase.signedIn);
    expect(app.locked, isFalse);
    await settle(app);
    app.dispose();
  });

  test('no biometric sign-in without a face or finger enrolled', () async {
    seed(lock: true, autoLogin: false);
    final app = AppState(biometrics: FakeBiometrics(kind: null));
    await app.init();
    expect(app.canBiometricSignIn, isFalse);
    app.dispose();
  });

  testWidgets('login form hides the saved password behind Face ID', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    seed(lock: true, autoLogin: false);
    final biometrics = FakeBiometrics();
    final app = AppState(biometrics: biometrics);
    await tester.runAsync(app.init);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: const MaterialApp(
          localizationsDelegates: [
            Strings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: Strings.supportedLocales,
          home: LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The saved account comes first, signed in through Face ID; backing
    // out of the prompt opens its form.
    expect(find.text('Saved accounts'), findsOneWidget);
    expect(find.byIcon(Icons.face_outlined), findsOneWidget);
    biometrics.nextFailure = BiometricFailure.cancelled;
    await tester.tap(find.text(server.baseUrl.host));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(biometrics.prompts, 1);
    expect(find.text('Sign in with Face ID'), findsOneWidget);
    final password = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Password'),
        matching: find.byType(EditableText),
      ),
    );
    expect(password.controller.text, isEmpty);
    app.dispose();
  });
}
