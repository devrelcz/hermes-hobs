import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/chat_controller.dart';
import 'sheets.dart';

/// Asks before switching to a model the server marks as expensive
/// (`confirm_required`). Shared by the hob profile and the chat composer.
Future<bool> confirmExpensiveModel(
  BuildContext context,
  String question,
) async {
  final s = Strings.of(context);
  return showConfirmSheet(
    context,
    icon: Icons.payments_outlined,
    title: s.confirmModelTitle,
    message: question.isEmpty ? s.confirmModelFallback : question,
    confirmLabel: s.switchModel,
    cancelLabel: s.cancel,
  );
}

/// Lets the user pick the model of this chat's session only (the composer's
/// model chip). The hob's profile keeps its default.
Future<void> pickSessionModel(BuildContext context, ChatController chat) async {
  final messenger = ScaffoldMessenger.of(context);
  final s = Strings.of(context);
  // Fresh list and current value every time the sheet opens.
  chat.loadModels();
  final choice = await showScreenSheet<ModelChoice>(
    context,
    kind: SheetKind.bottom,
    dragHandle: true,
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

/// Picks a model for a Hob's profile from [providers]. Returns the choice,
/// [ModelSearchSheet.inherit] to inherit the default profile's model again,
/// or null when the user backed out.
Future<ModelChoice?> pickProfileModel(
  BuildContext context, {
  required List<ModelProvider> providers,
  required ModelChoice? current,
}) {
  final s = Strings.of(context);
  return showScreenSheet<ModelChoice>(
    context,
    kind: SheetKind.bottom,
    dragHandle: true,
    builder: (context) => ModelSearchSheet(
      title: s.modelLabel,
      providers: providers,
      current: current,
      topOption: ModelTopOption(
        icon: Icons.undo,
        title: s.inheritModel,
        value: ModelSearchSheet.inherit,
        enabled: current != null,
      ),
    ),
  );
}

/// The session's model, the hob's default and every model of the
/// signed-in providers, searchable. Pops the picked [ModelChoice].
class SessionModelSheet extends StatelessWidget {
  const SessionModelSheet({super.key, required this.chat});

  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final current = chat.sessionModel;
        final fallback = chat.defaultModel;
        return ModelSearchSheet(
          title: s.sessionModelTitle,
          hint: s.sessionModelHint,
          providers: [
            for (final p in chat.modelProviders)
              if (p.authenticated || p.slug == current?.provider) p,
          ],
          current: current,
          fallback: fallback,
          topOption: fallback == null
              ? null
              : ModelTopOption(
                  key: const ValueKey('model:default'),
                  icon: Icons.undo,
                  title: s.useHobDefaultModel,
                  subtitle: fallback.shortLabel,
                  value: fallback,
                  enabled: chat.modelOverridden,
                ),
        );
      },
    );
  }
}

/// The tile above the list for leaving the list's models alone: back to
/// the Hob's default, or inheriting the default profile's model.
class ModelTopOption {
  const ModelTopOption({
    this.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.enabled = true,
  });

  final Key? key;
  final IconData icon;
  final String title;
  final String? subtitle;
  final ModelChoice value;
  final bool enabled;
}

/// A searchable list of models grouped by provider. Typing filters by model
/// id and provider name; the current model carries a check.
class ModelSearchSheet extends StatefulWidget {
  const ModelSearchSheet({
    super.key,
    required this.title,
    this.hint,
    required this.providers,
    required this.current,
    this.fallback,
    this.topOption,
  });

  /// Picked to inherit the default profile's model (no provider, no model).
  static const inherit = ModelChoice(provider: '', model: '');

  final String title;
  final String? hint;
  final List<ModelProvider> providers;
  final ModelChoice? current;

  /// Tagged as the Hob's default in the list.
  final ModelChoice? fallback;
  final ModelTopOption? topOption;

  @override
  State<ModelSearchSheet> createState() => _ModelSearchSheetState();
}

class _ModelSearchSheetState extends State<ModelSearchSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  static final _flat = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide.none,
  );

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final q = _query.text.trim().toLowerCase();
    final current = widget.current;
    bool matches(ModelProvider p, String m) =>
        q.isEmpty ||
        m.toLowerCase().contains(q) ||
        p.label.toLowerCase().contains(q) ||
        p.slug.toLowerCase().contains(q);
    final groups = [
      for (final p in widget.providers)
        (
          p,
          [
            for (final m in p.models)
              if (matches(p, m)) ModelChoice(provider: p.slug, model: m),
            // The current model may be off the provider's list.
            if (current != null &&
                current.provider == p.slug &&
                current.model.isNotEmpty &&
                !p.models.contains(current.model) &&
                matches(p, current.model))
              current,
          ],
        ),
    ].where((g) => g.$2.isNotEmpty).toList();

    Widget tile(ModelChoice c) {
      final selected = c.same(current);
      return ListTile(
        key: ValueKey('model:$c'),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(c.model, overflow: TextOverflow.ellipsis),
        subtitle: c.same(widget.fallback) ? Text(s.hobDefaultTag) : null,
        trailing: selected ? Icon(Icons.check, color: cs.primary) : null,
        selected: selected,
        onTap: () => Navigator.pop(context, c),
      );
    }

    final top = widget.topOption;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              isWideWindow(context) ? 24 : sheetHandleGap,
              20,
              0,
            ),
            child: Text(widget.title, style: theme.textTheme.titleLarge),
          ),
          if (widget.hint != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                widget.hint!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              autocorrect: false,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: s.searchModels,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        tooltip: s.clearSearch,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(_query.clear),
                      ),
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: _flat,
                enabledBorder: _flat,
                focusedBorder: _flat.copyWith(
                  borderSide: BorderSide(color: cs.primary, width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                if (top != null && q.isEmpty) ...[
                  ListTile(
                    key: top.key,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Icon(top.icon),
                    title: Text(top.title),
                    subtitle: top.subtitle == null ? null : Text(top.subtitle!),
                    enabled: top.enabled,
                    onTap: () => Navigator.pop(context, top.value),
                  ),
                  const Divider(indent: 20, endIndent: 20),
                ],
                if (widget.providers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(s.modelsUnavailable),
                  )
                else if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      s.noModelMatches,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (final (p, models) in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text(
                      p.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final m in models) tile(m),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
