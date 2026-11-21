import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'placeholders.dart';
import 'theme.dart';

/// What a waiting card asks for: a permission (lantern), a question
/// (moss) or a failure to deal with (error).
enum PromptTone { approval, question, problem }

/// A card above the composer that holds the chat until the user answers:
/// a Hob wants to run a command, asks something, or got stuck. It stands
/// apart from the messages: its own surface, a badge with the reason, and
/// the answers as real buttons.
class PromptCard extends StatelessWidget {
  const PromptCard({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    this.subtitle,
    this.body,
    this.command,
    required this.actions,
    this.secondary = const [],
  });

  final PromptTone tone;
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Free content between the header and the buttons (a description, a
  /// question with its choices).
  final Widget? body;

  /// The exact command, shown as code the user can select and copy.
  final String? command;

  /// The main answers, side by side; the last one is the suggested one.
  final List<Widget> actions;

  /// Quieter answers under the main ones ("allow for this chat").
  final List<Widget> secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (badgeBg, badgeFg) = switch (tone) {
      PromptTone.approval => (cs.tertiaryContainer, cs.onTertiaryContainer),
      PromptTone.question => (cs.primaryContainer, cs.onPrimaryContainer),
      PromptTone.problem => (cs.errorContainer, cs.onErrorContainer),
    };
    final cmd = command;
    return AppearIn(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: badgeBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 20, color: badgeFg),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (body != null) ...[const SizedBox(height: 12), body!],
                  if (cmd != null && cmd.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SelectableText(
                              cmd,
                              maxLines: 8,
                              minLines: 1,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: HobsTheme.monoFamily,
                                height: 1.45,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: MaterialLocalizations.of(context)
                                .copyButtonLabel,
                            visualDensity: VisualDensity.compact,
                            iconSize: 16,
                            color: cs.onSurfaceVariant,
                            onPressed: () =>
                                Clipboard.setData(ClipboardData(text: cmd)),
                            icon: const Icon(Icons.copy_outlined),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  ),
                  if (secondary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 4,
                      children: secondary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-height button for a [PromptCard]'s main row.
ButtonStyle promptButtonStyle() =>
    const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(0, 46)));
