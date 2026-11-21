import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/hermes_rpc.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/l10n/strings_cs.dart';
import 'package:hobs/l10n/strings_en.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/ui/format.dart';
import 'package:hobs/ui/login_screen.dart';
import 'package:hobs/ui/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credentials_test.dart' show settle;
import 'fake_hermes_server.dart';

Widget _app(AppState state, Widget home) => ChangeNotifierProvider.value(
  value: state,
  child: Consumer<AppState>(
    builder: (_, app, _) => MaterialApp(
      locale: app.languageCode == null ? null : Locale(app.languageCode!),
      supportedLocales: Strings.supportedLocales,
      localizationsDelegates: const [
        Strings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      localeListResolutionCallback: (locales, _) => Strings.resolve(locales),
      home: home,
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => Strings.current = const StringsCs());

  test('a chat header says when the Hob was last active, in words', () {
    final now = DateTime(2026, 11, 21, 12);
    const cs = StringsCs();
    String ago(Duration d) => cs.activeSince(now.subtract(d), now: now);
    expect(ago(const Duration(seconds: 20)), 'aktivní právě teď');
    expect(ago(const Duration(minutes: 5)), 'aktivní před 5 min');
    expect(ago(const Duration(hours: 3)), 'aktivní před 3 h');
    expect(ago(const Duration(hours: 30)), 'aktivní včera');
    expect(ago(const Duration(days: 4)), 'aktivní před 4 dny');
    expect(ago(const Duration(days: 12)), 'naposledy aktivní 9. 11.');
    expect(
      const StringsEn().activeSince(
        now.subtract(const Duration(days: 4)),
        now: now,
      ),
      'active 4 days ago',
    );
  });

  test('connection failures are worded in the app language', () {
    final offline = RpcException.local(
      RpcLocalFailure.notConnected,
      -1,
      'Not connected',
    );
    final dropped = RpcException.local(
      RpcLocalFailure.connectionClosed,
      -1,
      'Connection closed',
    );
    final slow = RpcException.local(RpcLocalFailure.timedOut, -2, 'x');
    Strings.current = const StringsCs();
    expect(
      AppState.describeError(offline),
      'Aplikace není připojená k serveru.',
    );
    expect(
      AppState.describeError(dropped),
      'Spojení se serverem se přerušilo.',
    );
    expect(AppState.describeError(slow), 'Vypršel časový limit.');
    Strings.current = const StringsEn();
    expect(
      AppState.describeError(offline),
      'The app is not connected to the server.',
    );
    // A server's own answer is shown as it came.
    expect(AppState.describeError(RpcException(4004, 'quota')), 'quota');
  });

  test('device languages resolve to a language pack', () {
    expect(Strings.resolve(const [Locale('cs', 'CZ')]).languageCode, 'cs');
    expect(Strings.resolve(const [Locale('sk')]).languageCode, 'cs');
    expect(Strings.resolve(const [Locale('en', 'GB')]).languageCode, 'en');
    expect(Strings.resolve(const [Locale('de')]).languageCode, 'en');
    expect(
      Strings.resolve(const [Locale('de'), Locale('cs')]).languageCode,
      'cs',
    );
    expect(Strings.resolve(null).languageCode, 'en');
  });

  test('czech counts new messages in the right case', () {
    const cs = StringsCs();
    expect(cs.newMessages(1), '1 nová');
    expect(cs.newMessages(3), '3 nové');
    expect(cs.newMessages(5), '5 nových');
  });

  testWidgets('login follows the device language', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(_app(AppState(), const LoginScreen()));
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Přihlásit'), findsNothing);

    tester.platformDispatcher.localesTestValue = const [Locale('cs', 'CZ')];
    await tester.pumpAndSettle();
    expect(find.text('Přihlásit'), findsOneWidget);
  });

  testWidgets('settings switch the language and remember it', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('cs', 'CZ')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final state = AppState();
    await tester.pumpWidget(_app(state, const SettingsScreen()));
    expect(find.text('Nastavení'), findsOneWidget);
    expect(find.text('Teď: Čeština'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(state.languageCode, 'en');
    expect(Strings.current.code, 'en');
    final now = DateTime(2026, 11, 20, 16);
    expect(dayTime(DateTime(2026, 11, 21, 9), now: now), 'tomorrow 09:00');
    expect(dayTime(DateTime(2026, 12, 24, 9), now: now), '24 Dec 09:00');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('language'), 'en');

    await tester.tap(find.text('Same as device'));
    await tester.pumpAndSettle();
    expect(find.text('Nastavení'), findsOneWidget);
    expect(state.languageCode, isNull);
    expect(prefs.getString('language'), isNull);
  });

  test('a stored error follows a language switch', () async {
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({});
    final server = FakeHermesServer();
    await server.start();
    final app = AppState();
    addTearDown(app.dispose);
    await app.setLanguage('cs');
    await app.login(
      serverUrl: server.baseUrl.toString(),
      username: 'u',
      password: 'p',
    );
    await settle(app);

    // The upgraded socket outlives the HTTP server; drop it too.
    await server.stop();
    await server.dropConnections();
    await app.refreshHobs();
    expect(app.hobsError, startsWith('Server nedostupný: '));

    await app.setLanguage('en');
    expect(app.hobsError, startsWith("Can't reach the server: "));
  });
}
