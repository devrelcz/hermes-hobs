import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import 'group_chat_screen.dart' show GroupAvatars;
import 'hob_avatar.dart';
import 'sheets.dart';

const _seenKey = 'welcomeSeen';

/// Once, after the first sign-in on this device: what a Hob is, in three
/// lines, and one button to start. Never again after that.
Future<void> maybeShowWelcome(BuildContext context, List<Hob> hobs) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_seenKey) ?? false) return;
  await prefs.setBool(_seenKey, true);
  if (!context.mounted) return;
  await showContentSheet<void>(
    context,
    kind: SheetKind.bottom,
    builder: (_) => _Welcome(hobs: hobs),
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.hobs});

  final List<Hob> hobs;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final faces = hobs.where((b) => !b.hidden).take(3).toList();
    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(text, style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        isWideWindow(context) ? 28 : sheetHandleGap + 4,
        24,
        20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: faces.isEmpty
                ? HobAvatar(
                    hob: Hob(
                      name: 'hob',
                      displayName: 'Hob',
                      shape: HobAvatar.blobShape('hello', null),
                    ),
                    size: 64,
                  )
                : GroupAvatars(hobs: faces, size: 64),
          ),
          const SizedBox(height: 20),
          Text(
            s.welcomeTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 24),
          line(Icons.person_outline, s.welcomeWhat),
          line(Icons.chat_bubble_outline, s.welcomeTalk),
          line(Icons.shield_outlined, s.welcomeSafe),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () => Navigator.pop(context),
            child: Text(s.welcomeStart),
          ),
        ],
      ),
    );
  }
}
