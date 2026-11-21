import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../api/group_models.dart';
import '../api/hermes_rpc.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/group_chat_controller.dart';
import 'format.dart';
import 'hob_avatar.dart';
import 'offline_bar.dart';
import 'theme.dart';

/// A group chat: the user and two to six Hobs in one room. Members answer in
/// rounds; `@handle` at the start of a message assigns it to one of them.
class GroupChatScreen extends StatelessWidget {
  const GroupChatScreen({
    super.key,
    required this.room,
    this.embedded = false,
    this.onClosed,
  });

  final GroupRoom room;

  /// True when shown beside the list (no back button).
  final bool embedded;

  /// Called after the group was disbanded from here.
  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AppState>().groupChatFor(room);
    return ChangeNotifierProvider.value(
      value: controller,
      child: _GroupChatView(embedded: embedded, onClosed: onClosed),
    );
  }
}

class _GroupChatView extends StatefulWidget {
  const _GroupChatView({required this.embedded, this.onClosed});

  final bool embedded;
  final VoidCallback? onClosed;

  @override
  State<_GroupChatView> createState() => _GroupChatViewState();
}

class _GroupChatViewState extends State<_GroupChatView> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(GroupChatController c) {
    final text = _input.text;
    if (text.trim().isEmpty || c.acting || c.disbanded) return;
    _input.clear();
    c.send(text);
    _focus.requestFocus();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Puts `@handle` in front of the draft (once).
  void _mention(GroupMember m) {
    final tag = '@${m.handle}';
    final text = _input.text.trimLeft();
    if (!text.startsWith(tag)) {
      _input.text = '$tag $text';
    }
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _focus.requestFocus();
  }

