import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/hermes_http.dart';
import 'package:hobs/api/hermes_rpc.dart';
import 'package:hobs/api/models.dart';
import 'package:hobs/l10n/strings.dart';
import 'package:hobs/state/chat_controller.dart';
import 'package:hobs/ui/model_picker.dart';

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

const _codex = ModelChoice(provider: 'openai-codex', model: 'gpt-6.2-sol');
const _pro = ModelChoice(provider: 'nous', model: 'hermes-4-pro');
const _default = ModelChoice(provider: 'nous', model: 'hermes-4');

void main() {
  late FakeHermesServer server;
  late HermesHttp http;
  late HermesRpc rpc;
  late ChatController chat;

  setUp(() async {
    // Real sockets to the fake server, also under the widget binding.
    HttpOverrides.global = null;
    server = FakeHermesServer();
    await server.start();
  });

  tearDown(() async {
    chat.dispose();
    await rpc.dispose();
    http.close();
    await server.stop();
  });

  Future<void> open() async {
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
    final cto = Hob.fromJson(
      (res['profiles'] as List).cast<Map<String, dynamic>>().first,
    );
    chat = ChatController(rpc: rpc, hob: cto);
    await chat.start();
    await waitFor(() => chat.defaultModel != null);
  }

  /// Every model call must stay on the session: the profile is untouched.
  void expectProfileUntouched() {
    expect(server.profileModel, {'provider': 'nous', 'default': 'hermes-4'});
    expect(server.configures, isEmpty);
    expect(server.cliCalls, isEmpty);
  }

  Future<void> switchSurvivesReconnect() async {
    // A session switch, an expensive one confirmed, then a network drop.
    expect(chat.sessionModel, _default);
    expect(chat.defaultModel, _default);
    expect(chat.modelOverridden, isFalse);
    expect(chat.modelProviders.map((p) => p.slug), ['nous', 'openai-codex']);

    final done = await chat.setSessionModel(_codex);
    expect(done.ok, isTrue);
    expect(chat.sessionModel, _codex);
    expect(chat.modelOverridden, isTrue);
    expect(server.sessionModels['botchat-tip'], {
      'provider': 'openai-codex',
      'model': 'gpt-6.2-sol',
    });

    final ask = await chat.setSessionModel(_pro);
    expect(ask.question, 'Pricey.');
    expect(chat.sessionModel, _codex, reason: 'not switched before the yes');
    final confirmed = await chat.setSessionModel(_pro, confirmed: true);
    expect(confirmed.ok, isTrue);
    expect(chat.sessionModel, _pro);
    expect(chat.error, isNull);
    expectProfileUntouched();

    // The resume snapshot reports the profile's model; the session's own
    // choice is re-read from the server, not kept from local state.
    await server.dropConnections();
    await waitFor(() => server.resumed.length == 2);
    await waitFor(
      () =>
          server.calls.where((c) => c['method'] == 'model.options').length >= 8,
    );
    await waitFor(() => chat.sessionModel == _pro);
    expect(chat.modelOverridden, isTrue);

    final back = await chat.useDefaultModel();
    expect(back.ok, isTrue);
    expect(chat.sessionModel, _default);
    expect(chat.modelOverridden, isFalse);
    expect(server.sessionModels['botchat-tip'], {
      'provider': 'nous',
      'model': 'hermes-4',
    });
    expectProfileUntouched();
  }

  test('legacy: session model switch, confirm, reconnect, default', () async {
    await open();
    await switchSurvivesReconnect();
    final sets = server.configSets.where((c) => c['key'] == 'model').toList();
    expect(sets.first, {
      'session_id': 'rt1',
      'key': 'model',
      'value': 'gpt-6.2-sol --provider openai-codex --session',
    });
    expect(sets[2]['confirm_expensive_model'], isTrue);
    expect(sets.last['value'], 'hermes-4 --provider nous --session');
  });

  test('canonical: session.mutate model with confirm token', () async {
    server.canonical = true;
    await open();
    await switchSurvivesReconnect();
    final mutations = server.calls
        .where((c) => c['method'] == 'session.mutate')
        .map((c) => c['params'] as Map)
        .toList();
    expect(mutations.every((m) => m['operation'] == 'model'), isTrue);
    expect(mutations.every((m) => m['profile'] == 'cto'), isTrue);
    expect(mutations.first['payload'], {
      'model': 'gpt-6.2-sol',
      'provider': 'openai-codex',
    });
    expect(mutations[1]['payload'], {
      'model': 'hermes-4-pro',
      'provider': 'nous',
    });
    expect(mutations[2]['payload'], {
      'model': 'hermes-4-pro',
      'provider': 'nous',
      'confirm': 'confirm-expensive-1',
    });
  });

  testWidgets('the sheet marks the session model and offers the default', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await open();
      await chat.setSessionModel(_codex);
    });
    ModelChoice? picked;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: Strings.supportedLocales,
        localizationsDelegates: const [Strings.delegate],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked = await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => SessionModelSheet(chat: chat),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Model for this chat'), findsOneWidget);
    expect(find.text("Hob's default"), findsOneWidget);
    final current = find.byKey(
      const ValueKey('model:openai-codex:gpt-6.2-sol'),
    );
    expect(
      find.descendant(of: current, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    await tester.tap(find.text("Use the Hob's default"));
    await tester.pumpAndSettle();
    expect(picked, _default);
    await tester.runAsync(() => server.dropConnections());
  });
}
