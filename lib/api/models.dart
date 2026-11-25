import 'dart:convert';

import '../l10n/strings.dart';
import 'attachments.dart';

/// Summary of a session row as `profiles.list {include_sessions: true}` reports it.
class SessionSummary {
  SessionSummary({
    required this.id,
    this.resolvedId,
    this.preview = '',
    this.lastActive,
    this.messageCount = 0,
  });

  final String id;

  /// Live tip after context compression; resume this one.
  final String? resolvedId;
  final String preview;
  final DateTime? lastActive;
  final int messageCount;

  String get resumeId =>
      (resolvedId != null && resolvedId!.isNotEmpty) ? resolvedId! : id;

  static SessionSummary? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return SessionSummary(
      id: id,
      resolvedId: j['resolved_id']?.toString(),
      preview: (j['preview']?.toString() ?? '').trim(),
      lastActive: epochToDate(j['last_active']),
      messageCount: (j['message_count'] as num?)?.toInt() ?? 0,
    );
  }
}

DateTime? epochToDate(Object? v) {
  if (v is! num || v <= 0) return null;
  // Hermes stores Unix seconds (float); tolerate milliseconds too.
  final ms = v > 1e12 ? v.toInt() : (v * 1000).toInt();
  return DateTime.fromMillisecondsSinceEpoch(ms);
}

/// A Hermes profile — each profile is an independent agent ("hob").
///
/// Bot Mode appearance lives in `profile.yaml` under `ui_meta['hermes-bots']`
/// (`title`, `sectionId`/`sectionName`, `color`, `shape`, `pinned`, `hidden`).
class Hob {
  Hob({
    required this.name,
    required this.displayName,
    this.description = '',
    this.model,
    this.provider,
    this.isDefault = false,
    this.sectionId,
    this.sectionName,
    this.color,
    this.shape,
    this.pinned = false,
    this.hidden = false,
    this.canonical,
    this.lastSession,
    this.workerActiveAt,
    this.meta = const {},
    this.metaRevision,
    this.roleTitle = '',
    this.profileDisplayName = '',
    this.previousNames = const [],
  });

  final String name;
  final String displayName;
  final String description;
  final String? model;
  final String? provider;
  final bool isDefault;
  final String? sectionId;
  final String? sectionName;
  final String? color;
  final String? shape;
  final bool pinned;
  final bool hidden;

  /// The hob's forever-chat: the session titled "Bot Chat" on its profile.
  final SessionSummary? canonical;
  final SessionSummary? lastSession;

  /// Heartbeat of the newest background worker (cron/kanban) session.
  final DateTime? workerActiveAt;

  /// Raw `ui_meta['hermes-bots']`. A write replaces the whole block, so edits
  /// send this map back with the changed keys.
  final Map<String, dynamic> meta;

  /// `ui_meta_revisions['hermes-bots']`: compare-and-swap guard for writes.
  /// Null when the server did not send revisions.
  final int? metaRevision;

  /// The profile's `title` (its role) as `profiles.list` reports it.
  final String roleTitle;

  /// The core profile display name (`hermes profile rename`).
  final String profileDisplayName;

  /// Names the profile had before a rename; old @handles still resolve.
  final List<String> previousNames;

  static const metaKey = 'hermes-bots';
  static const canonicalTitle = 'Bot Chat';

  factory Hob.fromJson(Map<String, dynamic> j) {
    String str(Object? v) => (v is String) ? v.trim() : '';
    final uiMeta = j['ui_meta'];
    final meta = (uiMeta is Map && uiMeta['hermes-bots'] is Map)
        ? Map<String, dynamic>.from(uiMeta['hermes-bots'] as Map)
        : const <String, dynamic>{};
    final name = str(j['name']);
    final display = [
      str(meta['title']),
      str(j['display_name']),
      str(j['bot_title']),
      name,
    ].firstWhere((s) => s.isNotEmpty, orElse: () => name);
    final worker = j['worker_session'];
    final model = str(j['model']);
    final revisions = j['ui_meta_revisions'];
    final revision = revisions is Map ? revisions[metaKey] : null;
    return Hob(
      name: name,
      displayName: display,
      description: str(j['description']).isNotEmpty
          ? str(j['description'])
          : str(meta['description']),
      model: model.isEmpty ? null : model,
      provider: str(j['provider']).isEmpty ? null : str(j['provider']),
      isDefault: j['is_default'] == true,
      sectionId: str(meta['sectionId']).isEmpty ? null : str(meta['sectionId']),
      sectionName: str(meta['sectionName']).isEmpty
          ? null
          : str(meta['sectionName']),
      color: str(meta['color']).isEmpty ? null : str(meta['color']),
      shape: str(meta['shape']).isEmpty ? null : str(meta['shape']),
      pinned: meta['pinned'] == true,
      hidden: meta['hidden'] == true,
      canonical: SessionSummary.fromJson(j['canonical_session']),
      lastSession: SessionSummary.fromJson(j['last_session']),
      workerActiveAt: worker is Map ? epochToDate(worker['last_active']) : null,
      meta: meta,
      metaRevision: revision is int ? revision : null,
      roleTitle: str(j['title']).isNotEmpty
          ? str(j['title'])
          : str(j['bot_title']),
      profileDisplayName: str(j['display_name']),
      previousNames: [
        for (final n
            in (j['previous_names'] is List
                ? j['previous_names'] as List
                : const []))
          if (n is String && n.trim().isNotEmpty) n.trim(),
      ],
    );
  }

