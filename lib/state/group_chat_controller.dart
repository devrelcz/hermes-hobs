import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/group_models.dart';
import '../api/hermes_rpc.dart';
import '../l10n/strings.dart';

/// How a member's latest turn in the current discussion went.
enum MemberState { idle, queued, working, replied, passed, failed, cancelled }

/// One group chat ("room") on the gateway, the way the dashboard drives it.
///
/// Read: `groups.state` (room, driver status) and `groups.log` (append-only
/// events, fetched incrementally by `since_seq`). The gateway announces
/// changes with the `groups.changed` event; while members work the app also
/// polls, so their status stays current. Write: `groups.send` posts a message
/// (members answer in rounds), `groups.stop` cancels the running round,
/// `groups.continue` grants more rounds, `groups.approve` / `groups.retry` /
/// `groups.discard` answer what waits on the user.
class GroupChatController extends ChangeNotifier {
  GroupChatController({
    required this.rpc,
    required this.profile,
    required this._room,
    this.onChanged,
  }) {
    _eventSub = rpc.events.listen(_onEvent);
    _reconnectSub = rpc.onReconnected.listen((_) => refresh());
    _statusSub = rpc.statusStream.listen((_) => _notify());
  }

  final HermesRpc rpc;

  /// The profile whose gateway owns the room (every call carries it).
  final String profile;

  /// Called after the log grew (roster preview / unread bookkeeping).
  final void Function(GroupChatController chat)? onChanged;

  late final StreamSubscription<GatewayEvent> _eventSub;
  late final StreamSubscription<void> _reconnectSub;
  late final StreamSubscription<ConnectionStatus> _statusSub;

  static const _pollBusy = Duration(seconds: 2);
  static const _pollIdle = Duration(seconds: 15);

  GroupRoom _room;
  GroupDriver? driver;
  final List<GroupEvent> log = [];
  int? _epoch;
  bool loading = true;
  bool disbanded = false;
  String? error;

  /// A message on its way: shown until the log carries it.
  String? pendingText;
  String? _pendingThread;

  /// True while a send, stop or another action is in flight.
  bool acting = false;

  Timer? _poll;
  Future<void>? _refreshing;
  bool _again = false;
  bool _disposed = false;

  GroupRoom get room => _room;
  String get roomId => _room.roomId;
  ConnectionStatus get connection => rpc.status;
  bool get busy => driver?.busy ?? false;
  int get lastSeq => log.isEmpty ? 0 : log.last.seq;

  Map<String, dynamic> _params([Map<String, dynamic>? extra]) => {
    'profile': profile,
    'room_id': roomId,
    ...?extra,
  };

  /// Loads the room and its whole log.
  Future<void> start() => refresh();

  /// Re-reads the driver status and fetches log events not seen yet.
  /// Calls made while one runs are folded into a single follow-up.
  Future<void> refresh() {
    if (_refreshing != null) {
      _again = true;
      return _refreshing!;
    }
    final f = _refreshing = _load().whenComplete(() {
      _refreshing = null;
      if (_again && !_disposed) {
        _again = false;
        refresh();
      }
    });
    return f;
  }

  Future<void> _load() async {
    var grew = false;
    try {
      await rpc.connect();
      final res = await rpc.request('groups.state', _params());
      if (_disposed || res is! Map) return;
      final room = res['room'];
      if (room is Map && room['disbanded_at'] != null) {
        disbanded = true;
        driver = null;
        error = null;
        return;
      }
      final parsed = GroupRoom.fromJson(room);
      if (parsed != null) _room = parsed;
      driver = GroupDriver.fromJson(res['driver_status']);
      final epoch = room is Map
          ? (room['authority_epoch'] as num?)?.toInt()
          : null;
      // A new authority epoch, or a log shorter than ours, starts over.
      if (epoch != _epoch || _room.latestSeq < lastSeq) {
        log.clear();
        _epoch = epoch;
      }
      if (_room.latestSeq > lastSeq) {
        grew = await _fetchLog();
      }
      if (_pendingThread != null &&
          log.any((e) => e.isUserMessage && e.threadId == _pendingThread)) {
        pendingText = null;
        _pendingThread = null;
      }
      error = null;
    } catch (e) {
      if (_disposed) return;
      error = Strings.current.groupLoadFailed(_describe(e));
    } finally {
      if (!_disposed) {
        loading = false;
        _schedulePoll();
        _notify();
        if (grew) onChanged?.call(this);
      }
    }
  }

