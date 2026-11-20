import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/group_models.dart';
import '../api/hermes_http.dart';
import '../api/hermes_rpc.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import 'biometrics.dart';
import 'chat_controller.dart';
import 'credentials_store.dart';
import 'group_chat_controller.dart';

enum AuthPhase { loading, signedOut, signedIn }

enum HobFilter { all, unread, pinned, active, recent, older }

/// One collapsible folder of the hob list.
class HobSection {
  HobSection({required this.key, required this.title, required this.hobs});

  /// `section:<id>` or [unassignedKey].
  final String key;
  final String title;
  final List<Hob> hobs;

  static const unassignedKey = 'section:unassigned';

  /// The group chats' own folder.
  static const groupsKey = 'section:groups';
}

/// App-wide state: login, the hob roster (Hermes profiles with their Bot Chat
/// summaries), local unread/collapse bookkeeping, and one live
/// [ChatController] per hob that survives navigating away from the chat.
class AppState extends ChangeNotifier {
  AppState({CredentialsStore? store, Biometrics? biometrics})
    : _store = store ?? CredentialsStore(),
      _biometrics = biometrics ?? Biometrics();

  final CredentialsStore _store;
  final Biometrics _biometrics;

  /// The biometric this device offers right now; null when there is none.
  BiometricKind? biometricKind;

  /// The user wants Face ID / Touch ID / fingerprint before the app opens.
  bool biometricLock = false;

  /// Signed in, but hidden behind the lock screen until the user verifies.
  bool locked = false;

  /// Coming back after at least this long in the background locks again.
  Duration relockAfter = const Duration(minutes: 1);

  DateTime? _hiddenAt;

  /// The system prompt can push the app to the background (Android's PIN
  /// screen), which must not count as leaving the app.
  bool _authenticating = false;

  AuthPhase phase = AuthPhase.loading;
  String serverUrl = CredentialsStore.defaultServer;
  String username = '';

  /// Remembered password (secure storage); null when not kept.
  String? _password;

  /// Why the user landed on the login screen without asking to (e.g. the
  /// remembered password was rejected). Shown by the login form.
  String? authError;

  String? get savedPassword => _password;

  /// Language picked in settings ("cs", "en"); null follows the device.
  String? languageCode;

  static const _languageKey = 'language';

  HermesHttp? _http;
  HermesRpc? _rpc;
  StreamSubscription<ConnectionStatus>? _statusSub;
  Timer? _rosterTimer;

  List<Hob> hobs = [];

  /// Hobs the roster hides. They still belong to folders, so a folder rename
  /// has to reach them too.
  List<Hob> _hiddenHobs = [];
  bool loadingHobs = false;
  String? hobsError;
  final Map<String, ChatController> _chats = {};

  /// Group chats of the default profile's gateway (`groups.list`).
  List<GroupRoom> groups = [];

  /// The gateway offers group chats (`groups.capabilities`); null until known.
  bool? groupsSupported;

  /// Profiles the gateway can seat in a group; null when it does not say.
  Set<String>? seatableProfiles;
  final Map<String, GroupChatController> _groupChats = {};
  Map<String, int> _groupSeen = {}; // room id -> last seen log seq
  StreamSubscription<GatewayEvent>? _groupEvents;
  Timer? _groupsDebounce;
  String? openGroup;

  // Local, per-device bookkeeping (like the dashboard's own storage).
  Map<String, int> _seen = {}; // hob name -> last seen activity (ms)
  Set<String> collapsed = {};

  /// Folder keys in the order the user dragged them into. Kept per device,
  /// like the dashboard keeps its own. Folders missing here go last, by name.
  List<String> sectionOrder = [];
  HobFilter filter = HobFilter.all;
  String query = '';
  String? openHob;

  static const _rosterEvery = Duration(seconds: 20);

  HermesRpc? get rpc => _rpc;
  ConnectionStatus get connection =>
      _rpc?.status ?? ConnectionStatus.disconnected;

  Future<void> init() async {
    await _loadLanguage();
    biometricLock = await _store.biometricLock();
    biometricKind = await _biometrics.available();
    locked = biometricLock;
    serverUrl = await _store.serverUrl();
    username = await _store.username();
    _password = await _store.password();
    await _loadLocal();
    final cookies = await _store.cookies();
    if (cookies.isEmpty) {
      if (await _store.autoLogin() && await _silentLogin()) return;
      phase = AuthPhase.signedOut;
      notifyListeners();
      return;
    }
    _setupClients(Uri.parse(serverUrl), cookies);
    try {
      await _http!.getJson('/api/auth/me');
      _enterSignedIn();
    } catch (e) {
      if (e is HermesHttpException && e.isUnauthorized) {
        await _teardown(clearCookies: true);
        if (await _silentLogin()) return;
        phase = AuthPhase.signedOut;
      } else {
        // Offline / server down: stay signed in, let the user retry.
        _enterSignedIn();
        hobsError = describeError(e);
      }
      notifyListeners();
    }
  }

