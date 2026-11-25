import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/attachments.dart';
import '../api/hermes_rpc.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import 'mentions.dart';
import 'notifications.dart';

enum ChatPhase { starting, idle, running, failed }

/// The hob's forever-chat ("Bot Chat"), as the Hermes dashboard uses it.
///
/// Open: `session.resume` the profile's canonical session (history included),
/// or, on a hob's first-ever chat, `session.create {title: "Bot Chat"}` and
/// claim the title with `session.title`. Then `prompt.submit` -> stream of
/// `message.*` / `tool.*` events -> `message.complete`. The runtime session id
/// changes after a reconnect; the durable id does not.
///
/// A [watchOnly] controller only listens, so a Hob whose chat is not open
/// can still notify: it attaches the existing Bot Chat without its history
/// (`omit_messages`), never creates one, and skips the model and approval
/// mode reads. [promote] turns it into a full chat when the user opens it.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.rpc,
    required Hob hob,
    this.findCanonical,
    this.onTurnSettled,
    this.onAlert,
    this.onPromptSent,
    this.roster,
    this._watchOnly = false,
    this.queue,
  }) {
    _hob = hob;
    _eventSub = rpc.events.listen(_onEvent);
    _requestSub = rpc.serverRequests.listen(_onServerRequest);
    _reconnectSub = rpc.onReconnected.listen((_) {
      // Watchers re-attach one after another, not all at once.
      final q = queue;
      if (_watchOnly && q != null) {
        unawaited(q(_reattach));
      } else {
        unawaited(_reattach());
      }
    });
    _statusSub = rpc.statusStream.listen((_) => _notify());
  }

  bool _watchOnly;

  /// Runs a watcher's (re)attach in turn with the other watchers.
  final Future<void> Function(Future<void> Function() job)? queue;

  /// True while this chat only watches for notifications (see the class).
  bool get watchOnly => _watchOnly;

  String? _watchTried;
  DateTime? _watchTriedAt;

  /// Attaches a watcher, unless it is attached already. A failed attach is
  /// retried when the Bot Chat changed or a while has passed.
  Future<void> watch() {
    if (!_watchOnly || _disposed || _sessionId != null) return Future.value();
    final id = _storedId ?? _hob.canonical?.resumeId;
    if (id == null) return Future.value();
    final at = _watchTriedAt;
    if (id == _watchTried &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 2)) {
      return Future.value();
    }
    _watchTried = id;
    _watchTriedAt = DateTime.now();
    return start();
  }

  /// The user opened this chat: load it fully (history, model, approval
  /// mode). What the watcher already alerted stays known.
  Future<void> promote() async {
    if (!_watchOnly) return;
    _watchOnly = false;
    final pending = _starting;
    if (pending != null) await pending;
    if (_disposed) return;
    await reload();
  }

  final HermesRpc rpc;
  late Hob _hob;

  /// Re-reads the roster and returns the hob's current canonical session.
  final Future<SessionSummary?> Function(String profile)? findCanonical;

  /// Called after a turn ends (roster preview / unread bookkeeping).
  final void Function(Hob hob)? onTurnSettled;

  /// A finished reply or a prompt that blocks the hob, as it happens live.
  /// Never fired for what a `session.resume` replays, and at most once per
  /// prompt / turn, so a reconnect does not repeat it.
  final void Function(Hob hob, HobAlert alert)? onAlert;

  /// The user sent a prompt (a good moment to ask for notifications).
  final void Function()? onPromptSent;

  /// The Hobs this one can @-mention (the visible roster).
  final List<Hob> Function()? roster;

  /// Hobs offered for an `@query` typed in this chat.
  List<Hob> mentionCandidates(String query) =>
      Mentions.candidates(query, roster?.call() ?? const [], _hob.name);

  /// True when [tag] (`@name`) names another Hob of the roster.
  bool mentionsHob(String tag) =>
      Mentions.resolve(tag, roster?.call() ?? const [], _hob.name).isNotEmpty;

  /// The tag picking [other] inserts, without the `@`.
  String mentionTag(Hob other) =>
      Mentions.tag(other, roster?.call() ?? const []);

  late final StreamSubscription<GatewayEvent> _eventSub;
  late final StreamSubscription<ServerRequest> _requestSub;
  late final StreamSubscription<void> _reconnectSub;
  late final StreamSubscription<ConnectionStatus> _statusSub;

  final List<ChatMessage> messages = [];
  ChatPhase phase = ChatPhase.starting;

  /// Why the last action failed, in the current language.
  String? get error => _error?.call();

  /// Kept as builders, not text, so a language switch re-words them.
  String Function()? _error;

  /// What the Hob is doing right now (a tool, a status line).
  String? get statusText => _status?.call();
  String Function()? _status;

  void _setStatus(String? text) => _status = text == null ? null : () => text;

  /// The model this session runs on, and its provider. A session-only
  /// switch shows here, not in the hob's profile.
  String? model;
  String? modelProvider;
  String? reasoningEffort;

  /// The hob's own model (its profile default, resolved), from
  /// `model.options {profile}`. Null until known.
  ModelChoice? defaultModel;

  /// Providers the session can switch to, from `model.options`.
  List<ModelProvider> modelProviders = const [];

  /// A switch the server will apply after the running turn (`deferred`).
  ModelChoice? _deferredModel;

  /// Canonical: the confirmation token the server issued for an expensive
  /// model, keyed by the choice it was issued for.
  final Map<ModelChoice, String> _modelConfirmTokens = {};

  /// Profile-wide `approvals.mode` (manual / smart / off). Null until known.
  String? approvalMode;

  String? _sessionId; // runtime id, valid for this socket
  String? _storedId; // durable id, survives reconnects
  ChatMessage? _current; // assistant row being streamed
  bool _segmentBreak = false;
  bool _disposed = false;
  Future<void>? _starting;

  ServerRequest? _approvalRequest;
  PendingApproval? approval;
  ServerRequest? _clarifyRequest;
  List<ClarifyQuestion>? clarify;

  // Canonical dialect (session authority) bookkeeping: controls and prompt
  // answers are fenced by the turn's execution generation, edits by the
  // session revision; approval/clarify arrive as `*.request` events.
  int? _generation;
  int? _revision;
  String? _approvalPromptId;
  int? _approvalGeneration;
  final Map<String, int> _clarifyPrompts = {}; // prompt_id -> generation

  /// Prompts (`prompt:<id>`, `request:<id>`) and turns (`turn:<generation>`)
  /// already alerted or seen in a snapshot, so replays don't alert again.
  /// Server-request ids are only unique while the request is open (a new
  /// socket may count from the start again), so `request:` keys are dropped
  /// once the request is answered or its turn ends.
  final Set<String> _alerted = {};

  void _forgetRequestAlerts() =>
      _alerted.removeWhere((k) => k.startsWith('request:'));

  /// True after the first `session.resume` / `session.create` of this chat.
  /// Prompts in that first snapshot are what the user opens the chat to;
  /// prompts first seen in a later (reconnect) snapshot arrived while the
  /// socket was down and still deserve an alert.
  bool _attached = false;

  Hob get hob => _hob;
  ConnectionStatus get connection => rpc.status;
  bool get busy => phase == ChatPhase.running;
  bool get ready => _sessionId != null && phase != ChatPhase.starting;

  /// Text of the newest user prompt (pinned at the top of the chat).
  String? get lastPrompt {
    for (final m in messages.reversed) {
      if (m.role == ChatRole.user) return m.text;
    }
    return null;
  }

  void updateHob(Hob hob) {
    final old = _hob;
    _hob = hob;
    // An edited profile shows in the chat header right away.
    if (old.displayName != hob.displayName ||
        old.shape != hob.shape ||
        old.color != hob.color ||
        old.description != hob.description) {
      notifyListeners();
    }
  }

  Future<void> start() =>
      _starting ??= _open().whenComplete(() => _starting = null);

  /// Re-reads the transcript from the server.
  Future<void> reload() {
    _sessionId = null;
    return start();
  }

  Future<void> _open() async {
    if (_disposed) return;
    phase = ChatPhase.starting;
    _error = null;
    _notify();
    try {
      await rpc.connect();
      final stored = _storedId ?? _hob.canonical?.resumeId;
      if (stored != null) {
        try {
          await _resume(stored, history: !_watchOnly);
          return;
        } on RpcException catch (e) {
          // Only a vanished row (archived, deleted) mints a new Bot Chat;
          // anything else (bad params, server error) must surface.
          if (!e.isNotFound) rethrow;
        }
      }
      // A watcher never creates the Bot Chat: there is nothing to watch.
      if (_watchOnly) throw StateError('no Bot Chat');
      await _createCanonical();
    } catch (e) {
      phase = ChatPhase.failed;
      _error = () => Strings.current.openChatFailed(e);
      _notify();
    }
  }

  /// Attaches the session. Without [history] the server leaves the
  /// transcript out (`omit_messages`): a watcher needs only the live events.
  Future<void> _resume(String storedId, {bool history = true}) async {
    final params = rpc.canonical
        // The canonical resume contract has no close_on_disconnect /
        // inline_images; display_projection returns display rows (text,
        // tool name + context) instead of raw model messages.
        ? {
            'session_id': storedId,
            'profile': _hob.name,
            'display_projection': true,
            if (!history) 'omit_messages': true,
          }
        : {
            'session_id': storedId,
            'profile': _hob.name,
            'close_on_disconnect': false,
            'inline_images': false,
            if (!history) 'omit_messages': true,
          };
    final res = await rpc.requestWith(
      'session.resume',
      params,
      timeout: const Duration(seconds: 90),
    ) as Map;
    _sessionId = res['session_id'] as String?;
    _storedId = (res['stored_session_id'] as String?) ?? storedId;
    _adoptSnapshot(res);
    messages
      ..clear()
      ..addAll(historyToMessages(res['display_messages'] ?? res['messages']));
    _current = null;
    final running = res['running'] == true || res['inflight'] == true;
    phase = running ? ChatPhase.running : ChatPhase.idle;
    _clearPrompts();
    final prompts = res['prompts'];
    if (prompts is List) {
      for (final pr in prompts.whereType<Map>()) {
        _onCanonicalPrompt(
          '${pr['kind']}.request',
          Map<String, dynamic>.from(pr),
          (pr['execution_generation'] as num?)?.toInt(),
          alert: _attached,
        );
      }
    }
    final pending = res['open_requests'];
    // Server requests from before the reconnect are gone unless the server
    // still lists them; their ids may be reused by the new socket.
    final stillOpen = {
      if (pending is List)
        for (final r in pending.whereType<Map>()) 'request:${r['id']}',
    };
    _alerted.removeWhere(
      (k) => k.startsWith('request:') && !stillOpen.contains(k),
    );
    if (pending is List) {
      for (final r in pending.whereType<Map>()) {
        // Requests opened before we attached: answer through request.answer.
        final id = r['id'];
        final method = r['method']?.toString();
        final params = r['params'];
        if (id != null && method != null && params is Map) {
          _onServerRequest(
            ServerRequest.detached(
              rpc,
              id,
              method,
              Map<String, dynamic>.from(params)
                ..putIfAbsent('session_id', () => _sessionId),
            ),
            alert: _attached,
          );
        }
      }
    }
    _attached = true;
    _notify();
  }

  Future<void> _createCanonical() async {
    final res = await rpc.requestWith(
      'session.create',
      rpc.canonical
          ? {
              'profile': _hob.name,
              'title': Hob.canonicalTitle,
              'hidden': true,
              'follow_profile_config': true,
              'request_id': uuidV4(),
              'source': 'gui',
            }
          : {
              'profile': _hob.name,
              'title': Hob.canonicalTitle,
              'hidden': true,
              'follow_profile_config': true,
              'close_on_disconnect': false,
            },
      timeout: const Duration(seconds: 90),
    ) as Map;
    final runtime = res['session_id'] as String?;
    _sessionId = runtime;
    _storedId = (res['stored_session_id'] as String?) ?? runtime;
    _adoptSnapshot(res);
    // The canonical owner records the create's title itself; the legacy
    // dispatcher defers it, so claim it explicitly there.
    if (runtime != null && !rpc.canonical) {
      try {
        // Materialize the row and claim the canonical title right away, so a
        // second open (here or in the dashboard) finds it instead of minting
        // a duplicate.
        await rpc.request('session.title', {
          'session_id': runtime,
          'title': Hob.canonicalTitle,
        });
      } on RpcException catch (e) {
        if (e.message.toLowerCase().contains('already in use') &&
            findCanonical != null) {
          // Someone else created the Bot Chat meanwhile: adopt theirs.
          final winner = await findCanonical!(_hob.name);
          if (winner != null) {
            rpc.request('session.close', {'session_id': runtime}).ignore();
            await _resume(winner.resumeId);
            return;
          }
        }
      }
    }
    messages.clear();
    phase = ChatPhase.idle;
    _attached = true;
    _notify();
  }

  Future<void> _reattach() async {
    final stored = _storedId;
    if (stored == null || _disposed) return;
    final wasRunning = phase == ChatPhase.running;
    try {
      // A watcher fetches the transcript only when a turn may have ended
      // meanwhile: the reply is in it.
      await _resume(stored, history: !_watchOnly || wasRunning);
      if (wasRunning &&
          phase != ChatPhase.running &&
          approval == null &&
          clarify == null) {
        // The turn ended while the socket was down: its message.complete
        // never reached us, so this is the only chance to tell the user.
        // Only with a reply after the prompt: a turn lost to a server
        // restart did not "finish".
        final reply = _lastAssistantText();
        if (reply.isNotEmpty) _alertReply(reply, key: null);
        onTurnSettled?.call(_hob);
      }
    } catch (e) {
      _error = () => Strings.current.recoverFailed(e);
      _notify();
    }
  }

  /// Maps `session.resume` / `session.history` rows to transcript rows.
  /// Consecutive tool rows fold into one activity line.
  static List<ChatMessage> historyToMessages(Object? rows) {
    final out = <ChatMessage>[];
    if (rows is! List) return out;
    for (final r in rows.whereType<Map>()) {
      final role = r['role']?.toString();
      final time = epochToDate(r['timestamp']);
      final text = (r['text'] ?? r['content'])?.toString() ?? '';
      switch (role) {
        case 'user':
          // Images are appended after the text, the mention note sits at
          // its end: take the references out first.
          final parsed = parseAttachmentRefs(text);
          final typed = Mentions.stripNote(parsed.text);
          if (typed.trim().isEmpty && parsed.attachments.isEmpty) continue;
          out.add(
            ChatMessage(role: ChatRole.user, text: typed, time: time)
              ..attachments.addAll(parsed.attachments),
          );
        case 'assistant':
          if (text.trim().isEmpty) continue;
          out.add(
            ChatMessage(role: ChatRole.assistant, text: text, time: time),
          );
        case 'tool':
          final last = out.isNotEmpty ? out.last : null;
          final row = (last != null && last.role == ChatRole.activity)
              ? last
              : (ChatMessage(role: ChatRole.activity, time: time)
                  ..let(out.add));
          row.tools.add(
            ToolActivity(
              id: r['tool_call_id']?.toString() ?? '${row.tools.length}',
              name: r['name']?.toString() ?? 'tool',
              preview: r['context']?.toString(),
              state: ToolState.done,
            ),
          );
        default:
          // system rows are model scaffolding; skip.
          break;
      }
    }
    return out;
  }

  /// Sends [text] with already uploaded [attachments] (see
  /// `ComposerDraft`), the way the dashboard composer does.
  Future<void> send(
    String text, {
    List<ChatAttachment> attachments = const [],
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    if (_sessionId == null) {
      _error = () => Strings.current.chatNotReady;
      _notify();
      return;
    }
    messages.add(
      ChatMessage(role: ChatRole.user, text: trimmed)
        ..attachments.addAll(attachments),
    );
    // Tagged Hobs get an identification note, like on the dashboard; the
    // transcript keeps the text as typed.
    final prompt = Mentions.annotate(
      trimmed,
      roster?.call() ?? const [],
      _hob.name,
    );
    phase = ChatPhase.running;
    _error = null;
    _status = null;
    _notify();
    onPromptSent?.call();
    try {
      await _submit(prompt, attachments);
    } on RpcException catch (e) {
      if (e.isSessionGone && _storedId != null) {
        await _reattach();
        try {
          await _submit(prompt, attachments);
          return;
        } catch (e2) {
          _failTurn('$e2');
          return;
        }
      }
      _failTurn(e.message);
    } catch (e) {
      _failTurn('$e');
    }
  }

  Future<void> _submit(String text, List<ChatAttachment> attachments) async {
    final turn = attachments.isEmpty
        ? PreparedTurn(text, const [])
        : await prepareTurn(
            rpc,
            sessionId: _sessionId!,
            text: text,
            attachments: attachments,
            scoped: _scoped,
          );
    await rpc.requestWith(
      'prompt.submit',
      _scoped({
        'session_id': _sessionId,
        'text': turn.text,
        if (turn.images.isNotEmpty) 'attachments': turn.images,
        // The canonical owner admits identified input only.
        if (rpc.canonical) 'submission_id': uuidV4(),
      }),
      timeout: const Duration(minutes: 5),
    );
  }

  /// Canonical dialect: the gateway routes every frame by its `profile` to
  /// that profile's owner, and the `session.resume` subscription lives there.
  /// A session verb without it lands on the launch profile's owner, which
  /// refuses the stranger (4001 `permission_denied`).
  Map<String, dynamic> _scoped(Map<String, dynamic> params) =>
      rpc.canonical ? {'profile': _hob.name, ...params} : params;

  Future<void> interrupt() async {
    final sid = _sessionId;
    if (sid == null) return;
    try {
      await rpc.request(
        'session.interrupt',
        _scoped({
          'session_id': sid,
          if (rpc.canonical && _generation != null)
            'execution_generation': _generation,
        }),
      );
    } catch (e) {
      _error = () => Strings.current.interruptFailed(e);
      _notify();
    }
  }

  static const effortLevels = ['minimal', 'low', 'medium', 'high', 'xhigh'];

  /// Session-scoped reasoning effort (like the dashboard's "Med" chip).
  Future<void> setReasoningEffort(String level) async {
    final sid = _sessionId;
    if (sid == null) return;
    final previous = reasoningEffort;
    reasoningEffort = level;
    _notify();
    try {
      if (rpc.canonical) {
        // Canonical: a revision-fenced `session.mutate` of the frozen policy.
        final res = await rpc.request(
          'session.mutate',
          _scoped({
            'session_id': sid,
            'request_id': uuidV4(),
            'expected_revision': _revision ?? 0,
            'operation': 'reasoning',
            'payload': {'effort': level},
            'expected_generation': ?_generation,
          }),
        );
        if (res is Map && res['revision'] is num) {
          _revision = (res['revision'] as num).toInt();
        }
      } else {
        await rpc.request('config.set', {
          'session_id': sid,
          'key': 'reasoning',
          'value': level,
          'scope': 'session',
        });
      }
    } catch (e) {
      reasoningEffort = previous;
      _error = () => Strings.current.reasoningChangeFailed(e);
      _notify();
    }
  }

  static const approvalModes = ['manual', 'smart', 'off'];

  /// Persistent `approvals.mode` of this hob's profile, the same setting as
  /// the dashboard's approval mode. It applies to every session of the hob,
  /// not only this chat, so it is sent with the profile, not as a session
  /// mutation.
  Future<void> setApprovalMode(String mode) async {
    final previous = approvalMode;
    approvalMode = mode;
    _notify();
    try {
      final res = await rpc.request('config.set', {
        'profile': _hob.name,
        'session_id': ?_sessionId,
        'key': 'approvals.mode',
        'value': mode,
      });
      final v = res is Map ? res['value'] : null;
      if (v is String && approvalModes.contains(v)) approvalMode = v;
      _notify();
    } catch (e) {
      approvalMode = previous;
      _error = () => Strings.current.approvalModeChangeFailed(e);
      _notify();
    }
  }

  /// Reads the current mode when the session snapshot did not carry it
  /// (canonical sessions report only `yolo`). Failure keeps the chip blank.
  Future<void> _loadApprovalMode() async {
    try {
      final res = await rpc.request('config.get', {
        'profile': _hob.name,
        'key': 'approvals.mode',
      });
      final v = res is Map ? res['value'] : null;
      if (v is String && approvalModes.contains(v)) {
        approvalMode = v;
        _notify();
      }
    } catch (_) {}
  }

  // --- session model -------------------------------------------------------

  ModelChoice? get sessionModel => model == null
      ? null
      : ModelChoice(provider: modelProvider ?? '', model: model!);

  /// True when this chat runs on another model than the hob's default.
  bool get modelOverridden {
    final current = sessionModel;
    final fallback = defaultModel;
    return current != null && fallback != null && !current.same(fallback);
  }

  /// Re-reads the session's model, the hob's default and the providers
  /// (`model.options` with and without the session). Failure keeps what is
  /// known.
  Future<void> loadModels() async {
    final sid = _sessionId;
    try {
      final results = await Future.wait([
        if (sid != null)
          rpc.requestWith('model.options', {
            'profile': _hob.name,
            'session_id': sid,
          }, timeout: const Duration(seconds: 30)),
        rpc.requestWith('model.options', {
          'profile': _hob.name,
        }, timeout: const Duration(seconds: 30)),
      ]);
      if (sid != _sessionId) return; // reattached meanwhile
      final fallback = ModelOptions.fromJson(results.last);
      final session = sid == null ? null : ModelOptions.fromJson(results.first);
      defaultModel = fallback.current ?? defaultModel;
      final providers = session?.providers.isNotEmpty == true
          ? session!.providers
          : fallback.providers;
      if (providers.isNotEmpty) modelProviders = providers;
      final current = session?.current;
      if (current != null && _deferredModel == null) {
        model = current.model;
        modelProvider = current.provider;
      }
      _notify();
    } catch (_) {}
  }

  /// Switches the model of this session only; the hob's profile keeps its
  /// default. Returns the server's question when the model needs an explicit
  /// confirmation (an expensive one): call again with [confirmed].
  Future<ModelSwitch> setSessionModel(
    ModelChoice choice, {
    bool confirmed = false,
  }) async {
    final sid = _sessionId;
    if (sid == null) return const ModelSwitch.failed();
    final previous = sessionModel;
    try {
      final res = await _switchModel(sid, choice, confirmed);
      if (res is Map &&
          (res['confirm_required'] == true ||
              res['status'] == 'confirmation_required')) {
        final token = res['confirm'];
        if (token is String) _modelConfirmTokens[choice] = token;
        return ModelSwitch.confirm(res['confirm_message']?.toString() ?? '');
      }
      _modelConfirmTokens.remove(choice);
      model = choice.model;
      modelProvider = choice.provider;
      final deferred = res is Map && res['status'] == 'deferred';
      _deferredModel = deferred ? choice : null;
      _error = null;
      _notify();
      if (!deferred) unawaited(loadModels());
      return deferred ? const ModelSwitch.deferred() : const ModelSwitch.done();
    } catch (e) {
      model = previous?.model;
      modelProvider = previous?.provider;
      _error = () => Strings.current.modelChangeFailed(e);
      _notify();
      return const ModelSwitch.failed();
    }
  }

  /// Puts this session back on the hob's default model. There is no
  /// "forget the session model" call, so this switches to the default.
  Future<ModelSwitch> useDefaultModel({bool confirmed = false}) async {
    final fallback = defaultModel;
    if (fallback == null) return const ModelSwitch.failed();
    return setSessionModel(fallback, confirmed: confirmed);
  }

  Future<Object?> _switchModel(
    String sid,
    ModelChoice choice,
    bool confirmed, {
    bool retried = false,
  }) async {
    if (!rpc.canonical) {
      // Legacy dispatcher: the dashboard's `/model … --session` as config.
      return rpc.request('config.set', {
        'session_id': sid,
        'key': 'model',
        'value': '${choice.model} --provider ${choice.provider} --session',
        if (confirmed) 'confirm_expensive_model': true,
      });
    }
    // Canonical: a revision-fenced `session.mutate` of the session's model;
    // an expensive model is confirmed by echoing the server's token.
    final token = confirmed ? _modelConfirmTokens[choice] : null;
    try {
      final res = await rpc.request(
        'session.mutate',
        _scoped({
          'session_id': sid,
          'request_id': uuidV4(),
          'expected_revision': _revision ?? 0,
          'operation': 'model',
          'payload': {
            'model': choice.model,
            'provider': choice.provider,
            'confirm': ?token,
          },
          'expected_generation': ?_generation,
        }),
      );
      if (res is Map && res['revision'] is num) {
        _revision = (res['revision'] as num).toInt();
      }
      return res;
    } on RpcException catch (e) {
      // Someone else edited the session meanwhile: adopt and retry once.
      final data = e.data;
      final reason = data is Map ? data['reason'] : null;
      if (retried ||
          data is! Map ||
          (reason != 'revision_conflict' && reason != 'stale_generation')) {
        rethrow;
      }
      if (data['revision'] is num) {
        _revision = (data['revision'] as num).toInt();
      }
      if (data['execution_generation'] is num) {
        _generation = (data['execution_generation'] as num).toInt();
      }
      return _switchModel(sid, choice, confirmed, retried: true);
    }
  }

  void toggleActivity(ChatMessage m) {
    m.expanded = !m.expanded;
    _notify();
  }

  // --- approvals / clarify -------------------------------------------------

  void answerApproval(String choice) {
    final promptId = _approvalPromptId;
    if (promptId != null && _sessionId != null) {
      rpc
          .request(
            'approval.respond',
            _scoped({
              'session_id': _sessionId,
              'execution_generation': _approvalGeneration ?? _generation ?? 0,
              'prompt_id': promptId,
              'choice': choice,
            }),
          )
          .catchError((Object e) {
            _error = () => Strings.current.approvalAnswerFailed(e);
            _notify();
            return null;
          });
    }
    final answered = _approvalRequest;
    answered?.respond({'choice': choice});
    if (answered != null) _alerted.remove('request:${answered.id}');
    _approvalRequest = null;
    _approvalPromptId = null;
    approval = null;
    _notify();
  }

  void answerClarify(Map<String, String?>? answers) {
    if (_clarifyPrompts.isNotEmpty && _sessionId != null) {
      // Canonical: one `clarify.respond` per question prompt; an empty
      // answer skips it.
      for (final e in _clarifyPrompts.entries) {
        rpc
            .request(
              'clarify.respond',
              _scoped({
                'session_id': _sessionId,
                'execution_generation': e.value,
                'prompt_id': e.key,
                'answer': answers?[e.key] ?? '',
              }),
            )
            .catchError((Object err) {
              _error = () => Strings.current.clarifyAnswerFailed(err);
              _notify();
              return null;
            });
      }
      _clarifyPrompts.clear();
    }
    final req = _clarifyRequest;
    if (req != null) {
      _alerted.remove('request:${req.id}');
      req.respond(
        answers == null ? {} : {'answers': answers, 'outcome': 'submitted'},
      );
    }
    _clarifyRequest = null;
    clarify = null;
    _notify();
  }

  void _clearPrompts() {
    _approvalRequest = null;
    _approvalPromptId = null;
    approval = null;
    _clarifyRequest = null;
    _clarifyPrompts.clear();
    clarify = null;
  }

  /// Snapshot fields of `session.resume` / `session.create` results.
  void _adoptSnapshot(Map res) {
    _applyInfo(res['info']);
    final g = res['execution_generation'];
    if (g is num) _generation = g.toInt();
    final r = res['revision'];
    if (r is num) _revision = r.toInt();
    if (_watchOnly) return;
    if (approvalMode == null) unawaited(_loadApprovalMode());
    // The snapshot's info may describe the profile, not a session-only
    // switch (a lazy runtime): re-read the session's model on every attach.
    unawaited(loadModels());
  }

  /// Canonical `approval.request` / `clarify.request` (live event or a
  /// snapshot's pending prompt).
  void _onCanonicalPrompt(
    String type,
    Map<String, dynamic> p,
    int? generation, {
    required bool alert,
  }) {
    final promptId = p['prompt_id']?.toString();
    if (promptId == null) return;
    final kind = switch (type) {
      'approval.request' => AlertKind.approval,
      'clarify.request' => AlertKind.clarify,
      _ => null,
    };
    if (kind != null) {
      _raise(
        'prompt:$promptId',
        HobAlert(
          kind,
          kind == AlertKind.approval
              ? _approvalText(p)
              : p['question']?.toString() ?? '',
        ),
        live: alert,
      );
    }
    final gen = generation ?? _generation ?? 0;
    final choices =
        (p['choices'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    if (type == 'approval.request') {
      _approvalPromptId = promptId;
      _approvalGeneration = gen;
      approval = PendingApproval(
        command: p['command']?.toString() ?? '',
        description: p['description']?.toString() ?? '',
        choices: choices.isEmpty ? const ['once', 'deny'] : choices,
        toolName: p['tool_name']?.toString(),
      );
    } else if (type == 'clarify.request') {
      _clarifyPrompts[promptId] = gen;
      final list = [...?clarify]..removeWhere((q) => q.qid == promptId);
      list.add(
        ClarifyQuestion(
          qid: promptId,
          question: p['question']?.toString() ?? '',
          choices: choices.isEmpty ? null : choices,
          multiSelect: p['multi_select'] == true,
        ),
      );
      clarify = list;
    }
  }

  void _onPromptSettled(String promptId) {
    if (_approvalPromptId == promptId) {
      _approvalPromptId = null;
      approval = null;
    }
    if (_clarifyPrompts.remove(promptId) != null) {
      final list = [...?clarify]..removeWhere((q) => q.qid == promptId);
      clarify = list.isEmpty ? null : list;
    }
  }

  void _onServerRequest(ServerRequest req, {bool alert = true}) {
    if (req.sessionId == null || req.sessionId != _sessionId) return;
    final p = req.params;
    switch (req.method) {
      case 'approval':
        _raise(
          'request:${req.id}',
          HobAlert(AlertKind.approval, _approvalText(p)),
          live: alert,
        );
        _approvalRequest = req;
        approval = PendingApproval(
          command: p['command']?.toString() ?? '',
          description: p['description']?.toString() ?? '',
          choices:
              (p['choices'] as List?)?.map((e) => e.toString()).toList() ??
              const ['once', 'deny'],
          toolName: p['tool_name']?.toString(),
        );
        _notify();
      case 'clarify':
        final qs = (p['questions'] as List?) ?? const [];
        final first = qs.whereType<Map>().firstOrNull;
        _raise(
          'request:${req.id}',
          HobAlert(AlertKind.clarify, first?['question']?.toString() ?? ''),
          live: alert,
        );
        _clarifyRequest = req;
        clarify = [
          for (final q in qs.whereType<Map>())
            ClarifyQuestion(
              qid: q['qid']?.toString() ?? '',
              question: q['question']?.toString() ?? '',
              choices: (q['choices'] as List?)
                  ?.map((e) => e.toString())
                  .toList(),
              multiSelect: q['multi_select'] == true,
            ),
        ];
        _notify();
      default:
        break;
    }
  }

  // --- events --------------------------------------------------------------

  ChatMessage _newAssistant() {
    final m = ChatMessage(role: ChatRole.assistant, streaming: true);
    messages.add(m);
    _current = m;
    _segmentBreak = false;
    return m;
  }

  /// Tool calls go into the activity row right after the current text; a
  /// later delta then opens a fresh assistant row below it.
  ChatMessage _activityRow() {
    final last = messages.isNotEmpty ? messages.last : null;
    if (last != null && last.role == ChatRole.activity) return last;
    final cur = _current;
    if (cur != null) {
      cur.streaming = false;
      if (cur.text.isEmpty) messages.remove(cur);
      _current = null;
    }
    final row = ChatMessage(role: ChatRole.activity);
    messages.add(row);
    return row;
  }

  void _onEvent(GatewayEvent ev) {
    if (ev.sessionId == null || ev.sessionId != _sessionId) return;
    final p = ev.payload;
    final gen = ev.generation;
    if (gen != null) {
      // Generation fence: a frame from an older turn is stale.
      if (_generation != null && gen < _generation!) return;
      _generation = gen;
    }
    if (ev.type == 'session.info' && p['revision'] is num) {
      _revision = (p['revision'] as num).toInt();
    }
    switch (ev.type) {
      case 'approval.request' || 'clarify.request':
        _onCanonicalPrompt(ev.type, p, gen, alert: true);
      case 'approval.settled' || 'clarify.settled':
        final id = p['prompt_id']?.toString();
        if (id != null) _onPromptSettled(id);
      case 'message.start':
        phase = ChatPhase.running;
      case 'message.delta':
        final t = p['text'];
        if (t is String) {
          final m = _current ?? _newAssistant();
          if (_segmentBreak && m.text.isNotEmpty && !m.text.endsWith('\n')) {
            m.text += '\n\n';
          }
          _segmentBreak = false;
          m.text += t;
          _status = null;
        } else {
          _segmentBreak = true;
        }
      case 'message.interim':
        final t = p['text'];
        final m = _current;
        if (m != null) {
          if (t is String && t.isNotEmpty) m.text = t;
          m.streaming = false;
          if (m.text.isEmpty) messages.remove(m);
          _current = null;
        } else if (t is String &&
            t.isNotEmpty &&
            p['already_streamed'] != true) {
          messages.add(ChatMessage(role: ChatRole.assistant, text: t));
        }
      case 'tool.generating':
        final tool = p['name']?.toString();
        _status = () => Strings.current.preparingTool(tool);
      case 'tool.start':
        final row = _activityRow();
        row.tools.add(
          ToolActivity(
            id: p['tool_id']?.toString() ?? '${row.tools.length}',
            name: p['name']?.toString() ?? 'tool',
            preview: (p['preview'] ?? p['context'])?.toString(),
          ),
        );
        _setStatus(p['name']?.toString());
      case 'tool.progress':
        final tool = _findTool(p['tool_id']?.toString());
        if (tool != null) {
          tool.progress = p['message']?.toString() ?? p['progress']?.toString();
        }
      case 'tool.complete':
        final tool = _findTool(p['tool_id']?.toString());
        if (tool != null) {
          tool.state = p['error'] != null ? ToolState.failed : ToolState.done;
          tool.summary = p['summary']?.toString();
          tool.durationS = (p['duration_s'] as num?)?.toDouble();
          tool.progress = null;
        }
        _status = null;
      case 'status.update':
        final t = p['text']?.toString();
        _setStatus((t == null || t.isEmpty) ? null : t);
      case 'thinking.delta':
        final t = p['text']?.toString();
        if (t != null && t.trim().isNotEmpty) _setStatus(t.trim());
      case 'session.info':
        _applyInfo(p);
      case 'message.complete':
        // A complete without a running turn is a replay (or a turn this
        // chat never saw start): render it, but don't alert.
        final live = phase == ChatPhase.running;
        _completeTurn(p);
        if (live && p['status'] != 'interrupted') {
          _alertReply(
            _lastAssistantText(),
            key: gen != null ? 'turn:$gen' : null,
          );
        }
      case 'request.cancel':
        final id = p['id'];
        if (_approvalRequest?.id == id) {
          _approvalRequest = null;
          approval = null;
        }
        if (_clarifyRequest?.id == id) {
          _clarifyRequest = null;
          clarify = null;
        }
      case 'approval.cancelled':
        _approvalRequest = null;
        approval = null;
      case 'error':
        final msg = p['message']?.toString();
        messages.add(
          msg == null
              ? ChatMessage(
                  role: ChatRole.error,
                  localized: () => Strings.current.unknownError,
                )
              : ChatMessage(role: ChatRole.error, text: msg),
        );
        if (phase == ChatPhase.running) _finishTurn();
      case 'notice':
        final t = (p['text'] ?? p['message'])?.toString();
        if (t != null && t.isNotEmpty) {
          messages.add(ChatMessage(role: ChatRole.notice, text: t));
        }
      default:
        return; // ignore without repaint
    }
    _notify();
  }

  ToolActivity? _findTool(String? id) {
    for (final m in messages.reversed) {
      for (final t in m.tools) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  void _completeTurn(Map<String, dynamic> p) {
    final status = p['status']?.toString() ?? 'complete';
    final finalText = (p['text'] as String?)?.isNotEmpty == true
        ? p['text'] as String
        : (p['rendered'] as String? ?? '');
    final m = _current;
    if (finalText.isNotEmpty) {
      final last = messages.isNotEmpty ? messages.last : null;
      // An already-sealed interim row with the same text: don't duplicate it.
      if (m == null &&
          last?.role == ChatRole.assistant &&
          last!.text == finalText) {
        // keep
      } else {
        (m ?? _newAssistant()).text = finalText;
      }
    }
    if (status == 'interrupted') {
      final target = _current ?? m;
      if (target != null) {
        target.interrupted = true;
      } else {
        messages.add(
          ChatMessage(
            role: ChatRole.notice,
            localized: () => Strings.current.interruptedNotice,
          ),
        );
      }
    } else if (status == 'error') {
      final err = p['error'];
      final msg = err is Map ? (err['message'] ?? err.toString()) : err;
      messages.add(
        msg == null
            ? ChatMessage(
                role: ChatRole.error,
                localized: () => Strings.current.replyFailed,
              )
            : ChatMessage(role: ChatRole.error, text: msg.toString()),
      );
    }
    final w = p['warning'];
    if (w is String && w.trim().isNotEmpty) {
      messages.add(ChatMessage(role: ChatRole.notice, text: w.trim()));
    }
    _finishTurn();
    onTurnSettled?.call(_hob);
    if (_deferredModel != null) {
      _deferredModel = null;
      unawaited(loadModels());
    }
  }

  // --- alerts --------------------------------------------------------------

  static String _approvalText(Map p) {
    final command = p['command']?.toString().trim() ?? '';
    if (command.isNotEmpty) return command;
    return p['description']?.toString().trim() ?? '';
  }

  String _lastAssistantText() {
    for (final m in messages.reversed) {
      if (m.role == ChatRole.user) break;
      if (m.role == ChatRole.assistant && m.text.trim().isNotEmpty) {
        return m.text;
      }
    }
    return '';
  }

  void _alertReply(String text, {required String? key}) {
    _raise(
      key ?? 'turn:${DateTime.now().microsecondsSinceEpoch}',
      HobAlert(AlertKind.reply, text),
      live: true,
    );
  }

  /// Alerts once per [key]. A snapshot ([live] false) only marks the key as
  /// known, so the same prompt arriving live later stays quiet too.
  void _raise(String key, HobAlert alert, {required bool live}) {
    if (!_alerted.add(key) || !live || _disposed) return;
    onAlert?.call(_hob, alert);
  }

  void _finishTurn() {
    final m = _current;
    if (m != null) {
      m.streaming = false;
      if (m.text.isEmpty) messages.remove(m);
    }
    for (final msg in messages) {
      msg.streaming = false;
      for (final t in msg.tools) {
        if (t.state == ToolState.running) t.state = ToolState.done;
      }
    }
    _current = null;
    _clearPrompts();
    _forgetRequestAlerts();
    _status = null;
    phase = ChatPhase.idle;
    // A watcher keeps only the tail: nobody reads its transcript.
    if (_watchOnly && messages.length > 4) {
      messages.removeRange(0, messages.length - 4);
    }
  }

  void _failTurn(String msg) {
    messages.add(ChatMessage(role: ChatRole.error, text: msg));
    _finishTurn();
    _notify();
  }

  void _applyInfo(Object? info) {
    if (info is! Map) return;
    final m = info['model'];
    // A pending (deferred) switch wins over the model of the running turn.
    if (m is String && m.isNotEmpty && _deferredModel == null) {
      model = m;
      final p = info['provider'];
      modelProvider = p is String ? p : null;
    }
    final r = info['reasoning_effort'];
    if (r is String && r.isNotEmpty) reasoningEffort = r;
    final a = info['approval_mode'];
    if (a is String && approvalModes.contains(a)) approvalMode = a;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _eventSub.cancel();
    _requestSub.cancel();
    _reconnectSub.cancel();
    _statusSub.cancel();
    // The Bot Chat is a forever-chat: never close it, just detach (the server
    // reaps the idle runtime after its grace period).
    super.dispose();
  }
}

/// Outcome of a session model switch.
class ModelSwitch {
  const ModelSwitch.done() : ok = true, deferred = false, question = null;
  const ModelSwitch.deferred() : ok = true, deferred = true, question = null;
  const ModelSwitch.failed() : ok = false, deferred = false, question = null;

  /// The server wants the switch confirmed ([question] may be empty).
  const ModelSwitch.confirm(String this.question)
    : ok = false,
      deferred = false;

  final bool ok;

  /// Applies after the running turn.
  final bool deferred;
  final String? question;
}

extension _Let<T> on T {
  T let(void Function(T) f) {
    f(this);
    return this;
  }
}