  /// Appends events after [lastSeq]. False when there was nothing new.
  Future<bool> _fetchLog() async {
    var grew = false;
    for (var guard = 0; guard < 200; guard++) {
      final since = lastSeq;
      final res = await rpc.request(
        'groups.log',
        _params({'since_seq': since, 'limit': 200}),
      );
      if (_disposed || res is! Map) return grew;
      final events =
          (res['events'] as List? ?? const [])
              .map(GroupEvent.fromJson)
              .nonNulls
              .where((e) => e.seq > since)
              .toList()
            ..sort((a, b) => a.seq.compareTo(b.seq));
      // The log is gapless: anything else means our cursor is stale.
      for (var i = 0; i < events.length; i++) {
        if (events[i].seq != since + i + 1) {
          log.clear();
          return true;
        }
      }
      log.addAll(events);
      grew = grew || events.isNotEmpty;
      if (res['has_more'] != true || events.isEmpty) return grew;
    }
    return grew;
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (_disposed || disbanded) return;
    final waiting = busy || pendingText != null;
    _poll = Timer(waiting ? _pollBusy : _pollIdle, refresh);
  }

  void _onEvent(GatewayEvent e) {
    if (e.type != 'groups.changed') return;
    final ids = e.payload['room_ids'];
    if (ids is List && !ids.contains(roomId)) return;
    refresh();
  }

  // --- derived views --------------------------------------------------------

  /// The member's latest state in the current discussion (the newest thing
  /// the user said), the way the dashboard's header chips show it.
  MemberState stateOf(String memberId) {
    final acts = driver?.activity.where((a) => a.memberId == memberId) ?? [];
    if (acts.any((a) => !a.queued)) return MemberState.working;
    if (acts.isNotEmpty) return MemberState.queued;
    final discussion = currentDiscussion;
    if (discussion == null) return MemberState.idle;
    for (final e in log.reversed) {
      if (e.memberId != memberId || e.discussionId != discussion) continue;
      switch (e.kind) {
        case 'turn.settled':
          return e.payload['passed'] == true
              ? MemberState.passed
              : MemberState.replied;
        case 'turn.failed':
          return MemberState.failed;
        case 'turn.cancelled':
          return MemberState.cancelled;
      }
    }
    return MemberState.idle;
  }

  /// The tool a working member runs right now, if the gateway says.
  String? toolOf(String memberId) {
    for (final a in driver?.activity ?? const <GroupActivity>[]) {
      if (a.memberId == memberId && a.tool != null) return a.tool;
    }
    return null;
  }

  /// Event id of the newest user message.
  String? get currentDiscussion {
    for (final e in log.reversed) {
      if (e.isUserMessage && e.eventId.isNotEmpty) return e.eventId;
    }
    return null;
  }

  /// The newest round ended at its cap: offer to let the members go on.
  GroupEvent? get continuable {
    for (final e in log.reversed) {
      if (e.isUserMessage || e.isMemberMessage) return null;
      if (e.kind == 'room.continued') return null;
      if (e.kind == 'room.activity') {
        return e.payload['status'] == 'bounded' && !busy ? e : null;
      }
    }
    return null;
  }

  /// Newest message text, for the roster row.
  String get preview {
    if (pendingText != null) return pendingText!;
    for (final e in log.reversed) {
      if ((e.isUserMessage || e.isMemberMessage) && e.text.trim().isNotEmpty) {
        return e.text;
      }
    }
    return '';
  }

