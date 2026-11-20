import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/chat_controller.dart';

/// Asks before switching to a model the server marks as expensive
/// (`confirm_required`). Shared by the hob profile and the chat composer.
Future<bool> confirmExpensiveModel(
  BuildContext context,
  String question,
) async {
  final s = Strings.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(s.confirmModelTitle),
      content: Text(question.isEmpty ? s.confirmModelFallback : question),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(s.switchModel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Lets the user pick the model of this chat's session only (the composer's
/// model chip). The hob's profile keeps its default.
Future<void> pickSessionModel(BuildContext context, ChatController chat) async {
  final messenger = ScaffoldMessenger.of(context);
  final s = Strings.of(context);
  // Fresh list and current value every time the sheet opens.
  chat.loadModels();
  final choice = await showModalBottomSheet<ModelChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SessionModelSheet(chat: chat),
  );
  if (choice == null || choice.same(chat.sessionModel)) return;
  var result = await chat.setSessionModel(choice);
  final question = result.question;
  if (question != null) {
    if (!context.mounted || !await confirmExpensiveModel(context, question)) {
      return;
    }
    result = await chat.setSessionModel(choice, confirmed: true);
  }
  if (result.deferred) {
    messenger.showSnackBar(
      SnackBar(content: Text(s.modelSwitchDeferred(choice.shortLabel))),
    );
  }
}

/// Bottom sheet: the session's model, the hob's default and every model of
/// the signed-in providers. Pops the picked [ModelChoice].
class SessionModelSheet extends StatelessWidget {
  const SessionModelSheet({super.key, required this.chat});

  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final current = chat.sessionModel;
        final fallback = chat.defaultModel;
        final providers = chat.modelProviders
            .where((p) => p.authenticated || p.slug == current?.provider)
            .toList();
        Widget tile(ModelChoice c) {
          final selected = c.same(current);
          return ListTile(
            key: ValueKey('model:$c'),
            dense: true,
            title: Text(c.model, overflow: TextOverflow.ellipsis),
            subtitle: c.same(fallback) ? Text(s.hobDefaultTag) : null,
            trailing: selected
                ? Icon(Icons.check, color: theme.colorScheme.primary)
                : null,
            selected: selected,
            onTap: () => Navigator.pop(context, c),
          );
        }

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scroll) => ListView(
            controller: scroll,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.sessionModelTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.sessionModelHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (fallback != null)
                ListTile(
                  key: const ValueKey('model:default'),
                  leading: const Icon(Icons.undo),
                  title: Text(s.useHobDefaultModel),
                  subtitle: Text(fallback.shortLabel),
                  enabled: chat.modelOverridden,
                  onTap: () => Navigator.pop(context, fallback),
                ),
              const Divider(),
              if (providers.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(s.modelsUnavailable),
                ),
              for (final p in providers) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Text(
                    p.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final m in p.models)
                  tile(ModelChoice(provider: p.slug, model: m)),
                // The session's model may be off the provider's list.
                if (current != null &&
                    current.provider == p.slug &&
                    !p.models.contains(current.model))
                  tile(current),
              ],
            ],
          ),
        );
      },
    );
  }
}
