import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/l10n/strings_cs.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/state/credentials_store.dart';
import 'package:hobs/state/pairing.dart';
import 'package:hobs/ui/accounts_ui.dart';
import 'package:hobs/ui/login_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'biometric_lock_test.dart' show FakeBiometrics;
import 'notifications_test.dart' show FakeNotifier, FakeBackgroundTime;

/// Pairing: a server's QR code carries its address and the sign-in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  String code(Map<String, Object?> fields) => jsonEncode(fields);

  PairingFailure failureOf(String raw) {
    try {
      PairingCode.parse(raw);
    } on PairingException catch (e) {
      return e.failure;
    }
    fail('accepted: $raw');
  }

  test('reads the code pair.sh draws', () {
    final c = PairingCode.parse(
      '{"v":1,"url":"https://agent.example.com","user":"admin","password":"p w/+=\\"x"}',
    );
    expect(c.serverUrl, 'https://agent.example.com');
    expect(c.username, 'admin');
    expect(c.password, 'p w/+="x');
  });

  test('refuses what is not a pairing code', () {
    for (final raw in [
      '',
      'https://example.com',
      '[1]',
      '"text"',
      code({'url': 'https://a.example', 'user': 'u', 'password': 'p'}),
      code({
        'v': '1',
        'url': 'https://a.example',
        'user': 'u',
        'password': 'p',
      }),
      code({'v': 0, 'url': 'https://a.example', 'user': 'u', 'password': 'p'}),
      code({'v': 1, 'url': 'a.example', 'user': 'u', 'password': 'p'}),
      code({'v': 1, 'url': 'ftp://a.example', 'user': 'u', 'password': 'p'}),
      code({'v': 1, 'url': 'https://a.example', 'user': ' ', 'password': 'p'}),
      code({'v': 1, 'url': 'https://a.example', 'user': 'u', 'password': ''}),
      code({'v': 1, 'url': 'https://a.example', 'user': 'u'}),
      code({'v': 1, 'url': 'https://a.example', 'user': 'u', 'password': 7}),
    ]) {
      expect(failureOf(raw), PairingFailure.notPairing, reason: raw);
    }
  });

  test('a newer format asks for an update, whatever else it holds', () {
    expect(
      failureOf(code({'v': 2, 'url': 'https://a.example', 'token': 't'})),
      PairingFailure.newerVersion,
    );
  });

  group('login screen', () {
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

    Widget screen(AppState app, Future<PairingCode?> Function() scan) =>
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(home: LoginScreen(scanPairingCode: (_) => scan())),
        );

    testWidgets('a scanned code fills the form and signs in with it', (
      tester,
    ) async {
      final app = newApp();
      await tester.runAsync(app.init);
      // Nothing listens there: the sign-in is tried and refused at once,
      // which leaves the filled form on screen.
      const code = PairingCode(
        serverUrl: 'http://127.0.0.1:1',
        username: 'admin',
        password: 'from the code',
      );
      await tester.pumpWidget(screen(app, () async => code));
      await tester.ensureVisible(find.byIcon(Icons.qr_code_scanner));
      await tester.tap(find.byIcon(Icons.qr_code_scanner));
      // The attempt is real I/O: let it run between frames.
      for (
        var i = 0;
        i < 100 && find.byType(FormErrorBox).evaluate().isEmpty;
        i++
      ) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(find.byType(FormErrorBox), findsOneWidget);
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .map((f) => f.controller!.text)
          .toList();
      expect(fields, ['http://127.0.0.1:1', 'admin', 'from the code']);
      expect(app.phase, AuthPhase.signedOut);
      app.dispose();
    });

    testWidgets('backing out of the scanner changes nothing', (tester) async {
      final app = newApp();
      await tester.runAsync(app.init);
      await tester.pumpWidget(screen(app, () async => null));
      await tester.ensureVisible(find.byIcon(Icons.qr_code_scanner));
      await tester.tap(find.byIcon(Icons.qr_code_scanner));
      await tester.pump();
      expect(app.phase, AuthPhase.signedOut);
      expect(find.byType(FormErrorBox), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).last)
            .controller!
            .text,
        isEmpty,
      );
      app.dispose();
    });
  });
}
