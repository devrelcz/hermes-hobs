import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// In-process stand-in for a gated Hermes dashboard: cookie login, ws-ticket,
/// and a JSON-RPC `/api/ws` socket that streams a scripted reply.
class FakeHermesServer {
  late HttpServer _server;
  final Set<String> _tickets = {};
  final List<Map<String, dynamic>> received = [];
  String? lastWsOrigin;
  bool capabilitiesAnnounced = false;
  int sessionCounter = 0;

  /// Speak the canonical session-authority dialect (gateway Webapp): strict
  /// params, prompts as events, generation-fenced controls.
  bool canonical = false;
  final List<Map<String, dynamic>> calls = [];

  /// Canonical: runtime session id -> profile whose owner holds the
  /// subscription. A session verb routed elsewhere is a stranger.
  final Map<String, String> _subscriptions = {};
  static const _sessionVerbs = {
    'prompt.submit',
    'file.attach',
    'session.interrupt',
    'session.mutate',
    'approval.respond',
    'clarify.respond',
  };

  static const _canonicalParams = {
    'session.resume': {
      'profile',
      'session_id',
      'title',
      'latest',
      'workspace',
      'source',
      'editor',
      'api_key',
      'defer_history',
      'omit_messages',
      'cols',
      'display_projection',
    },
    'session.create': {
      'profile',
      'request_id',
      'source',
      'cwd',
      'model',
      'provider',
      'toolsets',
      'reasoning',
      'title',
      'hidden',
      'follow_profile_config',
      'service_tier',
      'cwd_explicit',
    },
    'prompt.submit': {
      'profile',
      'session_id',
      'text',
      'submission_id',
      'input_id',
      'queued',
      'attachments',
    },
    'file.attach': {
      'session_id',
      'profile',
      'path',
      'data_url',
      'name',
      'staged_upload',
    },
    'session.interrupt': {'profile', 'session_id', 'execution_generation'},
    'approval.respond': {
      'profile',
      'session_id',
      'execution_generation',
      'prompt_id',
      'choice',
    },
    'session.mutate': {
      'profile',
      'session_id',
      'request_id',
      'expected_revision',
      'operation',
      'payload',
      'expected_generation',
    },
  };
  final List<Map<String, dynamic>> createParams = [];
  final List<String> titled = [];
  final List<String> resumed = [];
  final List<Map<String, dynamic>> configSets = [];
  final List<Map<String, dynamic>> configures = [];

  final List<List<String>> cliCalls = [];

  /// What `profiles.describe` reports as the profile's model.
  Map<String, dynamic> profileModel = {
    'provider': 'nous',
    'default': 'hermes-4',
  };

  /// The profile's SOUL.md, as `profiles.describe` reports it.
  String profileSoul = '# CTO\n\nVede vývoj.\n';

  /// Switching to this model needs `confirm_expensive_model`.
  String expensiveModel = 'hermes-4-pro';

  /// Profile-wide `approvals.mode` served by `config.get`.
  String approvalMode = 'manual';

  /// Rows returned by `profiles.list` (RPC) and `/api/profiles` (REST).
  List<Map<String, dynamic>> roster = [
    {
      'name': 'cto',
      'display_name': 'dev-cto',
      'ui_meta': {
        'hermes-bots': {
          'title': 'CTO',
          'sectionId': 's1',
          'sectionName': 'Vibee.one',
          'pinned': true,
          'color': '#F0997B',
          'shape': 'circle',
        },
      },
      'canonical_session': {
        'id': 'botchat-root',
        'resolved_id': 'botchat-tip',
        'preview': 'Analytik overil zdroje',
        'last_active': 1795187000,
        'message_count': 12,
      },
    },
    {
      'name': 'default',
      'display_name': '',
      'is_default': true,
      'model': 'hermes-4',
    },
    {
      'name': 'ghost',
      'ui_meta': {
        'hermes-bots': {'hidden': true},
      },
    },
  ];

