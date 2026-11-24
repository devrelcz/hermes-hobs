/// Ready-made teams of Hobs from the HobCrew catalog
/// (hobcrew.com/api/marketplace/v1/), with the marketplace repository
/// (github.com/devrelcz/hobs-marketplace) on jsDelivr as a fallback.
///
/// `index.json` lists one card per team; a team's `team.json` and its SOUL
/// files are fetched only when the team is opened. Parsing is lenient: an
/// entry the app cannot use is left out instead of failing the whole list.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The catalog format this app reads. Teams with another `schema` are
/// skipped: they need a newer app.
const teamSchemaVersion = 1;

/// Text per language code, as the catalog writes it: `{"en": …, "cs": …}`.
class LocalText {
  const LocalText(this.byLang);

  final Map<String, String> byLang;

  static const empty = LocalText({});

  bool get isEmpty => byLang.values.every((v) => v.trim().isEmpty);

  /// The text in [lang], else English, else any. Empty when there is none.
  String pick(String lang) =>
      (byLang[lang] ?? byLang['en'] ?? byLang.values.firstOrNull ?? '').trim();

  static LocalText fromJson(Object? j) {
    if (j is String) return LocalText({'en': j});
    if (j is! Map) return empty;
    return LocalText({
      for (final e in j.entries)
        if (e.value is String && (e.value as String).trim().isNotEmpty)
          e.key.toString(): e.value as String,
    });
  }
}

/// One team as `index.json` lists it.
class TeamCard {
  const TeamCard({
    required this.id,
    required this.version,
    required this.path,
    required this.name,
    this.summary = LocalText.empty,
    this.cover,
    this.members = 0,
    this.faces = const [],
    this.tags = const [],
  });

  final String id;
  final String version;

  /// `team.json`, relative to the catalog root.
  final String path;

  /// The team's picture (16:9 WebP), relative to the catalog root; null
  /// when the catalog gives none.
  final String? cover;
  final LocalText name;
  final LocalText summary;
  final int members;

  /// The members' faces in team order; empty when the catalog lists none.
  final List<TeamFace> faces;
  final List<String> tags;

  static TeamCard? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id']?.toString() ?? '';
    final path = j['path']?.toString() ?? '';
    final name = LocalText.fromJson(j['name']);
    if (id.isEmpty || !_safePath(path) || name.isEmpty) return null;
    final cover = j['cover']?.toString() ?? '';
    return TeamCard(
      id: id,
      version: j['version']?.toString() ?? '',
      path: path,
      name: name,
      summary: LocalText.fromJson(j['summary']),
      cover: _safePath(cover) ? cover : null,
      members: (j['members'] as num?)?.toInt() ?? 0,
      faces: [
        for (final f in (j['faces'] as List? ?? const []))
          if (f is Map) TeamFace.fromJson(f),
      ],
      tags: [
        for (final t in (j['tags'] as List? ?? const []))
          if (t is String) t,
      ],
    );
  }
}

/// A relative path inside the catalog: no scheme, no `..`, no leading `/`.
bool _safePath(String path) =>
    path.isNotEmpty &&
    !path.startsWith('/') &&
    !path.contains('..') &&
    !path.contains('://') &&
    RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(path);

/// A Hob's face: a shape (or blobatar) and an optional color.
class TeamFace {
  const TeamFace({this.shape, this.color});

  final String? shape;
  final String? color;

  static TeamFace fromJson(Object? j) {
    if (j is! Map) return const TeamFace();
    String? str(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    return TeamFace(shape: str(j['shape']), color: str(j['color']));
  }
}

/// A scheduled job a member comes with.
class TeamJobSpec {
  const TeamJobSpec({
    required this.name,
    required this.schedule,
    required this.prompt,
    this.toChat = true,
    this.continuity = false,
    this.repeat,
  });

  final LocalText name;
  final String schedule;
  final LocalText prompt;
  final bool toChat;
  final bool continuity;
  final int? repeat;

  static TeamJobSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = LocalText.fromJson(j['name']);
    final schedule = j['schedule']?.toString().trim() ?? '';
    final prompt = LocalText.fromJson(j['prompt']);
    if (name.isEmpty || schedule.isEmpty || prompt.isEmpty) return null;
    final repeat = (j['repeat'] as num?)?.toInt();
    return TeamJobSpec(
      name: name,
      schedule: schedule,
      prompt: prompt,
      toChat: j['to_chat'] != false,
      continuity: j['continuity'] == true,
      repeat: repeat != null && repeat > 0 ? repeat : null,
    );
  }
}

