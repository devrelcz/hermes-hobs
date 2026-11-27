import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/hermes_http.dart';
import 'package:hobs/api/hermes_rpc.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/state/chat_controller.dart';

import 'fake_hermes_server.dart';

Future<void> waitFor(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('condition not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late FakeHermesServer server;

  setUp(() async {
    server = FakeHermesServer();
    await server.start();
  });

  tearDown(() => server.stop());

  Future<HermesHttp> signedIn() async {
    final http = HermesHttp(baseUrl: server.baseUrl);
    await http.postJson('/auth/password-login', {
      'provider': 'basic',
      'username': 'u',
      'password': 'p',
      'next': '',
    });
    return http;
  }

  Future<List<Hob>> roster(HermesRpc rpc) async {
    await rpc.connect();
    final res =
        await rpc.request('profiles.list', {'include_sessions': true}) as Map;
    return (res['profiles'] as List)
        .cast<Map<String, dynamic>>()
        .map(Hob.fromJson)
        .where((b) => !b.hidden)
        .toList();
  }

  test('login stores session cookies and authenticates REST calls', () async {
    final http = HermesHttp(baseUrl: server.baseUrl);
    Map<String, String>? persisted;
    http.onCookiesChanged = (c) => persisted = c;

    await expectLater(
      http.postJson('/auth/password-login', {
        'provider': 'basic',
        'username': 'u',
        'password': 'bad',
        'next': '',
      }),
      throwsA(
        isA<HermesHttpException>().having((e) => e.statusCode, 'status', 401),
      ),
    );
    await http.postJson('/auth/password-login', {
      'provider': 'basic',
      'username': 'u',
      'password': 'p',
      'next': '',
    });

    expect(http.hasSession, isTrue);
    expect(persisted, {
      'hermes_session_at': 'AT1',
      'hermes_session_rt': 'RT1',
      'hermes_session_provider': 'basic',
    });
    final me = await http.getJson('/api/auth/me');
    expect(me['user_id'], 'u');
    http.close();
  });

  test(
    'roster: Bot Mode meta, canonical session, hidden hobs dropped',
    () async {
      final http = await signedIn();
      final rpc = HermesRpc(http);
      final hobs = await roster(rpc);

      expect(hobs.map((b) => b.name), ['cto', 'default']);
      final cto = hobs.first;
      expect(
        cto.displayName,
        'CTO',
        reason: 'ui_meta title wins over display_name',
      );
      expect(cto.sectionId, 's1');
      expect(cto.sectionName, 'Vibee.one');
      expect(cto.pinned, isTrue);
      expect(cto.canonical!.resumeId, 'botchat-tip');
      expect(cto.preview, 'Analytik overil zdroje');
      expect(hobs[1].displayName, 'default');
      expect(hobs[1].canonical, isNull);

      await rpc.dispose();
      http.close();
    },
  );

  test('sections: folders sorted, unassigned last, pinned first', () {
    final app = AppState();
    app.hobs = [
      Hob(name: 'a', displayName: 'Alfa'),
      Hob(
        name: 'z',
        displayName: 'Zeta',
        sectionId: 'f',
        sectionName: 'Finance',
      ),
      Hob(
        name: 'o',
        displayName: 'Omega',
        sectionId: 'v',
        sectionName: 'Vibee.one',
      ),
      Hob(
        name: 'p',
        displayName: 'Pinned',
        sectionId: 'v',
        sectionName: 'Vibee.one',
        pinned: true,
      ),
    ];
    final s = app.sections;
    expect(s.map((x) => x.title), ['Finance', 'Vibee.one', 'Nezařazení']);
    expect(s[1].hobs.map((b) => b.name), ['p', 'o']);
    expect(app.hasFolders, isTrue);

    app.setQuery('zet');
    expect(app.sections.single.hobs.single.name, 'z');
  });

  test(
    'opening a hob with a Bot Chat resumes it and folds tool rows',
    () async {
      final http = await signedIn();
      final rpc = HermesRpc(http);
      final cto = (await roster(rpc)).first;
      final chat = ChatController(rpc: rpc, hob: cto);

      await chat.start();
      expect(server.resumed, ['botchat-tip']);
      expect(server.createParams, isEmpty);
      expect(chat.phase, ChatPhase.idle);
      expect(chat.reasoningEffort, 'high');
      expect(chat.messages.map((m) => m.role), [
        ChatRole.user,
        ChatRole.activity,
        ChatRole.assistant,
      ]);
      expect(chat.messages[1].tools.map((t) => t.name), [
        'skill_view',
        'terminal',
      ]);
      expect(chat.lastPrompt, 'nastav monitoring');

      chat.dispose();
      await rpc.dispose();
      http.close();
    },
  );

  test('first chat with a hob creates and titles its Bot Chat', () async {
    final http = await signedIn();
    final rpc = HermesRpc(http);
    final plain = (await roster(rpc))[1];
    final chat = ChatController(rpc: rpc, hob: plain);

    await chat.start();
    expect(server.createParams.single, {
      'profile': 'default',
      'title': 'Bot Chat',
      'hidden': true,
      'follow_profile_config': true,
      'close_on_disconnect': false,
    });
    expect(server.titled, ['Bot Chat']);
    expect(server.capabilitiesAnnounced, isTrue);
    expect(
      server.lastWsOrigin,
      isNull,
      reason: 'native client must not send a foreign Origin',
    );

    chat.dispose();
    await rpc.dispose();
    http.close();
  });

  test('streamed turn: text, activity row, text, final', () async {
    final http = await signedIn();
    final rpc = HermesRpc(http);
    final chat = ChatController(
      rpc: rpc,
      hob: Hob(name: 'default', displayName: 'Hermes'),
    );
    await chat.start();

    await chat.send('Ahoj');
    await waitFor(() => chat.phase == ChatPhase.idle);

    expect(chat.messages.map((m) => m.role), [
      ChatRole.user,
      ChatRole.assistant,
      ChatRole.activity,
      ChatRole.assistant,
    ]);
    expect(chat.messages[1].text, 'Ahoj, ');
    expect(chat.messages[2].tools.single.name, 'web_search');
    expect(chat.messages[2].tools.single.state, ToolState.done);
    expect(chat.messages.last.text, 'Ahoj, svete!');
    expect(chat.messages.every((m) => !m.streaming), isTrue);
    final submit = server.received.firstWhere(
      (m) => m['method'] == 'prompt.submit',
    );
    expect(submit['params'], {'session_id': 'rt1', 'text': 'Ahoj'});

    await chat.setReasoningEffort('low');
    expect(server.configSets.single, {
      'session_id': 'rt1',
      'key': 'reasoning',
      'value': 'low',
      'scope': 'session',
    });
    expect(chat.reasoningEffort, 'low');

    await waitFor(() => chat.approvalMode == 'manual');
    await chat.setApprovalMode('smart');
    expect(server.configSets.last, {
      'profile': 'default',
      'session_id': 'rt1',
      'key': 'approvals.mode',
      'value': 'smart',
    });
    expect(chat.approvalMode, 'smart');
    expect(server.approvalMode, 'smart');

    chat.dispose();
    await rpc.dispose();
    http.close();
  });

  test('approval request is surfaced and answered', () async {
    server.askApproval = true;
    final http = await signedIn();
    final rpc = HermesRpc(http);
    final chat = ChatController(
      rpc: rpc,
      hob: Hob(name: 'default', displayName: 'Hermes'),
    );
    await chat.start();

    unawaited(chat.send('do it'));
    await waitFor(() => chat.approval != null);
    expect(chat.approval!.command, 'ls /');
    expect(chat.approval!.choices, ['once', 'deny']);

    chat.answerApproval('once');
    expect(await server.approvalAnswer.future, {'choice': 'once'});
    await waitFor(() => chat.phase == ChatPhase.idle);
    expect(chat.messages.last.text, 'Ahoj, svete!');
    expect(chat.approval, isNull);

    chat.dispose();
    await rpc.dispose();
    http.close();
  });

  test('cron jobs parse from cron.manage list', () async {
    final http = await signedIn();
    final rpc = HermesRpc(http);
    await rpc.connect();
    final res = await rpc.request('cron.manage', {
      'action': 'list',
      'profile': 'cto',
    }) as Map;
    final jobs = (res['jobs'] as List)
        .cast<Map<String, dynamic>>()
        .map(CronJob.fromJson)
        .toList();
    expect(jobs.single.name, 'Vibee poptavky');
    expect(jobs.single.nextRun, isNotNull);
    await rpc.dispose();
    http.close();
  });

  test('ws-ticket without session reports unauthorized', () async {
    final http = HermesHttp(baseUrl: server.baseUrl);
    final rpc = HermesRpc(http);
    var expired = false;
    rpc.onUnauthorized = () => expired = true;
    await expectLater(rpc.connect(), throwsA(isA<HermesHttpException>()));
    expect(expired, isTrue);
    await rpc.dispose();
    http.close();
  });

  group('canonical dialect (gateway Webapp)', () {
    setUp(() => server.canonical = true);

    test('resume uses only canonical params and display rows', () async {
      final http = await signedIn();
      final rpc = HermesRpc(http);
      final cto = (await roster(rpc)).first;
      expect(rpc.canonical, isTrue);
      final chat = ChatController(rpc: rpc, hob: cto);

      await chat.start();
      expect(chat.error, isNull);
      expect(chat.phase, ChatPhase.idle);
      final resume = server.calls.firstWhere(
        (c) => c['method'] == 'session.resume',
      );
      expect(resume['params'], {
        'session_id': 'botchat-tip',
        'profile': 'cto',
        'display_projection': true,
      });
      expect(chat.messages.map((m) => m.role), [
        ChatRole.user,
        ChatRole.activity,
        ChatRole.assistant,
      ]);
      expect(
        server.createParams,
        isEmpty,
        reason: 'must not mint a new Bot Chat',
      );

      chat.dispose();
      await rpc.dispose();
      http.close();
    });

    test('gateway preserves URLs in chat history and replies', () async {
      const url = 'https://example.org/a%20b?next=%2Fdocs&lang=cs#intro';
      const question = 'Podívej se na ($url).';
      const answer = '[Návod]($url)';
      server.history = [
        {'role': 'user', 'text': question},
        {'role': 'assistant', 'content': answer},
      ];
      server.replyText = answer;
      final http = await signedIn();
      final rpc = HermesRpc(http);
      final chat = ChatController(rpc: rpc, hob: (await roster(rpc)).first);
      addTearDown(() async {
        chat.dispose();
        await rpc.dispose();
        http.close();
      });

      await chat.start();
      expect(chat.messages.map((m) => m.text), [question, answer]);

      await chat.send(question);
      await waitFor(() => chat.phase == ChatPhase.idle);
      expect(chat.lastPrompt, question);
      expect(chat.messages.last.text, answer);
    });

    test('first chat creates Bot Chat with canonical params', () async {
      final http = await signedIn();
      final rpc = HermesRpc(http);
      final plain = (await roster(rpc))[1];
      final chat = ChatController(rpc: rpc, hob: plain);

      await chat.start();
      expect(chat.error, isNull);
      final p = server.createParams.single;
      expect(p.keys.toSet(), {
        'profile',
        'title',
        'hidden',
        'follow_profile_config',
        'request_id',
        'source',
      });
      expect(p['title'], 'Bot Chat');
      expect(
        server.titled,
        isEmpty,
        reason: 'canonical create records the title',
      );

      chat.dispose();
      await rpc.dispose();
      http.close();
    });

    test(
      'submit, approval event, interrupt and reasoning are fenced',
      () async {
        server.askApproval = true;
        final http = await signedIn();
        final rpc = HermesRpc(http);
        final chat = ChatController(
          rpc: rpc,
          hob: Hob(name: 'default', displayName: 'Hermes'),
        );
        await chat.start();

        unawaited(chat.send('do it'));
        await waitFor(() => chat.approval != null);
        final submit = server.calls.firstWhere(
          (c) => c['method'] == 'prompt.submit',
        );
        expect((submit['params'] as Map)['submission_id'], isA<String>());
        expect(chat.approval!.command, 'ls /');

        chat.answerApproval('once');
        expect(await server.approvalAnswer.future, {'choice': 'once'});
        final respond = server.calls.firstWhere(
          (c) => c['method'] == 'approval.respond',
        );
        expect(respond['params'], {
          'profile': 'default',
          'session_id': 'rt1',
          'execution_generation': 4,
          'prompt_id': 'p-approval',
          'choice': 'once',
        });
        await waitFor(() => chat.phase == ChatPhase.idle);
        expect(chat.messages.last.text, 'Ahoj, svete!');

        await chat.interrupt();
        final intr = server.calls.lastWhere(
          (c) => c['method'] == 'session.interrupt',
        );
        expect(intr['params'], {
          'profile': 'default',
          'session_id': 'rt1',
          'execution_generation': 4,
        });

        await chat.setReasoningEffort('high');
        final mutate = server.calls.lastWhere(
          (c) => c['method'] == 'session.mutate',
        );
        expect((mutate['params'] as Map)['operation'], 'reasoning');
        expect((mutate['params'] as Map)['payload'], {'effort': 'high'});
        expect(chat.error, isNull);

        chat.dispose();
        await rpc.dispose();
        http.close();
      },
    );

    test(
      'a named profile\'s turn is routed to that profile\'s owner',
      () async {
        // Regression: session verbs without `profile` reached the launch
        // profile's owner, which holds no subscription for the session and
        // answered 4001 `permission_denied`.
        final http = await signedIn();
        final rpc = HermesRpc(http);
        final cto = (await roster(rpc)).first;
        final chat = ChatController(rpc: rpc, hob: cto);
        await chat.start();

        await chat.send('ahoj');
        await waitFor(() => chat.phase == ChatPhase.idle);
        expect(chat.messages.where((m) => m.role == ChatRole.error), isEmpty);
        expect(chat.messages.last.text, 'Ahoj, svete!');
        final submit = server.calls.lastWhere(
          (c) => c['method'] == 'prompt.submit',
        );
        expect((submit['params'] as Map)['profile'], 'cto');

        await chat.interrupt();
        await chat.setReasoningEffort('low');
        expect(chat.error, isNull);
        expect(chat.reasoningEffort, 'low');

        chat.dispose();
        await rpc.dispose();
        http.close();
      },
    );
  });
}
