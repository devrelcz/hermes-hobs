import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One saved Hermes server and user, under a name the user chose. Its
/// password and session cookies live in secure storage under its [id].
class ServerAccount {
  const ServerAccount({
    required this.id,
    required this.name,
    required this.color,
    required this.serverUrl,
    required this.username,
  });

  /// Empty for the account that existed before accounts did: it keeps the
  /// original storage keys, so updating the app moves nothing.
  final String id;
  final String name;

  /// `#RRGGBB`, the account's mark on the avatar.
  final String color;
  final String serverUrl;
  final String username;

  String get host => Uri.tryParse(serverUrl)?.host ?? serverUrl;

  /// What the account is called when the user gave it no name: the host.
  String get label => name.trim().isEmpty ? host : name.trim();

  ServerAccount copyWith({
    String? name,
    String? color,
    String? serverUrl,
    String? username,
  }) => ServerAccount(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    serverUrl: serverUrl ?? this.serverUrl,
    username: username ?? this.username,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'server': serverUrl,
    'user': username,
  };

  static ServerAccount fromJson(Map<String, dynamic> j) => ServerAccount(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    color: j['color']?.toString() ?? accountColors.first,
    serverUrl: j['server']?.toString() ?? '',
    username: j['user']?.toString() ?? '',
  );
}

/// The colors an account can wear, in the order new accounts take them.
const accountColors = [
  '#1D9E75',
  '#7F77DD',
  '#D85A30',
  '#378ADD',
  '#D4537E',
  '#BA7517',
];

/// Persists the server URL + username (plain prefs) and the secrets — session
/// cookies and the remembered password — in secure storage only. When secure
/// storage fails, secrets live in memory for the rest of the run and are never
/// written to disk in plain text.
///
/// Everything but the biometric lock belongs to one account: [activeId]
/// picks which. The first account (id '') uses the original keys.
class CredentialsStore {
  CredentialsStore({FlutterSecureStorage? secure})
    : _secure = secure ?? _defaultSecure;

  /// On macOS the legacy keychain works in the sandbox without the
  /// keychain-access-groups entitlement and its provisioning profile.
  static const _defaultSecure = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static const _kServer = 'server_url';
  static const _kUser = 'username';
  static const _kCookies = 'session_cookies';
  static const _kPassword = 'password';
  static const _kAutoLogin = 'auto_login';
  static const _kBiometricLock = 'biometric_lock';

  final FlutterSecureStorage _secure;

  static const _kAccounts = 'accounts';
  static const _kActive = 'active_account';

  /// The account the per-account reads and writes go to.
  String activeId = '';

  /// [base] for the active account (the first account keeps the bare key).
  String _k(String base, [String? id]) {
    final of = id ?? activeId;
    return of.isEmpty ? base : '$base@$of';
  }

  /// The saved accounts, in the user's order. Before accounts existed there
  /// was one sign-in: it becomes the first account, under the server's
  /// name, the first time this runs.
  Future<List<ServerAccount>> accounts() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kAccounts);
    if (raw != null) {
      try {
        return [
          for (final j in jsonDecode(raw) as List)
            ServerAccount.fromJson(Map<String, dynamic>.from(j as Map)),
        ];
      } catch (_) {}
    }
    final server = p.getString(_kServer) ?? '';
    if (server.isEmpty) return [];
    final first = ServerAccount(
      id: '',
      name: '',
      color: accountColors.first,
      serverUrl: server,
      username: p.getString(_kUser) ?? '',
    );
    await saveAccounts([first]);
    return [first];
  }

  Future<void> saveAccounts(List<ServerAccount> accounts) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kAccounts,
      jsonEncode([for (final a in accounts) a.toJson()]),
    );
  }

  /// The account the app opened last.
  Future<String> savedActiveId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kActive) ?? '';
  }

  Future<void> saveActiveId(String id) async {
    activeId = id;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kActive, id);
  }

  /// A fresh account id.
  static String newId() {
    final r = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return [for (var i = 0; i < 8; i++) chars[r.nextInt(chars.length)]].join();
  }

  /// Drops everything stored for account [id]: its password, cookies and
  /// sign-in. Nothing changes on the server.
  Future<void> forget(String id) async {
    final p = await SharedPreferences.getInstance();
    for (final key in [_kServer, _kUser, _kAutoLogin]) {
      await p.remove(_k(key, id));
    }
    for (final key in [_kPassword, _kCookies]) {
      _memory.remove(_k(key, id));
      try {
        await _secure.delete(key: _k(key, id));
      } catch (_) {}
    }
  }

  /// Secrets that secure storage refused, kept only for this run.
  final Map<String, String> _memory = {};

  /// Empty until the user signs in once; there is no default server.
  Future<String> serverUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_k(_kServer)) ?? '';
  }

  Future<String> username() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_k(_kUser)) ?? '';
  }

  Future<void> saveLogin({
    required String serverUrl,
    required String username,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k(_kServer), serverUrl);
    await p.setString(_k(_kUser), username);
  }

  /// The remembered password, or null when the user did not want it kept.
  Future<String?> password({String? account}) async {
    final v = await _readSecret(_k(_kPassword, account));
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Stores [password]; null forgets it.
  Future<void> savePassword(String? password, {String? account}) =>
      _writeSecret(_k(_kPassword, account), password);

  /// Whether the app may sign in on its own with the remembered password.
  /// Cleared by an explicit logout so the user stays signed out.
  Future<bool> autoLogin() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_k(_kAutoLogin)) ?? true;
  }

  Future<void> setAutoLogin(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_k(_kAutoLogin), value);
  }

  /// Whether the app asks for Face ID / Touch ID / fingerprint before it
  /// shows anything, and offers it instead of typing the password.
  Future<bool> biometricLock() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kBiometricLock) ?? false;
  }

  Future<void> setBiometricLock(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kBiometricLock, value);
  }

  Future<Map<String, String>> cookies({String? account}) async {
    final raw = await _readSecret(_k(_kCookies, account));
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCookies(Map<String, String> cookies, {String? account}) =>
      _writeSecret(
        _k(_kCookies, account),
        cookies.isEmpty ? null : jsonEncode(cookies),
      );

  // --- secure storage, memory-only fallback -------------------------------

  Future<String?> _readSecret(String key) async {
    await _purgePlainCopy(key);
    try {
      final v = await _secure.read(key: key);
      if (v != null) return v;
    } catch (_) {
      // Secure storage unavailable: fall through to this run's memory copy.
    }
    return _memory[key];
  }

  Future<void> _writeSecret(String key, String? value) async {
    await _purgePlainCopy(key);
    if (value == null) {
      _memory.remove(key);
    } else {
      _memory[key] = value;
    }
    try {
      if (value == null) {
        await _secure.delete(key: key);
      } else {
        await _secure.write(key: key, value: value);
      }
      _memory.remove(key);
    } catch (_) {
      // Keep the memory copy only; nothing goes to disk.
    }
  }

  /// Earlier builds wrote secrets to prefs in plain text when the keychain
  /// failed. Move such a copy into secure storage (or this run's memory) and
  /// delete it from disk.
  Future<void> _purgePlainCopy(String key) async {
    final p = await SharedPreferences.getInstance();
    final plain = p.getString(key);
    if (plain == null) return;
    await p.remove(key);
    try {
      if (await _secure.read(key: key) == null) {
        await _secure.write(key: key, value: plain);
      }
    } catch (_) {
      _memory.putIfAbsent(key, () => plain);
    }
  }
}