  /// Signs in with the remembered password, if any. Returns true when signed
  /// in; otherwise leaves the reason in [authError]. A rejected password is
  /// forgotten so it is not retried forever.
  Future<bool> _silentLogin() async {
    final password = _password;
    if (password == null || username.isEmpty) return false;
    try {
      await _passwordLogin(serverUrl, username, password);
      authError = null;
      await _loadLocal();
      _enterSignedIn();
      return true;
    } catch (e) {
      if (e is HermesHttpException && e.isUnauthorized) {
        _password = null;
        await _store.savePassword(null);
        authError = Strings.current.savedPasswordExpired;
      } else {
        authError = describeError(e);
      }
      return false;
    }
  }

  void _setupClients(Uri base, Map<String, String> cookies) {
    final http = HermesHttp(baseUrl: base, cookies: cookies);
    http.onCookiesChanged = (c) => _store.saveCookies(c);
    final rpc = HermesRpc(http)..onUnauthorized = _onSessionExpired;
    _statusSub = rpc.statusStream.listen((s) {
      if (s == ConnectionStatus.connected) unawaited(refreshHobs(silent: true));
      notifyListeners();
    });
    // A room changed: refresh the roster rows (debounced, rounds are chatty).
    _groupEvents = rpc.events.listen((e) {
      if (e.type != 'groups.changed') return;
      _groupsDebounce?.cancel();
      _groupsDebounce = Timer(
        const Duration(milliseconds: 600),
        () => unawaited(refreshGroups()),
      );
    });
    _http = http;
    _rpc = rpc;
  }

