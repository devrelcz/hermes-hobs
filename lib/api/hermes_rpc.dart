import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'hermes_http.dart';

/// JSON-RPC error returned by the Hermes gateway.
/// Why a request failed on this side of the wire, with no answer from the
/// server to show. The app words these itself, in the user's language.
enum RpcLocalFailure { notConnected, connectionClosed, timedOut }

class RpcException implements Exception {
  RpcException(this.code, this.message, [this.data]) : local = null;

  /// A failure of the connection itself; [message] is only for logs.
  RpcException.local(this.local, this.code, this.message) : data = null;

  final int code;
  final String message;
  final Object? data;

  /// Set when the request never got a server answer.
  final RpcLocalFailure? local;

  /// Malformed request (unknown / missing params). The canonical dialect
  /// reports it as 4001 `invalid_params`, so it must not read as "gone".
  bool get isInvalidParams =>
      code == 4000 || message == 'invalid_params' || code == -32602;

  /// Runtime session no longer exists (resume it with the stored id).
  bool get isSessionGone =>
      !isInvalidParams &&
      (code == 4001 || message.toLowerCase().contains('session not found'));

  /// The stored session itself is gone (deleted / archived).
  bool get isNotFound =>
      !isInvalidParams && message.toLowerCase().contains('not found');

  @override
  String toString() => 'RPC $code: $message';
}

/// One `{"method":"event"}` notification from the gateway.
class GatewayEvent {
  GatewayEvent(
    this.type,
    this.sessionId,
    this.payload,
    this.seq, {
    this.generation,
  });

  final String type;
  final String? sessionId;
  final Map<String, dynamic> payload;
  final int? seq;

  /// Canonical dialect: the turn's `execution_generation` (fences controls).
  final int? generation;
}

/// Random RFC 4122 v4 id (submission / request ids for the canonical dialect).
String uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// A request the server sends to the client (`approval`, `clarify`, ...).
/// Answer exactly once with [respond] or [decline].
class ServerRequest {
  ServerRequest(this._rpc, this.id, this.method, this.params)
    : detached = false;

  /// A request opened before this socket attached (`open_requests` from
  /// `session.resume`): answered through the `request.answer` RPC.
  ServerRequest.detached(this._rpc, this.id, this.method, this.params)
    : detached = true;

  final HermesRpc _rpc;
  final Object id;
  final String method;
  final Map<String, dynamic> params;
  final bool detached;
  bool _answered = false;

  String? get sessionId => params['session_id'] as String?;
  bool get answered => _answered;

  void respond(Map<String, dynamic> result) {
    if (_answered) return;
    _answered = true;
    if (detached) {
      _rpc.request('request.answer', {'id': id, 'result': result}).ignore();
    } else {
      _rpc._sendRaw({'jsonrpc': '2.0', 'id': id, 'result': result});
    }
  }

  void decline() {
    if (_answered) return;
    _answered = true;
    _rpc._sendRaw({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': -32601, 'message': 'not handled'},
    });
  }
}

enum ConnectionStatus { disconnected, connecting, connected }

/// JSON-RPC 2.0 client for the Hermes dashboard's `/api/ws` gateway socket.
///
/// Auth: a single-use ticket from `POST /api/auth/ws-ticket` (cookie-authed)
/// passed as `?ticket=`. After `gateway.ready` we announce
/// `client.capabilities {server_requests: true}` so approval/clarify requests
/// are routed to us, then keep the socket alive with `gateway.ping` every 15 s.
/// The socket auto-reconnects with backoff; [onReconnected] lets session
/// owners re-attach their sessions.
class HermesRpc {
  HermesRpc(this.http);

  final HermesHttp http;

  static const _pingEvery = Duration(seconds: 15);
  static const _deadAfter = Duration(seconds: 45);

