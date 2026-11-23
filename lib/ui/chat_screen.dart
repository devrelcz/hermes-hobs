import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../api/hermes_rpc.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/chat_controller.dart';
import '../state/composer_draft.dart';
import 'placeholders.dart';
import 'prompt_card.dart';
import 'sheets.dart';
import 'attachments_ui.dart';
import '../state/mentions.dart';
import 'hob_avatar.dart';
import 'offline_bar.dart';
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
    final app = context.read<AppState>();
    final controller = app.chatFor(hob);
    return ChangeNotifierProvider.value(
      value: controller,
      child: ChangeNotifierProvider.value(
        value: app.draftFor(hob),
        child: ChatView(embedded: embedded),
      ),
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

  /// The newest question and the message list, to tell whether that
  /// question is still on screen. Only once it scrolls away does the
  /// pinned copy above the list show.
  final _lastUserKey = GlobalKey();
  final _listKey = GlobalKey();
  bool _promptOffscreen = false;

  /// Search within the chat: the typed words, the messages that hold them
  /// (newest first) and the one on screen.
  bool _searching = false;
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  List<ChatMessage> _matches = const [];
  int _match = 0;
  final _matchKeys = Expando<GlobalKey>();

  void _openSearch() {
    setState(() {
      _searching = true;
      _query.clear();
      _matches = const [];
    });
    // The composer may hold the focus: take it, or typing would go there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _queryFocus.requestFocus();
    });
  }

  void _closeSearch() => setState(() {
    _searching = false;
    _matches = const [];
  });

  void _runSearch(ChatController c) {
    final q = _query.text.trim().toLowerCase();
    final found = q.isEmpty
        ? const <ChatMessage>[]
        : [
            for (final m in c.messages.reversed)
              if ((m.role == ChatRole.user || m.role == ChatRole.assistant) &&
                  m.text.toLowerCase().contains(q))
                m,
          ];
    setState(() {
      _matches = found;
      _match = 0;
    });
    if (found.isNotEmpty) _reveal(found.first, older: true);
  }

  /// Steps to the next older ([delta] 1) or newer (-1) match.
  void _step(int delta) {
    if (_matches.isEmpty) return;
    setState(
      () => _match = (_match + delta + _matches.length) % _matches.length,
    );
    _reveal(_matches[_match], older: delta >= 0);
  }

  /// Scrolls until [m] is built, then brings it into view. The list builds
  /// rows lazily, so a far one is reached a screen at a time.
  Future<void> _reveal(ChatMessage m, {required bool older}) async {
    final key = _matchKeys[m] ??= GlobalKey();
    final still = MediaQuery.disableAnimationsOf(context);
    for (var i = 0; i < 80 && mounted; i++) {
      final ctx = key.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.4,
          duration: still ? Duration.zero : const Duration(milliseconds: 220),
        );
        return;
      }
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      // The list is reversed: older messages lie at larger offsets.
      final next = (pos.pixels + (older ? 1 : -1) * pos.viewportDimension * 0.8)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (next == pos.pixels) older = !older;
      _scroll.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// The `@word` being typed and the Hobs it can become.
  ({int start, String query})? _mention;
  List<Hob> _mentionOptions = const [];
  int _mentionIndex = 0;

  /// `@` position the user dismissed with Escape; stays closed until they
  /// start another mention.
  int? _mentionDismissedAt;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _input.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    final sel = _input.selection;
    final active = sel.isValid && sel.isCollapsed
        ? Mentions.activeQuery(_input.text, sel.baseOffset)
        : null;
    if (active?.start != _mentionDismissedAt) _mentionDismissedAt = null;
    final options = active == null || _mentionDismissedAt != null
        ? const <Hob>[]
        : context.read<ChatController>().mentionCandidates(active.query);
    if (options.isEmpty && _mentionOptions.isEmpty) {
      _mention = active;
      return;
    }
    setState(() {
      if (active?.query != _mention?.query) _mentionIndex = 0;
      _mention = active;
      _mentionOptions = options;
      if (_mentionIndex >= options.length) _mentionIndex = 0;
    });
  }

  bool get _mentionOpen => _mentionOptions.isNotEmpty && _mention != null;

  void _pickMention(Hob hob) {
    final m = _mention;
    if (m == null) return;
    final c = context.read<ChatController>();
    final text = _input.text;
    final end = (m.start + 1 + m.query.length).clamp(0, text.length);
    final insert = '@${c.mentionTag(hob)} ';
    final next = text.replaceRange(m.start, end, insert);
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: m.start + insert.length),
    );
    _focus.requestFocus();
  }

  void _moveMention(int delta) {
    if (!_mentionOpen) return;
    setState(() {
      final n = _mentionOptions.length;
      _mentionIndex = (_mentionIndex + delta + n) % n;
    });
  }

  void _dismissMention() {
    final m = _mention;
    if (m == null) return;
    setState(() {
      _mentionDismissedAt = m.start;
      _mentionOptions = const [];
    });
  }

  /// Whether the newest question has left the list's visible area (a row
  /// the list has not even built is far off screen).
  void _checkPrompt() {
    if (!mounted) return;
    final row = _lastUserKey.currentContext?.findRenderObject() as RenderBox?;
    final list = _listKey.currentContext?.findRenderObject() as RenderBox?;
    var off = true;
    if (row != null && row.attached && list != null && list.attached) {
      final top = row.localToGlobal(Offset.zero).dy;
      final bottom = top + row.size.height;
      final listTop = list.localToGlobal(Offset.zero).dy;
      final listBottom = listTop + list.size.height;
      off = bottom < listTop + 12 || top > listBottom - 12;
    }
    if (off != _promptOffscreen) setState(() => _promptOffscreen = off);
  }

  void _onScroll() {
    _checkPrompt();
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
    _query.dispose();
    _queryFocus.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send(ChatController c) {
    // Enter while picking a Hob takes the highlighted one.
    if (_mentionOpen) {
      _pickMention(_mentionOptions[_mentionIndex]);
      return;
    }
    final draft = context.read<ComposerDraft>();
    final text = _input.text;
    if (c.busy || !c.ready || !draft.ready) return;
    if (text.trim().isEmpty && draft.isEmpty) return;
    _input.clear();
    HapticFeedback.lightImpact();
    c.send(text, attachments: draft.take());
    _focus.requestFocus();
    if (_scroll.hasClients) _jumpToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ChatController>();
    final draft = context.watch<ComposerDraft>();
    if (draft.prefill != null) {
      // Text shared from another app: into the field, never sent by itself.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final shared = draft.takePrefill();
        if (shared == null || !mounted) return;
        final current = _input.text.trim();
        _input.text = current.isEmpty ? shared : '$current\n\n$shared';
      });
    }
    final theme = Theme.of(context);
    final s = Strings.of(context);
    final working = c.busy || c.hob.workingNow;
    var prompt = c.lastPrompt;
    if (prompt != null && prompt.isEmpty) {
      // An attachment-only message: pin its file names instead.
      final last = c.messages.lastWhere((m) => m.role == ChatRole.user);
      prompt = last.attachments.map((a) => a.name).join(', ');
    }
    return Scaffold(
      appBar: _searching
          ? _searchBar(c, s, theme)
          : AppBar(
              toolbarHeight: textBarHeight(context, text: 38, rest: 18),
              automaticallyImplyLeading: !widget.embedded,
              titleSpacing: widget.embedded ? 16 : 0,
              title: Row(
                children: [
                  Tooltip(
                    message: s.editHob(c.hob.displayName),
                    child: InkResponse(
                      onTap: () => HobDetailScreen.open(context, c.hob),
                      radius: 24,
                      child: HobHero(
                        name: c.hob.name,
                        enabled: !widget.embedded,
                        child: HobAvatar(
                          hob: c.hob,
                          size: 30,
                          working: working,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.hob.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                PopupMenuButton<String>(
                  tooltip: s.chatMenu,
                  position: PopupMenuPosition.under,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onSelected: (v) {
                    if (v == 'search') _openSearch();
                    if (v == 'cron') showCronSheet(context, c.hob);
                    if (v == 'profile') HobDetailScreen.open(context, c.hob);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'search',
                      child: _MenuLine(
                        icon: Icons.search,
                        label: s.searchInChat,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'profile',
                      child: _MenuLine(
                        icon: Icons.badge_outlined,
                        label: s.hobProfile,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'cron',
                      child: _MenuLine(
                        icon: Icons.event_repeat_outlined,
                        label: s.scheduledJobs,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
      body: Column(
        children: [
          // Offline, the bar above the app already says why.
          if (c.connection != ConnectionStatus.connected &&
              c.phase != ChatPhase.starting &&
              !isOffline(context))
            InlineBanner(
              icon: Icons.wifi_off,
              message: s.connectionLost,
              actionLabel: s.reconnectNow,
              onAction: () => context.read<AppState>().onAppResumed(),
            ),
          // The question this reply answers, once it scrolled away.
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: prompt != null && _promptOffscreen
                ? _PinnedPrompt(
                    text: prompt,
                    expanded: _promptExpanded,
                    onTap: () =>
                        setState(() => _promptExpanded = !_promptExpanded),
                  )
                : const SizedBox(width: double.infinity),
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
                      child: AppearIn(
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            elevation: 3,
                            shadowColor: theme.colorScheme.shadow.withValues(
                              alpha: 0.3,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: _jumpToBottom,
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          label: Text(
                            c.messages.length > _countWhenLeft
                                ? s.newMessages(
                                    c.messages.length - _countWhenLeft,
                                  )
                                : s.jumpToEnd,
                          ),
                        ),
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
          if (_mentionOpen)
            _MentionSuggestions(
              options: _mentionOptions,
              highlighted: _mentionIndex,
              tagOf: c.mentionTag,
              onPick: _pickMention,
            ),
          CallbackShortcuts(
            bindings: _mentionOpen
                ? {
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                        _moveMention(1),
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                        _moveMention(-1),
                    const SingleActivator(LogicalKeyboardKey.tab): () =>
                        _pickMention(_mentionOptions[_mentionIndex]),
                    const SingleActivator(LogicalKeyboardKey.escape):
                        _dismissMention,
                  }
                : const {},
            child: _Composer(
              controller: _input,
              focusNode: _focus,
              chat: c,
              draft: draft,
              onSend: () => _send(c),
            ),
          ),
        ],
      ),
    );
  }

  /// The header while searching: the field, how many found and which one,
  /// and arrows to the older and newer hits.
  PreferredSizeWidget _searchBar(ChatController c, Strings s, ThemeData theme) {
    final n = _matches.length;
    final typed = _query.text.trim().isNotEmpty;
    return AppBar(
      toolbarHeight: textBarHeight(context, text: 38, rest: 18),
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        icon: const Icon(Icons.close),
        onPressed: _closeSearch,
      ),
      titleSpacing: 0,
      title: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
          const SingleActivator(LogicalKeyboardKey.enter): () => _step(1),
          const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
              _step(-1),
        },
        child: TextField(
          controller: _query,
          focusNode: _queryFocus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => _runSearch(c),
          onSubmitted: (_) => _step(1),
          decoration: InputDecoration(
            hintText: s.searchInChat,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            isDense: true,
          ),
        ),
      ),
      actions: [
        if (typed)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  n == 0 ? s.searchNone : s.searchCount(_match + 1, n),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        IconButton(
          tooltip: s.searchOlder,
          onPressed: n > 1 ? () => _step(1) : null,
          icon: const Icon(Icons.keyboard_arrow_up),
        ),
        IconButton(
          tooltip: s.searchNewer,
          onPressed: n > 1 ? () => _step(-1) : null,
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  String _subtitle(ChatController c, Strings s) {
    if (c.phase == ChatPhase.starting) return s.openingChat;
    if (c.busy) return s.workingOn(c.statusText);
    if (c.hob.workingNow) return s.workingInBackground;
    final last = c.hob.lastActive;
    return last != null ? s.activeSince(last) : c.hob.description;
  }

  /// Desktops have a pointer to hover with.
  static bool get _pointer => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };

  Widget _buildMessages(ChatController c, ThemeData theme) {
    if (c.phase == ChatPhase.starting && c.messages.isEmpty) {
      return const ChatSkeleton();
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
    bool endOfTurn(int i) {
      final m = items[i];
      return m.role == ChatRole.assistant &&
          !m.streaming &&
          (i == 0 || items[i - 1].role == ChatRole.user);
    }

    // Time and copy stay out under the newest reply only; older replies
    // show them under a mouse pointer (on touch, text selection copies).
    final newestEnd = [for (var i = 0; i < items.length; i++) i]
        .where(endOfTurn)
        .firstOrNull;
    final newestUser = items.indexWhere((m) => m.role == ChatRole.user);
    // Rows move as replies stream in: recheck the question after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPrompt());
    return SelectionArea(
      child: ListView.builder(
        key: _listKey,
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
          final hit = _matches.contains(m);
          final current = hit && identical(_matches[_match], m);
          final row = _MessageRow(
            key: i == newestUser ? _lastUserKey : null,
            message: items[i],
            meta: !endOfTurn(i)
                ? _Meta.none
                : i == newestEnd
                ? _Meta.shown
                : _pointer
                ? _Meta.onHover
                : _Meta.none,
            controller: c,
          );
          // Just written or just started: it slides in. Older rows built
          // again by scrolling stay put.
          final fresh =
              DateTime.now().difference(m.time) < const Duration(seconds: 2)
              ? AppearIn(key: ValueKey(m), child: row)
              : row;
          // A search hit: keyed so the search can scroll to it, and lit
          // while it is the current one.
          final shown = !hit
              ? fresh
              : KeyedSubtree(
                  key: _matchKeys[m] ??= GlobalKey(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      // Only the hit on screen is lit; the bar counts the rest.
                      color: current
                          ? theme.colorScheme.tertiaryContainer.withValues(
                              alpha: 0.7,
                            )
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: fresh,
                  ),
                );
          // The first message of a day carries the day above it (the list
          // runs newest first, so "first" is the next item's neighbour).
          final older = i + 1 < items.length ? items[i + 1] : null;
          if (older != null && sameDay(older.time, m.time)) return shown;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DaySeparator(label: dayLabel(m.time)),
              shown,
            ],
          );
        },
      ),
    );
  }
}

/// [text] with every `@tag` that names a Hob in [mentionStyle].
TextSpan _withMentions(
  String text,
  ChatController chat,
  TextStyle mentionStyle,
) {
  final spans = <InlineSpan>[];
  var last = 0;
  final pattern = RegExp(r'(^|\s)(@[a-z0-9][a-z0-9_-]*)', caseSensitive: false);
  for (final m in pattern.allMatches(text)) {
    final tag = m.group(2)!;
    if (!chat.mentionsHob(tag)) continue;
    final start = m.start + m.group(1)!.length;
    if (start > last) spans.add(TextSpan(text: text.substring(last, start)));
    spans.add(TextSpan(text: tag, style: mentionStyle));
    last = start + tag.length;
  }
  if (spans.isEmpty) return TextSpan(text: text);
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return TextSpan(children: spans);
}

/// The Hobs an `@word` in the composer can become.
class _MentionSuggestions extends StatelessWidget {
  const _MentionSuggestions({
    required this.options,
    required this.highlighted,
    required this.tagOf,
    required this.onPick,
  });

  final List<Hob> options;
  final int highlighted;
  final String Function(Hob) tagOf;
  final void Function(Hob) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Material(
        key: const ValueKey('mention-suggestions'),
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 232),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: options.length,
            itemBuilder: (context, i) {
              final hob = options[i];
              return ListTile(
                dense: true,
                selected: i == highlighted,
                selectedTileColor: cs.secondaryContainer,
                selectedColor: cs.onSecondaryContainer,
                leading: HobAvatar(hob: hob, size: 28),
                title: Text(hob.displayName, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '@${tagOf(hob)}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                onTap: () => onPick(hob),
              );
            },
          ),
        ),
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

/// Whether a reply shows its time and copy button.
enum _Meta { none, shown, onHover }

class _MessageRow extends StatefulWidget {
  const _MessageRow({
    super.key,
    required this.message,
    required this.meta,
    required this.controller,
  });

  final ChatMessage message;
  final _Meta meta;
  final ChatController controller;

  @override
  State<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<_MessageRow> {
  bool _hover = false;

  /// [child] read as one message, its author first.
  static Widget _spoken(BuildContext context, String who, Widget child) =>
      MergeSemantics(
        child: Semantics(
          label: Strings.of(context).messageFrom(who),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final controller = widget.controller;
    final showMeta =
        widget.meta == _Meta.shown || (widget.meta == _Meta.onHover && _hover);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    switch (message.role) {
      case ChatRole.user when message.system != null:
        return _SystemTurnRow(
          message: message,
          onToggle: () => controller.toggleActivity(message),
        );
      case ChatRole.user when message.scheduledJob != null:
        return _spoken(
          context,
          Strings.of(context).scheduledRun,
          _ScheduledOutputCard(message: message),
        );
      case ChatRole.user:
        // Your side of the conversation: on the right, never full width,
        // the corner nearest the composer a little sharper. A screen
        // reader hears who wrote it first.
        return _spoken(
          context,
          Strings.of(context).you,
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: LayoutBuilder(
              builder: (context, box) => Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (box.maxWidth * 0.82).clamp(0, 620),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.attachments.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: message.text.isEmpty ? 0 : 8,
                            ),
                            child: MessageAttachments(
                              attachments: message.attachments,
                              profile: controller.hob.name,
                            ),
                          ),
                        if (message.text.isNotEmpty)
                          Text.rich(
                            _withMentions(
                              message.text,
                              controller,
                              const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      case ChatRole.assistant:
        final body = Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarkdownBody(
                data: message.text + (message.streaming ? ' ▍' : ''),
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  code: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: HobsTheme.monoFamily,
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
              if (widget.meta != _Meta.none)
                // Keeps its height while hidden, so hovering never moves
                // the messages below.
                Visibility.maintain(
                  visible: showMeta,
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
                          showToast(
                            context,
                            Strings.of(context).copied,
                            icon: Icons.content_copy,
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
        final spoken = _spoken(context, controller.hob.displayName, body);
        if (widget.meta != _Meta.onHover) return spoken;
        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: spoken,
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

/// A quiet chip summarizing consecutive tool calls; tap to expand.
/// A scheduled job's output handed to the Hob: not something the user
/// wrote, so not a bubble on their side. A card across the chat, headed by
/// the job's name; a long output folds until it is opened.
class _ScheduledOutputCard extends StatefulWidget {
  const _ScheduledOutputCard({required this.message});

  final ChatMessage message;

  @override
  State<_ScheduledOutputCard> createState() => _ScheduledOutputCardState();
}

class _ScheduledOutputCardState extends State<_ScheduledOutputCard> {
  static const _foldAt = 600;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final m = widget.message;
    final long = m.text.length > _foldAt;
    final folded = long && !m.expanded;
    final text = folded
        ? '${m.text.substring(0, _foldAt).trimRight()}…'
        : m.text;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  s.scheduledRun,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    m.scheduledJob!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  clockTime(m.time),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.outline,
                  ),
                ),
              ],
            ),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 6),
              MarkdownBody(
                data: text,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ),
            ],
            if (long)
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => setState(() => m.expanded = !m.expanded),
                child: Text(m.expanded ? s.showLess : s.showMore),
              ),
          ],
        ),
      ),
    );
  }
}

/// A turn the gateway wrote in the user's place, as one quiet line that
/// opens on tap: another Hob's message with this Hob's answer to it, or a
/// note that background work finished. Neither is the user's to read
/// first, so neither is a bubble on their side.
class _SystemTurnRow extends StatelessWidget {
  const _SystemTurnRow({required this.message, required this.onToggle});

  final ChatMessage message;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final turn = message.system!;
    final handle = turn.handle;
    final name = handle == null
        ? null
        : context.read<AppState>().hobNamed(handle)?.displayName;
    final sender = name ?? turn.sender;
    final title = turn.title(s, name: name);
    final reply = message.reply;
    final line = [
      title,
      if (turn.kind == SystemTurnKind.agentMessage && reply != null)
        s.withReply
      else if (turn.summary.isNotEmpty)
        turn.summary,
    ].join(' · ');
    final icon = switch (turn.kind) {
      SystemTurnKind.agentMessage => Icons.smart_toy_outlined,
      SystemTurnKind.delegationDone => Icons.task_alt,
      SystemTurnKind.processDone => Icons.terminal,
    };
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodySmall?.copyWith(height: 1.45),
      code: theme.textTheme.bodySmall?.copyWith(
        fontFamily: HobsTheme.monoFamily,
        backgroundColor: cs.surfaceContainerHighest,
      ),
    );

    Widget block(IconData icon, String heading, String body) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: cs.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  heading,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            MarkdownBody(data: body, styleSheet: sheet),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              expanded: message.expanded,
              child: InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: cs.outline),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          line,
                          style: muted,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        message.expanded
                            ? Icons.expand_less
                            : Icons.chevron_right,
                        size: 16,
                        color: cs.outline,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (message.expanded) ...[
              block(icon, title, message.text),
              if (reply != null && reply.isNotEmpty)
                block(
                  Icons.reply,
                  [
                    s.replyTo(sender),
                    if (message.replyTools.isNotEmpty)
                      s.toolCallCount(message.replyTools.length),
                  ].join(' · '),
                  reply,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              expanded: message.expanded,
              label: Strings.of(context).toolsUsed,
              child: InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                      const SizedBox(width: 2),
                      Icon(
                        message.expanded
                            ? Icons.expand_less
                            : Icons.chevron_right,
                        size: 16,
                        color: cs.outline,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (message.expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 0, 4),
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
                                        fontFamily: HobsTheme.monoFamily,
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
    return Semantics(
      liveRegion: true,
      child: Padding(
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
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.chat,
    required this.draft,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ChatController chat;
  final ComposerDraft draft;
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
            DraftStrip(draft: draft),
            Container(
              padding: const EdgeInsets.fromLTRB(0, 2, 4, 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: AttachButton(draft: draft, enabled: canType),
                  ),
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
                        // Android keyboards insert clipboard images and GIFs.
                        contentInsertionConfiguration:
                            ContentInsertionConfiguration(
                              onContentInserted: (content) {
                                final data = content.data;
                                if (data == null || data.isEmpty) return;
                                draft.addImage(
                                  data,
                                  Uri.tryParse(content.uri)
                                          ?.pathSegments
                                          .lastOrNull ??
                                      'pasted-image',
                                  mime: content.mimeType,
                                );
                              },
                            ),
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
                            tooltip: draft.ready ? s.send : s.waitForUploads,
                            onPressed: chat.ready && draft.ready
                                ? onSend
                                : null,
                            icon: const Icon(Icons.arrow_upward, size: 20),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: _ChatSettingsChip(chat: chat, style: chipStyle),
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
    final s = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    void answer(String choice) {
      HapticFeedback.selectionClick();
      controller.answerApproval(choice);
    }

    // Deny and allow-once are the main pair; any other choice the server
    // offers (this chat, always) sits quieter below.
    final more = [
      for (final c in a.choices)
        if (c != 'deny' && c != 'once') c,
    ];
    return PromptCard(
      tone: PromptTone.approval,
      icon: Icons.shield_outlined,
      title: s.approvalTitle(a.toolName),
      subtitle: s.approvalWaiting,
      body: a.description.isEmpty
          ? null
          : Text(a.description, style: Theme.of(context).textTheme.bodyMedium),
      command: a.command,
      actions: [
        if (a.choices.contains('deny'))
          OutlinedButton(
            style: promptButtonStyle().merge(
              OutlinedButton.styleFrom(foregroundColor: cs.error),
            ),
            onPressed: () => answer('deny'),
            child: Text(s.deny),
          ),
        if (a.choices.contains('once'))
          FilledButton(
            style: promptButtonStyle(),
            onPressed: () => answer('once'),
            child: Text(s.allowOnce),
          ),
      ],
      secondary: [
        for (final c in more)
          TextButton(onPressed: () => answer(c), child: Text(_label(s, c))),
      ],
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
    return PromptCard(
      tone: PromptTone.question,
      icon: Icons.help_outline,
      title: s.hobAsks,
      subtitle: s.clarifyWaiting,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final q in qs) ...[
            Text(q.question, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            if (q.choices != null && q.choices!.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final ch in q.choices!)
                    ChoiceChip(
                      label: Text(ch),
                      selected: _answers[q.qid] == ch,
                      side: BorderSide.none,
                      color: WidgetStateProperty.resolveWith(
                        (st) => st.contains(WidgetState.selected)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHigh,
                      ),
                      onSelected: (_) => setState(
                        () =>
                            _answers[q.qid] = _answers[q.qid] == ch ? null : ch,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _text.putIfAbsent(q.qid, TextEditingController.new),
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                isDense: true,
                hintText: (q.choices?.isNotEmpty ?? false)
                    ? s.orOwnAnswer
                    : s.answerHint,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
      actions: [
        OutlinedButton(
          style: promptButtonStyle(),
          onPressed: () => widget.controller.answerClarify(null),
          child: Text(s.skip),
        ),
        FilledButton(
          style: promptButtonStyle(),
          onPressed: _submit,
          child: Text(s.answer),
        ),
      ],
    );
  }
}

/// The chat's settings in one chip under the composer: the model, the
/// reasoning level and the approval mode. Tapping it opens them in a sheet.
/// A model off the Hob's default and approvals turned off stand out.
class _ChatSettingsChip extends StatelessWidget {
  const _ChatSettingsChip({required this.chat, required this.style});

  final ChatController chat;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final unasked = chat.approvalMode == 'off';
    final model = chat.sessionModel?.shortLabel ?? chat.model;
    final effort = _Composer._effortLabels[chat.reasoningEffort];
    final parts = [?model, ?effort];
    return Tooltip(
      message: s.chatSettings,
      child: InkWell(
        key: const ValueKey('chat-settings'),
        borderRadius: BorderRadius.circular(14),
        onTap: chat.ready ? () => showChatSettings(context, chat) : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            border: unasked ? Border.all(color: cs.error) : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _Composer._approvalIcons[chat.approvalMode] ?? Icons.tune,
                size: 14,
                color: unasked ? cs.error : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  parts.isEmpty ? s.chatSettings : parts.join('  ·  '),
                  style: chat.modelOverridden
                      ? style?.copyWith(color: cs.primary)
                      : style,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more, size: 16, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chat's model, reasoning level and approval mode in one sheet. Every
/// choice applies at once; the sheet stays open until dismissed.
Future<void> showChatSettings(BuildContext context, ChatController chat) {
  return showContentSheet<void>(
    context,
    kind: SheetKind.bottom,
    builder: (context) => ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final s = Strings.of(context);
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        final model = chat.sessionModel?.shortLabel ?? chat.model;
        return Padding(
          padding: EdgeInsets.only(
            top: isWideWindow(context) ? 16 : sheetHandleGap - 8,
            bottom: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(s.chatSettings, style: theme.textTheme.titleLarge),
              ),
              if (model != null) ...[
                heading(s.modelLabel),
                ListTile(
                  key: const ValueKey('session-model'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: const Icon(Icons.memory_outlined),
                  title: Text(model, overflow: TextOverflow.ellipsis),
                  subtitle: chat.modelOverridden
                      ? Text(s.sessionModelTag)
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => pickSessionModel(context, chat),
                ),
              ],
              heading(s.reasoningLevel),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final l in ChatController.effortLevels)
                      ChoiceChip(
                        label: Text(_Composer._effortLabels[l] ?? l),
                        selected: chat.reasoningEffort == l,
                        showCheckmark: false,
                        side: BorderSide.none,
                        color: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? cs.primary
                              : cs.surfaceContainerHigh,
                        ),
                        onSelected: (_) => chat.setReasoningEffort(l),
                      ),
                  ],
                ),
              ),
              heading(s.approvalHeading),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(
                  s.approvalScope,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              for (final m in ChatController.approvalModes)
                ListTile(
                  key: m == chat.approvalMode
                      ? const ValueKey('approval-mode')
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: Icon(
                    _Composer._approvalIcons[m],
                    color: m == 'off' ? cs.error : null,
                  ),
                  title: Text(s.approvalModeLabel(m)),
                  subtitle: Text(s.approvalModeHint(m)),
                  trailing: m == chat.approvalMode
                      ? Icon(Icons.check, color: cs.primary)
                      : null,
                  selected: m == chat.approvalMode,
                  onTap: () => chat.setApprovalMode(m),
                ),
            ],
          ),
        );
      },
    ),
  );
}

/// An icon and a label in a popup menu.
class _MenuLine extends StatelessWidget {
  const _MenuLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}
