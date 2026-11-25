import 'dart:convert';

import '../api/hermes_http.dart';

/// Why a scanned code cannot be used.
enum PairingFailure {
  /// Not a pairing code at all: another QR code, or a damaged one.
  notPairing,

  /// A pairing code in a format newer than this app knows.
  newerVersion,

  /// A HobCrew code expired, was already used, or could not be exchanged.
  unavailable,
}

class PairingException implements Exception {
  const PairingException(this.failure);

  final PairingFailure failure;

  @override
  String toString() => 'PairingException(${failure.name})';
}

/// What a Hermes server's pairing QR code carries: where the server is and
/// how to sign in. hermes-box draws it with `./pair.sh`, as JSON:
///
///     {"v":1,"url":"https://agent.example.com","user":"admin","password":"..."}
class PairingCode {
  const PairingCode({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  /// The format this app reads.
  static const version = 1;

  final String serverUrl;
  final String username;
  final String password;

  /// Reads the text of a scanned code. Throws a [PairingException] for
  /// anything that is not a complete pairing code.
  static PairingCode parse(String raw) {
    const notPairing = PairingException(PairingFailure.notPairing);
    final Object? decoded;
    try {
      decoded = jsonDecode(raw.trim());
    } on FormatException {
      throw notPairing;
    }
    if (decoded is! Map<String, dynamic>) throw notPairing;
    final v = decoded['v'];
    final url = decoded['url'];
    final user = decoded['user'];
    final password = decoded['password'];
    if (v is! int || url is! String) throw notPairing;
    if (v > version) throw const PairingException(PairingFailure.newerVersion);
    if (v != version || user is! String || password is! String) {
      throw notPairing;
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.host.isEmpty ||
        user.trim().isEmpty ||
        password.isEmpty) {
      throw notPairing;
    }
    return PairingCode(
      serverUrl: url.trim(),
      username: user.trim(),
      password: password,
    );
  }
}

/// Only HobCrew's own web origin can exchange the code. The origin setting
/// is a build-time override for local development, never taken from a scan.
class MobilePairingLink {
  MobilePairingLink._(this.token);

  static final _origin = Uri.parse(
    const String.fromEnvironment(
      'HOBCREW_PAIRING_ORIGIN',
      defaultValue: 'https://hobcrew.com',
    ),
  );
  static const _crewDomain = String.fromEnvironment(
    'HOBCREW_PAIRING_APPS_DOMAIN',
    defaultValue: 'apps.hobcrew.com',
  );
  static final _tokenPattern = RegExp(r'^[a-zA-Z0-9_-]{43}$');

  final String token;

  static MobilePairingLink? tryParse(Uri uri) {
    if (uri.userInfo.isNotEmpty || uri.hasQuery) return null;
    String? token;
    if (uri.scheme == _origin.scheme &&
        uri.host == _origin.host &&
        uri.port == _origin.port &&
        uri.path == '/pair') {
      token = uri.fragment;
    } else if (uri.scheme == 'hobcrew' &&
        uri.host == 'pair' &&
        !uri.hasPort &&
        !uri.hasFragment &&
        uri.pathSegments.length == 1) {
      token = uri.pathSegments.single;
    }
    return token != null && _tokenPattern.hasMatch(token)
        ? MobilePairingLink._(token)
        : null;
  }

  Future<PairingCode> redeem() async {
    final http = HermesHttp(baseUrl: _origin);
    try {
      final response = await http.postJson('/api/mobile-pairing/redeem', {
        'token': token,
      });
      final result = PairingCode.parse(jsonEncode(response));
      final server = Uri.parse(result.serverUrl);
      if (server.scheme != 'https' ||
          !server.host.endsWith('.$_crewDomain') ||
          server.userInfo.isNotEmpty ||
          server.port != 443 ||
          !(server.path.isEmpty || server.path == '/') ||
          server.hasQuery ||
          server.hasFragment) {
        throw const PairingException(PairingFailure.unavailable);
      }
      return result;
    } catch (_) {
      throw const PairingException(PairingFailure.unavailable);
    } finally {
      http.close();
    }
  }
}
