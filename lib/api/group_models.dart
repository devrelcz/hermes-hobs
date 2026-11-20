/// Group chats ("rooms") as the gateway's `groups.*` API reports them.
///
/// A room seats two to six Hobs. The gateway owns the conversation: a user
/// message goes in with `groups.send`, the members answer in rounds, and every
/// step lands in an append-only log read with `groups.log`.
library;

import 'models.dart';

/// One seat of a room.
class GroupMember {
  const GroupMember({
    required this.memberId,
    required this.handle,
    required this.profile,
    this.displayName = '',
  });

  final String memberId;

  /// What `@handle` addresses in a message.
  final String handle;

  /// The Hob's profile name.
  final String profile;
  final String displayName;

  static GroupMember? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['member_id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final profile = j['profile']?.toString() ?? '';
    return GroupMember(
      memberId: id,
      handle: j['handle']?.toString() ?? id,
      profile: profile.isEmpty ? id : profile,
      displayName: j['display_name']?.toString().trim() ?? '',
    );
  }

  /// The seat as `groups.create` takes it: a Hob of this gateway.
  static Map<String, dynamic> localSeat(String profile) => {
    'member_id': profile,
    'profile': profile,
    'handle': profile,
    'target': {'kind': 'local', 'profile': profile},
  };
}

/// A room as `groups.list` / `groups.state` describe it.
class GroupRoom {
  const GroupRoom({
    required this.roomId,
    required this.name,
    required this.members,
    this.latestSeq = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String roomId;
  final String name;
  final List<GroupMember> members;

  /// Sequence number of the newest log event.
  final int latestSeq;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static GroupRoom? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['room_id']?.toString() ?? '';
    if (id.isEmpty || j['disbanded_at'] != null) return null;
    return GroupRoom(
      roomId: id,
      name: j['name']?.toString().trim() ?? '',
      members: (j['members'] as List? ?? const [])
          .map(GroupMember.fromJson)
          .nonNulls
          .toList(),
      latestSeq: (j['latest_seq'] as num?)?.toInt() ?? 0,
      createdAt: epochToDate(j['created_at']),
      updatedAt: epochToDate(j['updated_at']),
    );
  }

  GroupRoom copyWith({String? name, int? latestSeq, DateTime? updatedAt}) =>
      GroupRoom(
        roomId: roomId,
        name: name ?? this.name,
        members: members,
        latestSeq: latestSeq ?? this.latestSeq,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// One entry of a room's log (`groups.log`).
///
/// Kinds the app shows: `message.user` (you), `message.member` (a Hob's
/// reply), `turn.settled` / `turn.failed` / `turn.cancelled` (how a member's
/// turn ended) and `room.activity` (the round ended or hit its cap).
class GroupEvent {
  const GroupEvent({
    required this.seq,
    required this.eventId,
    required this.kind,
    required this.actorKind,
    required this.actorId,
    required this.payload,
    this.createdAt,
  });

  final int seq;
  final String eventId;
  final String kind;

  /// `user`, `member` or `gateway`.
  final String actorKind;
  final String actorId;
  final Map<String, dynamic> payload;
  final DateTime? createdAt;

  String get text => (payload['text'] ?? payload['content'] ?? '').toString();
  String get memberId => (payload['member_id'] ?? '').toString();
  String get threadId => (payload['thread_id'] ?? '').toString();
  String get discussionId => (payload['discussion_event_id'] ?? '').toString();

  bool get isUserMessage => kind == 'message.user' || kind == 'message';
  bool get isMemberMessage => kind == 'message.member' && actorKind == 'member';

  static GroupEvent? fromJson(Object? j) {
    if (j is! Map) return null;
    final seq = (j['seq'] as num?)?.toInt();
    if (seq == null) return null;
    final actor = j['actor'];
    final payload = j['payload'];
    return GroupEvent(
      seq: seq,
      eventId: j['event_id']?.toString() ?? '',
      kind: j['kind']?.toString() ?? '',
      actorKind: actor is Map ? actor['kind']?.toString() ?? '' : '',
      actorId: actor is Map ? actor['id']?.toString() ?? '' : '',
      payload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : const <String, dynamic>{},
      createdAt: epochToDate(j['created_at']),
    );
  }
}

/// A step that waits on the user (`driver_status.pending_actions`): a command
/// to approve, or a failed turn to retry or drop.
class GroupAction {
  const GroupAction({
    required this.kind,
    required this.memberId,
    required this.taskId,
    required this.generation,
    this.requestId = '',
    this.command = '',
    this.description = '',
    this.choices = const [],
  });

  /// `approval`, `retry` or `discard`.
  final String kind;
  final String memberId;
  final String taskId;
  final int generation;
  final String requestId;
  final String command;
  final String description;
  final List<String> choices;

  static GroupAction? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = j['kind']?.toString() ?? '';
    final member = j['member_id']?.toString() ?? '';
    final task = j['task_id']?.toString() ?? '';
    final gen = (j['execution_generation'] as num?)?.toInt() ?? 0;
    if (kind.isEmpty || member.isEmpty || task.isEmpty || gen < 1) return null;
    final approval = j['approval'];
    return GroupAction(
      kind: kind,
      memberId: member,
      taskId: task,
      generation: gen,
      requestId: j['request_id']?.toString() ?? '',
      command: approval is Map ? approval['command']?.toString() ?? '' : '',
      description: approval is Map
          ? approval['description']?.toString() ?? ''
          : '',
      choices: approval is Map
          ? (approval['choices'] as List? ?? const [])
                .map((c) => c.toString())
                .toList()
          : const [],
    );
  }
}

/// What a member is doing right now (`driver_status.member_activity`).
class GroupActivity {
  const GroupActivity({
    required this.memberId,
    required this.queued,
    this.startedAt,
    this.tool,
  });

  final String memberId;
  final bool queued;
  final DateTime? startedAt;
  final String? tool;

  static GroupActivity? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['member_id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final tool = j['tool']?.toString() ?? '';
    return GroupActivity(
      memberId: id,
      queued: j['status'] == 'queued',
      startedAt: epochToDate(j['started_at']),
      tool: tool.isEmpty ? null : tool,
    );
  }
}

/// The room's driver: whether members are working, and what waits on you.
class GroupDriver {
  const GroupDriver({
    this.working = false,
    this.blocked = false,
    this.activity = const [],
    this.actions = const [],
    this.maxRounds = 0,
    this.lastError,
  });

  final bool working;
  final bool blocked;
  final List<GroupActivity> activity;
  final List<GroupAction> actions;
  final int maxRounds;
  final String? lastError;

  bool get busy => working || activity.isNotEmpty;

  static GroupDriver? fromJson(Object? j) {
    if (j is! Map) return null;
    final err = j['last_error'];
    return GroupDriver(
      working: j['working'] == true,
      blocked: j['blocked'] == true,
      activity: (j['member_activity'] as List? ?? const [])
          .map(GroupActivity.fromJson)
          .nonNulls
          .toList(),
      actions: (j['pending_actions'] as List? ?? const [])
          .map(GroupAction.fromJson)
          .nonNulls
          .toList(),
      maxRounds: (j['max_rounds'] as num?)?.toInt() ?? 0,
      lastError: err == null
          ? null
          : (err is Map ? (err['message'] ?? err['detail']) : err)?.toString(),
    );
  }
}