/// One seat of a team.
class TeamMemberSpec {
  const TeamMemberSpec({
    required this.key,
    required this.handle,
    required this.title,
    this.description = LocalText.empty,
    this.face = const TeamFace(),
    this.soulPaths = const {},
    this.soul = '',
    this.preferModels = const [],
    this.jobs = const [],
  });

  /// Stable id inside the team; SOULs and prompts say `{{@key}}`.
  final String key;

  /// The profile name the member would like.
  final String handle;
  final LocalText title;
  final LocalText description;
  final TeamFace face;

  /// SOUL.md per language, relative to the team's `team.json`.
  final Map<String, String> soulPaths;

  /// The SOUL.md text once [TeamCatalogClient.fetchTeam] loaded it.
  final String soul;

  /// `provider/model` ids, best first. The first one the server offers wins.
  final List<String> preferModels;
  final List<TeamJobSpec> jobs;

  TeamMemberSpec withSoul(String soul) => TeamMemberSpec(
    key: key,
    handle: handle,
    title: title,
    description: description,
    face: face,
    soulPaths: soulPaths,
    soul: soul,
    preferModels: preferModels,
    jobs: jobs,
  );

  /// The SOUL path for [lang], else English, else any.
  String? soulPathFor(String lang) =>
      soulPaths[lang] ?? soulPaths['en'] ?? soulPaths.values.firstOrNull;

  static final _handle = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

  static TeamMemberSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final key = j['key']?.toString() ?? '';
    final handle = j['handle']?.toString() ?? '';
    final title = LocalText.fromJson(j['title']);
    if (key.isEmpty ||
        !_handle.hasMatch(handle) ||
        handle == 'default' ||
        title.isEmpty) {
      return null;
    }
    final soul = j['soul'];
    final model = j['model'];
    return TeamMemberSpec(
      key: key,
      handle: handle,
      title: title,
      description: LocalText.fromJson(j['description']),
      face: TeamFace.fromJson(j['face']),
      soulPaths: {
        if (soul is Map)
          for (final e in soul.entries)
            if (e.value is String && _safePath(e.value as String))
              e.key.toString(): e.value as String,
      },
      preferModels: [
        if (model is Map)
          for (final m in (model['prefer'] as List? ?? const []))
            if (m is String && m.contains('/')) m,
      ],
      jobs: (j['jobs'] as List? ?? const [])
          .map(TeamJobSpec.fromJson)
          .nonNulls
          .toList(),
    );
  }
}

/// A whole team as its `team.json` describes it.
class TeamSpec {
  const TeamSpec({
    required this.id,
    required this.version,
    required this.name,
    required this.members,
    this.summary = LocalText.empty,
    this.description = LocalText.empty,
    this.folder = LocalText.empty,
    this.createGroup = true,
    this.groupName = LocalText.empty,
  });

  final String id;
  final String version;
  final LocalText name;
  final LocalText summary;
  final LocalText description;

  /// The folder the members go into; the team name when empty.
  final LocalText folder;
  final bool createGroup;

  /// The group chat's name; the team name when empty.
  final LocalText groupName;
  final List<TeamMemberSpec> members;

  /// A group chat seats two to six.
  static const minMembers = 2;
  static const maxMembers = 6;

  TeamSpec withMembers(List<TeamMemberSpec> members) => TeamSpec(
    id: id,
    version: version,
    name: name,
    summary: summary,
    description: description,
    folder: folder,
    createGroup: createGroup,
    groupName: groupName,
    members: members,
  );

  /// Null when the file is not a team this app can import: another schema,
  /// no name, too few or too many members, or two members sharing a key or
  /// a handle.
  static TeamSpec? fromJson(Object? j) {
    if (j is! Map || j['schema'] != teamSchemaVersion) return null;
    final id = j['id']?.toString() ?? '';
    final name = LocalText.fromJson(j['name']);
    if (id.isEmpty || name.isEmpty) return null;
    final members = (j['members'] as List? ?? const [])
        .map(TeamMemberSpec.fromJson)
        .nonNulls
        .toList();
    if (members.length < minMembers || members.length > maxMembers) {
      return null;
    }
    if (members.map((m) => m.key).toSet().length != members.length ||
        members.map((m) => m.handle).toSet().length != members.length) {
      return null;
    }
    final group = j['group'];
    return TeamSpec(
      id: id,
      version: j['version']?.toString() ?? '',
      name: name,
      summary: LocalText.fromJson(j['summary']),
      description: LocalText.fromJson(j['description']),
      folder: LocalText.fromJson(j['folder']),
      createGroup: group is! Map || group['create'] != false,
      groupName: group is Map
          ? LocalText.fromJson(group['name'])
          : LocalText.empty,
      members: members,
    );
  }
}

