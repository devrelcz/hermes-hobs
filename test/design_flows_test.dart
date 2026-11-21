import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/ui/format.dart';
import 'package:hobs/ui/hobs_screen.dart';
import 'package:hobs/ui/new_hob_screen.dart';
import 'package:hobs/ui/settings_screen.dart';
import 'package:hobs/ui/sheets.dart';
import 'package:hobs/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_hermes_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpList(WidgetTester tester, AppState app) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: const MaterialApp(home: HobsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppState signedIn() => AppState()
    ..phase = AuthPhase.signedIn
    ..hobs = [
      Hob(name: 'cto', displayName: 'CTO'),
      Hob(name: 'posta', displayName: 'Pošta'),
      Hob(name: 'dev', displayName: 'Dev'),
    ];

  testWidgets('the welcome shows once per device', (tester) async {
    await pumpList(tester, signedIn());
    expect(find.text('Vítej u Hobíků'), findsOneWidget);
    await tester.tap(find.text('Začít'));
    await tester.pumpAndSettle();
    expect(find.text('Vítej u Hobíků'), findsNothing);

    // A new screen (next launch) does not greet again.
    await tester.pumpWidget(const SizedBox());
    await pumpList(tester, signedIn());
    expect(find.text('Vítej u Hobíků'), findsNothing);
  });

  testWidgets('the welcome waits while signed out', (tester) async {
    await pumpList(
      tester,
      AppState()..hobs = [Hob(name: 'a', displayName: 'A')],
    );
    expect(find.text('Vítej u Hobíků'), findsNothing);
  });

  testWidgets('Ctrl+N opens a new Hob', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({'welcomeSeen': true});
    await pumpList(tester, signedIn());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(NewHobScreen), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a new group is picked from faces, two at least', (tester) async {
    SharedPreferences.setMockInitialValues({'welcomeSeen': true});
    await pumpList(tester, signedIn()..groupsSupported = true);
    await tester.tap(find.byTooltip('Vytvořit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nový skupinový chat'));
    await tester.pumpAndSettle();

    FilledButton create() =>
        tester.widget(find.widgetWithText(FilledButton, 'Vytvořit'));
    expect(create().onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('pick-cto')));
    await tester.pump();
    expect(create().onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('pick-posta')));
    await tester.pump();
    expect(create().onPressed, isNotNull);
    expect(find.text('Vybráno 2 z nejvýš 6, aspoň 2.'), findsOneWidget);
  });

  testWidgets('a text sheet keeps a bad link and says why', (tester) async {
    String? result = 'untouched';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showTextSheet(
              context,
              title: 'Link',
              action: 'Add',
              cancel: 'Cancel',
              validate: (v) => v.startsWith('https://') ? null : 'Bad link',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.text('Bad link'), findsOneWidget);
    expect(result, 'untouched');

    await tester.enterText(find.byType(TextField), 'https://example.com');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(result, 'https://example.com');
  });

  Color dotColor(WidgetTester tester) {
    final dot = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('connection-dot')),
    );
    return (dot.decoration! as BoxDecoration).color!;
  }

  testWidgets('the avatar dot is red while cut off', (tester) async {
    SharedPreferences.setMockInitialValues({'welcomeSeen': true});
    await pumpList(tester, signedIn());
    final cs = Theme.of(tester.element(find.byType(HobsScreen))).colorScheme;
    expect(dotColor(tester), cs.error);
    expect(find.byTooltip('Účet: Odpojeno'), findsOneWidget);
  });

  testWidgets('the avatar dot is green once connected', (tester) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({'welcomeSeen': true});
    FlutterSecureStorage.setMockInitialValues({});
    final server = FakeHermesServer();
    final app = AppState();
    await tester.runAsync(() async {
      await server.start();
      await app.login(
        serverUrl: server.baseUrl.toString(),
        username: 'u',
        password: 'p',
      );
      for (var i = 0; i < 40 && app.connection.name != 'connected'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: HobsTheme.lightTheme(),
          home: const HobsScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(dotColor(tester), HobsColors.light.working);
    expect(find.byTooltip('Účet: Připojeno'), findsOneWidget);
    await tester.runAsync(() async {
      app.dispose();
      await server.stop();
    });
  });

  test('days between messages are named like people say them', () {
    final now = DateTime(2026, 11, 21, 18); // a Saturday
    expect(dayLabel(DateTime(2026, 11, 21, 8), now: now), 'Dnes');
    expect(dayLabel(DateTime(2026, 11, 20, 23), now: now), 'Včera');
    expect(dayLabel(DateTime(2026, 11, 17, 9), now: now), 'Úterý');
    expect(dayLabel(DateTime(2026, 11, 2, 9), now: now), '2. 11.');
    expect(dayLabel(DateTime(2025, 12, 24, 9), now: now), '24. 12. 2025');
  });

  testWidgets('swiping a Hob right pins it, left hides it', (tester) async {
    SharedPreferences.setMockInitialValues({'welcomeSeen': true});
    final app = signedIn();
    await pumpList(tester, app);
    // Offline: the write is refused, so the snackbar proves the swipe ran.
    await tester.fling(find.text('Dev'), const Offset(300, 0), 1200);
    await tester.pumpAndSettle();
    expect(
      find.text('Změnu se nepodařilo uložit. Zkuste to znovu.'),
      findsOneWidget,
    );
    expect(find.text('Dev'), findsOneWidget, reason: 'the row springs back');

    // Left: the hide is tried (and, offline, refused and rolled back).
    final shown = <String>[];
    await tester.fling(find.text('Pošta'), const Offset(-300, 0), 1200);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      for (final w in tester.widgetList<SnackBar>(find.byType(SnackBar))) {
        final c = w.content;
        if (c is Text) shown.add(c.data ?? '');
      }
    }
    expect(shown, contains('Pošta je skrytý'));
    expect(app.hobNamed('posta')!.hidden, isFalse);
  });

  testWidgets('settings end with the app version and the licenses', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: signedIn()..username = 'daniel',
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Licence'), 200);
    expect(find.text('O aplikaci'), findsOneWidget);
    expect(find.text('Přihlášen jako'), findsOneWidget);
    expect(find.text('daniel'), findsOneWidget);
  });
}