  Future<void> _rename(GroupChatController c) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: Strings.of(context).renameGroupTitle,
        initial: c.room.name,
      ),
    );
    if (name == null) return;
    await c.rename(name);
  }

  Future<void> _disband(GroupChatController c) async {
    final s = Strings.of(context);
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.disbandGroup),
        content: Text(s.disbandGroupBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.disband),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await c.disband();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AppState.describeError(e))),
      );
      return;
    }
    app.forgetGroup(c.roomId);
    widget.onClosed?.call();
    if (!widget.embedded && navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GroupChatController>();
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final members = c.room.members;
    final working = [
      for (final m in members)
        if (c.stateOf(m.memberId) == MemberState.working) app.memberName(m),
    ];
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? 16 : 0,
        title: Row(
          children: [
            GroupAvatars(
              hobs: [for (final m in members) app.memberHob(m)],
              size: 30,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.room.name.isEmpty ? s.groupChats : c.room.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    working.isNotEmpty
                        ? s.groupWorking(working.join(', '))
                        : s.groupMembers(members.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: working.isNotEmpty
                          ? HobsColors.of(context).working
                          : cs.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!c.disbanded)
            PopupMenuButton<String>(
              tooltip: s.groupOptions,
              onSelected: (v) {
                if (v == 'rename') _rename(c);
                if (v == 'disband') _disband(c);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'rename',
                  child: _MenuRow(
                    icon: Icons.edit_outlined,
                    label: s.renameGroup,
                  ),
                ),
                PopupMenuItem(
                  value: 'disband',
                  child: _MenuRow(
                    icon: Icons.delete_outline,
                    label: s.disbandGroup,
                    color: cs.error,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Offline, the bar above the app already says why.
          if (c.connection != ConnectionStatus.connected &&
              !c.loading &&
              !isOffline(context))
            MaterialBanner(
              content: Text(s.connectionLost),
              leading: const Icon(Icons.wifi_off),
              actions: [
                TextButton(
                  onPressed: () => app.onAppResumed(),
                  child: Text(s.reconnectNow),
                ),
              ],
            ),
          _MemberStrip(chat: c, onMention: _mention),
          const Divider(height: 1),
          Expanded(child: _buildLog(c, app, theme)),
          if (c.error != null)
            Container(
              width: double.infinity,
              color: cs.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                c.error!,
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ),
          for (final a in c.driver?.actions ?? const <GroupAction>[])
            _ActionCard(key: ValueKey(a.taskId), chat: c, action: a),
          if (c.disbanded)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  s.groupDisbanded,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            _GroupComposer(
              controller: _input,
              focusNode: _focus,
              chat: c,
              onSend: () => _send(c),
            ),
        ],
      ),
    );
  }

  Widget _buildLog(GroupChatController c, AppState app, ThemeData theme) {
    if (c.loading && c.log.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final rows = _rows(c);
    if (rows.isEmpty && c.pendingText == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GroupAvatars(
                hobs: [for (final m in c.room.members) app.memberHob(m)],
                size: 56,
              ),
              const SizedBox(height: 12),
              Text(
                Strings.of(context).groupEmpty,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }
    final continuable = c.continuable;
    final items = <Widget>[
      if (c.pendingText != null)
        _UserBubble(text: c.pendingText!, time: null, pending: true),
      ...rows.reversed,
    ];
    final working = [
      for (final m in c.room.members)
        if (c.stateOf(m.memberId) == MemberState.working) m,
    ];
    return SelectionArea(
      child: ListView(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        children: [
          if (continuable != null)
            _ContinueRow(onContinue: () => c.continueRound(continuable)),
          for (final m in working)
            _WorkingRow(
              hob: app.memberHob(m),
              name: app.memberName(m),
              tool: c.toolOf(m.memberId),
            ),
          ...items,
        ],
      ),
    );
  }

  /// The log as rows, oldest first: messages, failed and stopped turns.
  List<Widget> _rows(GroupChatController c) {
    final app = context.read<AppState>();
    final s = Strings.of(context);
    final byId = {for (final m in c.room.members) m.memberId: m};
    final rows = <Widget>[];
    for (final e in c.log) {
      if (e.isUserMessage) {
        if (e.text.trim().isEmpty) continue;
        rows.add(_UserBubble(text: e.text, time: e.createdAt));
      } else if (e.isMemberMessage) {
        if (e.text.trim().isEmpty) continue;
        final m = byId[e.memberId.isNotEmpty ? e.memberId : e.actorId];
        rows.add(
          _MemberMessage(
            hob: m == null ? null : app.memberHob(m),
            name: m == null ? e.actorId : app.memberName(m),
            text: e.text,
            time: e.createdAt,
          ),
        );
      } else if (e.kind == 'turn.failed') {
        final m = byId[e.memberId];
        final reason = (e.payload['error'] ?? e.payload['reason_code'])
            ?.toString()
            .split('\n')
            .first
            .trim();
        rows.add(
          _Notice(
            text: s.turnFailed(
              m == null ? e.memberId : app.memberName(m),
              reason,
            ),
            error: true,
          ),
        );
      } else if (e.kind == 'room.stop_requested') {
        rows.add(_Notice(text: s.turnCancelled));
      }
    }
    return rows;
  }
}

/// Overlapping faces of a group's members (at most three).
class GroupAvatars extends StatelessWidget {
  const GroupAvatars({super.key, required this.hobs, this.size = 38});

  final List<Hob> hobs;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shown = hobs.take(3).toList();
    final face = shown.length == 1 ? size : size * 0.62;
    final step = shown.length <= 1 ? 0.0 : (size - face) / (shown.length - 1);
    final bg = Theme.of(context).colorScheme.surface;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: step * i,
              top: shown.length <= 1 ? 0 : (i.isEven ? 0 : size - face),
              child: Container(
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                padding: const EdgeInsets.all(1),
                child: HobAvatar(hob: shown[i], size: face - 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// The members with their state; tapping one starts the draft with `@handle`.
class _MemberStrip extends StatelessWidget {
  const _MemberStrip({required this.chat, required this.onMention});

  final GroupChatController chat;
  final void Function(GroupMember m) onMention;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final m in chat.room.members)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Builder(
                builder: (context) {
                  final state = chat.stateOf(m.memberId);
                  final busy =
                      state == MemberState.working ||
                      state == MemberState.queued;
                  final color = switch (state) {
                    MemberState.working => HobsColors.of(context).working,
                    MemberState.failed => cs.error,
                    _ => cs.onSurfaceVariant,
                  };
                  return Tooltip(
                    message: s.mention(m.handle),
                    child: ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: HobAvatar(
                        hob: app.memberHob(m),
                        size: 20,
                        working: busy,
                      ),
                      label: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: app.memberName(m)),
                            TextSpan(
                              text: ' · ${s.memberStateLabel(state.name)}',
                              style: TextStyle(color: color),
                            ),
                          ],
                        ),
                        style: theme.textTheme.labelMedium,
                      ),
                      onPressed: chat.disbanded ? null : () => onMention(m),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text, this.time, this.pending = false});

  final String text;
  final DateTime? time;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Opacity(
        opacity: pending ? 0.6 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Byline(name: Strings.of(context).you, time: time),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberMessage extends StatelessWidget {
  const _MemberMessage({
    required this.hob,
    required this.name,
    required this.text,
    this.time,
  });

  final Hob? hob;
  final String name;
  final String text;
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hob case final h?)
            HobAvatar(hob: h, size: 28)
          else
            const SizedBox(width: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: _Byline(name: name, time: time),
                    ),
                    IconButton(
                      tooltip: Strings.of(context).copy,
                      visualDensity: VisualDensity.compact,
                      iconSize: 14,
                      color: cs.outline,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
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
                MarkdownBody(
                  data: text,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Byline extends StatelessWidget {
  const _Byline({required this.name, this.time});

  final String name;
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = time;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (t != null)
            TextSpan(
              text: '  ${clockTime(t)}',
              style: TextStyle(color: theme.colorScheme.outline),
            ),
        ],
      ),
      style: theme.textTheme.labelMedium,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.stop_circle_outlined,
            size: 15,
            color: error ? cs.error : cs.outline,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: error ? cs.error : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkingRow extends StatelessWidget {
  const _WorkingRow({required this.hob, required this.name, this.tool});

  final Hob hob;
  final String name;
  final String? tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = Strings.of(context);
    final what = tool == null ? s.working : (s.toolLabel(tool!) ?? tool!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          HobAvatar(hob: hob, size: 22, working: true),
          const SizedBox(width: 10),
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$name · $what',
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

class _ContinueRow extends StatelessWidget {
  const _ContinueRow({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = Strings.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.roundCapped,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          OutlinedButton(onPressed: onContinue, child: Text(s.continueRound)),
        ],
      ),
    );
  }
}

/// What waits on the user: a command to approve, or a failed turn.
class _ActionCard extends StatelessWidget {
  const _ActionCard({super.key, required this.chat, required this.action});

  final GroupChatController chat;
  final GroupAction action;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final theme = Theme.of(context);
    final s = Strings.of(context);
    GroupMember? member;
    for (final m in chat.room.members) {
      if (m.memberId == action.memberId) member = m;
    }
    final name = member == null ? action.memberId : app.memberName(member);
    final approval = action.kind == 'approval';
    final busy = chat.acting;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              approval ? s.memberAsks(name) : s.memberFailed(name),
              style: theme.textTheme.titleSmall,
            ),
            if (action.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(action.description),
            ],
            if (action.command.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  action.command,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: approval
                  ? [
                      if (action.choices.contains('once'))
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () => chat.answer(action, choice: 'once'),
                          child: Text(s.allowOnce),
                        ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => chat.answer(action, choice: 'deny'),
                        child: Text(s.deny),
                      ),
                    ]
                  : [
                      FilledButton(
                        onPressed: busy ? null : () => chat.answer(action),
                        child: Text(s.retry),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => chat.answer(action, discard: true),
                        child: Text(s.discardTurn),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupComposer extends StatelessWidget {
  const _GroupComposer({
    required this.controller,
    required this.focusNode,
    required this.chat,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final GroupChatController chat;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final ready =
        !chat.loading && chat.connection == ConnectionStatus.connected;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Container(
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
                    const SingleActivator(LogicalKeyboardKey.enter): onSend,
                  },
                  child: TextField(
                    key: const ValueKey('group-input'),
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: ready ? s.groupMessageHint : s.connecting,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: chat.busy
                    ? IconButton.filledTonal(
                        tooltip: s.stop,
                        onPressed: chat.acting ? null : chat.stop,
                        icon: const Icon(Icons.stop, size: 20),
                      )
                    : IconButton.filled(
                        tooltip: s.send,
                        onPressed: ready && !chat.acting ? onSend : null,
                        icon: const Icon(Icons.arrow_upward, size: 20),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

/// Asks for a name; returns it, or null when cancelled.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: s.groupNameLabel),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _name.text),
          child: Text(s.save),
        ),
      ],
    );
  }
}
