import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../api/hermes_rpc.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/chat_controller.dart';
import 'hob_avatar.dart';
import 'model_picker.dart';
import 'hob_detail_screen.dart';
import 'cron_sheet.dart';
import 'format.dart';
import 'pull_up_reload.dart';
import 'theme.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.hob, this.embedded = false});

  final Hob hob;

  /// True when shown beside the hob list (no back button).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AppState>().chatFor(hob);
    return ChangeNotifierProvider.value(
      value: controller,
      child: ChatView(embedded: embedded),
    );
  }
}

class ChatView extends StatefulWidget {
  const ChatView({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _awayFromBottom = false;
  int _countWhenLeft = 0;
  bool _promptExpanded = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    // The list is reversed: offset 0 is the newest message.
    final away = _scroll.hasClients && _scroll.offset > 240;
    if (away != _awayFromBottom) {
      setState(() {
        _awayFromBottom = away;
        if (away) {
          _countWhenLeft = context.read<ChatController>().messages.length;
        }
      });
    }
  }

  void _jumpToBottom() {
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send(ChatController c) {
    final text = _input.text;
    if (text.trim().isEmpty || c.busy || !c.ready) return;
    _input.clear();
    c.send(text);
    _focus.requestFocus();
    if (_scroll.hasClients) _jumpToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ChatController>();
    final theme = Theme.of(context);
    final s = Strings.of(context);
    final working = c.busy || c.hob.workingNow;
    final prompt = c.lastPrompt;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? 16 : 0,
        title: Row(
          children: [
            Tooltip(
              message: s.editHob(c.hob.displayName),
              child: InkResponse(
                onTap: () => HobDetailScreen.open(context, c.hob),
                radius: 24,
                child: HobAvatar(hob: c.hob, size: 30, working: working),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.hob.displayName, overflow: TextOverflow.ellipsis),
                  Text(
                    _subtitle(c, s),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: c.busy
                          ? HobsColors.of(context).working
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: s.scheduledJobs,
            onPressed: () => showCronSheet(context, c.hob),
            icon: const Icon(Icons.event_repeat_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (c.connection != ConnectionStatus.connected &&
              c.phase != ChatPhase.starting)
            MaterialBanner(
              content: Text(s.connectionLost),
              leading: const Icon(Icons.wifi_off),
              actions: [
                TextButton(
                  onPressed: () => context.read<AppState>().onAppResumed(),
                  child: Text(s.reconnectNow),
                ),
              ],
            ),
          if (prompt != null && c.messages.length > 2)
            _PinnedPrompt(
              text: prompt,
              expanded: _promptExpanded,
              onTap: () => setState(() => _promptExpanded = !_promptExpanded),
            ),
          Expanded(
            child: Stack(
              children: [
                PullUpReload(
                  onReload: c.reload,
                  child: _buildMessages(c, theme),
                ),
                if (_awayFromBottom)
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ActionChip(
                        avatar: const Icon(Icons.arrow_downward, size: 16),
                        label: Text(
                          c.messages.length > _countWhenLeft
                              ? s.newMessages(
                                  c.messages.length - _countWhenLeft,
                                )
                              : s.jumpToEnd,
                        ),
                        onPressed: _jumpToBottom,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (c.error != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  if (c.phase == ChatPhase.failed)
                    TextButton(onPressed: c.start, child: Text(s.tryAgain)),
                ],
              ),
            ),
          if (c.approval != null) _ApprovalCard(controller: c),
          if (c.clarify != null)
            _ClarifyCard(key: ObjectKey(c.clarify), controller: c),
          _Composer(
            controller: _input,
            focusNode: _focus,
            chat: c,
            onSend: () => _send(c),
          ),
        ],
      ),
    );
  }

  String _subtitle(ChatController c, Strings s) {
    if (c.phase == ChatPhase.starting) return s.openingChat;
    if (c.busy) return s.workingOn(c.statusText);
    if (c.hob.workingNow) return s.workingInBackground;
    final last = c.hob.lastActive;
    return last != null ? s.activeAgo(relativeAge(last)) : (c.hob.description);
  }

  Widget _buildMessages(ChatController c, ThemeData theme) {
    if (c.phase == ChatPhase.starting && c.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (c.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HobAvatar(hob: c.hob, size: 64),
              const SizedBox(height: 12),
              Text(
                Strings.of(context).writeTo(c.hob.displayName),
                style: theme.textTheme.titleMedium,
              ),
              if (c.hob.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  c.hob.description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final items = c.messages.reversed.toList();
    final showTyping = c.busy && items.first.role == ChatRole.user;
    return SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        itemCount: items.length + (showTyping ? 1 : 0),
        itemBuilder: (context, i) {
          if (showTyping) {
            if (i == 0) return _TypingRow(status: c.statusText);
            i -= 1;
          }
          final m = items[i];
          // Meta row (time, copy) under the last assistant row of a turn.
          final newer = i > 0 ? items[i - 1] : null;
          final endOfTurn =
              m.role == ChatRole.assistant &&
              !m.streaming &&
              (newer == null || newer.role == ChatRole.user);
          return _MessageRow(message: m, showMeta: endOfTurn, controller: c);
        },
      ),
    );
  }
}

class _PinnedPrompt extends StatelessWidget {
  const _PinnedPrompt({
    required this.text,
    required this.expanded,
    required this.onTap,
  });

  final String text;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.push_pin_outlined,
                  size: 15,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    maxLines: expanded ? 8 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: cs.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.showMeta,
    required this.controller,
  });

  final ChatMessage message;
  final bool showMeta;
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    switch (message.role) {
      case ChatRole.user:
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              message.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
        );
      case ChatRole.assistant:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarkdownBody(
                data: message.text + (message.streaming ? ' ▍' : ''),
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  code: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (message.interrupted)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    Strings.of(context).interruptedTag,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.outline,
                    ),
                  ),
                ),
              if (showMeta)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Text(
                        clockTime(message.time),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.outline,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: Strings.of(context).copy,
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        color: cs.outline,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: message.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(Strings.of(context).copied),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_outlined),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case ChatRole.activity:
        return _ActivityRow(
          message: message,
          onToggle: () => controller.toggleActivity(message),
        );
      case ChatRole.notice:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            message.text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        );
      case ChatRole.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: cs.onErrorContainer, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message.text,
                    style: TextStyle(color: cs.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

/// One muted line summarizing consecutive tool calls; tap to expand.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.message, required this.onToggle});

  final ChatMessage message;
  final VoidCallback onToggle;

  String _summary(Strings s) {
    String label(String tool) => s.toolLabel(tool) ?? tool.replaceAll('_', ' ');

    final tools = message.tools;
    final running = tools.where((t) => t.state == ToolState.running).toList();
    if (running.isNotEmpty) {
      final t = running.last;
      final detail = t.progress ?? t.preview;
      return '${label(t.name)}${detail != null && detail.isNotEmpty ? ' · $detail' : ''}';
    }
    final counts = <String, int>{};
    for (final t in tools) {
      final l = label(t.name);
      counts[l] = (counts[l] ?? 0) + 1;
    }
    return counts.entries
        .map((e) => e.value > 1 ? '${e.key} ×${e.value}' : e.key)
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final running = message.toolsRunning;
    final failed = message.tools.any((t) => t.state == ToolState.failed);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  if (running)
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    )
                  else
                    Icon(
                      failed ? Icons.error_outline : Icons.build_outlined,
                      size: 14,
                      color: failed ? cs.error : cs.outline,
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _summary(Strings.of(context)),
                      style: muted,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    message.expanded ? Icons.expand_less : Icons.chevron_right,
                    size: 16,
                    color: cs.outline,
                  ),
                ],
              ),
            ),
          ),
          if (message.expanded)
            Padding(
              padding: const EdgeInsets.only(left: 21, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final t in message.tools)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            switch (t.state) {
                              ToolState.running => Icons.more_horiz,
                              ToolState.done => Icons.check,
                              ToolState.failed => Icons.close,
                            },
                            size: 13,
                            color: t.state == ToolState.failed
                                ? cs.error
                                : cs.outline,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: t.name,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  if ((t.summary ?? t.preview) != null)
                                    TextSpan(
                                      text: '  ${t.summary ?? t.preview}',
                                    ),
                                  if (t.durationS != null)
                                    TextSpan(
                                      text:
                                          '  ${t.durationS!.toStringAsFixed(1)} s',
                                    ),
                                ],
                              ),
                              style: muted,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TypingRow extends StatelessWidget {
  const _TypingRow({this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              status ?? Strings.of(context).thinking,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.chat,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ChatController chat;
  final VoidCallback onSend;

  static const _effortLabels = {
    'minimal': 'Min',
    'low': 'Low',
    'medium': 'Med',
    'high': 'High',
    'xhigh': 'Max',
  };

  static const _approvalIcons = {
    'manual': Icons.front_hand_outlined,
    'smart': Icons.auto_awesome_outlined,
    'off': Icons.bolt,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final canType = chat.ready || chat.busy;
    final chipStyle = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: {
                        // Enter sends, Shift+Enter adds a newline (desktop keyboards).
                        const SingleActivator(LogicalKeyboardKey.enter): onSend,
                      },
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: canType,
                        minLines: 1,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: chat.ready ? s.messageHint : s.connecting,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: chat.busy
                        ? IconButton.filledTonal(
                            tooltip: s.stop,
                            onPressed: chat.interrupt,
                            icon: const Icon(Icons.stop, size: 20),
                          )
                        : IconButton.filled(
                            tooltip: s.send,
                            onPressed: chat.ready ? onSend : null,
                            icon: const Icon(Icons.arrow_upward, size: 20),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (chat.model != null)
                  Flexible(
                    child: _ModelChip(chat: chat, style: chipStyle),
                  ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  enabled: chat.ready,
                  tooltip: s.reasoningLevel,
                  initialValue: chat.reasoningEffort,
                  onSelected: chat.setReasoningEffort,
                  itemBuilder: (_) => [
                    for (final l in ChatController.effortLevels)
                      PopupMenuItem(
                        value: l,
                        child: Text('${_effortLabels[l]} · $l'),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _effortLabels[chat.reasoningEffort] ??
                              (chat.reasoningEffort ?? s.reasoning),
                          style: chipStyle,
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  key: const ValueKey('approval-mode'),
                  enabled: chat.ready,
                  tooltip: s.approvalModeTooltip,
                  initialValue: chat.approvalMode,
                  onSelected: chat.setApprovalMode,
                  itemBuilder: (_) => [
                    for (final m in ChatController.approvalModes)
                      PopupMenuItem(
                        value: m,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(_approvalIcons[m]),
                          title: Text(s.approvalModeLabel(m)),
                          subtitle: Text(s.approvalModeHint(m)),
                        ),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        // "off" runs commands unasked: make it visible.
                        color: chat.approvalMode == 'off'
                            ? cs.error
                            : cs.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _approvalIcons[chat.approvalMode] ??
                              Icons.shield_outlined,
                          size: 14,
                          color: chat.approvalMode == 'off'
                              ? cs.error
                              : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          s.approvalModeLabel(chat.approvalMode ?? ''),
                          style: chipStyle,
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.controller});

  final ChatController controller;

  static String _label(Strings s, String choice) => switch (choice) {
    'once' => s.allowOnce,
    'session' => s.allowSession,
    'always' => s.allowAlways,
    'deny' => s.deny,
    _ => choice,
  };

  @override
  Widget build(BuildContext context) {
    final a = controller.approval!;
    final theme = Theme.of(context);
    final s = Strings.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.approvalTitle(a.toolName),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (a.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(a.description),
            ],
            if (a.command.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  a.command,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final choice in a.choices)
                  choice == 'deny'
                      ? OutlinedButton(
                          onPressed: () => controller.answerApproval(choice),
                          child: Text(_label(s, choice)),
                        )
                      : FilledButton.tonal(
                          onPressed: () => controller.answerApproval(choice),
                          child: Text(_label(s, choice)),
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClarifyCard extends StatefulWidget {
  const _ClarifyCard({super.key, required this.controller});

  final ChatController controller;

  @override
  State<_ClarifyCard> createState() => _ClarifyCardState();
}

class _ClarifyCardState extends State<_ClarifyCard> {
  final Map<String, String?> _answers = {};
  final Map<String, TextEditingController> _text = {};

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final qs = widget.controller.clarify!;
    final out = <String, String?>{};
    for (final q in qs) {
      final typed = _text[q.qid]?.text.trim();
      out[q.qid] = (typed != null && typed.isNotEmpty)
          ? typed
          : _answers[q.qid];
    }
    widget.controller.answerClarify(out);
  }

  @override
  Widget build(BuildContext context) {
    final qs = widget.controller.clarify!;
    final theme = Theme.of(context);
    final s = Strings.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: theme.colorScheme.secondaryContainer,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.45,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.help_outline, size: 18),
                  const SizedBox(width: 8),
                  Text(s.hobAsks, style: theme.textTheme.titleSmall),
                ],
              ),
              for (final q in qs) ...[
                const SizedBox(height: 10),
                Text(q.question),
                const SizedBox(height: 6),
                if (q.choices != null && q.choices!.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final ch in q.choices!)
                        ChoiceChip(
                          label: Text(ch),
                          selected: _answers[q.qid] == ch,
                          onSelected: (_) =>
                              setState(() => _answers[q.qid] = ch),
                        ),
                    ],
                  ),
                TextField(
                  controller: _text.putIfAbsent(
                    q.qid,
                    TextEditingController.new,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: (q.choices?.isNotEmpty ?? false)
                        ? s.orOwnAnswer
                        : s.answerHint,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => widget.controller.answerClarify(null),
                    child: Text(s.skip),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _submit, child: Text(s.answer)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The session's model in the composer. Tapping it picks a model for this
/// chat only; a chat off the hob's default model is outlined and tagged.
class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.chat, required this.style});

  final ChatController chat;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final overridden = chat.modelOverridden;
    final label = chat.sessionModel?.shortLabel ?? chat.model!;
    return Tooltip(
      message: overridden
          ? '${s.modelTooltip} · ${s.sessionModelTag}'
          : s.modelTooltip,
      child: InkWell(
        key: const ValueKey('session-model'),
        borderRadius: BorderRadius.circular(12),
        onTap: chat.ready ? () => pickSessionModel(context, chat) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: overridden ? cs.primary : cs.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (overridden) ...[
                Icon(Icons.push_pin_outlined, size: 12, color: cs.primary),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  style: overridden
                      ? style?.copyWith(color: cs.primary)
                      : style,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 16, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