  WebSocket? _ws;
  int _nextId = 1;
  final Map<Object, Completer<dynamic>> _pending = {};
  final _events = StreamController<GatewayEvent>.broadcast();
  final _requests = StreamController<ServerRequest>.broadcast();
  final _status = StreamController<ConnectionStatus>.broadcast();
  final _reconnected = StreamController<void>.broadcast();
  ConnectionStatus _current = ConnectionStatus.disconnected;
  Completer<void>? _ready;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  DateTime _lastFrame = DateTime.now();
  int _attempt = 0;
  bool _closedByUser = false;
  bool _everConnected = false;

  /// True when `gateway.ready` advertised `session_authority`: the server
  /// speaks the canonical `hermes-gateway-v1` session dialect (the gateway
  /// Webapp), whose session verbs take different params than the legacy
  /// TUI dispatcher.
  bool canonical = false;

  /// Called when the session expired and re-login is needed.
  void Function()? onUnauthorized;

  Stream<GatewayEvent> get events => _events.stream;
  Stream<ServerRequest> get serverRequests => _requests.stream;
  Stream<ConnectionStatus> get statusStream => _status.stream;
  Stream<void> get onReconnected => _reconnected.stream;
  ConnectionStatus get status => _current;

  void _setStatus(ConnectionStatus s) {
    if (_current == s) return;
    _current = s;
    _status.add(s);
  }

