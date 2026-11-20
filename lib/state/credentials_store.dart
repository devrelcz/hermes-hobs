import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the server URL + username (plain prefs) and the secrets — session
/// cookies and the remembered password — in secure storage only. When secure
/// storage fails, secrets live in memory for the rest of the run and are never
/// written to disk in plain text.
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
  static const defaultServer = 'https://hermes.devrel.cz';

  final FlutterSecureStorage _secure;

  /// Secrets that secure storage refused, kept only for this run.
  final Map<String, String> _memory = {};

  Future<String> serverUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kServer) ?? defaultServer;
  }

  Future<String> username() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kUser) ?? '';
  }

  Future<void> saveLogin({
    required String serverUrl,
    required String username,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServer, serverUrl);
    await p.setString(_kUser, username);
  }

  /// The remembered password, or null when the user did not want it kept.
  Future<String?> password() async {
    final v = await _readSecret(_kPassword);
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Stores [password]; null forgets it.
  Future<void> savePassword(String? password) =>
      _writeSecret(_kPassword, password);

  /// Whether the app may sign in on its own with the remembered password.
  /// Cleared by an explicit logout so the user stays signed out.
  Future<bool> autoLogin() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAutoLogin) ?? true;
  }

  Future<void> setAutoLogin(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoLogin, value);
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

  Future<Map<String, String>> cookies() async {
    final raw = await _readSecret(_kCookies);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCookies(Map<String, String> cookies) =>
      _writeSecret(_kCookies, cookies.isEmpty ? null : jsonEncode(cookies));

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
