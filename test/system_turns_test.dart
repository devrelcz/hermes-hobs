import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/l10n/strings_cs.dart';
import 'package:hobs/state/chat_controller.dart';

/// Turns the gateway writes in the user's place: messages from other Hobs
/// and notes that background work finished.
void main() {
  setUp(() => Strings.current = const StringsCs());

  group('parse', () {
    test('a message from another Hob names the writer', () {
      final p = SystemTurn.parse(
        'Message from 🤖 CTO (@dev-cto): Priorita běžná. Navrhni pilot.',
      )!;
      expect(p.turn.kind, SystemTurnKind.agentMessage);
      expect(p.turn.sender, 'CTO');
      expect(p.turn.handle, 'dev-cto');
      expect(p.body, 'Priorita běžná. Navrhni pilot.');

      final spaced = SystemTurn.parse(
        'Message from 🤖 Dev Developer (@dev-developer): Hotovo.',
      )!;
      expect(spaced.turn.sender, 'Dev Developer');
      expect(spaced.turn.handle, 'dev-developer');

      final agent = SystemTurn.parse("Message from agent 'planovac': Ahoj")!;
      expect(agent.turn.handle, 'planovac');
      expect(agent.body, 'Ahoj');
    });

    test('finished background work keeps its goal or command', () {
      final d = SystemTurn.parse(
        '[ASYNC DELEGATION COMPLETE — deleg_7da775fb]\n'
        'A background subagent you dispatched earlier has finished.\n\n'
        "Original goal: Manual run of cron job 'Vibee' (21eb3d1763f8)\n"
        'Context you provided: …',
      )!;
      expect(d.turn.kind, SystemTurnKind.delegationDone);
      expect(d.turn.summary, "Manual run of cron job 'Vibee' (21eb3d1763f8)");

      final p = SystemTurn.parse(
        '[IMPORTANT: Background process proc_b800 completed normally '
        '(exit code 0).\nCommand: python3 /opt/hermes/tools/bot_mode_dm.py\n…',
      )!;
      expect(p.turn.kind, SystemTurnKind.processDone);
      expect(p.turn.summary, 'python3 /opt/hermes/tools/bot_mode_dm.py');
    });

    test('the server mark is enough on its own', () {
      final p = SystemTurn.parse(
        'Something new',
        kind: 'process_complete',
        meta: {'display_text': 'Background Process Finished: make'},
      )!;
      expect(p.turn.kind, SystemTurnKind.processDone);
      expect(p.turn.summary, 'Background Process Finished: make');
    });

    test("the user's own words stay theirs", () {
      expect(SystemTurn.parse('Jsme online?'), isNull);
      expect(SystemTurn.parse('Message from me: hi'), isNull);
      expect(SystemTurn.parse('jak bude @analytik vyhledávat?'), isNull);
    });

    test('a preview names the writer', () {
      final p = SystemTurn.ofPreview('Message from 🤖 CTO (@dev-cto): Ahoj, ');
      expect(p?.sender, 'CTO');
      expect(p?.text, 'Ahoj,');
      expect(SystemTurn.ofPreview('Ano, jsem online.'), isNull);
    });
  });

  group('history', () {
    test("a Hob's answer folds into the message it answers", () {
      final rows = ChatController.historyToMessages([
        {'role': 'user', 'text': 'Ahoj'},
        {'role': 'assistant', 'text': 'Ahoj!'},
        {
          'role': 'user',
          'display_kind': 'internal_notification',
          'text': 'Message from 🤖 CTO (@dev-cto): Jsi tam?',
        },
        {'role': 'tool', 'name': 'web_search', 'context': 'x'},
        {'role': 'assistant', 'text': ''},
        {'role': 'assistant', 'text': 'Jsem.'},
        {'role': 'assistant', 'text': 'Nic nemám rozpracované.'},
        {'role': 'user', 'text': 'Díky'},
        {'role': 'assistant', 'text': 'Není zač.'},
      ]);
      expect(rows.map((m) => m.role), [
        ChatRole.user,
        ChatRole.assistant,
        ChatRole.user,
        ChatRole.user,
        ChatRole.assistant,
      ]);
      final folded = rows[2];
      expect(folded.system?.sender, 'CTO');
      expect(folded.text, 'Jsi tam?');
      expect(folded.reply, 'Jsem.\n\nNic nemám rozpracované.');
      expect(folded.replyTools.single.name, 'web_search');
      expect(rows[3].text, 'Díky');
      expect(rows[3].system, isNull);
    });

    test('after background work the answer stays in the chat', () {
      final rows = ChatController.historyToMessages([
        {
          'role': 'user',
          'display_kind': 'process_complete',
          'text': '[IMPORTANT: Background process p1 completed.\nCommand: ls',
        },
        {'role': 'assistant', 'text': 'Monitoring je nastavený.'},
      ]);
      expect(rows.first.system?.kind, SystemTurnKind.processDone);
      expect(rows.first.reply, isNull);
      expect(rows.last.role, ChatRole.assistant);
      expect(rows.last.text, 'Monitoring je nastavený.');
    });

    test("a scheduled job's output is a job card, its answer a bubble", () {
      const header =
          '[Cronjob "[bot:posta] Hodinová kontrola e-mailů" output — '
          'scheduled job, not the user. Review it, act on anything that '
          'needs action, and summarize for the chat.]';
      expect(
        SystemTurn.parse(
          '$header\n\nNic nového',
          kind: 'internal_notification',
        ),
        isNull,
      );
      final rows = ChatController.historyToMessages([
        {
          'role': 'user',
          'display_kind': 'internal_notification',
          'text': '$header\n\nZásilkovna převzala zásilku.',
        },
        {'role': 'assistant', 'text': 'Balík je na cestě.'},
      ]);
      expect(rows.first.system, isNull);
      expect(rows.first.scheduledJob, '[bot:posta] Hodinová kontrola e-mailů');
      expect(rows.first.text, 'Zásilkovna převzala zásilku.');
      expect(rows.first.reply, isNull);
      expect(rows.last.role, ChatRole.assistant);
      expect(rows.last.text, 'Balík je na cestě.');
    });

    test('hidden scaffolding stays out', () {
      final rows = ChatController.historyToMessages([
        {
          'role': 'assistant',
          'display_kind': 'hidden',
          'text': '[PRIOR CONTEXT — for reference only]',
        },
        {'role': 'assistant', 'text': 'Ahoj'},
      ]);
      expect(rows.single.text, 'Ahoj');
    });
  });
}
