import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/l10n/strings_cs.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/state/chat_controller.dart';
import 'package:hobs/state/cron_schedule.dart';
import 'package:hobs/ui/cron_editor.dart';
import 'package:hobs/ui/cron_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credentials_test.dart' show settle;
import 'fake_hermes_server.dart';

/// Scheduled jobs: the editor's schedule, the job list and its actions, and
/// a job's output in the chat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('schedule', () {
    test('calendar choices become cron expressions', () {
      final s = CronSchedule(hour: 7, minute: 30);
      expect((s..freq = CronFreq.hourly).toSchedule(), '30 * * * *');
      expect((s..freq = CronFreq.daily).toSchedule(), '30 7 * * *');
      expect((s..freq = CronFreq.weekdays).toSchedule(), '30 7 * * 1-5');
      s
        ..freq = CronFreq.weekly
        ..weekday = DateTime.sunday;
      expect(s.toSchedule(), '30 7 * * 0');
      s.weekday = DateTime.wednesday;
      expect(s.toSchedule(), '30 7 * * 3');
      s
        ..freq = CronFreq.monthly
        ..dayOfMonth = 15;
      expect(s.toSchedule(), '30 7 15 * *');
    });

    test('a delay runs once, an interval repeats in minutes', () {
      final s = CronSchedule(freq: CronFreq.once, amount: 2)
        ..unit = CronUnit.hours;
      expect(s.toSchedule(), '2h');
      expect(s.repeats, isFalse);
      s.freq = CronFreq.interval;
      expect(s.toSchedule(), 'every 120m');
      expect(s.repeats, isTrue);
      s.unit = CronUnit.days;
      expect(s.toSchedule(), 'every 2880m');
      s.amount = 0;
      expect(s.toSchedule(), isNull);
    });

    test('a typed expression needs five fields', () {
      final s = CronSchedule(freq: CronFreq.advanced);
      for (final bad in ['', '0 9 * *', '0 9 * * 1 2', 'zítra v 9']) {
        s.expression = bad;
        expect(s.toSchedule(), isNull, reason: bad);
      }
      s.expression = '  */15   8-18 * * 1-5 ';
      expect(s.toSchedule(), '*/15 8-18 * * 1-5');
    });
  });

  group('job json', () {
    test('reads the REST shape', () {
      final job = CronJob.fromJson({
        'id': 'a1',
        'name': '[bot:dev-cto] Ranní přehled',
        'prompt': 'Full prompt',
        'schedule': {
          'kind': 'cron',
          'expr': '0 9 * * *',
          'display': '0 9 * * *',
        },
        'schedule_display': '0 9 * * *',
        'repeat': {'times': 10, 'completed': 3},
        'enabled': true,
        'state': 'scheduled',
        'deliver': 'bot-chat:dev-cto',
        'live_execution': {'id': 'x'},
      });
      expect(job.name, 'Ranní přehled');
      expect(job.schedule, '0 9 * * *');
      expect(job.prompt, 'Full prompt');
      expect(job.repeatTimes, 10);
      expect(job.repeatCompleted, 3);
      expect(job.deliverHob, 'dev-cto');
      expect(job.running, isTrue);
      expect(job.paused, isFalse);
    });

    test('reads the cron.manage shape, schedule and repeat as strings', () {
      final job = CronJob.fromJson({
        'job_id': 'b2',
        'name': 'Monitoring',
        'schedule':
            '{"kind":"cron","expr":"*/5 * * * *","display":"*/5 * * * *"}',
        'repeat': '{"times":null,"completed":0}',
        'prompt_preview': 'Check the sites',
        'enabled': false,
        'deliver': 'local',
      });
      expect(job.id, 'b2');
      expect(job.schedule, '*/5 * * * *');
      expect(job.prompt, 'Check the sites');
      expect(job.repeatTimes, isNull);
      expect(job.deliverHob, isNull);
      expect(job.paused, isTrue);
    });
  });

  group('output in the chat', () {
    const header =
        '[Cronjob "Vibee – poptávky CZ/SK" output — scheduled job, not the '
        'user. Review it, act on anything that needs action, and summarize '
        'for the chat.]';

    test('is told apart from what the user wrote', () {
      final parsed = ScheduledOutput.parse('$header\n\nTEST – nic nového');
      expect(parsed?.job, 'Vibee – poptávky CZ/SK');
      expect(parsed?.output, 'TEST – nic nového');
      expect(ScheduledOutput.parse('Jsme online?'), isNull);
      expect(ScheduledOutput.parse('[SILENT]'), isNull);
      // A preview cut short still names the job.
      expect(
        ScheduledOutput.jobOf('[Cronjob "Vibee – poptávky CZ/SK" output — sch'),
        'Vibee – poptávky CZ/SK',
      );
      expect(ScheduledOutput.jobOf('Hello'), isNull);
    });

    test('history rows keep the job and the output', () {
      Strings.current = const StringsCs();
      final rows = ChatController.historyToMessages([
        {'role': 'user', 'text': '$header\n\n**Nic** nového.'},
        {'role': 'assistant', 'text': 'Shrnutí: nic nového.'},
      ]);
      expect(rows.first.role, ChatRole.user);
      expect(rows.first.scheduledJob, 'Vibee – poptávky CZ/SK');
      expect(rows.first.text, '**Nic** nového.');
      expect(rows.last.scheduledJob, isNull);
    });
  });

  group('jobs on the server', () {
    late FakeHermesServer server;
    late AppState app;
    final hob = Hob(name: 'cto', displayName: 'CTO');

    setUp(() async {
      HttpOverrides.global = null;
      server = FakeHermesServer();
      await server.start();
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      Strings.current = const StringsCs();
      app = AppState();
      await app.login(
        serverUrl: server.baseUrl.toString(),
        username: 'u',
        password: 'p',
      );
      await settle(app);
    });

    tearDown(() async {
      app.dispose();
      await server.stop();
    });

    test('are listed per Hob over REST', () async {
      final jobs = await app.cronJobs(hob);
      expect(jobs.single.name, 'Vibee poptavky');
      expect(jobs.single.repeatTimes, 10);
      expect(jobs.single.deliverHob, 'cto');
      expect(
        await app.cronJobs(Hob(name: 'mail', displayName: 'Mail')),
        isEmpty,
      );
    });

    test('pause, resume, run, history and delete', () async {
      final job = (await app.cronJobs(hob)).single;
      await app.setCronEnabled(job, false);
      expect((await app.cronJobs(hob)).single.paused, isTrue);
      await app.setCronEnabled(job, true);
      expect((await app.cronJobs(hob)).single.paused, isFalse);

      expect(await app.cronRuns(job), isEmpty);
      await app.triggerCron(job);
      final runs = await app.cronRuns(job);
      expect(runs.single.duration, const Duration(seconds: 42));
      expect(runs.single.toolCalls, 3);
      expect(runs.single.failed, isFalse);

      await app.deleteCron(job);
      expect(await app.cronJobs(hob), isEmpty);
      expect(server.cronActions, [
        'pause j1',
        'resume j1',
        'trigger j1',
        'delete j1',
      ]);
    });

    test('a new job is tagged for the Hob like the dashboard does', () async {
      await app.createCron(
        hob,
        name: ' Ranní přehled ',
        schedule: '0 8 * * *',
        prompt: ' Shrň novinky. ',
        repeat: 5,
        continuity: true,
        toChat: true,
      );
      expect(server.cronAdds.single, {
        'action': 'add',
        'name': '[bot:cto] Ranní přehled',
        'schedule': '0 8 * * *',
        'prompt': 'Shrň novinky.',
        'profile': 'cto',
        'repeat': 5,
        'continuity': true,
        'deliver': 'bot-chat',
      });
      final added = (await app.cronJobs(hob)).last;
      expect(added.name, 'Ranní přehled');
      expect(added.deliverHob, 'cto');

      await app.createCron(
        hob,
        name: 'Jednou',
        schedule: '30m',
        prompt: 'Připomeň mi pauzu.',
      );
      expect(server.cronAdds.last.containsKey('repeat'), isFalse);
      expect(server.cronAdds.last.containsKey('deliver'), isFalse);
      expect(server.cronAdds.last.containsKey('continuity'), isFalse);
    });

    testWidgets('the sheet switches a job off and opens its detail', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            home: Scaffold(
              body: CronSheet(app: app, hob: hob),
            ),
          ),
        ),
      );
      Future<void> settleIo() async {
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }

      await settleIo();
      expect(find.text('Vibee poptavky'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await settleIo();
      expect(server.cronJobs.single['state'], 'paused');
      expect(find.text('Pozastaveno'), findsOneWidget);

      await tester.tap(find.text('Vibee poptavky'));
      await settleIo();
      expect(find.text('Spustit teď'), findsOneWidget);
      // The output goes to the Hob's chat, named as the roster names it.
      expect(find.text('Chat Hobíka CTO'), findsOneWidget);
      expect(find.text('Úloha ještě neběžela.'), findsOneWidget);
      expect(find.text('Proběhlo 0 z 10'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      // Idle keep-alive connections time out.
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('the editor schedules a daily job at nine', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(home: CronEditorScreen(hob: hob)),
        ),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Ranní přehled');
      await tester.enterText(fields.at(1), 'Shrň novinky.');
      await tester.enterText(fields.at(2), '3');
      await tester.tap(find.text('Vytvořit úlohu'));
      for (var i = 0; i < 20 && server.cronAdds.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(server.cronAdds.single['schedule'], '0 9 * * *');
      expect(server.cronAdds.single['repeat'], 3);
      expect(server.cronAdds.single['name'], '[bot:cto] Ranní přehled');
      expect(server.cronAdds.single.containsKey('deliver'), isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    });
  });
}