  void _enterSignedIn() {
    phase = AuthPhase.signedIn;
    notifyListeners();
    _rpc!.connect().catchError((_) {});
    unawaited(refreshHobs());
    _rosterTimer?.cancel();
    _rosterTimer = Timer.periodic(_rosterEvery, (_) {
      if (connection == ConnectionStatus.connected) {
        unawaited(refreshHobs(silent: true));
      }
    });
  }

  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
    bool rememberPassword = true,
  }) async {
    await _passwordLogin(serverUrl, username, password);
    locked = false;
    this.serverUrl = serverUrl;
    this.username = username;
    _password = rememberPassword ? password : null;
    authError = null;
    await _store.saveLogin(serverUrl: serverUrl, username: username);
    await _store.savePassword(_password);
    await _store.setAutoLogin(true);
    await _loadLocal();
    _enterSignedIn();
  }

  /// POSTs the password login on fresh clients; on success the session
  /// cookies are in the client (and persisted via [_setupClients]).
  Future<void> _passwordLogin(
    String serverUrl,
    String username,
    String password,
  ) async {
    await _teardown(clearCookies: true);
    _setupClients(Uri.parse(serverUrl), {});
    try {
      await _http!.postJson('/auth/password-login', {
        'provider': 'basic',
        'username': username,
        'password': password,
        'next': '',
      });
      if (!_http!.hasSession) {
        throw HermesHttpException(500, Strings.current.errorNoSessionCookie);
      }
    } catch (e) {
      await _teardown(clearCookies: true);
      rethrow;
    }
  }

  Future<void> logout() async {
    final http = _http;
    if (http != null) {
      try {
        await http.postJson('/auth/logout', null);
      } catch (_) {
        // 302 to /login or network error: cookies are dropped locally anyway.
      }
    }
    await _teardown(clearCookies: true);
    // Keep the password for the login form, but do not sign back in on our own.
    await _store.setAutoLogin(false);
    authError = null;
    locked = false;
    phase = AuthPhase.signedOut;
    notifyListeners();
  }

  void _onSessionExpired() {
    if (phase != AuthPhase.signedIn) return;
    // Leave signedIn right away so concurrent 401s do not race us here.
    phase = AuthPhase.loading;
    notifyListeners();
    _teardown(clearCookies: true).then((_) async {
      hobsError = null;
      if (await _silentLogin()) return;
      phase = AuthPhase.signedOut;
      notifyListeners();
    });
  }

  Future<void> _teardown({required bool clearCookies}) async {
    _rosterTimer?.cancel();
    _rosterTimer = null;
    for (final c in _chats.values) {
      c.dispose();
    }
    _chats.clear();
    for (final c in _groupChats.values) {
      c.dispose();
    }
    _groupChats.clear();
    _groupsDebounce?.cancel();
    await _groupEvents?.cancel();
    _groupEvents = null;
    await _statusSub?.cancel();
    _statusSub = null;
    await _rpc?.dispose();
    _rpc = null;
    if (clearCookies) {
      _http?.clearCookies();
      await _store.saveCookies({});
    }
    _http?.close();
    _http = null;
    hobs = [];
    _hiddenHobs = [];
    groups = [];
    groupsSupported = null;
    seatableProfiles = null;
  }

  // --- roster --------------------------------------------------------------

  Future<List<Hob>> _fetchRoster() async {
    final all = await _fetchAllHobs();
    _hiddenHobs = all.where((b) => b.hidden).toList();
    return all.where((b) => !b.hidden).toList();
  }

  Future<List<Hob>> _fetchAllHobs() async {
    final rpc = _rpc;
    if (rpc != null) {
      try {
        await rpc.connect();
        final res = await rpc.requestWith('profiles.list', {
          'include_sessions': true,
        }, timeout: const Duration(seconds: 30)) as Map;
        return _parseRoster(res['profiles']);
      } on HermesHttpException {
        rethrow;
      } catch (_) {
        // Socket not ready: fall back to REST (no Bot Chat previews there).
      }
    }
    final res = await _http!.getJson('/api/profiles') as Map;
    return _parseRoster(res['profiles']);
  }

  static List<Hob> _parseRoster(Object? rows) => (rows as List? ?? const [])
      .whereType<Map>()
      .map((m) => Hob.fromJson(Map<String, dynamic>.from(m)))
      .where((b) => b.name.isNotEmpty)
      .toList();

  Future<void> refreshHobs({bool silent = false}) async {
    if (_http == null) return;
    if (loadingHobs) return;
    loadingHobs = true;
    if (!silent) {
      hobsError = null;
      notifyListeners();
    }
    try {
      final list = await _fetchRoster();
      hobs = list;
      hobsError = null;
      for (final b in list) {
        _chats[b.name]?.updateHob(b);
      }
      // First sight of a hob: everything already there counts as read.
      var seededSeen = false;
      for (final b in list) {
        if (!_seen.containsKey(b.name)) {
          _seen[b.name] = b.lastActive?.millisecondsSinceEpoch ?? 0;
          seededSeen = true;
        }
      }
      if (seededSeen) unawaited(_saveSeen());
      unawaited(refreshGroups());
    } catch (e) {
      if (e is HermesHttpException && e.isUnauthorized) {
        loadingHobs = false;
        _onSessionExpired();
        return;
      }
      if (!silent || hobs.isEmpty) hobsError = describeError(e);
    } finally {
      loadingHobs = false;
      notifyListeners();
    }
  }

  Future<SessionSummary?> _findCanonical(String profile) async {
    try {
      final list = await _fetchRoster();
      hobs = list;
      notifyListeners();
      for (final b in list) {
        if (b.name == profile) return b.canonical;
      }
    } catch (_) {}
    return null;
  }

  // --- derived views -------------------------------------------------------

  bool isUnread(Hob b) {
    if (b.name == openHob) return false;
    final last = b.canonical?.lastActive;
    if (last == null) return false;
    return last.millisecondsSinceEpoch > (_seen[b.name] ?? 0) + 1000;
  }

  bool isWorking(Hob b) => b.workingNow || (_chats[b.name]?.busy ?? false);

  bool _matchesFilter(Hob b) {
    final last = b.lastActive;
    final age = last == null ? null : DateTime.now().difference(last);
    switch (filter) {
      case HobFilter.all:
        break;
      case HobFilter.unread:
        if (!isUnread(b)) return false;
      case HobFilter.pinned:
        if (!b.pinned) return false;
      case HobFilter.active:
        if (!(isWorking(b) ||
            (age != null && age < const Duration(minutes: 15)))) {
          return false;
        }
      case HobFilter.recent:
        if (age == null || age > const Duration(days: 1)) return false;
      case HobFilter.older:
        if (age != null && age <= const Duration(days: 1)) return false;
    }
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return b.displayName.toLowerCase().contains(q) ||
        b.name.toLowerCase().contains(q) ||
        b.description.toLowerCase().contains(q);
  }

  /// Hobs grouped into the user's folders (`ui_meta.sectionId/sectionName`),
  /// "Nezařazení" last. Inside a folder: pinned first, then newest activity.
  List<HobSection> get sections => _sections(hobs.where(_matchesFilter));

  List<HobSection> _sections(Iterable<Hob> members) {
    final byKey = <String, HobSection>{};
    for (final b in members) {
      final key = b.sectionId != null
          ? 'section:${b.sectionId}'
          : HobSection.unassignedKey;
      final title = b.sectionId != null
          ? (b.sectionName ?? Strings.current.folderFallback)
          : Strings.current.unassigned;
      byKey
          .putIfAbsent(key, () => HobSection(key: key, title: title, hobs: []))
          .hobs
          .add(b);
    }
    int byActivity(Hob a, Hob b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final ta = a.lastActive?.millisecondsSinceEpoch ?? 0;
      final tb = b.lastActive?.millisecondsSinceEpoch ?? 0;
      if (ta != tb) return tb.compareTo(ta);
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    }

    for (final s in byKey.values) {
      s.hobs.sort(byActivity);
    }
    int rank(HobSection s) {
      final i = sectionOrder.indexOf(s.key);
      return i < 0 ? sectionOrder.length : i;
    }

    final named =
        byKey.values.where((s) => s.key != HobSection.unassignedKey).toList()
          ..sort((a, b) {
            final byRank = rank(a).compareTo(rank(b));
            if (byRank != 0) return byRank;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
    final rest = byKey[HobSection.unassignedKey];
    return [...named, ?rest];
  }

  /// True when the server has no user folders at all: draw a flat list.
  bool get hasFolders => hobs.any((b) => b.sectionId != null);

  void setFilter(HobFilter f) {
    filter = f;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void toggleSection(String key) {
    if (!collapsed.remove(key)) collapsed.add(key);
    notifyListeners();
    unawaited(_saveLocal());
  }

  /// Moves folder [key] in front of folder [before], or to the end of the
  /// folders when [before] is null. Works on every folder, also the ones the
  /// current search or filter hides.
  void moveSection(String key, {String? before}) {
    if (key == HobSection.unassignedKey || key == before) return;
    final order = [
      for (final s in _sections(hobs))
        if (s.key != HobSection.unassignedKey && s.key != key) s.key,
    ];
    final at = before == null ? -1 : order.indexOf(before);
    order.insert(at < 0 ? order.length : at, key);
    sectionOrder = order;
    notifyListeners();
    unawaited(_saveLocal());
  }

  /// Renames folder [key] the way the dashboard does: the name lives in every
  /// member hob's profile metadata, so each member gets the new name.
  /// Throws when the server refuses a write.
  Future<void> renameSection(String key, String name) async {
    final title = name.trim();
    final rpc = _rpc;
    if (title.isEmpty || rpc == null || key == HobSection.unassignedKey) return;
    try {
      for (final b in [...hobs, ..._hiddenHobs]) {
        if ('section:${b.sectionId}' != key || b.sectionName == title) continue;
        if (!await _writeSectionName(rpc, b, title)) {
          // Someone else edited the hob meanwhile: reread it and retry once.
          final fresh = (await _fetchAllHobs()).where((x) => x.name == b.name);
          if (fresh.isEmpty ||
              !await _writeSectionName(rpc, fresh.first, title)) {
            throw StateError(Strings.current.renameFolderFailed);
          }
        }
      }
    } finally {
      await refreshHobs(silent: true);
    }
  }

  Future<bool> _writeSectionName(HermesRpc rpc, Hob b, String title) =>
      _writeMeta(rpc, b, {...b.meta, 'sectionName': title});

  /// Replaces the hob's whole `hermes-bots` block. False when the server
  /// refused it, e.g. because someone else edited the hob meanwhile.
  Future<bool> _writeMeta(
    HermesRpc rpc,
    Hob b,
    Map<String, dynamic> meta,
  ) async {
    final res = await rpc.request('profiles.configure', {
      'name': b.name,
      'ui_meta': {Hob.metaKey: meta},
      if (b.metaRevision != null)
        'ui_meta_expected_revisions': {Hob.metaKey: b.metaRevision},
    });
    final applied = res is Map ? res['applied'] : null;
    return applied is Map && applied['ui_meta'] == true;
  }

  // --- hob profile ---------------------------------------------------------

  /// The hob as the roster knows it now (hidden ones included).
  Hob? hobNamed(String name) {
    for (final b in [...hobs, ..._hiddenHobs]) {
      if (b.name == name) return b;
    }
    return null;
  }

  HermesRpc get _connected {
    final rpc = _rpc;
    if (rpc == null) throw RpcException(-1, 'Not connected');
    return rpc;
  }

  /// The provider, model and SOUL.md the hob's profile is set to.
  Future<HobSetup> hobSetup(Hob hob) async {
    final res = await _connected.requestWith('profiles.describe', {
      'name': hob.name,
    }, timeout: const Duration(seconds: 30));
    if (res is! Map) return const HobSetup();
    final model = res['model'];
    return HobSetup(
      provider: model is Map ? model['provider']?.toString().trim() ?? '' : '',
      model: model is Map ? model['default']?.toString().trim() ?? '' : '',
      soul: res['soul']?.toString() ?? '',
    );
  }

  /// Providers and their models a hob can be switched to.
  Future<List<ModelProvider>> modelProviders() async {
    final res = await _connected.requestWith('model.options', {
      'include_unconfigured': true,
      'explicit_only': false,
    }, timeout: const Duration(seconds: 30));
    return ModelOptions.fromJson(res).providers;
  }

  /// Saves the hob's title and face. A null [shape] or [color] goes back to
  /// the one derived from the hob's name. Throws when the server refuses.
  Future<void> saveHobAppearance(
    Hob hob, {
    required String title,
    required String? shape,
    required String? color,
  }) async {
    final rpc = _connected;
    Map<String, dynamic> edited(Hob b) {
      final meta = {...b.meta};
      void put(String key, String? value) =>
          value == null ? meta.remove(key) : meta[key] = value;
      final faceChanged = shape != b.shape || color != b.color;
      put('title', title.trim().isEmpty ? null : title.trim());
      put('shape', shape);
      put('color', color);
      // The dashboard's mark for a face the user picked by hand.
      if (faceChanged) meta['custom'] = true;
      return meta;
    }

    if (await _writeMeta(rpc, hob, edited(hob))) return;
    // Someone else edited the hob meanwhile: reread it and retry once.
    final fresh = (await _fetchAllHobs()).where((x) => x.name == hob.name);
    if (fresh.isEmpty ||
        !await _writeMeta(rpc, fresh.first, edited(fresh.first))) {
      throw StateError(Strings.current.hobSaveRefused);
    }
  }

  /// Saves the hob's description (`hermes profile describe`).
  Future<void> saveHobDescription(Hob hob, String text) async {
    _checkCli(
      await _connected.requestWith('cli.exec', {
        'argv': ['profile', 'describe', hob.name, '--text', text.trim()],
      }, timeout: const Duration(seconds: 30)),
    );
  }

  /// Switches the hob to [provider] and [model]; both empty makes it inherit
  /// the launch profile's model again. Returns the server's question when it
  /// wants the switch confirmed (an expensive model): ask the user and call
  /// again with [confirmed].
  Future<String?> saveHobModel(
    Hob hob, {
    required String provider,
    required String model,
    bool confirmed = false,
  }) async {
    final rpc = _connected;
    if (provider.isEmpty && model.isEmpty) {
      _checkCli(
        await rpc.requestWith('cli.exec', {
          'argv': ['--profile', hob.name, 'config', 'unset', 'model'],
        }, timeout: const Duration(seconds: 30)),
      );
      return null;
    }
    final res = await rpc.requestWith('profiles.configure', {
      'name': hob.name,
      'model': model,
      'provider': provider,
      if (confirmed) 'confirm_expensive_model': true,
    }, timeout: const Duration(seconds: 30));
    if (res is Map && res['confirm_required'] == true && !confirmed) {
      return res['confirm_message']?.toString() ?? '';
    }
    final applied = res is Map ? res['applied'] : null;
    if (applied is! Map || applied['model'] != true) {
      throw StateError(Strings.current.hobSaveRefused);
    }
    return null;
  }

  /// Replaces the hob's SOUL.md. Throws when the server refuses.
  Future<void> saveHobSoul(Hob hob, String soul) async {
    final res = await _connected.requestWith('profiles.configure', {
      'name': hob.name,
      'soul': soul.trim(),
    }, timeout: const Duration(seconds: 30));
    final applied = res is Map ? res['applied'] : null;
    if (applied is! Map || applied['soul'] != true) {
      throw StateError(Strings.current.hobSaveRefused);
    }
  }

  static void _checkCli(Object? res) {
    if (res is! Map) return;
    final code = res['code'];
    if (res['blocked'] == true || (code is num && code != 0)) {
      final err = (res['stderr'] ?? res['error'] ?? '').toString().trim();
      throw StateError(err.isEmpty ? Strings.current.hobSaveRefused : err);
    }
  }

  // --- chats ---------------------------------------------------------------

  /// Returns the live chat for [hob], creating and opening it on first use.
  ChatController chatFor(Hob hob) {
    final existing = _chats[hob.name];
    if (existing != null) return existing;
    final c = ChatController(
      rpc: _rpc!,
      hob: hob,
      findCanonical: _findCanonical,
      onTurnSettled: (b) {
        if (openHob == b.name) markSeen(b.name);
        unawaited(refreshHobs(silent: true));
      },
    );
    _chats[hob.name] = c;
    unawaited(c.start());
    return c;
  }

  void setOpenHob(String? name) {
    final prev = openHob;
    openHob = name;
    if (name != null) markSeen(name);
    if (prev != null && prev != name) markSeen(prev);
    Future.microtask(notifyListeners);
  }

  void markSeen(String name) {
    _seen[name] = DateTime.now().millisecondsSinceEpoch;
    unawaited(_saveSeen());
  }

  // --- group chats ---------------------------------------------------------

  /// The profile whose gateway holds the group chats: the default one, like
  /// the dashboard opened on its launch profile.
  String get groupProfile {
    for (final b in [...hobs, ..._hiddenHobs]) {
      if (b.isDefault) return b.name;
    }
    return 'default';
  }

  bool _loadingGroups = false;

  /// Re-reads the rooms (`groups.list`, paged). A gateway without group chats
  /// leaves the list empty and hides "new group chat".
  Future<void> refreshGroups() async {
    final rpc = _rpc;
    if (rpc == null || _loadingGroups) return;
    _loadingGroups = true;
    try {
      await rpc.connect();
      final profile = groupProfile;
      if (groupsSupported == null) {
        try {
          final cap = await rpc.request('groups.capabilities', {
            'profile': profile,
          });
          final methods = cap is Map ? cap['methods'] : null;
          groupsSupported =
              cap is Map &&
              cap['driver'] == true &&
              (methods is! List || methods.contains('groups.create'));
          final seatable = cap is Map ? cap['seatable_profiles'] : null;
          seatableProfiles = seatable is List
              ? seatable.map((e) => e.toString()).toSet()
              : null;
        } on RpcException {
          groupsSupported = false;
        }
      }
      if (groupsSupported != true) return;
      final rooms = <GroupRoom>[];
      var offset = 0;
      for (var page = 0; page < 50; page++) {
        final res = await rpc.request('groups.list', {
          'profile': profile,
          'limit': 100,
          'offset': offset,
        });
        if (res is! Map) break;
        rooms.addAll(
          (res['rooms'] as List? ?? const []).map(GroupRoom.fromJson).nonNulls,
        );
        final next = res['next_offset'];
        if (next is! int || next <= offset) break;
        offset = next;
      }
      if (_disposed || !identical(rpc, _rpc)) return;
      groups = rooms;
      // First sight of a room: what is already there counts as read.
      var seeded = false;
      for (final r in rooms) {
        if (!_groupSeen.containsKey(r.roomId)) {
          _groupSeen[r.roomId] = r.latestSeq;
          seeded = true;
        }
      }
      if (seeded) unawaited(_saveGroupSeen());
      for (final id in [..._groupChats.keys]) {
        if (!rooms.any((r) => r.roomId == id)) {
          // Disbanded elsewhere: the open chat says so itself.
          unawaited(_groupChats[id]!.refresh());
        }
      }
    } catch (_) {
      // Group chats are extra: the Hob roster carries the error, if any.
    } finally {
      _loadingGroups = false;
      if (!_disposed) notifyListeners();
    }
  }

  GroupRoom? groupById(String roomId) {
    for (final r in groups) {
      if (r.roomId == roomId) return r;
    }
    return _groupChats[roomId]?.room;
  }

  /// The Hob behind a seat; a stand-in when the roster does not know it.
  Hob memberHob(GroupMember m) =>
      hobNamed(m.profile) ??
      Hob(
        name: m.profile,
        displayName: m.displayName.isNotEmpty ? m.displayName : m.handle,
      );

  /// What the member is called in this app: the Hob's title.
  String memberName(GroupMember m) => memberHob(m).displayName;

  int _latestSeq(GroupRoom r) {
    final live = _groupChats[r.roomId]?.lastSeq ?? 0;
    return live > r.latestSeq ? live : r.latestSeq;
  }

  bool isGroupUnread(GroupRoom r) {
    if (r.roomId == openGroup) return false;
    return _latestSeq(r) > (_groupSeen[r.roomId] ?? 0);
  }

  bool isGroupWorking(GroupRoom r) => _groupChats[r.roomId]?.busy ?? false;

  /// Newest message of a room the app has open; null before it is loaded.
  String? groupPreview(GroupRoom r) {
    final p = _groupChats[r.roomId]?.preview ?? '';
    return p.isEmpty ? null : p;
  }

  DateTime? groupLastActive(GroupRoom r) =>
      _groupChats[r.roomId]?.lastActive ?? r.updatedAt ?? r.createdAt;

  bool _groupMatches(GroupRoom r) {
    final last = groupLastActive(r);
    final age = last == null ? null : DateTime.now().difference(last);
    switch (filter) {
      case HobFilter.all:
        break;
      case HobFilter.unread:
        if (!isGroupUnread(r)) return false;
      case HobFilter.pinned:
        return false;
      case HobFilter.active:
        if (!(isGroupWorking(r) ||
            (age != null && age < const Duration(minutes: 15)))) {
          return false;
        }
      case HobFilter.recent:
        if (age == null || age > const Duration(days: 1)) return false;
      case HobFilter.older:
        if (age != null && age <= const Duration(days: 1)) return false;
    }
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return r.name.toLowerCase().contains(q) ||
        r.members.any(
          (m) =>
              m.handle.toLowerCase().contains(q) ||
              memberName(m).toLowerCase().contains(q),
        );
  }

  /// Rooms the search and filter let through, newest activity first.
  List<GroupRoom> get visibleGroups {
    final list = groups.where(_groupMatches).toList()
      ..sort((a, b) {
        final ta = groupLastActive(a)?.millisecondsSinceEpoch ?? 0;
        final tb = groupLastActive(b)?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });
    return list;
  }

  /// Returns the live chat for [room], loading it on first use.
  GroupChatController groupChatFor(GroupRoom room) {
    final existing = _groupChats[room.roomId];
    if (existing != null) return existing;
    final c = GroupChatController(
      rpc: _rpc!,
      profile: groupProfile,
      room: room,
      onChanged: (chat) {
        final i = groups.indexWhere((r) => r.roomId == chat.roomId);
        if (i >= 0) {
          groups[i] = chat.room.copyWith(latestSeq: chat.lastSeq);
        }
        if (openGroup == chat.roomId) markGroupSeen(chat.roomId);
        notifyListeners();
      },
    );
    _groupChats[room.roomId] = c;
    unawaited(c.start());
    return c;
  }

  void setOpenGroup(String? roomId) {
    final prev = openGroup;
    openGroup = roomId;
    if (roomId != null) markGroupSeen(roomId);
    if (prev != null && prev != roomId) markGroupSeen(prev);
    Future.microtask(notifyListeners);
  }

  void markGroupSeen(String roomId) {
    final r = groupById(roomId);
    if (r == null) return;
    _groupSeen[roomId] = _latestSeq(r);
    unawaited(_saveGroupSeen());
  }

  /// Name for a new room: the members' titles, made unique among the rooms.
  String groupNameFor(List<Hob> members) {
    final base = members.map((b) => b.displayName).join(', ');
    final taken = groups.map((r) => r.name).toSet();
    if (!taken.contains(base)) return base;
    for (var i = 2; ; i++) {
      final name = '$base ($i)';
      if (!taken.contains(name)) return name;
    }
  }

  /// Seats [members] (two to six Hobs) in a new room.
  Future<GroupRoom> createGroup(List<Hob> members, {String? name}) async {
    final rpc = _connected;
    final res = await rpc.requestWith('groups.create', {
      'profile': groupProfile,
      'room_id': uuidV4(),
      'name': (name?.trim().isNotEmpty ?? false)
          ? name!.trim()
          : groupNameFor(members),
      'members': [for (final b in members) GroupMember.localSeat(b.name)],
    }, timeout: const Duration(seconds: 30));
    final room = res is Map ? GroupRoom.fromJson(res['room']) : null;
    if (room == null) throw StateError(Strings.current.groupCreateFailed);
    groups = [room, ...groups.where((r) => r.roomId != room.roomId)];
    _groupSeen[room.roomId] = room.latestSeq;
    unawaited(_saveGroupSeen());
    notifyListeners();
    return room;
  }

  /// Drops a disbanded room from the list.
  void forgetGroup(String roomId) {
    groups = groups.where((r) => r.roomId != roomId).toList();
    _groupChats.remove(roomId)?.dispose();
    _groupSeen.remove(roomId);
    unawaited(_saveGroupSeen());
    if (openGroup == roomId) openGroup = null;
    notifyListeners();
  }

  Future<List<CronJob>> cronJobs(Hob hob) async {
    final rpc = _rpc;
    if (rpc == null) return [];
    await rpc.connect();
    final res = await rpc.requestWith('cron.manage', {
      'action': 'list',
      'profile': hob.name,
      'include_disabled': true,
    }, timeout: const Duration(seconds: 30));
    if (res is! Map) return [];
    if (res['success'] == false && res['error'] != null) {
      throw Exception(res['error'].toString());
    }
    final jobs = res['jobs'];
    if (jobs is! List) return [];
    return jobs
        .whereType<Map>()
        .map((j) => CronJob.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  void onAppResumed() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (biometricLock &&
        phase == AuthPhase.signedIn &&
        hiddenAt != null &&
        DateTime.now().difference(hiddenAt) >= relockAfter) {
      locked = true;
      notifyListeners();
    }
    unawaited(_refreshBiometricKind());
    _rpc?.reconnectNow();
    if (phase == AuthPhase.signedIn) unawaited(refreshHobs(silent: true));
    for (final c in _groupChats.values) {
      unawaited(c.refresh());
    }
  }

  /// The app left the screen (backgrounded, minimized).
  void onAppHidden() {
    if (_authenticating) return;
    _hiddenAt ??= DateTime.now();
  }

  // --- biometrics ----------------------------------------------------------

  /// The user may have enrolled or removed a face/finger in the meantime.
  Future<void> _refreshBiometricKind() async {
    final kind = await _biometrics.available();
    if (kind == biometricKind) return;
    biometricKind = kind;
    notifyListeners();
  }

  /// Runs the system prompt; throws [BiometricException] when it does not
  /// let the user in.
  Future<void> _verify() async {
    _authenticating = true;
    try {
      await _biometrics.authenticate(Strings.current.biometricReason);
    } finally {
      _authenticating = false;
    }
  }

  /// Lifts the lock screen once the user is verified.
  Future<void> unlock() async {
    await _verify();
    locked = false;
    _hiddenAt = null;
    notifyListeners();
  }

  /// Turning the lock on asks for the biometric first, so nobody enables
  /// something their device then refuses.
  Future<void> setBiometricLock(bool value) async {
    if (value == biometricLock) return;
    if (value) await _verify();
    biometricLock = value;
    await _store.setBiometricLock(value);
    notifyListeners();
  }

  /// The login screen can sign in with a biometric instead of the password:
  /// the lock is on and the password is remembered.
  bool get canBiometricSignIn =>
      biometricLock &&
      biometricKind != null &&
      _password != null &&
      username.isNotEmpty;

  /// Verifies the user, then signs in with the remembered password.
  Future<void> biometricSignIn() async {
    final password = _password;
    if (password == null) return;
    await _verify();
    try {
      await login(serverUrl: serverUrl, username: username, password: password);
    } catch (e) {
      if (e is HermesHttpException && e.isUnauthorized) {
        // The server no longer takes it; do not offer it again.
        _password = null;
        await _store.savePassword(null);
        notifyListeners();
      }
      rethrow;
    }
  }

  // --- language ------------------------------------------------------------

  Future<void> _loadLanguage() async {
    try {
      final p = await SharedPreferences.getInstance();
      _applyLanguage(p.getString(_languageKey));
    } catch (_) {}
  }

  /// Switches the app language; null goes back to following the device.
  Future<void> setLanguage(String? code) async {
    if (code == languageCode) return;
    _applyLanguage(code);
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      if (code == null) {
        await p.remove(_languageKey);
      } else {
        await p.setString(_languageKey, code);
      }
    } catch (_) {}
  }

  void _applyLanguage(String? code) {
    final known = Strings.supportedLocales.any((l) => l.languageCode == code);
    languageCode = known ? code : null;
    Strings.current = Strings.forLocale(
      languageCode != null
          ? Locale(languageCode!)
          : Strings.resolve(PlatformDispatcher.instance.locales),
    );
  }

  // --- local persistence ---------------------------------------------------

  String get _localKey => 'local::$serverUrl::$username';

  Future<void> _loadLocal() async {
    try {
      final p = await SharedPreferences.getInstance();
      final seen = p.getString('$_localKey::seen');
      _seen = seen == null
          ? {}
          : Map<String, int>.from(jsonDecode(seen) as Map);
      collapsed = (p.getStringList('$_localKey::collapsed') ?? const [])
          .toSet();
      sectionOrder = p.getStringList('$_localKey::sectionOrder') ?? [];
      final groupSeen = p.getString('$_localKey::groupSeen');
      _groupSeen = groupSeen == null
          ? {}
          : Map<String, int>.from(jsonDecode(groupSeen) as Map);
    } catch (_) {
      _groupSeen = {};
      _seen = {};
      collapsed = {};
      sectionOrder = [];
    }
  }

  Future<void> _saveSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('$_localKey::seen', jsonEncode(_seen));
    } catch (_) {}
  }

  Future<void> _saveGroupSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('$_localKey::groupSeen', jsonEncode(_groupSeen));
    } catch (_) {}
  }

  Future<void> _saveLocal() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('$_localKey::collapsed', collapsed.toList());
      await p.setStringList('$_localKey::sectionOrder', sectionOrder);
    } catch (_) {}
  }

  static String describeError(Object e) {
    final s = Strings.current;
    if (e is HermesHttpException) {
      switch (e.statusCode) {
        case 401:
          return s.errorBadCredentials;
        case 404:
          return s.errorNoPasswordLogin;
        case 429:
          return s.errorTooManyAttempts;
        case 503:
          return s.errorServerDown;
      }
      return s.errorServer(e.message);
    }
    if (e is SocketException) return s.errorUnreachable(e.message);
    if (e is HandshakeException) return s.errorTls(e.message);
    if (e is TimeoutException) return s.errorTimeout;
    if (e is FormatException) return s.errorBadServerUrl;
    if (e is StateError) return e.message;
    if (e is RpcException) return e.message;
    return e.toString();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _teardown(clearCookies: false);
    super.dispose();
  }
}