  DateTime? get lastActive {
    for (final e in log.reversed) {
      if (e.createdAt != null) return e.createdAt;
    }
    return _room.updatedAt ?? _room.createdAt;
  }

  // --- actions --------------------------------------------------------------

  /// Posts [text] to the room; `@handle` at the start assigns it to a member.
  Future<void> send(String text) async {
    final body = text.trim();
    if (body.isEmpty || acting) return;
    final eventId = uuidV4();
    pendingText = body;
    _pendingThread = eventId;
    error = null;
    await _act(
      () async {
        final res = await rpc.request(
          'groups.send',
          _params({
            'event_id': eventId,
            'payload': {'text': body, 'attachments': [], 'thread_id': eventId},
          }),
        );
        if (res is Map &&
            ((res.containsKey('accepted') && res['accepted'] != true) ||
                (res.containsKey('client_event_id') &&
                    res['client_event_id'] != eventId))) {
          throw StateError(Strings.current.groupSendUnconfirmed);
        }
      },
      onError: () {
        pendingText = null;
        _pendingThread = null;
      },
    );
  }

  /// Cancels the running round.
  Future<void> stop() =>
      _act(() => rpc.request('groups.stop', _params({'cancel_id': uuidV4()})));

  /// Lets the members go on after a round hit its cap.
  Future<void> continueRound(GroupEvent bounded) {
    final discussion = bounded.discussionId.isNotEmpty
        ? bounded.discussionId
        : currentDiscussion;
    if (discussion == null) return Future.value();
    return _act(
      () => rpc.request(
        'groups.continue',
        _params({'discussion_event_id': discussion}),
      ),
    );
  }

  /// Answers a pending action: [choice] is `once` / `deny` for an approval.
  /// A failed turn is retried, or dropped with [discard].
  Future<void> answer(
    GroupAction action, {
    String? choice,
    bool discard = false,
  }) {
    final method = switch (action.kind) {
      _ when discard => 'groups.discard',
      'approval' => 'groups.approve',
      'retry' => 'groups.retry',
      _ => 'groups.discard',
    };
    return _act(
      () => rpc.request(
        method,
        _params({
          'member_id': action.memberId,
          'task_id': action.taskId,
          'execution_generation': action.generation,
          if (action.kind == 'approval') ...{
            'request_id': action.requestId,
            'choice': choice,
          },
        }),
      ),
    );
  }

  Future<void> rename(String name) async {
    final title = name.trim();
    if (title.isEmpty || title == _room.name) return;
    await _act(() async {
      final res = await rpc.request(
        'groups.rename',
        _params({'event_id': uuidV4(), 'name': title}),
      );
      final room = res is Map ? GroupRoom.fromJson(res['room']) : null;
      _room = room ?? _room.copyWith(name: title);
    });
    onChanged?.call(this);
  }

  /// Ends the room for good. Throws when the gateway does not confirm it.
  Future<void> disband() async {
    final res = await rpc.request(
      'groups.disband',
      _params({'cancel_id': uuidV4()}),
    );
    final tomb = res is Map ? res['tombstone'] : null;
    if (tomb is! Map || tomb['room_id'] != roomId) {
      throw StateError(Strings.current.groupDisbandUnconfirmed);
    }
    disbanded = true;
    _poll?.cancel();
    _notify();
  }

  Future<void> _act(
    Future<void> Function() body, {
    VoidCallback? onError,
  }) async {
    acting = true;
    _notify();
    try {
      await rpc.connect();
      await body();
    } catch (e) {
      onError?.call();
      error = _describe(e);
    } finally {
      acting = false;
      _notify();
    }
    await refresh();
  }

  static String _describe(Object e) {
    if (e is RpcException) {
      final data = e.data;
      if (data is Map && data['detail'] is String) return data['detail'];
      return e.message;
    }
    if (e is StateError) return e.message;
    return e.toString();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _eventSub.cancel();
    _reconnectSub.cancel();
    _statusSub.cancel();
    super.dispose();
  }
}