  /// Opens the socket (idempotent). Completes after `gateway.ready` and the
  /// capability handshake.
  Future<void> connect() async {
    _closedByUser = false;
    if (_current == ConnectionStatus.connected) return;
    if (_ready != null && !_ready!.isCompleted) return _ready!.future;
    final ready = _ready = Completer<void>();
    // Prevent "unhandled future error" when nobody awaits a failed attempt.
    ready.future.ignore();
    _setStatus(ConnectionStatus.connecting);
    try {
      final ticketResp = await http.postJson('/api/auth/ws-ticket', null);
      final ticket = (ticketResp as Map)['ticket'] as String;
      final base = http.baseUrl;
      final wsUri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '${base.path}/api/ws',
        queryParameters: {'ticket': ticket},
      );
      // No Origin header: the dashboard accepts native clients without one.
      final ws = await WebSocket.connect(wsUri.toString())
          .timeout(const Duration(seconds: 20));
      _ws = ws;
      _lastFrame = DateTime.now();
      ws.listen(
        _onFrame,
        onDone: () => _onClosed(ws, ws.closeCode, ws.closeReason),
        onError: (Object e) => _onClosed(ws, null, e.toString()),
        cancelOnError: true,
      );
      // gateway.ready completes [ready] (see _onEvent). Guard against a
      // server that never sends it.
      await ready.future.timeout(const Duration(seconds: 20));
    } catch (e) {
      if (e is HermesHttpException && e.isUnauthorized) {
        _closedByUser = true;
        onUnauthorized?.call();
      }
      if (!ready.isCompleted) ready.completeError(e);
      await _ws?.close();
      _ws = null;
      _setStatus(ConnectionStatus.disconnected);
      _scheduleReconnect();
      rethrow;
    }
  }

  Future<void> _afterReady() async {
    try {
      await request('client.capabilities', {'server_requests': true});
    } catch (_) {
      // Older servers: approvals simply won't be routed to us.
    }
    _attempt = 0;
    _setStatus(ConnectionStatus.connected);
    _startHeartbeat();
    final wasReconnect = _everConnected;
    _everConnected = true;
    if (!(_ready?.isCompleted ?? true)) _ready!.complete();
    if (wasReconnect) _reconnected.add(null);
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingEvery, (_) {
      if (DateTime.now().difference(_lastFrame) > _deadAfter) {
        _ws?.close(4000, 'heartbeat timeout');
        return;
      }
      requestWith('gateway.ping', {}, timeout: _deadAfter).ignore();
    });
  }

  /// Sends a JSON-RPC request and resolves with its `result`.
  Future<dynamic> request(String method, [Map<String, dynamic>? params]) =>
      requestWith(method, params);

  Future<dynamic> requestWith(
    String method,
    Map<String, dynamic>? params, {
    Duration timeout = const Duration(seconds: 60),
  }) {
    final ws = _ws;
    if (ws == null || ws.readyState != WebSocket.open) {
      return Future.error(
        RpcException.local(RpcLocalFailure.notConnected, -1, 'Not connected'),
      );
    }
    final id = 'c${_nextId++}';
    final c = Completer<dynamic>();
    _pending[id] = c;
    _sendRaw({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    return c.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw RpcException.local(
          RpcLocalFailure.timedOut,
          -2,
          '$method timed out',
        );
      },
    );
  }

  void _sendRaw(Map<String, dynamic> frame) {
    final ws = _ws;
    if (ws == null || ws.readyState != WebSocket.open) return;
    ws.add(jsonEncode(frame));
  }

  void _onFrame(dynamic data) {
    _lastFrame = DateTime.now();
    if (data is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final method = decoded['method'];
    final id = decoded['id'];
    if (method == 'event') {
      _onEvent(decoded['params']);
    } else if (method is String && id != null) {
      final params = decoded['params'];
      final req = ServerRequest(
        this,
        id,
        method,
        params is Map<String, dynamic> ? params : <String, dynamic>{},
      );
      if (_requests.hasListener) {
        _requests.add(req);
      } else {
        req.decline();
      }
    } else if (id != null) {
      final c = _pending.remove(id);
      if (c == null || c.isCompleted) return;
      final err = decoded['error'];
      if (err is Map) {
        c.completeError(
          RpcException(
            (err['code'] as num?)?.toInt() ?? -32000,
            err['message']?.toString() ?? 'error',
            err['data'],
          ),
        );
      } else {
        c.complete(decoded['result']);
      }
    }
  }

  void _onEvent(Object? params) {
    if (params is! Map) return;
    final type = params['type']?.toString() ?? '';
    final payload = params['payload'];
    if (type == 'gateway.ready') {
      canonical = payload is Map && payload['session_authority'] == true;
      _afterReady();
      return;
    }
    final p = payload is Map<String, dynamic> ? payload : <String, dynamic>{};
    _events.add(
      GatewayEvent(
        type,
        params['session_id'] as String?,
        p,
        (params['seq'] as num?)?.toInt(),
        generation:
            ((params['execution_generation'] ?? p['execution_generation'])
                    as num?)
                ?.toInt(),
      ),
    );
  }

  void _onClosed(WebSocket ws, int? code, String? reason) {
    if (!identical(ws, _ws)) return;
    _ws = null;
    _pingTimer?.cancel();
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(
          RpcException.local(
            RpcLocalFailure.connectionClosed,
            -1,
            'Connection closed',
          ),
        );
      }
    }
    _pending.clear();
    if (_ready != null && !_ready!.isCompleted) {
      _ready!.completeError(
        reason == null || reason.isEmpty
            ? RpcException.local(
                RpcLocalFailure.connectionClosed,
                code ?? -1,
                'closed',
              )
            : RpcException(code ?? -1, reason),
      );
    }
    _setStatus(ConnectionStatus.disconnected);
    // A refused ticket (4401) is retried with a fresh one; a dead cookie
    // surfaces as 401 from /api/auth/ws-ticket and stops the loop.
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closedByUser) return;
    _reconnectTimer?.cancel();
    final secs = [1, 2, 4, 8, 15, 30][_attempt.clamp(0, 5)];
    _attempt++;
    _reconnectTimer = Timer(Duration(seconds: secs), () {
      connect().catchError((_) {});
    });
  }

  /// Reconnect right away (e.g. app returned to foreground).
  void reconnectNow() {
    if (_closedByUser || _current != ConnectionStatus.disconnected) return;
    _reconnectTimer?.cancel();
    _attempt = 0;
    connect().catchError((_) {});
  }

  Future<void> close() async {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    final ws = _ws;
    _ws = null;
    await ws?.close();
    _setStatus(ConnectionStatus.disconnected);
  }

  Future<void> dispose() async {
    await close();
    await _events.close();
    await _requests.close();
    await _status.close();
    await _reconnected.close();
  }
}
