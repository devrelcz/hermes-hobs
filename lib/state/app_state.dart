import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
import 'composer_draft.dart';
import 'credentials_store.dart';
import 'group_chat_controller.dart';
import 'notifications.dart';

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
  AppState({
    CredentialsStore? store,
    Biometrics? biometrics,
    Notifier? notifier,
    BackgroundTime? backgroundTime,
  }) : _store = store ?? CredentialsStore(),
       _biometrics = biometrics ?? Biometrics(),
       _notifier = notifier ?? LocalNotifier(),
       _backgroundTime = backgroundTime ?? BackgroundTime();

  final CredentialsStore _store;
  final Biometrics _biometrics;
  final Notifier _notifier;
  final BackgroundTime _backgroundTime;
  StreamSubscription<String>? _tapSub;

  /// The user wants notifications (Settings). On by default; the system
  /// permission is asked for when the first prompt is sent.
  bool notificationsEnabled = true;

  /// The system refuses notifications (denied, or turned off for the app).
  bool notificationsBlocked = false;
  bool _permissionAsked = false;

  static const _notificationsKey = 'notifications';
  static const _notificationsAskedKey = 'notifications_asked';

  /// The app is on screen and focused. Notifications for the chat the user
  /// is looking at are pointless; everything else notifies.
  bool appActive = true;

  /// A hob whose notification the user tapped; [takePendingChat] hands it to
  /// the hob list once the app is unlocked and the hob is known.
  String? pendingChat;

  /// A group chat (room id) whose notification the user tapped;
  /// [takePendingGroup] hands it over like [pendingChat].
  String? pendingGroup;

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
  String serverUrl = '';
  String username = '';

  /// Remembered password (secure storage); null when not kept.
  String? _password;

  /// Why the user landed on the login screen without asking to (e.g. the
  /// remembered password was rejected). Shown by the login form.
  String? get authError => _authError?.call();

  /// Errors are kept as builders, not text, so a language switch re-words
  /// them.
  String Function()? _authError;

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

  /// Why the Hob list could not load, in the current language.
  String? get hobsError => _hobsError?.call();
  String Function()? _hobsError;
  final Map<String, ChatController> _chats = {};
  final Map<String, ComposerDraft> _drafts = {};

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

  /// Notifications: the newest log seq of each room already looked at
  /// (alerted or not), so a replay never notifies twice. Seeded with what is
  /// there when a room is first seen in this run.
  final Map<String, int> _groupCursor = {};

  /// Notifications: the room's pending actions already alerted.
  final Map<String, Set<String>> _groupActionsAlerted = {};

  /// Rooms `groups.changed` named since the last look.
  final Set<String> _changedRooms = {};
  bool _peekingGroups = false;

  /// Watchers (re)attach one after another, so many Hobs never mean a burst
  /// of `session.resume` calls.
  _SerialQueue _watchQueue = _SerialQueue();

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

  /// Cookie-authenticated REST client (uploads, image thumbnails).
  HermesHttp? get http => _http;
  ConnectionStatus get connection =>
      _rpc?.status ?? ConnectionStatus.disconnected;

  Future<void> init() async {
    await _loadLanguage();
    await _initNotifications();
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
        _hobsError = () => describeError(e);
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
      _authError = null;
      await _loadLocal();
      _enterSignedIn();
      return true;
    } catch (e) {
      if (e is HermesHttpException && e.isUnauthorized) {
        _password = null;
        await _store.savePassword(null);
        _authError = () => Strings.current.savedPasswordExpired;
      } else {
        _authError = () => describeError(e);
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
      final ids = e.payload['room_ids'];
      if (ids is List) _changedRooms.addAll(ids.map((i) => i.toString()));
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
    _authError = null;
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
    _authError = null;
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
      _hobsError = null;
      if (await _silentLogin()) return;
      phase = AuthPhase.signedOut;
      notifyListeners();
    });
  }

  Future<void> _teardown({required bool clearCookies}) async {
    unawaited(_backgroundTime.end());
    _rosterTimer?.cancel();
    _rosterTimer = null;
    for (final c in _chats.values) {
      c.dispose();
    }
    _chats.clear();
    _watchQueue = _SerialQueue();
    _groupCursor.clear();
    _groupActionsAlerted.clear();
    _changedRooms.clear();
    for (final d in _drafts.values) {
      d.dispose();
    }
    _drafts.clear();
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
      _hobsError = null;
      notifyListeners();
    }
    try {
      final list = await _fetchRoster();
      hobs = list;
      _hobsError = null;
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
      _syncWatchers();
      unawaited(refreshGroups());
    } catch (e) {
      if (e is HermesHttpException && e.isUnauthorized) {
        loadingHobs = false;
        _onSessionExpired();
        return;
      }
      if (!silent || hobs.isEmpty) _hobsError = () => describeError(e);
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
    for (final s in byKey.values) {
      s.hobs.sort(_byActivity);
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

  /// The dashboard's roster order: pinned first, then newest activity.
  static int _byActivity(Hob a, Hob b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final ta = a.lastActive?.millisecondsSinceEpoch ?? 0;
    final tb = b.lastActive?.millisecondsSinceEpoch ?? 0;
    if (ta != tb) return tb.compareTo(ta);
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  /// Hidden hobs that match the search and filter, in roster order. The list
  /// shows them in their own collapsed group at the end, like the dashboard.
  List<Hob> get hiddenHobs =>
      _hiddenHobs.where(_matchesFilter).toList()..sort(_byActivity);

  @visibleForTesting
  set hiddenHobsForTest(List<Hob> list) => _hiddenHobs = list;

  /// Whether the hidden group is open. Not kept: it starts closed.
  bool hiddenExpanded = false;

  void toggleHidden() {
    hiddenExpanded = !hiddenExpanded;
    notifyListeners();
  }

  /// Every folder a hob belongs to (hidden hobs included), in the order the
  /// list shows them. What "Move to folder" offers.
  List<({String id, String name})> get folders {
    final byId = <String, String>{};
    for (final b in [...hobs, ..._hiddenHobs]) {
      final id = b.sectionId;
      if (id == null) continue;
      byId.putIfAbsent(
        id,
        () => b.sectionName ?? Strings.current.folderFallback,
      );
    }
    int rank(String id) {
      final i = sectionOrder.indexOf('section:$id');
      return i < 0 ? sectionOrder.length : i;
    }

    return [for (final e in byId.entries) (id: e.key, name: e.value)]
      ..sort((a, b) {
        final byRank = rank(a.id).compareTo(rank(b.id));
        if (byRank != 0) return byRank;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
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
    if (title.isEmpty || _rpc == null || key == HobSection.unassignedKey) {
      return;
    }
    try {
      for (final b in [...hobs, ..._hiddenHobs]) {
        if ('section:${b.sectionId}' != key || b.sectionName == title) continue;
        await _editMeta(
          b,
          (x) => {...x.meta, 'sectionName': title},
          refused: Strings.current.renameFolderFailed,
        );
      }
    } finally {
      await refreshHobs(silent: true);
    }
  }

  // --- hob menu: pin, hide, move to folder ---------------------------------
  //
  // Same keys the dashboard writes. Turning a flag off writes false and
  // leaving a folder writes null rather than dropping the key: the dashboard
  // merges what it reads over what it already has, so a missing key would
  // not clear it there.

  Future<void> setHobPinned(Hob hob, bool pinned) =>
      _editMetaNow(hob, (b) => {...b.meta, 'pinned': pinned});

  Future<void> setHobHidden(Hob hob, bool hidden) =>
      _editMetaNow(hob, (b) => {...b.meta, 'hidden': hidden});

  /// Moves the hob into folder [sectionId] named [sectionName]; a null id
  /// takes it out of its folder.
  Future<void> moveHobToFolder(
    Hob hob,
    String? sectionId,
    String? sectionName,
  ) => _editMetaNow(
    hob,
    (b) => {
      ...b.meta,
      'sectionId': sectionId,
      'sectionName': sectionId == null ? null : sectionName,
    },
  );

  /// Creates folder [name] with the hob as its first member. A folder exists
  /// only through its members, like on the dashboard.
  Future<void> moveHobToNewFolder(Hob hob, String name) {
    final title = name.trim();
    if (title.isEmpty) return Future.value();
    return moveHobToFolder(hob, newFolderId(), title);
  }

  /// A folder id in the dashboard's format (`sec-<time>-<random>`).
  static String newFolderId() {
    final rnd = Random();
    final tail = List.generate(
      5,
      (_) => rnd.nextInt(36).toRadixString(36),
    ).join();
    return 'sec-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '-$tail';
  }

  /// Shows the edited hob at once, then writes it. Puts the hob back the way
  /// it was and rethrows when the server refuses.
  Future<void> _editMetaNow(
    Hob hob,
    Map<String, dynamic> Function(Hob b) edit,
  ) async {
    final before = hobNamed(hob.name) ?? hob;
    _putHob(before.withMeta(edit(before)));
    try {
      await _editMeta(before, edit, refused: Strings.current.hobChangeFailed);
    } catch (_) {
      _putHob(before);
      rethrow;
    } finally {
      await refreshHobs(silent: true);
    }
  }

  /// Puts [hob] in place of the roster's copy, in the visible or the hidden
  /// list as its flag says.
  void _putHob(Hob hob) {
    hobs = [...hobs.where((b) => b.name != hob.name), if (!hob.hidden) hob];
    _hiddenHobs = [
      ..._hiddenHobs.where((b) => b.name != hob.name),
      if (hob.hidden) hob,
    ];
    notifyListeners();
  }

  /// Rewrites the hob's whole `hermes-bots` block as [edit] makes it from the
  /// current one. When someone else edited the hob meanwhile, rereads it and
  /// retries once. Throws a [StateError] saying [refused] when the server
  /// still refuses.
  Future<void> _editMeta(
    Hob hob,
    Map<String, dynamic> Function(Hob b) edit, {
    required String refused,
  }) async {
    final rpc = _connected;
    if (await _writeMeta(rpc, hob, edit(hob))) return;
    final fresh = (await _fetchAllHobs()).where((x) => x.name == hob.name);
    if (fresh.isEmpty ||
        !await _writeMeta(rpc, fresh.first, edit(fresh.first))) {
      throw StateError(refused);
    }
  }

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

    await _editMeta(hob, edited, refused: Strings.current.hobSaveRefused);
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
  /// A Hob watched for notifications turns into a full chat.
  ChatController chatFor(Hob hob) {
    final existing = _chats[hob.name];
    if (existing != null) {
      if (existing.watchOnly) unawaited(existing.promote());
      return existing;
    }
    final c = _newChat(hob);
    _chats[hob.name] = c;
    unawaited(c.start());
    return c;
  }

  ChatController _newChat(Hob hob, {bool watchOnly = false}) => ChatController(
    rpc: _rpc!,
    hob: hob,
    findCanonical: _findCanonical,
    roster: () => hobs,
    onTurnSettled: (b) {
      if (openHob == b.name) markSeen(b.name);
      unawaited(refreshHobs(silent: true));
      _releaseBackgroundTime();
    },
    onAlert: _onAlert,
    onPromptSent: () => unawaited(_askNotificationPermissionOnce()),
    watchOnly: watchOnly,
    queue: _watchQueue.run,
  );

  /// Watches the Bot Chat of every visible Hob whose chat is not open, so it
  /// can notify: a [ChatController.watchOnly] attach without history, one
  /// after another. Hobs without a Bot Chat have nothing to watch; hidden
  /// Hobs and notifications turned off watch nothing.
  void _syncWatchers() {
    if (_rpc == null || phase != AuthPhase.signedIn || !notificationsEnabled) {
      _stopWatchers();
      return;
    }
    final visible = {for (final b in hobs) b.name};
    for (final name in [..._chats.keys]) {
      final c = _chats[name]!;
      if (c.watchOnly && !visible.contains(name)) {
        _chats.remove(name)!.dispose();
      }
    }
    for (final b in hobs) {
      if (b.canonical == null) continue;
      final c = _chats[b.name] ??= _newChat(b, watchOnly: true);
      if (c.watchOnly && !c.ready) unawaited(_watchQueue.run(c.watch));
    }
  }

  void _stopWatchers() {
    for (final name in [..._chats.keys]) {
      if (_chats[name]!.watchOnly) _chats.remove(name)!.dispose();
    }
  }

  @visibleForTesting
  Set<String> get watchedHobs => {
    for (final e in _chats.entries)
      if (e.value.watchOnly) e.key,
  };

  /// The composer attachments (and shared text) waiting for [hob]'s chat.
  ComposerDraft draftFor(Hob hob) {
    final http = _http;
    final uploader = http == null ? null : AttachmentUploader(http, hob.name);
    return (_drafts[hob.name] ??= ComposerDraft(uploader))..uploader = uploader;
  }

  void setOpenHob(String? name) {
    final prev = openHob;
    openHob = name;
    if (name != null) {
      markSeen(name);
      unawaited(_notifier.clear(NotifyTarget.hob(name).key));
    }
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
      for (final r in rooms) {
        final cursor = _groupCursor[r.roomId];
        if (cursor == null || r.latestSeq < cursor) {
          // First sight (or a log that started over): nothing to tell.
          _groupCursor[r.roomId] = r.latestSeq;
        }
      }
      unawaited(_peekGroups());
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
      onLoaded: (chat) {
        _onGroupActivity(chat.room, chat.log, chat.driver);
        if (!chat.busy) _releaseBackgroundTime();
      },
      onSent: () => unawaited(_askNotificationPermissionOnce()),
    );
    _groupChats[room.roomId] = c;
    unawaited(c.start());
    return c;
  }

  void setOpenGroup(String? roomId) {
    final prev = openGroup;
    openGroup = roomId;
    if (roomId != null) {
      markGroupSeen(roomId);
      unawaited(_notifier.clear(NotifyTarget.group(roomId).key));
    }
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
    _groupCursor[room.roomId] = room.latestSeq;
    unawaited(_saveGroupSeen());
    notifyListeners();
    return room;
  }

  /// Drops a disbanded room from the list.
  void forgetGroup(String roomId) {
    groups = groups.where((r) => r.roomId != roomId).toList();
    _groupChats.remove(roomId)?.dispose();
    _groupSeen.remove(roomId);
    _groupCursor.remove(roomId);
    _groupActionsAlerted.remove(roomId);
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
    setAppActive(true);
    unawaited(_backgroundTime.end());
    unawaited(_refreshNotificationPermission());
    if (biometricLock &&
        phase == AuthPhase.signedIn &&
        hiddenAt != null &&
        DateTime.now().difference(hiddenAt) >= relockAfter) {
      locked = true;
      notifyListeners();
    }
    unawaited(_refreshBiometricKind());
    reconnect();
  }

  /// Reconnects the socket now (skipping its backoff) and refreshes the
  /// lists: after the app returns to the screen or the network comes back.
  void reconnect() {
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
    setAppActive(false);
    // A reply still streaming (in a chat, a watched Hob or a group) gets
    // iOS's short grace period to finish and notify; there is no keep-alive
    // beyond that.
    if (_anyBusy) unawaited(_backgroundTime.begin());
  }

  bool get _anyBusy =>
      _chats.values.any((c) => c.busy) || _groupChats.values.any((c) => c.busy);

  /// Whether the app is on screen and focused (macOS: the window is key).
  void setAppActive(bool value) {
    if (_authenticating && !value) return;
    if (appActive == value) return;
    appActive = value;
    if (value && openHob != null) {
      unawaited(_notifier.clear(NotifyTarget.hob(openHob!).key));
    }
    if (value && openGroup != null) {
      unawaited(_notifier.clear(NotifyTarget.group(openGroup!).key));
    }
  }

  void _releaseBackgroundTime() {
    if (_anyBusy) return;
    unawaited(_backgroundTime.end());
  }

  // --- notifications -------------------------------------------------------

  Future<void> _initNotifications() async {
    try {
      final p = await SharedPreferences.getInstance();
      notificationsEnabled = p.getBool(_notificationsKey) ?? true;
      _permissionAsked = p.getBool(_notificationsAskedKey) ?? false;
    } catch (_) {}
    _tapSub ??= _notifier.taps.listen(openChatFromNotification);
    final launchedFor = await _notifier.init();
    if (launchedFor != null) _setPending(launchedFor);
    if (_permissionAsked) await _refreshNotificationPermission();
  }

  /// Whether a notification for [hob] would tell the user anything new: not
  /// when they are looking at that chat right now.
  bool _chatVisible(String hob) => appActive && !locked && openHob == hob;

  void _onAlert(Hob hob, HobAlert alert) {
    if (!notificationsEnabled || _chatVisible(hob.name)) return;
    final s = Strings.current;
    final preview = notificationPreview(alert.text);
    final body = switch (alert.kind) {
      AlertKind.reply => preview.isEmpty ? s.notifyReplyDone : preview,
      AlertKind.approval => s.notifyApproval(preview),
      AlertKind.clarify => s.notifyClarify(preview),
    };
    unawaited(
      _notifier.show(
        key: NotifyTarget.hob(hob.name).key,
        title: hob.displayName,
        body: body,
        blocking: alert.blocking,
      ),
    );
    if (alert.kind == AlertKind.reply) _releaseBackgroundTime();
  }

  bool _groupVisible(String roomId) =>
      appActive && !locked && openGroup == roomId;

  /// Looks at rooms the app has no live chat for, when their log grew past
  /// what was already looked at or `groups.changed` named them:
  /// `groups.state` (pending actions) and `groups.log` from the cursor.
  /// One room after another; rooms with a live chat report themselves.
  Future<void> _peekGroups() async {
    final rpc = _rpc;
    if (rpc == null || _peekingGroups) return;
    if (!notificationsEnabled) {
      for (final r in groups) {
        _groupCursor[r.roomId] = r.latestSeq;
      }
      _changedRooms.clear();
      return;
    }
    _peekingGroups = true;
    try {
      while (true) {
        final due = groups.where(
          (r) =>
              !_groupChats.containsKey(r.roomId) &&
              (_changedRooms.contains(r.roomId) ||
                  r.latestSeq > (_groupCursor[r.roomId] ?? r.latestSeq)),
        );
        if (due.isEmpty) break;
        final room = due.first;
        _changedRooms.remove(room.roomId);
        try {
          await _peekGroup(rpc, room);
        } catch (_) {
          // Best effort: the next roster refresh looks again.
          _groupCursor[room.roomId] = room.latestSeq;
        }
        if (!identical(rpc, _rpc) || _disposed) return;
      }
    } finally {
      _peekingGroups = false;
    }
  }

  Future<void> _peekGroup(HermesRpc rpc, GroupRoom room) async {
    final params = {'profile': groupProfile, 'room_id': room.roomId};
    final state = await rpc.request('groups.state', params);
    if (state is! Map) return;
    final current = GroupRoom.fromJson(state['room']) ?? room;
    final driver = GroupDriver.fromJson(state['driver_status']);
    final cursor = _groupCursor[room.roomId] ?? current.latestSeq;
    var events = const <GroupEvent>[];
    if (current.latestSeq > cursor) {
      // Only the newest few matter for one notification.
      final since = max(cursor, current.latestSeq - 50);
      final res = await rpc.request('groups.log', {
        ...params,
        'since_seq': since,
        'limit': 50,
      });
      if (res is Map) {
        events = (res['events'] as List? ?? const [])
            .map(GroupEvent.fromJson)
            .nonNulls
            .toList();
      }
    }
    _onGroupActivity(current, events, driver);
    // The log is in; the cursor never stays behind the room.
    if ((_groupCursor[room.roomId] ?? 0) < current.latestSeq) {
      _groupCursor[room.roomId] = current.latestSeq;
    }
  }

  /// Notifies about a room's new member messages ([events] after the
  /// cursor) and its new pending actions, unless the room is on screen.
  /// Everything passed in counts as looked at, shown or not.
  void _onGroupActivity(
    GroupRoom room,
    Iterable<GroupEvent> events,
    GroupDriver? driver,
  ) {
    final id = room.roomId;
    var newest = 0;
    for (final e in events) {
      if (e.seq > newest) newest = e.seq;
    }
    final cursor = _groupCursor[id];
    final fresh = cursor == null
        ? const <GroupEvent>[]
        : [
            for (final e in events)
              if (e.seq > cursor &&
                  e.isMemberMessage &&
                  e.text.trim().isNotEmpty)
                e,
          ];
    if (cursor == null || newest > cursor) {
      _groupCursor[id] = max(newest, cursor == null ? room.latestSeq : 0);
    }
    final actions = [
      for (final a in driver?.actions ?? const <GroupAction>[])
        if (a.kind == 'approval' || a.kind == 'retry') a,
    ];
    String actionKey(GroupAction a) =>
        '${a.kind}:${a.memberId}:${a.taskId}:${a.generation}:${a.requestId}';
    // A room looked at before in this run has no actions alerted yet.
    final known =
        _groupActionsAlerted[id] ?? (cursor == null ? null : <String>{});
    final keys = {for (final a in actions) actionKey(a)};
    final newActions = known == null
        ? const <GroupAction>[]
        : [
            for (final a in actions)
              if (!known.contains(actionKey(a))) a,
          ];
    // Only what is still pending stays known: an answered action is gone.
    _groupActionsAlerted[id] = keys;
    if (cursor == null && known == null) return; // first sight: seed only
    if (fresh.isEmpty && newActions.isEmpty) return;
    if (!notificationsEnabled || _groupVisible(id)) return;
    final s = Strings.current;
    String who(String memberId) {
      for (final m in room.members) {
        if (m.memberId == memberId) return memberName(m);
      }
      return memberId;
    }

    final String body;
    if (newActions.isNotEmpty) {
      final a = newActions.last;
      final what = notificationPreview(
        a.command.isNotEmpty ? a.command : a.description,
      );
      body =
          '${who(a.memberId)}: '
          '${a.kind == 'approval' ? s.notifyApproval(what) : s.notifyGroupFailed}';
    } else {
      final e = fresh.last;
      body =
          '${who(e.memberId.isNotEmpty ? e.memberId : e.actorId)}: '
          '${notificationPreview(e.text)}';
    }
    unawaited(
      _notifier.show(
        key: NotifyTarget.group(id).key,
        title: room.name.isNotEmpty
            ? room.name
            : room.members.map(memberName).join(', '),
        body: body,
        blocking: newActions.isNotEmpty,
      ),
    );
  }

  /// The first prompt the user sends is when a notification starts to make
  /// sense ("tell me when it's done"), so that is when the system asks.
  Future<void> _askNotificationPermissionOnce() async {
    if (_permissionAsked || !notificationsEnabled) return;
    _permissionAsked = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_notificationsAskedKey, true);
    } catch (_) {}
    final granted = await _notifier.requestPermission();
    if (notificationsBlocked != !granted) {
      notificationsBlocked = !granted;
      notifyListeners();
    }
  }

  Future<void> _refreshNotificationPermission() async {
    if (!_permissionAsked) return;
    final ok = await _notifier.permitted();
    if (ok == null || notificationsBlocked == !ok) return;
    notificationsBlocked = !ok;
    notifyListeners();
  }

  /// Settings switch. Turning it on asks the system for permission; the
  /// switch stays on even when the system refuses, and [notificationsBlocked]
  /// tells the user where to fix it.
  Future<void> setNotificationsEnabled(bool value) async {
    notificationsEnabled = value;
    notifyListeners();
    if (value) {
      // What happened while they were off is not news.
      for (final r in groups) {
        _groupCursor[r.roomId] = _latestSeq(r);
      }
    }
    _syncWatchers();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_notificationsKey, value);
      if (value) await p.setBool(_notificationsAskedKey, true);
    } catch (_) {}
    if (!value) return;
    _permissionAsked = true;
    final granted = await _notifier.requestPermission();
    notificationsBlocked = !granted;
    notifyListeners();
  }

  /// The user tapped a notification ([NotifyTarget.key]): open that Hob's
  /// or group's chat as soon as the app is unlocked.
  void openChatFromNotification(String payload) {
    _setPending(payload);
    notifyListeners();
  }

  void _setPending(String payload) {
    final target = NotifyTarget.parse(payload);
    if (target == null) return;
    pendingChat = target.isGroup ? null : target.id;
    pendingGroup = target.isGroup ? target.id : null;
  }

  /// The hob to open for a tapped notification, once it can be shown: the
  /// app is signed in and unlocked and the roster knows the hob. Consumes it.
  Hob? takePendingChat() {
    final name = pendingChat;
    if (name == null || phase != AuthPhase.signedIn || locked) return null;
    final hob = _chats[name]?.hob ?? hobNamed(name);
    if (hob == null) {
      // Not in the roster (yet): wait for it, unless it is gone for good.
      if (hobs.isNotEmpty && !loadingHobs) pendingChat = null;
      return null;
    }
    pendingChat = null;
    return hob;
  }

  /// The group to open for a tapped notification, once it can be shown:
  /// signed in, unlocked and the room is listed. Consumes it.
  GroupRoom? takePendingGroup() {
    final id = pendingGroup;
    if (id == null || phase != AuthPhase.signedIn || locked) return null;
    final room = groupById(id);
    if (room == null) {
      // Rooms not loaded yet: wait; otherwise it is gone (or unsupported).
      if (groupsSupported == false ||
          (groupsSupported == true && !_loadingGroups)) {
        pendingGroup = null;
      }
      return null;
    }
    pendingGroup = null;
    return room;
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

  /// Async work (a roster refresh, a reconnect) may finish after sign-out
  /// tore the state down; its last repaint is then a no-op.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tapSub?.cancel();
    _teardown(clearCookies: false);
    super.dispose();
  }
}

/// Runs jobs one after another, with a short pause between them.
class _SerialQueue {
  Future<void> _tail = Future.value();

  static const _gap = Duration(milliseconds: 50);

  Future<void> run(Future<void> Function() job) {
    final next = _tail.then((_) async {
      try {
        await job();
      } catch (_) {
        // A failed job must not stop the ones after it.
      }
      await Future<void>.delayed(_gap);
    });
    _tail = next;
    return next;
  }
}
