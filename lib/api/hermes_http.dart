import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Thrown for any non-2xx response from the Hermes dashboard.
class HermesHttpException implements Exception {
  HermesHttpException(this.statusCode, this.message, {this.body});

  final int statusCode;
  final String message;
  final Object? body;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'HTTP $statusCode: $message';
}

/// Thrown by [HermesHttp.upload] after [UploadCancel.cancel].
class UploadCancelled implements Exception {
  const UploadCancelled();

  @override
  String toString() => 'Upload cancelled';
}

/// Lets the caller abort a running [HermesHttp.upload].
class UploadCancel {
  bool _cancelled = false;
  HttpClientRequest? _request;

  bool get cancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _request?.abort(const UploadCancelled());
  }

  void _attach(HttpClientRequest r) => _request = r;
  void _detach() => _request = null;
}

/// Minimal cookie-aware HTTP client for the Hermes dashboard.
///
/// Hermes' gated dashboard authenticates with session cookies
/// (`hermes_session_at`, `hermes_session_rt`, `hermes_session_provider`,
/// `__Host-`-prefixed over HTTPS). The auth middleware silently rotates them
/// on any request, so every `Set-Cookie` is folded back into [cookies] and
/// [onCookiesChanged] lets the caller persist the new values.
///
/// Uses `dart:io` directly because `package:http` folds multiple Set-Cookie
/// headers into one comma-joined string, which breaks on `Expires=` dates.
class HermesHttp {
  HermesHttp({required Uri baseUrl, Map<String, String>? cookies})
    : baseUrl = _normalizeBase(baseUrl),
      cookies = {...?cookies};

  final Uri baseUrl;
  final Map<String, String> cookies;
  void Function(Map<String, String> cookies)? onCookiesChanged;

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 30);

  static Uri _normalizeBase(Uri u) {
    var path = u.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return u.replace(path: path, query: null, fragment: null);
  }

  Uri resolve(String path, [Map<String, String>? query]) {
    return baseUrl.replace(
      path: '${baseUrl.path}$path',
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  /// Origin the dashboard expects on same-origin requests and WS upgrades.
  String get origin {
    final defaultPort = baseUrl.scheme == 'https' ? 443 : 80;
    final port = baseUrl.hasPort && baseUrl.port != defaultPort
        ? ':${baseUrl.port}'
        : '';
    return '${baseUrl.scheme}://${baseUrl.host}$port';
  }

  String get cookieHeader =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  bool get hasSession => cookies.keys.any((k) => k.contains('hermes_session_'));

  Future<dynamic> getJson(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> postJson(
    String path,
    Object? body, {
    Map<String, String>? query,
  }) => _send('POST', path, body: body, query: query);

  Future<dynamic> deleteJson(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = resolve(path, query);
    final req = await _client.openUrl(method, uri);
    _prepare(req);
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      req.headers.contentType = ContentType.json;
      req.contentLength = bytes.length;
      req.add(bytes);
    }
    final resp = await req.close().timeout(const Duration(seconds: 30));
    return _decode(resp);
  }

  void _prepare(HttpClientRequest req) {
    req.followRedirects = false;
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    // Same-origin markers: the dashboard's CSRF/origin guard accepts these.
    req.headers.set('Origin', origin);
    req.headers.set(HttpHeaders.refererHeader, '$origin/');
    if (cookies.isNotEmpty) {
      req.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    }
  }

  /// Sends [body] in chunks, reporting the bytes written so far, and decodes
  /// the JSON reply like [postJson]. [cancel] aborts the request mid-way;
  /// the future then fails with [UploadCancelled].
  Future<dynamic> upload(
    String path, {
    required List<int> body,
    required String contentType,
    Map<String, String>? query,
    void Function(int sent, int total)? onProgress,
    UploadCancel? cancel,
  }) async {
    if (cancel?.cancelled ?? false) throw const UploadCancelled();
    final req = await _client.openUrl('POST', resolve(path, query));
    _prepare(req);
    req.headers.set(HttpHeaders.contentTypeHeader, contentType);
    req.contentLength = body.length;
    cancel?._attach(req);
    try {
      const chunk = 64 * 1024;
      var sent = 0;
      onProgress?.call(0, body.length);
      while (sent < body.length) {
        if (cancel?.cancelled ?? false) throw const UploadCancelled();
        final end = (sent + chunk).clamp(0, body.length);
        req.add(body.sublist(sent, end));
        await req.flush();
        sent = end;
        onProgress?.call(sent, body.length);
      }
      final resp = await req.close().timeout(const Duration(minutes: 2));
      return await _decode(resp);
    } catch (e) {
      if (cancel?.cancelled ?? false) throw const UploadCancelled();
      rethrow;
    } finally {
      cancel?._detach();
    }
  }

  /// Raw bytes of a GET (an image the dashboard serves); throws on non-2xx.
  Future<Uint8List> getBytes(String path, {Map<String, String>? query}) async {
    final req = await _client.openUrl('GET', resolve(path, query));
    _prepare(req);
    req.headers.set(HttpHeaders.acceptHeader, '*/*');
    final resp = await req.close().timeout(const Duration(seconds: 30));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return await _decode(resp) as Uint8List; // throws
    }
    _absorbCookies(resp);
    final b = BytesBuilder(copy: false);
    await for (final c in resp) {
      b.add(c);
    }
    return b.takeBytes();
  }

  Future<dynamic> _decode(HttpClientResponse resp) async {
    _absorbCookies(resp);
    final text = await resp.transform(utf8.decoder).join();
    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        decoded = text;
      }
    }
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return decoded;
    }
    if (resp.statusCode == 302 || resp.statusCode == 303) {
      // The gate redirects unauthenticated HTML routes to /login.
      throw HermesHttpException(401, 'Not signed in', body: decoded);
    }
    throw HermesHttpException(
      resp.statusCode,
      _errorMessage(decoded, resp.reasonPhrase),
      body: decoded,
    );
  }

  static String _errorMessage(Object? decoded, String fallback) {
    if (decoded is Map) {
      final detail =
          decoded['detail'] ?? decoded['error'] ?? decoded['message'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail != null) return detail.toString();
    }
    if (decoded is String && decoded.isNotEmpty && decoded.length < 300) {
      return decoded;
    }
    return fallback;
  }

  void _absorbCookies(HttpClientResponse resp) {
    var changed = false;
    // `resp.cookies` throws on a malformed header; parse raw values defensively.
    for (final raw
        in resp.headers[HttpHeaders.setCookieHeader] ?? const <String>[]) {
      final first = raw.split(';').first;
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      final name = first.substring(0, eq).trim();
      var value = first.substring(eq + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      final lower = raw.toLowerCase();
      final expired =
          value.isEmpty ||
          RegExp(r'max-age=0(?!\d)').hasMatch(lower) ||
          lower.contains('expires=thu, 01 jan 1970');
      if (expired) {
        if (cookies.remove(name) != null) changed = true;
      } else if (cookies[name] != value) {
        cookies[name] = value;
        changed = true;
      }
    }
    if (changed) onCookiesChanged?.call(Map.of(cookies));
  }

  void clearCookies() {
    if (cookies.isEmpty) return;
    cookies.clear();
    onCookiesChanged?.call(const {});
  }

  void close() => _client.close(force: true);
}