  /// Transcript returned by `session.resume`.
  List<Map<String, dynamic>> history = [
    {'role': 'user', 'text': 'nastav monitoring', 'timestamp': 1795186000},
    {'role': 'tool', 'name': 'skill_view', 'context': 'vibee-market-listening'},
    {'role': 'tool', 'name': 'terminal', 'context': 'crontab -l'},
    {
      'role': 'assistant',
      'text': 'Monitoring sverim Analytikovi.',
      'timestamp': 1795186100,
    },
    {'role': 'system', 'text': 'scaffolding'},
  ];

  /// Images stored by `POST /api/chat/image-upload`: host path -> bytes.
  final Map<String, List<int>> images = {};

  /// Every upload request: `{route, profile, name, bytes}`.
  final List<Map<String, dynamic>> uploads = [];

  /// When set, uploads wait for it before answering (cancel tests).
  Completer<void>? holdUploads;

  /// `GET /api/fs/download` requests (paths).
  final List<String> downloads = [];

  /// When true, the next prompt triggers an approval request before replying.
  bool askApproval = false;
  final Completer<Map<String, dynamic>> approvalAnswer = Completer();

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  bool _authed(HttpRequest r) =>
      (r.headers.value(HttpHeaders.cookieHeader) ?? '').contains(
        'hermes_session_at=AT1',
      );

  Future<void> _json(
    HttpRequest r,
    int status,
    Object body, {
    List<String> cookies = const [],
  }) async {
    r.response.statusCode = status;
    r.response.headers.contentType = ContentType.json;
    for (final c in cookies) {
      r.response.headers.add(HttpHeaders.setCookieHeader, c);
    }
    r.response.write(jsonEncode(body));
    await r.response.close();
  }

  Future<void> _handle(HttpRequest r) async {
    final path = r.uri.path;
    if (path == '/auth/password-login' && r.method == 'POST') {
      final body = jsonDecode(await utf8.decodeStream(r)) as Map;
      if (body['provider'] == 'basic' &&
          body['username'] == 'u' &&
          body['password'] == 'p') {
        return _json(
          r,
          200,
          {'ok': true, 'next': '/'},
          cookies: [
            'hermes_session_at=AT1; HttpOnly; Path=/; Max-Age=43200; SameSite=Lax',
            'hermes_session_rt=RT1; HttpOnly; Path=/; Max-Age=2592000; SameSite=Lax',
            'hermes_session_provider=basic; Path=/; Expires=Wed, 21 Oct 2099 07:28:00 GMT',
          ],
        );
      }
      return _json(r, 401, {'detail': 'Invalid credentials'});
    }
    if (path == '/api/ws' && WebSocketTransformer.isUpgradeRequest(r)) {
      final ticket = r.uri.queryParameters['ticket'];
      lastWsOrigin = r.headers.value('origin');
      if (ticket == null || !_tickets.remove(ticket)) {
        r.response.statusCode = 403;
        return r.response.close();
      }
      final ws = await WebSocketTransformer.upgrade(r);
      return _serveWs(ws);
    }
    if (!_authed(r)) {
      return _json(r, 401, {'error': 'unauthenticated', 'reason': 'no_cookie'});
    }
    final profile = r.uri.queryParameters['profile'] ?? 'default';
    final home = '/srv/hermes/profiles/$profile';
    if (path == '/api/chat/image-upload' && r.method == 'POST') {
      final body = jsonDecode(await utf8.decodeStream(r)) as Map;
      await holdUploads?.future;
      final dataUrl = body['data_url'] as String;
      final comma = dataUrl.indexOf(',');
      final mime = dataUrl.substring(5, dataUrl.indexOf(';'));
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      final name = body['filename'] as String;
      final stored = '$home/cache/images/dashboard_1_$name';
      images[stored] = bytes;
      uploads.add({
        'route': 'image',
        'profile': profile,
        'name': name,
        'bytes': bytes,
      });
      return _json(r, 200, {
        'ok': true,
        'path': stored,
        'name': 'dashboard_1_$name',
        'bytes': bytes.length,
        'mime_type': mime,
      });
    }
    if (path == '/api/chat/file-upload' && r.method == 'POST') {
      final raw = await r.fold<List<int>>([], (a, b) => a..addAll(b));
      await holdUploads?.future;
      final text = latin1.decode(raw);
      final name = utf8.decode(
        latin1.encode(
          RegExp(r'filename="([^"]*)"').firstMatch(text)!.group(1)!,
        ),
      );
      final start = text.indexOf('\r\n\r\n') + 4;
      final end = text.lastIndexOf('\r\n--');
      final bytes = raw.sublist(start, end);
      final stored = '$home/uploads/u1_$name';
      uploads.add({
        'route': 'file',
        'profile': profile,
        'name': name,
        'bytes': bytes,
        'contentType': r.headers.contentType?.mimeType,
      });
      return _json(r, 200, {
        'ok': true,
        'path': stored,
        'size': bytes.length,
        'staged_upload': {
          'install_id': 'i1',
          'path': stored,
          'profile_home': home,
        },
      });
    }
    if (path == '/api/fs/download' && r.method == 'GET') {
      final p = r.uri.queryParameters['path'] ?? '';
      downloads.add(p);
      final bytes = images[p];
      if (bytes == null) return _json(r, 404, {'detail': 'not found'});
      r.response.headers.contentType = ContentType('image', 'png');
      r.response.add(bytes);
      return r.response.close();
    }
    switch (path) {
      case '/api/auth/me':
        return _json(r, 200, {'user_id': 'u', 'provider': 'basic'});
      case '/api/auth/ws-ticket':
        final t =
            'T${_tickets.length + 1}${DateTime.now().microsecondsSinceEpoch}';
        _tickets.add(t);
        return _json(r, 200, {'ticket': t, 'ttl_seconds': 30});
      case '/api/profiles':
        return _json(r, 200, {'profiles': roster});
    }
    return _json(r, 404, {'detail': 'not found'});
  }

