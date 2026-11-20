import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/hermes_http.dart';
import 'package:hobs/api/hermes_rpc.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/state/chat_controller.dart';
import 'package:hobs/state/composer_draft.dart';
import 'package:hobs/state/mentions.dart';
import 'package:hobs/ui/chat_screen.dart';
import 'package:provider/provider.dart';

import 'fake_hermes_server.dart';

Hob hob(
  String name, {
  String title = '',
  String displayName = '',
  List<String> previous = const [],
}) => Hob.fromJson({
  'name': name,
  'display_name': displayName,
  if (previous.isNotEmpty) 'previous_names': previous,
  'ui_meta': {
    'hermes-bots': {if (title.isNotEmpty) 'title': title},
  },
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Widget tests stub HttpClient; the fake server needs real sockets.
  HttpOverrides.global = null;

  group('Mentions', () {
    final cto = hob('cto', title: 'CTO');
    final buddy = hob('research', title: 'Research Buddy');
    final main = hob('default');
    final roster = [cto, buddy, main];

    test('tags use the friendly name, the default profile is @hermes', () {
      expect(Mentions.tag(cto, roster), 'cto');
      expect(Mentions.tag(buddy, roster), 'research-buddy');
      expect(Mentions.tag(main, roster), 'hermes');
      // A real "hermes" profile keeps @hermes; the default answers to its name.
      final taken = [...roster, hob('hermes')];
      expect(Mentions.handle(main, taken), 'default');
    });

    test('the @word under the cursor opens the picker', () {
      expect(Mentions.activeQuery('ahoj @re', 8), (start: 5, query: 're'));
      expect(Mentions.activeQuery('@', 1), (start: 0, query: ''));
      expect(Mentions.activeQuery('mail@example', 12), isNull);
      expect(Mentions.activeQuery('@cto hotovo', 11), isNull);
    });

    test('candidates skip the open Hob and match by prefix', () {
      expect(Mentions.candidates('', roster, 'cto'), [buddy, main]);
      expect(Mentions.candidates('res', roster, 'cto'), [buddy]);
      expect(Mentions.candidates('her', roster, 'cto'), [main]);
      expect(Mentions.candidates('xyz', roster, 'cto'), isEmpty);
    });

    test('resolve finds every form, once, outside code', () {
      expect(
        Mentions.resolve(
          '@researchbuddy a @research, pak @hermes',
          roster,
          'cto',
        ),
        [buddy, main],
      );
      expect(Mentions.resolve('`@hermes` a mail@cto.cz', roster, 'cto'), []);
      // A Hob does not tag itself.
      expect(Mentions.resolve('@cto', roster, 'cto'), []);
      // Old names still resolve.
      final renamed = hob('analyst', previous: ['analytik']);
      expect(Mentions.resolve('@analytik', [cto, renamed], 'cto'), [renamed]);
    });

    test('annotate adds the dashboard note and stripNote removes it', () {
      expect(Mentions.annotate('bez zmínky', roster, 'cto'), 'bez zmínky');
      expect(Mentions.annotate('@nikdo ahoj', roster, 'cto'), '@nikdo ahoj');
      final sent = Mentions.annotate(
        '@research-buddy zjisti to',
        roster,
        'cto',
      );
      expect(
        sent,
        startsWith(
          '@research-buddy zjisti to\n\n'
          '[@mentions resolved from the Bot Mode roster — the user is '
          'referring to: @research = agent profile "research" '
          '("Research Buddy"). If they want',
        ),
      );
      expect(sent, contains('message_agent tool'));
      expect(Mentions.stripNote(sent), '@research-buddy zjisti to');
    });
  });

  group('chat', () {
    late FakeHermesServer server;
    late HermesHttp http;
    late HermesRpc rpc;
    late List<Hob> roster;

    Future<void> connect() async {
      server = FakeHermesServer();
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
      roster = (res['profiles'] as List)
          .cast<Map<String, dynamic>>()
          .map(Hob.fromJson)
          .where((b) => !b.hidden)
          .toList();
    }

    Future<void> disconnect() async {
      await rpc.dispose();
      http.close();
      await server.stop();
    }

    test(
      'a tagged Hob adds the note to the prompt, not the transcript',
      () async {
        await connect();
        final chat = ChatController(
          rpc: rpc,
          hob: roster.first,
          roster: () => roster,
        );
        await chat.start();
        await chat.send('@hermes zkontroluj logy');
        final submit = server.received.lastWhere(
          (m) => m['method'] == 'prompt.submit',
        );
        final text = (submit['params'] as Map)['text'] as String;
        expect(text, startsWith('@hermes zkontroluj logy\n\n[@mentions'));
        expect(text, contains('@hermes = agent profile "default"'));
        expect(chat.messages.last.text, '@hermes zkontroluj logy');

        // History shows what the user typed.
        final rows = ChatController.historyToMessages([
          {'role': 'user', 'text': text},
        ]);
        expect(rows.single.text, '@hermes zkontroluj logy');
        chat.dispose();
        await disconnect();
      },
    );

    testWidgets('typing @ offers the other Hobs and inserts the tag', (
      tester,
    ) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      late ChatController chat;
      await tester.runAsync(() async {
        await connect();
        chat = ChatController(
          rpc: rpc,
          hob: roster.first,
          roster: () => roster,
        );
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
            home: ChatView(),
          ),
        ),
      );
      await tester.pump();

      final input = find.byType(TextField).first;
      expect(find.byKey(const ValueKey('mention-suggestions')), findsNothing);
      await tester.enterText(input, 'ahoj @her');
      await tester.pump();
      final list = find.byKey(const ValueKey('mention-suggestions'));
      expect(list, findsOneWidget);
      expect(
        find.descendant(of: list, matching: find.text('@hermes')),
        findsOneWidget,
      );
      // The open Hob is not offered.
      expect(
        find.descendant(of: list, matching: find.text('@cto')),
        findsNothing,
      );

      await tester.tap(
        find.descendant(of: list, matching: find.byType(ListTile)),
      );
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, 'ahoj @hermes ');
      expect(list, findsNothing);

      // On a hardware keyboard, Enter takes the highlighted Hob, not send.
      await tester.enterText(input, '@h');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, '@hermes ');

      chat.dispose();
      await tester.runAsync(disconnect);
    });
  });
}
