import 'dart:convert';

/// Why a scanned code cannot be used.
enum PairingFailure {
  /// Not a pairing code at all: another QR code, or a damaged one.
  notPairing,

  /// A pairing code in a format newer than this app knows.
  newerVersion,
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
