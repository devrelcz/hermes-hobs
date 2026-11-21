import '../l10n/strings.dart';

/// Compact relative age like the dashboard roster: "teď", "56m", "2h", "3d".
String relativeAge(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return Strings.current.now;
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 30) return '${d.inDays}d';
  return Strings.current.shortDate(t);
}

String clockTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "dnes 9:00", "zítra 9:00", or "23. 11. 9:00".
String dayTime(DateTime t, {DateTime? now}) {
  final s = Strings.current;
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  final prefix = switch (diff) {
    0 => s.today,
    1 => s.tomorrow,
    -1 => s.yesterday,
    _ => s.shortDate(t),
  };
  return '$prefix ${clockTime(t)}';
}

/// One line of plain text from a markdown reply, for previews: code
/// blocks, link and image targets, list and quote marks and emphasis go,
/// whitespace collapses. "V [archivu](https://…)" reads "V archivu".
String plainPreview(String s) => s
    .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
    .replaceAllMapped(
      // The server cuts long previews, so the link may end unclosed.
      RegExp(r'!?\[([^\]]*)\]\([^)\s]*\)?'),
      (m) => m.group(1) ?? '',
    )
    .replaceAll(RegExp(r'^\s*(?:[-*+•]|\d+[.)])\s+', multiLine: true), '')
    .replaceAll(RegExp(r'[*_`#>~]+'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