  void _serveWs(WebSocket ws) {
    void send(Map<String, dynamic> m) =>
        ws.add(jsonEncode({'jsonrpc': '2.0', ...m}));
    void event(String type, String sid, [Map<String, dynamic>? payload]) =>
        send({
          'method': 'event',
          'params': {'type': type, 'session_id': sid, 'payload': ?payload},
        });

    send({
      'method': 'event',
      'params': {
        'type': 'gateway.ready',
        'payload': {
          'heartbeat': true,
          'session_authority': ?(canonical ? true : null),
        },
      },
    });

    ws.listen((data) async {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      received.add(msg);
      final id = msg['id'];
      final method = msg['method'] as String?;
      final params = (msg['params'] as Map?)?.cast<String, dynamic>() ?? {};
      if (method == null) {
        // Response to a server request.
        if (id == 'srq-approval' && !approvalAnswer.isCompleted) {
          approvalAnswer.complete(
            (msg['result'] as Map).cast<String, dynamic>(),
          );
        }
        return;
      }
      calls.add({'method': method, 'params': params});
      final allowed = canonical ? _canonicalParams[method] : null;
      if (allowed != null) {
        final bad = params.keys.where((k) => !allowed.contains(k)).toList();
        final missing = switch (method) {
          'prompt.submit' => params['submission_id'] == null,
          'session.interrupt' ||
          'approval.respond' => params['execution_generation'] == null,
          _ => false,
        };
        if (bad.isNotEmpty || missing) {
          send({
            'id': id,
            'error': {
              'code': 4001,
              'message': 'invalid_params',
              'data': {'reason': 'invalid_params', 'fields': bad},
            },
          });
          return;
        }
      }
      if (canonical && _sessionVerbs.contains(method)) {
        // Frames route by `profile` (absent = the launch profile's owner).
        final owner = params['profile'] ?? 'default';
        if (_subscriptions[params['session_id']] != owner) {
          send({
            'id': id,
            'error': {
              'code': 4001,
              'message': 'permission_denied',
              'data': {'reason': 'permission_denied'},
            },
          });
          return;
        }
      }
      switch (method) {
        case 'approval.respond':
          if (!approvalAnswer.isCompleted) {
            approvalAnswer.complete({'choice': params['choice']});
          }
          send({
            'id': id,
            'result': {'status': 'resolved', 'prompt_id': params['prompt_id']},
          });
        case 'session.interrupt':
          send({
            'id': id,
            'result': {'status': 'interrupted'},
          });
        case 'session.mutate':
          send({
            'id': id,
            'result': {
              'session_id': params['session_id'],
              'operation': params['operation'],
              'revision': 2,
            },
          });
        case 'client.capabilities':
          capabilitiesAnnounced = params['server_requests'] == true;
          send({
            'id': id,
            'result': {
              'server_requests': ['approval', 'clarify'],
            },
          });
        case 'gateway.ping':
          send({
            'id': id,
            'result': {'ok': true},
          });
        case 'profiles.configure':
          configures.add(params);
          final row = roster.firstWhere((r) => r['name'] == params['name']);
          final revisions = Map<String, dynamic>.from(
            (row['ui_meta_revisions'] ?? const {}) as Map,
          );
          if (params['soul'] != null) {
            profileSoul = params['soul'] as String;
            send({
              'id': id,
              'result': {
                'ok': true,
                'applied': {'soul': true},
              },
            });
            return;
          }
          if (params['ui_meta'] == null) {
            // A model switch; an expensive model wants a confirmation first.
            final ask =
                params['model'] == expensiveModel &&
                params['confirm_expensive_model'] != true;
            if (!ask) {
              profileModel = {
                'provider': params['provider'],
                'default': params['model'],
              };
            }
            send({
              'id': id,
              'result': ask
                  ? {'confirm_required': true, 'confirm_message': 'Pricey.'}
                  : {
                      'ok': true,
                      'applied': {'model': true},
                    },
            });
            return;
          }
          final expected = params['ui_meta_expected_revisions'] as Map?;
          final incoming = params['ui_meta'] as Map;
          final stale = incoming.keys.any(
            (k) => expected != null && expected[k] != (revisions[k] ?? 0),
          );
          if (!stale) {
            final meta = Map<String, dynamic>.from(
              (row['ui_meta'] ?? const {}) as Map,
            );
            for (final e in incoming.entries) {
              meta[e.key as String] = e.value;
              revisions[e.key as String] = ((revisions[e.key] ?? 0) as int) + 1;
            }
            row['ui_meta'] = meta;
            row['ui_meta_revisions'] = revisions;
          }
          send({
            'id': id,
            'result': {
              'ok': !stale,
              'applied': {'ui_meta': !stale},
            },
          });
        case 'profiles.describe':
          send({
            'id': id,
            'result': {
              'name': params['name'],
              'model': profileModel,
              'soul': profileSoul,
            },
          });
        case 'model.options':
          send({
            'id': id,
            'result': {
              'providers': [
                {
                  'slug': 'nous',
                  'name': 'Nous',
                  'models': ['hermes-4', 'hermes-4-pro'],
                },
                {
                  'slug': 'openai-codex',
                  'name': 'Codex',
                  'models': [
                    {'id': 'gpt-6.2-sol'},
                  ],
                },
              ],
            },
          });
        case 'cli.exec':
          cliCalls.add(List<String>.from(params['argv'] as List));
          final argv = cliCalls.last;
          if (argv.length == 5 && argv[1] == 'describe') {
            roster.firstWhere((r) => r['name'] == argv[2])['description'] =
                argv[4];
          }
          if (argv.contains('unset')) {
            profileModel = {'provider': '', 'default': ''};
          }
          send({
            'id': id,
            'result': {'code': 0, 'stdout': ''},
          });
        case 'profiles.list':
          send({
            'id': id,
            'result': {'profiles': roster, 'bot_mode_protocol': true},
          });
        case 'session.create':
          sessionCounter++;
          createParams.add(params);
          _subscriptions['rt$sessionCounter'] =
              (params['profile'] ?? 'default') as String;
          send({
            'id': id,
            'result': {
              'session_id': 'rt$sessionCounter',
              'stored_session_id': 'st$sessionCounter',
              'message_count': 0,
              'messages': [],
              'execution_generation': ?(canonical ? 1 : null),
              'revision': ?(canonical ? 1 : null),
              'info': {
                'model': 'hermes-4',
                'reasoning_effort': 'medium',
                'profile_name': params['profile'],
              },
            },
          });
        case 'session.title':
          titled.add(params['title'] as String);
          send({
            'id': id,
            'result': {'title': params['title']},
          });
        case 'session.resume':
          resumed.add(params['session_id'] as String);
          sessionCounter++;
          _subscriptions['rt$sessionCounter'] =
              (params['profile'] ?? 'default') as String;
          send({
            'id': id,
            'result': {
              'session_id': 'rt$sessionCounter',
              'stored_session_id': params['session_id'],
              'running': false,
              'messages': history,
              'display_messages':
                  ?(canonical && params['display_projection'] == true
                  ? history
                  : null),
              'execution_generation': ?(canonical ? 3 : null),
              'revision': ?(canonical ? 1 : null),
              'info': {'model': 'hermes-4', 'reasoning_effort': 'high'},
            },
          });
        case 'config.get':
          send({
            'id': id,
            'result': {
              'value': params['key'] == 'approvals.mode' ? approvalMode : null,
            },
          });
        case 'config.set':
          configSets.add(params);
          if (params['key'] == 'approvals.mode') {
            approvalMode = params['value'] as String;
          }
          send({
            'id': id,
            'result': {'key': params['key'], 'value': params['value']},
          });
        case 'cron.manage':
          send({
            'id': id,
            'result': {
              'success': true,
              'jobs': [
                {
                  'job_id': 'j1',
                  'name': 'Vibee poptavky',
                  'schedule': '0 9 * * 1-5',
                  'enabled': true,
                  'state': 'scheduled',
                  'next_run_at': '2026-11-23T09:00:00+01:00',
                },
              ],
            },
          });
        case 'file.attach':
          final staged = params['staged_upload'] as Map?;
          final name = params['name'] as String;
          final stored = '/srv/work/attachments/$name';
          send({
            'id': id,
            'result': staged == null
                ? {'attached': false, 'message': 'no upload'}
                : {
                    'attached': true,
                    'name': name,
                    'path': stored,
                    'ref_path': 'attachments/$name',
                    'ref_text': '@file:${formatRef('attachments/$name')}',
                    'uploaded': true,
                  },
          });
        case 'image.attach':
          send({
            'id': id,
            'result': {'attached': true, 'path': params['path'], 'count': 1},
          });
        case 'session.close':
          send({
            'id': id,
            'result': {'closed': true},
          });
        case 'prompt.submit':
          final sid = params['session_id'] as String;
          send({
            'id': id,
            'result': {'status': 'streaming'},
          });
          event('message.start', sid);
          if (askApproval && canonical) {
            send({
              'method': 'event',
              'params': {
                'type': 'approval.request',
                'session_id': sid,
                'execution_generation': 4,
                'payload': {
                  'prompt_id': 'p-approval',
                  'kind': 'approval',
                  'command': 'ls /',
                  'description': 'list root',
                  'choices': ['once', 'deny'],
                },
              },
            });
            await approvalAnswer.future;
            event('approval.settled', sid, {'prompt_id': 'p-approval'});
          } else if (askApproval) {
            send({
              'id': 'srq-approval',
              'method': 'approval',
              'params': {
                'session_id': sid,
                'command': 'ls /',
                'description': 'list root',
                'choices': ['once', 'deny'],
              },
            });
            await approvalAnswer.future;
          }
          event('message.delta', sid, {'text': 'Ahoj, '});
          event('tool.start', sid, {
            'tool_id': 't1',
            'name': 'web_search',
            'preview': 'q',
          });
          event('tool.complete', sid, {
            'tool_id': 't1',
            'name': 'web_search',
            'duration_s': 0.4,
          });
          event('message.delta', sid, {'text': null});
          event('message.delta', sid, {'text': 'svete'});
          event('message.complete', sid, {
            'text': 'Ahoj, svete!',
            'status': 'complete',
          });
        default:
          send({
            'id': id,
            'error': {'code': 4000, 'message': 'unknown method $method'},
          });
      }
    });
  }
}

/// The server's reference quoting (`format_reference_value`).
String formatRef(String v) =>
    RegExp(r'''[\s()\[\]{}<>"'`]''').hasMatch(v) ? '`$v`' : v;