/// Fetches a catalog's text files. Swapped out in tests.
typedef CatalogFetch = Future<String> Function(Uri uri);

class TeamCatalogException implements Exception {
  const TeamCatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads the marketplace: the index, then a team with its SOULs.
class TeamCatalogClient {
  /// Without [root], the official catalog is read, and its jsDelivr mirror
  /// when the official one cannot be reached. A [root] given here is read
  /// alone unless a [fallback] is given too.
  TeamCatalogClient({Uri? root, Uri? fallback, CatalogFetch? fetch})
    : _primary = root ?? defaultRoot,
      _fallback = root == null ? (fallback ?? fallbackRoot) : fallback,
      _fetch = fetch ?? _httpGet {
    _root = _primary;
  }

  /// The official catalog, served by the HobCrew API. Its layout is the
  /// marketplace repository's, and its format version is in the path.
  static final defaultRoot = Uri.parse(
    'https://hobcrew.com/api/marketplace/v1/',
  );

  /// The marketplace repository through jsDelivr, pinned to its major
  /// version tag. Read when [defaultRoot] cannot be reached.
  static final fallbackRoot = Uri.parse(
    'https://cdn.jsdelivr.net/gh/devrelcz/hobs-marketplace@v1/',
  );

  final Uri _primary;
  final Uri? _fallback;
  late Uri _root;
  final CatalogFetch _fetch;

  /// The catalog the last [fetchIndex] read; teams and covers come from it.
  Uri get root => _root;

  /// A SOUL.md larger than this is refused; the repository's limit is 16 KB.
  static const maxSoulBytes = 64 * 1024;

  /// Where [card]'s picture is, or null when it has none.
  Uri? coverOf(TeamCard card) {
    final cover = card.cover;
    return cover == null ? null : root.resolve(cover);
  }

  /// The teams the catalog lists, in its order. Tries the main catalog
  /// first every time, and the fallback when the main one fails.
  Future<List<TeamCard>> fetchIndex() async {
    try {
      return await _fetchIndex(_primary);
    } on Object {
      final fallback = _fallback;
      if (fallback == null) rethrow;
      return _fetchIndex(fallback);
    }
  }

  Future<List<TeamCard>> _fetchIndex(Uri from) async {
    final json = await _json(from.resolve('index.json'));
    if (json is! Map || json['schema'] != teamSchemaVersion) {
      throw const TeamCatalogException('Unsupported catalog');
    }
    final cards = (json['teams'] as List? ?? const [])
        .map(TeamCard.fromJson)
        .nonNulls
        .toList();
    _root = from;
    return cards;
  }

  /// The team [card] points at, with the SOUL of every member in [lang]
  /// (English when the team has none in it).
  Future<TeamSpec> fetchTeam(TeamCard card, String lang) async {
    final teamUri = root.resolve(card.path);
    final team = TeamSpec.fromJson(await _json(teamUri));
    if (team == null) {
      throw const TeamCatalogException('Unsupported team');
    }
    final members = await Future.wait(
      team.members.map((m) async {
        final path = m.soulPathFor(lang);
        if (path == null) return m;
        final soul = await _fetch(teamUri.resolve(path));
        if (utf8.encode(soul).length > maxSoulBytes) {
          throw const TeamCatalogException('SOUL.md too large');
        }
        return m.withSoul(soul);
      }),
    );
    return team.withMembers(members);
  }

  Future<Object?> _json(Uri uri) async {
    final body = await _fetch(uri);
    try {
      return jsonDecode(body);
    } on FormatException {
      throw TeamCatalogException('Not JSON: $uri');
    }
  }

  static Future<String> _httpGet(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 30));
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw TeamCatalogException('HTTP ${res.statusCode}: $uri');
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }
}
