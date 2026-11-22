import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/ui/chat_screen.dart';
import 'package:hobs/state/composer_draft.dart';
import 'package:hobs/state/chat_controller.dart';
import 'package:hobs/api/hermes_rpc.dart';
import 'package:hobs/api/hermes_http.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/ui/avatar_bitmap.dart';
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
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message!.endsWith(', Odpojeno'),
      ),
      findsOneWidget,
    );
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
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message!.endsWith(', Připojeno'),
      ),
      findsOneWidget,
    );
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
    expect(find.text('Neoficiální komunitní aplikace'), findsOneWidget);
    expect(find.textContaining('Nous Research'), findsOneWidget);
    expect(find.text('Přihlášen jako'), findsOneWidget);
    expect(find.text('daniel'), findsOneWidget);
  });

  testWidgets('a Hob face renders to a PNG for notifications', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final bytes = await tester.runAsync(
      () => AvatarBitmaps.of(Hob(name: 'cto', displayName: 'CTO'), size: 48),
    );
    expect(bytes, isNotNull);
    expect(bytes!.sublist(1, 4), 'PNG'.codeUnits);
  });

  testWidgets('a screen reader hears a Hob row as one item with actions', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({'welcomeSeen': true});
    await pumpList(tester, signedIn());
    final row = find.bySemanticsLabel(RegExp(r'^CTO, '));
    expect(row, findsOneWidget);
    final node = tester.getSemantics(row);
    final labels = node
        .getSemanticsData()
        .customSemanticsActionIds!
        .map((id) => CustomSemanticsAction.getAction(id)!.label)
        .toList();
    expect(labels, containsAll(['Připnout', 'Skrýt']));
    expect(node.getSemanticsData().label, contains('Zatím bez zpráv'));
    handle.dispose();
  });

  testWidgets('search in a chat counts the hits and keeps the composer', (
    tester,
  ) async {
    HttpOverrides.global = null;
    late FakeHermesServer server;
    late HermesRpc rpc;
    late HermesHttp http;
    late ChatController chat;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await tester.runAsync(() async {
      server = FakeHermesServer()
        ..history = [
          {'role': 'user', 'text': 'Kdy je záloha?', 'timestamp': now - 90},
          {
            'role': 'assistant',
            'text': 'Záloha je v noci.',
            'timestamp': now - 60,
          },
          {'role': 'user', 'text': 'Díky', 'timestamp': now - 30},
        ];
      await server.start();
      http = HermesHttp(baseUrl: server.baseUrl);
      await http.postJson('/auth/password-login', {
        'provider': 'basic',
        'username': 'u',
        'password': 'p',
        'next': '',
      });
      rpc = HermesRpc(http);
      await rpc.connect();
      final res =
          await rpc.request('profiles.list', {'include_sessions': true}) as Map;
      final roster = (res['profiles'] as List)
          .cast<Map<String, dynamic>>()
          .map(Hob.fromJson)
          .toList();
      chat = ChatController(rpc: rpc, hob: roster.first, roster: () => roster);
      await chat.start();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: chat),
          ChangeNotifierProvider(create: (_) => ComposerDraft(null)),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            Strings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: Strings.supportedLocales,
          locale: Locale('cs'),
          home: ChatView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'rozepsáno');
    await tester.tap(find.byTooltip('Další možnosti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hledat v konverzaci'));
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(TextField),
    );
    expect(
      tester.widget<TextField>(field).focusNode!.hasFocus,
      isTrue,
      reason: 'typing goes to the search, not the composer',
    );
    await tester.enterText(field, 'ZÁLOH');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 z 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Zavřít'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 z 2'), findsNothing);
    expect(find.text('rozepsáno'), findsOneWidget);
    await tester.runAsync(() async {
      await rpc.dispose();
      http.close();
      await server.stop();
    });
  });
}