  /// This hob as it reads once [meta] replaced its `hermes-bots` block: what
  /// the roster shows before the server confirms a write.
  Hob withMeta(Map<String, dynamic> meta) {
    String? str(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    return Hob(
      name: name,
      displayName: displayName,
      description: description,
      model: model,
      provider: provider,
      isDefault: isDefault,
      sectionId: str(meta['sectionId']),
      sectionName: str(meta['sectionName']),
      color: str(meta['color']),
      shape: str(meta['shape']),
      pinned: meta['pinned'] == true,
      hidden: meta['hidden'] == true,
      canonical: canonical,
      lastSession: lastSession,
      workerActiveAt: workerActiveAt,
      meta: meta,
      metaRevision: metaRevision,
    );
  }

  /// The title the user typed for this hob; empty when the name stands in.
  String get customTitle {
    final t = meta['title'];
    return t is String ? t.trim() : '';
  }

  /// What the roster row shows: the Bot Chat's latest message.
  String get preview => canonical?.preview ?? '';

  DateTime? get lastActive {
    final a = canonical?.lastActive;
    final w = workerActiveAt;
    if (a == null) return w;
    if (w == null) return a;
    return a.isAfter(w) ? a : w;
  }

  /// A worker heartbeat within two minutes means the hob is busy right now.
  bool get workingNow {
    final w = workerActiveAt;
    return w != null &&
        DateTime.now().difference(w) < const Duration(minutes: 2);
  }

  String get initials {
    final parts = displayName
        .split(RegExp(r'[\s_\-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/// One model provider of `model.options` with the models it offers.
class ModelProvider {
  ModelProvider({
    required this.slug,
    this.name = '',
    this.models = const [],
    this.authenticated = true,
  });

  final String slug;
  final String name;
  final List<String> models;

  /// False when the server has no credentials for it (`authenticated:false`):
  /// a session can't run on it, though a profile may still name it.
  final bool authenticated;

  String get label => name.isEmpty || name == slug ? slug : '$name ($slug)';

  static ModelProvider? fromJson(Object? j) {
    if (j is! Map) return null;
    final slug = j['slug']?.toString().trim() ?? '';
    if (slug.isEmpty) return null;
    final models = <String>[];
    for (final m in (j['models'] as List? ?? const [])) {
      final id = m is Map
          ? (m['id'] ?? m['name'])?.toString() ?? ''
          : m?.toString() ?? '';
      if (id.isNotEmpty && !models.contains(id)) models.add(id);
    }
    return ModelProvider(
      slug: slug,
      name: j['name']?.toString().trim() ?? '',
      models: models,
      authenticated: j['authenticated'] != false,
    );
  }
}

/// A model on a provider, as `model.options` and the model switches name it.
class ModelChoice {
  const ModelChoice({required this.provider, required this.model});

  final String provider;
  final String model;

  /// Short label for chips: the model id without a vendor prefix
  /// ("anthropic/claude-opus-5.5" -> "claude-opus-5.5").
  String get shortLabel => model.contains('/') ? model.split('/').last : model;

  bool same(ModelChoice? o) =>
      o != null &&
      o.model == model &&
      (o.provider.isEmpty || provider.isEmpty || o.provider == provider);

  @override
  bool operator ==(Object other) =>
      other is ModelChoice &&
      other.provider == provider &&
      other.model == model;

  @override
  int get hashCode => Object.hash(provider, model);

  @override
  String toString() => provider.isEmpty ? model : '$provider:$model';
}

/// `model.options` result: the providers with their models, and the model in
/// effect. With a `session_id` that is the session's model (including a
/// session-only switch); with only a `profile` it is the profile's default.
class ModelOptions {
  const ModelOptions({this.providers = const [], this.current});

  final List<ModelProvider> providers;
  final ModelChoice? current;

  static ModelOptions fromJson(Object? j) {
    if (j is! Map) return const ModelOptions();
    final model = j['model']?.toString().trim() ?? '';
    return ModelOptions(
      providers: (j['providers'] as List? ?? const [])
          .map(ModelProvider.fromJson)
          .nonNulls
          .toList(),
      current: model.isEmpty
          ? null
          : ModelChoice(
              provider: j['provider']?.toString().trim() ?? '',
              model: model,
            ),
    );
  }
}

/// What `profiles.describe` reports beyond the roster: the model the profile
/// runs on and its SOUL.md. An empty provider and model mean the profile
/// inherits the model of the launch profile.
class HobSetup {
  const HobSetup({this.provider = '', this.model = '', this.soul = ''});

  final String provider;
  final String model;

  /// The profile's SOUL.md: its persona and standing instructions.
  final String soul;
}

enum ChatRole { user, assistant, activity, notice, error }

/// Kinds of turns the gateway hands a Hob in the user's place.
enum SystemTurnKind {
  /// Another Hob wrote (its `message_agent` tool): "Message from 🤖 …".
  agentMessage,

  /// A background subagent the Hob dispatched is done.
  delegationDone,

  /// A background process the Hob started has ended.
  processDone,
}

/// A user turn the gateway wrote rather than the user: a message from
/// another Hob, or a note that background work finished. The dashboard
/// marks these rows with `display_kind` (`internal_notification`,
/// `async_delegation_complete`, `process_complete`) and shows them as
/// quiet, folded lines; their text is recognised as well, for history rows
/// that come without the mark.
class SystemTurn {
  const SystemTurn({
    required this.kind,
    this.sender,
    this.handle,
    this.summary = '',
  });

  final SystemTurnKind kind;

  /// For [SystemTurnKind.agentMessage]: the writer's name and profile.
  final String? sender;
  final String? handle;

  /// One line saying what it is about: the dashboard's `display_text`, the
  /// subagent's goal or the process's command.
  final String summary;

  static final _fromHob = RegExp(
    r'^Message from 🤖\s*(.+?)\s*\(@([^)\s]+)\):\s*',
  );
  static final _fromHobLoose = RegExp(r'^Message from 🤖\s*([^:\n]+):\s*');
  static final _fromAgent = RegExp(r"^Message from agent '([^']+)':\s*");
  static final _delegation = RegExp(r'^\[ASYNC DELEGATION COMPLETE\b');
  static final _process = RegExp(r'^\[IMPORTANT: Background process\b');
  static final _goal = RegExp(r'^Original goal:\s*(.+)$', multiLine: true);
  static final _command = RegExp(r'^Command:\s*(.+)$', multiLine: true);

  /// What [text] is, with the body to show, or null for the user's own
  /// words. [kind] and [meta] are the row's `display_kind` and
  /// `display_metadata` when the server sends them.
  static ({SystemTurn turn, String body})? parse(
    String text, {
    String? kind,
    Object? meta,
  }) {
    final t = text.trim();
    // A scheduled job's output carries the same `internal_notification`
    // mark as a message from another Hob, but it is this Hob's own job:
    // it has its own card (see [ScheduledOutput]).
    if (ScheduledOutput.jobOf(t) != null) return null;
    final display = meta is Map ? meta['display_text']?.toString() : null;
    var m = _fromHob.firstMatch(t);
    if (m != null) {
      return (
        turn: SystemTurn(
          kind: SystemTurnKind.agentMessage,
          sender: m.group(1)!.trim(),
          handle: m.group(2),
          summary: display ?? '',
        ),
        body: t.substring(m.end).trim(),
      );
    }
    m = _fromAgent.firstMatch(t) ?? _fromHobLoose.firstMatch(t);
    if (m != null) {
      final who = m.group(1)!.trim();
      return (
        turn: SystemTurn(
          kind: SystemTurnKind.agentMessage,
          sender: who,
          handle: _fromAgent.hasMatch(t) ? who : null,
          summary: display ?? '',
        ),
        body: t.substring(m.end).trim(),
      );
    }
    if (kind == 'async_delegation_complete' || _delegation.hasMatch(t)) {
      return (
        turn: SystemTurn(
          kind: SystemTurnKind.delegationDone,
          summary: _goal.firstMatch(t)?.group(1)?.trim() ?? display ?? '',
        ),
        body: t,
      );
    }
    if (kind == 'process_complete' || _process.hasMatch(t)) {
      return (
        turn: SystemTurn(
          kind: SystemTurnKind.processDone,
          summary: _command.firstMatch(t)?.group(1)?.trim() ?? display ?? '',
        ),
        body: t,
      );
    }
    if (kind == 'internal_notification') {
      return (
        turn: SystemTurn(
          kind: SystemTurnKind.agentMessage,
          summary: display ?? '',
        ),
        body: t,
      );
    }
    return null;
  }

  /// The row's heading: "Message from CTO", "Background task done", …
  /// [name] is the writer as the roster names it, when known.
  String title(Strings s, {String? name}) => switch (kind) {
    SystemTurnKind.agentMessage => s.messageFromHob(name ?? sender),
    SystemTurnKind.delegationDone => s.delegationDone,
    SystemTurnKind.processDone => s.processDone,
  };

  /// The writer and the start of the message from a session preview that
  /// begins with another Hob's message, or null.
  static ({String sender, String text})? ofPreview(String preview) {
    final p = preview.trim();
    final m =
        _fromHob.firstMatch(p) ??
        _fromAgent.firstMatch(p) ??
        _fromHobLoose.firstMatch(p);
    if (m == null) return null;
    return (sender: m.group(1)!.trim(), text: p.substring(m.end).trim());
  }
}

/// A scheduled job's output that the gateway hands to the Hob whose chat
/// the job delivers to, as a user turn headed like
///
///     [Cronjob "Morning briefing" output — scheduled job, not the user. …]
///
/// followed by the output itself.
class ScheduledOutput {
  ScheduledOutput._();

  static final _header = RegExp(r'^\s*\[Cronjob "(.*?)" output\b[^\n]*\]\s*');

  /// The job's name and its output, or null for anything else.
  static ({String job, String output})? parse(String text) {
    final m = _header.firstMatch(text);
    if (m == null) return null;
    return (job: m.group(1)!.trim(), output: text.substring(m.end).trim());
  }

  static final _start = RegExp(r'^\s*\[Cronjob "([^"]*)');

  /// The job's name from the start of such a turn, which may be cut short
  /// (a session preview), or null.
  static String? jobOf(String text) =>
      _start.firstMatch(text)?.group(1)?.trim();
}

enum ToolState { running, done, failed }

class ToolActivity {
  ToolActivity({
    required this.id,
    required this.name,
    this.preview,
    this.state = ToolState.running,
  });

  final String id;
  final String name;
  String? preview;
  String? summary;
  String? progress;
  double? durationS;
  ToolState state;
}

/// One row of the transcript. `activity` rows group consecutive tool calls
/// into the single collapsible line the dashboard shows between replies.
class ChatMessage {
  ChatMessage({
    required this.role,
    this.text = '',
    this.streaming = false,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  final ChatRole role;
  String text;
  bool streaming;
  DateTime time;
  final List<ToolActivity> tools = [];

  /// For a user row that is a scheduled job's output handed to the Hob
  /// (see [ScheduledOutput]): the job's name. [text] is then the output.
  String? scheduledJob;

  /// For a user row the gateway wrote, not the user (see [SystemTurn]):
  /// what it is. [text] is then its body.
  SystemTurn? system;

  /// For a [SystemTurn.agentMessage] row: the Hob's answer to the other
  /// Hob, folded into the same row ([replyTools] are the tools it used).
  String? reply;
  final List<ToolActivity> replyTools = [];

  /// Images, files and links sent with a user message.
  final List<ChatAttachment> attachments = [];
  bool interrupted = false;
  bool expanded = false;

  bool get toolsRunning => tools.any((t) => t.state == ToolState.running);
}

/// An approval request for a dangerous command (`approval` server request).
class PendingApproval {
  PendingApproval({
    required this.command,
    required this.description,
    required this.choices,
    this.toolName,
  });

  final String command;
  final String description;
  final List<String> choices;
  final String? toolName;
}

class ClarifyQuestion {
  ClarifyQuestion({
    required this.qid,
    required this.question,
    this.choices,
    this.multiSelect = false,
  });

  final String qid;
  final String question;
  final List<String>? choices;
  final bool multiSelect;
}

/// A scheduled (cron) job, as `GET /api/cron/jobs` reports it (the richer
/// shape) or `cron.manage {action: "list"}` (older servers).
class CronJob {
  CronJob({
    required this.id,
    required this.name,
    required this.schedule,
    this.prompt = '',
    this.enabled = true,
    this.state,
    this.nextRun,
    this.lastRun,
    this.lastStatus,
    this.lastError,
    this.deliver,
    this.repeatTimes,
    this.repeatCompleted = 0,
    this.running = false,
  });

  final String id;

  /// The name as people read it: without the `[bot:<profile>] ` tag the
  /// dashboard puts in front of the jobs it creates for a bot.
  final String name;
  final String schedule;
  final String prompt;
  final bool enabled;
  final String? state;
  final DateTime? nextRun;
  final DateTime? lastRun;
  final String? lastStatus;
  final String? lastError;

  /// Where a run's output goes: `local` (run history only),
  /// `bot-chat:<profile>` (that Hob's chat, which answers it), or another
  /// gateway target.
  final String? deliver;

  /// How many runs the job makes before it stops; null for no end.
  final int? repeatTimes;
  final int repeatCompleted;

  /// A run is going on right now.
  final bool running;

  bool get paused => !enabled || state == 'paused';

  bool get failed =>
      lastStatus == 'error' || lastStatus == 'failed' || lastError != null;

  /// The Hob whose chat gets the output, or null.
  String? get deliverHob => deliver != null && deliver!.startsWith('bot-chat:')
      ? deliver!.substring('bot-chat:'.length)
      : null;

  static final _botTag = RegExp(r'^\[bot:[^\]]*\]\s*');

  /// [raw] without its `[bot:<profile>] ` tag.
  static String displayName(String raw) => raw.replaceFirst(_botTag, '');

  static DateTime? _date(Object? v) {
    if (v is num) return epochToDate(v);
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
    return null;
  }

  /// A JSON object the server may also send as a JSON string.
  static Map? _object(Object? v) {
    if (v is Map) return v;
    if (v is String && v.startsWith('{')) {
      try {
        final d = jsonDecode(v);
        if (d is Map) return d;
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static String _schedule(Map<String, dynamic> j) {
    final display = j['schedule_display'];
    if (display is String && display.isNotEmpty) return display;
    final raw = j['schedule'];
    final o = _object(raw);
    if (o != null) {
      return (o['display'] ?? o['expr'] ?? o['value'] ?? '?').toString();
    }
    return raw?.toString() ?? '?';
  }

  factory CronJob.fromJson(Map<String, dynamic> j) {
    final repeat = _object(j['repeat']);
    final times = repeat?['times'] ?? (j['repeat'] is num ? j['repeat'] : null);
    final raw = j['name']?.toString() ?? '';
    final name = displayName(raw).trim();
    return CronJob(
      id: j['job_id']?.toString() ?? j['id']?.toString() ?? '',
      name: name.isEmpty ? Strings.current.jobFallback : name,
      schedule: _schedule(j),
      prompt: (j['prompt'] ?? j['prompt_preview'])?.toString() ?? '',
      enabled: j['enabled'] != false,
      state: j['state']?.toString(),
      nextRun: _date(j['next_run_at']),
      lastRun: _date(j['last_run_at']),
      lastStatus: j['last_status']?.toString(),
      lastError: j['last_error']?.toString(),
      deliver: j['deliver']?.toString(),
      repeatTimes: times is num ? times.toInt() : null,
      repeatCompleted: (repeat?['completed'] as num?)?.toInt() ?? 0,
      running: j['live_execution'] != null,
    );
  }
}

/// One run of a [CronJob]: the session it ran in, as
/// `GET /api/cron/jobs/<id>/runs` lists it.
class CronRun {
  CronRun({
    required this.id,
    this.startedAt,
    this.endedAt,
    this.endReason,
    this.toolCalls = 0,
    this.active = false,
  });

  final String id;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? endReason;
  final int toolCalls;
  final bool active;

  Duration? get duration => startedAt != null && endedAt != null
      ? endedAt!.difference(startedAt!)
      : null;

  /// Ended some other way than finishing its work.
  bool get failed =>
      !active &&
      endReason != null &&
      endReason != 'cron_complete' &&
      endReason != 'completed';

  factory CronRun.fromJson(Map<String, dynamic> j) => CronRun(
    id: j['id']?.toString() ?? '',
    startedAt: CronJob._date(j['started_at']),
    endedAt: CronJob._date(j['ended_at']),
    endReason: j['end_reason']?.toString(),
    toolCalls: (j['tool_call_count'] as num?)?.toInt() ?? 0,
    active: j['is_active'] == true || (j['ended_at'] == null),
  );
}
