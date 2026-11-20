import '../api/models.dart';

/// @-mentions of other Hobs, the way the dashboard's Bot Mode does them.
///
/// Typing `@` in a chat offers the other Hobs of the roster. On send, every
/// tag that resolves to a Hob adds an identification note to the prompt, so
/// the agent knows who "@research-buddy" is and can contact it with its
/// `message_agent` tool. Nothing is delivered by the app itself.
///
/// The rules mirror the dashboard (`plugins/hermes-bots/data.ts` and the
/// mention middleware in `plugin.tsx`), limited to one connection.
class Mentions {
  Mentions._();

  /// Tokens no friendly name may turn into: they are reserved aliases.
  static const _reserved = {'all', 'everyone', 'user', 'default', 'hermes'};

  static final _validForm = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

  /// Start of the note the dashboard appends; history rows are cut here.
  static const notePrefix =
      '[@mentions resolved from the Bot Mode roster — the user is referring to: ';

  static bool _isDefault(Hob hob) => hob.name.trim().toLowerCase() == 'default';

  /// True when a real `hermes` profile holds @hermes, so the default profile
  /// answers to its own name instead.
  static bool _hermesTaken(List<Hob> roster) =>
      roster.any((h) => h.name.trim() == 'hermes');

  /// The profile handle: the name, with the default profile as `hermes`.
  static String handle(Hob hob, List<Hob> roster) =>
      _isDefault(hob) && !_hermesTaken(roster) ? 'hermes' : hob.name;

  /// Taggable forms of free text: slugified ("Research Buddy" ->
  /// research-buddy) and collapsed (researchbuddy).
  static List<String> nameForms(String? value) {
    final name = (value ?? '').trim().toLowerCase();
    if (name.isEmpty) return const [];
    final slug = name
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final collapsed = name.replaceAll(RegExp(r'[^a-z0-9_-]+'), '');
    return {
      slug,
      collapsed,
    }.where((f) => _validForm.hasMatch(f) && !_reserved.contains(f)).toList();
  }

  static List<String> _friendlyNames(Hob hob) => [
    hob.customTitle,
    hob.roleTitle,
    hob.profileDisplayName,
  ];

  /// What picking a Hob inserts (without the `@`): the slug of its friendly
  /// name when it has one, the profile handle otherwise.
  static String tag(Hob hob, List<Hob> roster) {
    for (final friendly in _friendlyNames(hob)) {
      final forms = nameForms(friendly);
      if (forms.isNotEmpty) return forms.first;
    }
    return handle(hob, roster);
  }

  /// The `@word` being typed right before [cursor], or null. [start] is the
  /// index of its `@`.
  static ({int start, String query})? activeQuery(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) return null;
    final before = text.substring(0, cursor);
    final m = RegExp(r'(^|\s)@([^\s@]*)$').firstMatch(before);
    if (m == null) return null;
    final query = m.group(2)!;
    return (start: cursor - query.length - 1, query: query);
  }

  /// Hobs offered for [query]: everyone but [active], matched by prefix on
  /// tag, handle or name. At most [limit] rows, like the dashboard.
  static List<Hob> candidates(
    String query,
    List<Hob> roster,
    String active, {
    int limit = 8,
  }) {
    final q = query.toLowerCase();
    final out = <Hob>[];
    for (final hob in roster) {
      if (hob.name == active) continue;
      if (q.isNotEmpty &&
          !tag(hob, roster).toLowerCase().startsWith(q) &&
          !handle(hob, roster).toLowerCase().startsWith(q) &&
          !hob.displayName.toLowerCase().startsWith(q)) {
        continue;
      }
      out.add(hob);
      if (out.length == limit) break;
    }
    return out;
  }

  /// The Hobs [text] tags, in order of first mention. Code spans and blocks
  /// are skipped, and so is [active]: a Hob does not tag itself. A form two
  /// Hobs share resolves to neither.
  static List<Hob> resolve(String text, List<Hob> roster, String active) {
    final prose = text
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'`[^`\n]*`'), ' ');
    final byForm = <String, Hob?>{};
    final others = roster.where((h) => h.name.isNotEmpty && h.name != active);
    for (final hob in others) {
      final forms = <String>{
        handle(hob, roster).toLowerCase(),
        hob.name.toLowerCase(),
        for (final f in _friendlyNames(hob)) ...nameForms(f),
      };
      for (final form in forms) {
        if (form.isEmpty) continue;
        if (byForm.containsKey(form) && byForm[form] != hob) {
          byForm[form] = null;
        } else {
          byForm[form] = hob;
        }
      }
    }
    // Old names fill gaps only: a live name always wins.
    for (final hob in others) {
      for (final old in hob.previousNames) {
        for (final form in nameForms(old)) {
          byForm.putIfAbsent(form, () => hob);
        }
      }
    }
    final out = <Hob>[];
    final pattern = RegExp(
      r'(^|\s)@([a-z0-9][a-z0-9_-]*)(?:@[a-z0-9][a-z0-9_-]*)?',
      caseSensitive: false,
    );
    for (final m in pattern.allMatches(prose)) {
      final hob = byForm[m.group(2)!.toLowerCase()];
      if (hob != null && !out.contains(hob)) out.add(hob);
    }
    return out;
  }

  /// The identification note appended to a prompt that tags [mentioned].
  static String note(List<Hob> mentioned, List<Hob> roster) {
    final lines = mentioned.map((hob) {
      final title = hob.customTitle.isNotEmpty
          ? hob.customTitle
          : hob.roleTitle;
      return '@${handle(hob, roster)} = agent profile "${hob.name}"'
          '${title.isNotEmpty ? ' ("$title")' : ''}';
    });
    return '\n\n$notePrefix${lines.join('; ')}. If they want one of these '
        'agents contacted, compose your own message and send it with your '
        'message_agent tool (agents on other connected machines are reachable '
        'too — the Desktop relays it); never forward the user’s text '
        'verbatim. If this session has no message_agent tool, agent messaging '
        'is unavailable here — say so.]';
  }

  /// [text] with the note for its mentions, or unchanged when it tags no Hob.
  static String annotate(String text, List<Hob> roster, String active) {
    if (!RegExp(
      r'(^|\s)@[a-z0-9][a-z0-9_-]*',
      caseSensitive: false,
    ).hasMatch(text)) {
      return text;
    }
    final mentioned = resolve(text, roster, active);
    return mentioned.isEmpty ? text : text + note(mentioned, roster);
  }

  /// A user row from history without the note, as the user typed it.
  static String stripNote(String text) {
    final i = text.lastIndexOf(notePrefix);
    if (i < 0) return text;
    return text.substring(0, i).trimRight();
  }
}
