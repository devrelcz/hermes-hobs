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

  /// Profiles whose `ui_meta` writes are always refused, as a stale revision.
  final Set<String> refuseMeta = {};

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

  /// Session-only model switches: stored session id -> {provider, model}.
  /// `model.options {session_id}` reports them; the profile keeps its own.
  final Map<String, Map<String, String>> sessionModels = {};
  final Map<String, String> _storedOf = {}; // runtime id -> stored id
  static const _modelConfirmToken = 'confirm-expensive-1';
  final List<WebSocket> _sockets = [];

  /// Closes every open socket, like a network drop (the client reconnects).
  Future<void> dropConnections() async {
    for (final ws in List.of(_sockets)) {
      await ws.close();
    }
    _sockets.clear();
  }

  Map<String, String> _profileDefault() {
    final model = profileModel['default']?.toString() ?? '';
    // An inheriting profile runs on the launch profile's model.
    return model.isEmpty
        ? {'provider': 'nous', 'model': 'hermes-4'}
        : {'provider': '${profileModel['provider']}', 'model': model};
  }

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

  /// Canonical: prompts still waiting for an answer, reported in the
  /// `session.resume` snapshot (`prompts`).
  List<Map<String, dynamic>> pendingPrompts = [];

  /// After a `session.resume`, send a stray `message.complete` for the
  /// resumed session, like a server replaying the last turn's events.
  bool replayCompleteOnResume = false;

  /// Images stored by `POST /api/chat/image-upload`: host path -> bytes.
  final Map<String, List<int>> images = {};

  /// Every upload request: `{route, profile, name, bytes}`.
  final List<Map<String, dynamic>> uploads = [];

  /// When set, uploads wait for it before answering (cancel tests).
  Completer<void>? holdUploads;

  /// `GET /api/fs/download` requests (paths).
  final List<String> downloads = [];

  /// Group chats (`groups.*`): room id -> room, and each room's log.
  bool groupsEnabled = true;
  final Map<String, Map<String, dynamic>> rooms = {};
  final Map<String, List<Map<String, dynamic>>> roomLogs = {};

  /// When set, members wait for it before answering a group message.
  Completer<void>? groupHold;
  final List<Map<String, dynamic>> groupActivity = [];
  int _broadcast = 0;

  Map<String, dynamic> _roomState(String id) => {
    ...rooms[id]!,
    'latest_seq': roomLogs[id]!.length,
  };

  void _appendRoom(
    String id,
    String kind,
    Map<String, dynamic> actor,
    Map<String, dynamic> payload,
  ) {
    final log = roomLogs[id]!;
    log.add({
      'room_id': id,
      'seq': log.length + 1,
      'event_id': '$kind:${log.length + 1}',
      'kind': kind,
      'actor': actor,
      'authority_epoch': 1,
      'payload': payload,
      'created_at': 1795205956 + log.length,
    });
  }

  /// When true, the next prompt triggers an approval request before replying.
  bool askApproval = false;

  /// Pause between `message.start` and the rest of a turn (manual runs).
  Duration replyDelay = Duration.zero;
  Completer<Map<String, dynamic>> approvalAnswer = Completer();

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> start({int port = 0}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
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
    _sockets.add(ws);
    void send(Map<String, dynamic> m) {
      // A dropped socket ([dropConnections]) may still have handlers in flight.
      if (ws.closeCode != null) return;
      try {
        ws.add(jsonEncode({'jsonrpc': '2.0', ...m}));
      } on StateError {
        // Closed meanwhile.
      }
    }

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
        case 'session.mutate' when params['operation'] == 'model':
          final payload = (params['payload'] as Map).cast<String, dynamic>();
          final ask =
              payload['model'] == expensiveModel &&
              payload['confirm'] != _modelConfirmToken;
          if (!ask) {
            sessionModels[_storedOf[params['session_id']]!] = {
              'provider': payload['provider'] as String,
              'model': payload['model'] as String,
            };
          }
          send({
            'id': id,
            'result': {
              'session_id': params['session_id'],
              'operation': 'model',
              'revision': 2,
              'status': ask ? 'confirmation_required' : 'applied',
              if (ask) 'confirm': _modelConfirmToken,
              if (ask) 'confirm_message': 'Pricey.',
            },
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
          final stale =
              refuseMeta.contains(params['name']) ||
              incoming.keys.any(
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
          final stored = _storedOf[params['session_id']];
          final current =
              (stored == null ? null : sessionModels[stored]) ??
              _profileDefault();
          send({
            'id': id,
            'result': {
              ...current,
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
          _storedOf['rt$sessionCounter'] = 'st$sessionCounter';
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
          _storedOf['rt$sessionCounter'] = params['session_id'] as String;
          send({
            'id': id,
            'result': {
              'session_id': 'rt$sessionCounter',
              'stored_session_id': params['session_id'],
              // A prompt waiting for an answer means the turn is not over.
              'running': canonical && pendingPrompts.isNotEmpty,
              'messages': history,
              'display_messages':
                  ?(canonical && params['display_projection'] == true
                  ? history
                  : null),
              'execution_generation': ?(canonical ? 3 : null),
              'revision': ?(canonical ? 1 : null),
              'prompts': ?(canonical ? pendingPrompts : null),
              'info': {'model': 'hermes-4', 'reasoning_effort': 'high'},
            },
          });
          if (replayCompleteOnResume) {
            event('message.complete', 'rt$sessionCounter', {
              'text': 'Monitoring sverim Analytikovi.',
              'status': 'complete',
            });
          }
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
          if (params['key'] == 'model') {
            // The dashboard's `<model> --provider <slug> --session`.
            final words = (params['value'] as String).split(' ');
            final scoped = words.contains('--session');
            final provider = words[words.indexOf('--provider') + 1];
            if (words.first == expensiveModel &&
                params['confirm_expensive_model'] != true) {
              send({
                'id': id,
                'result': {
                  'confirm_required': true,
                  'confirm_message': 'Pricey.',
                },
              });
              return;
            }
            if (scoped) {
              sessionModels[_storedOf[params['session_id']]!] = {
                'provider': provider,
                'model': words.first,
              };
            } else {
              profileModel = {'provider': provider, 'default': words.first};
            }
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
        case 'groups.capabilities' when groupsEnabled:
          send({
            'id': id,
            'result': {
              'protocol_version': 2,
              'driver': true,
              'methods': [
                'groups.list',
                'groups.state',
                'groups.log',
                'groups.create',
                'groups.send',
                'groups.stop',
                'groups.rename',
                'groups.disband',
              ],
              'seatable_profiles': [for (final r in roster) r['name']],
            },
          });
        case 'groups.list' when groupsEnabled:
          send({
            'id': id,
            'result': {
              'rooms': [for (final rid in rooms.keys) _roomState(rid)],
              'next_offset': null,
            },
          });
        case 'groups.create' when groupsEnabled:
          final rid = params['room_id'] as String;
          rooms[rid] = {
            'room_id': rid,
            'name': params['name'],
            'members': params['members'],
            'authority_epoch': 1,
            'created_at': 1795205794,
            'updated_at': 1795205794,
          };
          roomLogs[rid] = [];
          send({
            'id': id,
            'result': {'room': _roomState(rid)},
          });
        case 'groups.state' when groupsEnabled:
          final rid = params['room_id'] as String;
          send({
            'id': id,
            'result': {
              'room': _roomState(rid),
              'change_events': true,
              'context': {'routing': 'everyone'},
              'driver_status': {
                'running': true,
                'working': groupActivity.isNotEmpty,
                'member_activity': groupActivity,
                'pending_actions': [],
                'max_rounds': 3,
              },
            },
          });
        case 'groups.log' when groupsEnabled:
          final rid = params['room_id'] as String;
          final since = params['since_seq'] as int;
          final limit = params['limit'] as int;
          final rest = roomLogs[rid]!.skip(since).toList();
          send({
            'id': id,
            'result': {
              'events': rest.take(limit).toList(),
              'latest_seq': roomLogs[rid]!.length,
              'has_more': rest.length > limit,
            },
          });
        case 'groups.rename' when groupsEnabled:
          final rid = params['room_id'] as String;
          rooms[rid]!['name'] = params['name'];
          send({
            'id': id,
            'result': {'room': _roomState(rid)},
          });
        case 'groups.disband' when groupsEnabled:
          final rid = params['room_id'] as String;
          rooms.remove(rid);
          send({
            'id': id,
            'result': {
              'tombstone': {'room_id': rid, 'disbanded_at': 1795206000.5},
            },
          });
        case 'groups.send' when groupsEnabled:
          final rid = params['room_id'] as String;
          final eventId = params['event_id'] as String;
          final payload = (params['payload'] as Map).cast<String, dynamic>();
          _appendRoom(rid, 'message.user', {
            'id': 'desktop',
            'kind': 'user',
          }, payload);
          final discussion = roomLogs[rid]!.last['event_id'];
          send({
            'id': id,
            'result': {'accepted': true, 'client_event_id': eventId},
          });
          void changed() => send({
            'method': 'event',
            'params': {
              'type': 'groups.changed',
              'session_id': '',
              'payload': {
                'room_ids': [rid],
                'broadcast_id': 'b:${++_broadcast}',
              },
            },
          });
          changed();
          final members = (rooms[rid]!['members'] as List).cast<Map>();
          final hold = groupHold;
          if (hold != null) {
            groupActivity
              ..clear()
              ..add({
                'member_id': members.first['member_id'],
                'status': 'running',
                'started_at': 1795205957,
                'tool': 'web_search',
              });
            changed();
            await hold.future;
            groupActivity.clear();
          }
          for (final m in members) {
            final mid = m['member_id'] as String;
            _appendRoom(
              rid,
              'message.member',
              {'id': mid, 'kind': 'member', 'profile': m['profile']},
              {
                'discussion_event_id': discussion,
                'member_id': mid,
                'text': 'Ahoj od $mid',
                'thread_id': payload['thread_id'],
              },
            );
            _appendRoom(
              rid,
              'turn.settled',
              {'id': 'install:fake', 'kind': 'gateway'},
              {
                'discussion_event_id': discussion,
                'member_id': mid,
                'passed': false,
              },
            );
          }
          _appendRoom(
            rid,
            'room.activity',
            {'id': 'install:fake', 'kind': 'gateway'},
            {'status': 'settled', 'reason_code': 'silent_round'},
          );
          changed();
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
          if (replyDelay > Duration.zero) await Future.delayed(replyDelay);
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
