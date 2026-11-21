import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/group_models.dart';
import '../api/hermes_rpc.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/share_inbox.dart';
import 'hob_avatar.dart';
import 'chat_screen.dart';
import 'format.dart';
import 'group_chat_screen.dart';
import 'new_group_sheet.dart';
import 'new_hob_screen.dart';
import 'placeholders.dart';
import 'settings_screen.dart';
import 'share_target_sheet.dart';
import 'sheets.dart';
import 'theme.dart';
import 'welcome_sheet.dart';

/// Hob roster grouped into the user's folders. On wide screens the chat
/// opens beside the list (like the dashboard); on phones it is pushed.
class HobsScreen extends StatefulWidget {
  const HobsScreen({super.key});

  @override
  State<HobsScreen> createState() => _HobsScreenState();
}

class _HobsScreenState extends State<HobsScreen> {
  String? _selected;
  bool _wide = false;

  /// The share last offered, so one share opens the picker once.
  List<SharedItem>? _offeredShare;

  /// Room id of the group chat open beside the list (wide screens).
  String? _selectedGroup;

  static const _splitBreakpoint = 840.0;

  /// Width of the list beside a chat on wide windows: dragged by the line
  /// between them, kept on this device.
  double _paneWidth = 340;
  static const _paneMin = 280.0;
  static const _paneMax = 520.0;
  static const _paneKey = 'listPaneWidth';

  /// The search field, for the keyboard shortcut that jumps into it.
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final w = p.getDouble(_paneKey);
      if (w != null && mounted) {
        setState(() => _paneWidth = w.clamp(_paneMin, _paneMax));
      }
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _savePaneWidth() async =>
      (await SharedPreferences.getInstance()).setDouble(_paneKey, _paneWidth);

  /// ⌘ on Apple keyboards, Ctrl elsewhere.
  static SingleActivator _shortcut(LogicalKeyboardKey key) {
    final apple = switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => true,
      _ => false,
    };
    return SingleActivator(key, meta: apple, control: !apple);
  }

  /// A share from another app: once the Hob list is visible (signed in,
  /// unlocked), ask which Hob gets it and open that chat with it in the
  /// composer.
  bool _welcomeChecked = false;

  /// A share is waiting for its Hob (or was just offered).
  bool get _sharePending {
    try {
      return context.read<ShareInbox>().pending != null;
    } on ProviderNotFoundException {
      return false;
    }
  }

  /// The first time a signed-in list has loaded on this device.
  void _maybeWelcome(AppState app) {
    // Not over something the user came for: a share to place, a chat a
    // notification opens.
    if (_welcomeChecked ||
        app.phase != AuthPhase.signedIn ||
        app.locked ||
        app.loadingHobs ||
        app.pendingChat != null ||
        app.pendingGroup != null ||
        _sharePending) {
      return;
    }
    _welcomeChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowWelcome(context, app.hobs);
    });
  }

  void _maybeOfferShare(AppState app) {
    ShareInbox? inbox;
    try {
      inbox = context.watch<ShareInbox>();
    } on ProviderNotFoundException {
      return;
    }
    final items = inbox.pending;
    if (items == null || app.locked || identical(items, _offeredShare)) {
      return;
    }
    _offeredShare = items;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _offerShare(inbox!, items),
    );
  }

  Future<void> _offerShare(ShareInbox inbox, List<SharedItem> items) async {
    if (!mounted) return;
    final app = context.read<AppState>();
    Navigator.of(context).popUntil((r) => r.isFirst);
    final hob = await showShareTargetSheet(context, items);
    if (!mounted) return;
    if (hob == null) {
      inbox.dismiss();
      return;
    }
    await inbox.deliverTo(app.draftFor(hob));
    if (mounted) unawaited(_open(hob, _wide));
  }

  Future<void> _open(Hob hob, bool wide) async {
    final app = context.read<AppState>();
    app.setOpenGroup(null);
    if (wide) {
      setState(() {
        _selected = hob.name;
        _selectedGroup = null;
      });
      app.setOpenHob(hob.name);
      return;
    }
    app.setOpenHob(hob.name);
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ChatScreen(hob: hob)));
    if (!mounted) return;
    // A notification may have replaced this chat with another one already.
    if (app.openHob == hob.name) app.setOpenHob(null);
    app.refreshHobs(silent: true);
  }

  bool _openingPending = false;

  /// A tapped notification: once the lock is gone and the hob (or group) is
  /// known, show its chat on top of the list (closing whatever was open above
  /// it).
  void _openPending(bool wide) {
    if (_openingPending) return;
    _openingPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openingPending = false;
      if (!mounted) return;
      final app = context.read<AppState>();
      final hob = app.takePendingChat();
      if (hob != null) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        _open(hob, wide);
        return;
      }
      final room = app.takePendingGroup();
      if (room == null) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      _openGroup(room, wide);
    });
  }

  Future<void> _openGroup(GroupRoom room, bool wide) async {
    final app = context.read<AppState>();
    app.setOpenHob(null);
    app.setOpenGroup(room.roomId);
    if (wide) {
      setState(() {
        _selectedGroup = room.roomId;
        _selected = null;
      });
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => GroupChatScreen(room: room)));
    if (!mounted) return;
    // A notification may have replaced this group with another chat already.
    if (app.openGroup == room.roomId) app.setOpenGroup(null);
  }

  Future<void> _newGroup(bool wide) async {
    final room = await showNewGroupDialog(context);
    if (room == null || !mounted) return;
    await _openGroup(room, wide);
  }

  Future<void> _newHob(bool wide) async {
    final s = Strings.of(context);
    final hob = await NewHobScreen.open(context);
    if (hob == null || !mounted) return;
    if (mounted) showToast(context, s.hobCreated(hob.displayName));
    await _open(hob, wide);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    _maybeOfferShare(app);
    _maybeWelcome(app);
    return LayoutBuilder(
      builder: (context, c) {
        final wide = _wide = c.maxWidth >= _splitBreakpoint;
        if ((app.pendingChat != null || app.pendingGroup != null) &&
            !app.locked) {
          _openPending(wide);
        }
        // Hidden hobs stay open too: they can be opened from their group.
        final name = _selected;
        final selected = name == null ? null : app.hobNamed(name);
        final group = _selectedGroup == null
            ? null
            : app.groupById(_selectedGroup!);
        final list = _HobList(
          searchFocus: _searchFocus,
          selected: wide ? _selected : null,
          heroes: !wide,
          selectedGroup: wide ? _selectedGroup : null,
          onOpen: (b) => _open(b, wide),
          onOpenGroup: (r) => _openGroup(r, wide),
          onNewGroup: () => _newGroup(wide),
          onNewHob: () => _newHob(wide),
          onDeleted: (hob) {
            if (_selected == hob.name) setState(() => _selected = null);
          },
        );
        // Keyboard: new Hob, find, settings. Over both panes, so they work
        // with the cursor in a chat too.
        Widget keys(Widget child) => CallbackShortcuts(
          bindings: {
            _shortcut(LogicalKeyboardKey.keyN): () => _newHob(wide),
            _shortcut(LogicalKeyboardKey.keyK): _searchFocus.requestFocus,
            _shortcut(LogicalKeyboardKey.comma): () =>
                SettingsScreen.open(context),
          },
          child: Focus(autofocus: true, child: child),
        );
        if (!wide) return keys(list);
        final pane = _paneWidth.clamp(
          _paneMin,
          (c.maxWidth - 360).clamp(_paneMin, _paneMax),
        );
        // Both panes are Scaffolds. Under one outer Scaffold neither is a
        // root one, so a snackbar shows once across the window instead of
        // once in each pane.
        return keys(
          Scaffold(
            body: Row(
              children: [
                SizedBox(width: pane, child: list),
                _PaneDivider(
                  onDrag: (dx) => setState(
                    () => _paneWidth = (pane + dx).clamp(_paneMin, _paneMax),
                  ),
                  onDone: _savePaneWidth,
                ),
                Expanded(
                  child: group != null
                      ? GroupChatScreen(
                          key: ValueKey('group:${group.roomId}'),
                          room: group,
                          embedded: true,
                          onClosed: () => setState(() => _selectedGroup = null),
                        )
                      : selected == null
                      ? const _EmptyDetail()
                      : ChatScreen(
                          key: ValueKey(selected.name),
                          hob: selected,
                          embedded: true,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The line between the list and the chat. Dragging it (mouse or finger)
/// resizes the list; it shows a resize cursor and thickens under the
/// pointer.
class _PaneDivider extends StatefulWidget {
  const _PaneDivider({required this.onDrag, required this.onDone});

  final ValueChanged<double> onDrag;
  final VoidCallback onDone;

  @override
  State<_PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<_PaneDivider> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: Strings.of(context).resizeList,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _active = true),
        onExit: (_) => setState(() => _active = false),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => setState(() => _active = true),
          onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
          onHorizontalDragEnd: (_) {
            setState(() => _active = false);
            widget.onDone();
          },
          // A wide grab area around a one-point line.
          child: SizedBox(
            width: 9,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: _active ? 3 : 1,
                color: _active ? cs.primary : cs.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The right pane of a wide window before a chat is picked: a few of the
/// user's own Hobs, waiting.
class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = Strings.of(context);
    final faces = app.hobs.where((b) => !b.hidden).take(3).toList();
    return Scaffold(
      body: EmptyState(
        art: faces.isEmpty
            ? const EmptyArt(icon: Icons.forum_outlined)
            : GroupAvatars(hobs: faces, size: 72),
        title: s.pickHob,
        body: s.pickHobHint,
      ),
    );
  }
}

class _HobList extends StatefulWidget {
  const _HobList({
    required this.onOpen,
    required this.onOpenGroup,
    required this.onNewGroup,
    required this.onNewHob,
    this.onDeleted,
    this.selected,
    this.selectedGroup,
    this.heroes = false,
    this.searchFocus,
  });

  /// The search field's focus, owned by the screen for ⌘K.
  final FocusNode? searchFocus;

  /// Faces fly into the chat's header: only when the chat opens over the
  /// list, never beside it.
  final bool heroes;

  final void Function(Hob hob) onOpen;

  /// After [hob] was deleted on the server.
  final void Function(Hob hob)? onDeleted;
  final void Function(GroupRoom room) onOpenGroup;
  final VoidCallback onNewGroup;
  final VoidCallback onNewHob;
  final String? selected;
  final String? selectedGroup;

  @override
  State<_HobList> createState() => _HobListState();
}

class _HobListState extends State<_HobList> {
  final _search = TextEditingController();

  /// The list sits under the bar: a hairline marks where the bar ends.
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _search.text = context.read<AppState>().query;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static List<(HobFilter, String)> _filters(Strings s) => [
    (HobFilter.all, s.filterAll),
    (HobFilter.unread, s.filterUnread),
    (HobFilter.pinned, s.filterPinned),
    (HobFilter.active, s.filterActive),
    (HobFilter.recent, s.filterRecent),
    (HobFilter.older, s.filterOlder),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final s = Strings.of(context);
    final sections = app.sections;
    final unread =
        app.hobs.where(app.isUnread).length +
        app.groups.where(app.isGroupUnread).length;
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 20,
        // Title and status line; grows with large system text.
        toolbarHeight: textBarHeight(context, text: 44, rest: 20),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.hobsTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            _ConnectionLine(status: app.connection),
          ],
        ),
        actions: [
          _NewButton(
            groups: app.groupsSupported == true,
            onNewHob: widget.onNewHob,
            onNewGroup: widget.onNewGroup,
          ),
          const SizedBox(width: 8),
          _AccountButton(app: app),
          const SizedBox(width: 12),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(
            _searchHeight(context) + _filterBarHeight(context) + 1,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  focusNode: widget.searchFocus,
                  onChanged: app.setQuery,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: s.searchHobs,
                    hintStyle: TextStyle(color: cs.onSurfaceVariant),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    suffixIcon: app.query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: s.clearSearch,
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _search.clear();
                              app.setQuery('');
                            },
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: cs.surfaceContainerHigh,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    // Flat until focused: the field reads as part of the
                    // bar, not as a form.
                    border: _flatField,
                    enabledBorder: _flatField,
                    focusedBorder: _flatField.copyWith(
                      borderSide: BorderSide(color: cs.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
              _FilterBar(
                filters: _filters(s),
                selected: app.filter,
                unread: unread,
                onSelected: app.setFilter,
              ),
              _ScrollEdge(visible: _scrolled),
            ],
          ),
        ),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
            final scrolled = n.metrics.pixels > 0.5;
            if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
          }
          return false;
        },
        child: RefreshIndicator(
          onRefresh: () {
            HapticFeedback.selectionClick();
            return app.refreshHobs();
          },
          child: _buildBody(app, theme, s, sections),
        ),
      ),
    );
  }

  /// The search field with its margins, and the chip row: both hold a
  /// line of text that grows with the system text size.
  static double _searchHeight(BuildContext context) =>
      textBarHeight(context, text: 20, rest: 36);
  static double _filterBarHeight(BuildContext context) =>
      textBarHeight(context, text: 20, rest: 24);

  static final _flatField = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide.none,
  );

  Widget _buildBody(
    AppState app,
    ThemeData theme,
    Strings s,
    List<HobSection> sections,
  ) {
    if (app.loadingHobs && app.hobs.isEmpty) {
      return const HobListSkeleton();
    }
    if (app.hobsError != null && app.hobs.isEmpty) {
      return EmptyState(
        art: const EmptyArt(icon: Icons.cloud_off_outlined, error: true),
        title: s.hobsLoadFailed,
        body: app.hobsError,
        action: OutlinedButton(
          onPressed: app.refreshHobs,
          child: Text(s.retry),
        ),
      );
    }
    final hidden = app.hiddenHobs;
    final rooms = app.visibleGroups;
    final groupSection = rooms.isEmpty ? null : _groups(app, rooms);
    if (sections.isEmpty && groupSection == null && hidden.isEmpty) {
      if (app.hobs.isEmpty) {
        return EmptyState(
          art: HobAvatar(
            hob: Hob(
              name: 'hob',
              displayName: 'Hob',
              shape: HobAvatar.blobShape('hello', null),
            ),
            size: 72,
          ),
          title: s.noHobsTitle,
          body: s.noHobs,
          action: FilledButton.icon(
            onPressed: widget.onNewHob,
            icon: const Icon(Icons.add),
            label: Text(s.newHob),
          ),
        );
      }
      return EmptyState(
        art: const EmptyArt(icon: Icons.search_off),
        title: s.noMatches,
        action: TextButton(
          onPressed: () {
            _search.clear();
            app.setQuery('');
            app.setFilter(HobFilter.all);
          },
          child: Text(s.showAllHobs),
        ),
      );
    }
    if (!app.hasFolders) {
      return ListView(
        children: [
          ?groupSection,
          if (groupSection != null && sections.isNotEmpty)
            _SectionHeader(
              title: s.unassigned,
              count: sections.expand((s) => s.hobs).length,
              collapsed: false,
              unread: 0,
              onTap: () {},
            ),
          for (final b in sections.expand((s) => s.hobs)) _hobRow(app, b),
          _hiddenGroup(app, hidden),
          const SizedBox(height: 24),
        ],
      );
    }
    // Folders are the draggable items; "unassigned" always stays last.
    final folders = [
      for (final s in sections)
        if (s.key != HobSection.unassignedKey) s,
    ];
    final rest = [
      for (final s in sections)
        if (s.key == HobSection.unassignedKey) s,
    ];
    return ReorderableListView.builder(
      onReorderStart: (_) => HapticFeedback.selectionClick(),
      header: groupSection,
      buildDefaultDragHandles: false,
      itemCount: folders.length,
      onReorderItem: (from, to) {
        final others = [...folders]..removeAt(from);
        app.moveSection(
          folders[from].key,
          before: to < others.length ? others[to].key : null,
        );
      },
      proxyDecorator: (child, _, _) => Material(
        elevation: 6,
        color: theme.colorScheme.surface,
        child: child,
      ),
      itemBuilder: (context, i) => KeyedSubtree(
        key: ValueKey(folders[i].key),
        child: _section(app, folders[i], dragIndex: i),
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in rest) _section(app, s),
          _hiddenGroup(app, hidden),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// The group chats' folder: rooms newest first, collapsible like the rest.
  Widget _groups(AppState app, List<GroupRoom> rooms) {
    const key = HobSection.groupsKey;
    final isCollapsed = app.collapsed.contains(key) && app.query.isEmpty;
    final s = Strings.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionHeader(
          title: s.groupChats,
          icon: Icons.forum_outlined,
          count: rooms.length,
          collapsed: isCollapsed,
          unread: rooms.where(app.isGroupUnread).length,
          onTap: () => app.toggleSection(key),
        ),
        if (!isCollapsed)
          for (final r in rooms)
            _GroupRow(
              room: r,
              hobs: [for (final m in r.members) app.memberHob(m)],
              preview: app.groupPreview(r),
              lastActive: app.groupLastActive(r),
              selected: r.roomId == widget.selectedGroup,
              unread: app.isGroupUnread(r),
              working: app.isGroupWorking(r),
              onTap: () => widget.onOpenGroup(r),
            ),
      ],
    );
  }

  Widget _hobRow(AppState app, Hob b) => _HobRow(
    hob: b,
    hero: widget.heroes,
    selected: b.name == widget.selected,
    unread: app.isUnread(b),
    working: app.isWorking(b),
    onTap: () => widget.onOpen(b),
    onMenu: (at, mouse) => _hobMenu(app, b, at, mouse: mouse),
    onSwipePin: () => _change(() => app.setHobPinned(b, !b.pinned)),
    onSwipeHide: () => _setHidden(app, b, !b.hidden),
  );

  /// Hidden hobs in one closed group at the end, the dashboard's way back to
  /// them. A search opens it.
  Widget _hiddenGroup(AppState app, List<Hob> hidden) {
    if (hidden.isEmpty) return const SizedBox.shrink();
    final open = app.hiddenExpanded || app.query.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionHeader(
          title: Strings.of(context).hiddenHobs,
          icon: Icons.visibility_off_outlined,
          count: hidden.length,
          collapsed: !open,
          unread: hidden.where(app.isUnread).length,
          onTap: app.toggleHidden,
        ),
        if (open)
          for (final b in hidden) _hobRow(app, b),
      ],
    );
  }

  /// Pin, hide, move and delete: what a long-press (or right-click) on a hob
  /// offers, in a popover at the finger or pointer on every screen size.
  Future<void> _hobMenu(
    AppState app,
    Hob hob,
    Offset at, {
    required bool mouse,
  }) async {
    final s = Strings.of(context);
    final error = Theme.of(context).colorScheme.error;
    final actions = [
      (
        _HobAction.pin,
        hob.pinned ? Icons.push_pin : Icons.push_pin_outlined,
        hob.pinned ? s.unpinHob : s.pinHob,
      ),
      (
        _HobAction.hide,
        hob.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        hob.hidden ? s.unhideHob : s.hideHob,
      ),
      (_HobAction.move, Icons.drive_file_move_outlined, s.moveToFolder),
    ];
    final action = await showMenu<_HobAction>(
      context: context,
      position: _menuPosition(at),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        for (final (value, icon, label) in actions)
          PopupMenuItem(
            value: value,
            child: _MenuRow(icon: icon, label: label),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _HobAction.delete,
          child: _MenuRow(
            icon: Icons.delete_outline,
            label: s.deleteHob,
            color: error,
          ),
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _HobAction.pin:
        await _change(() => app.setHobPinned(hob, !hob.pinned));
      case _HobAction.hide:
        await _setHidden(app, hob, !hob.hidden);
      case _HobAction.move:
        await _moveToFolder(app, hob, at);
      case _HobAction.delete:
        await _delete(app, hob);
    }
  }

  /// Asks in a bottom sheet, then deletes the hob on the server. Its chat,
  /// if open beside the list, closes with it.
  Future<void> _delete(AppState app, Hob hob) async {
    final s = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showConfirmSheet(
      context,
      icon: Icons.delete_outline,
      title: s.deleteHobTitle(hob.displayName),
      message: s.deleteHobMessage,
      confirmLabel: s.deleteHob,
      cancelLabel: s.cancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await app.deleteHob(hob);
      HapticFeedback.lightImpact();
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(s.hobDeleteFailed(AppState.describeError(e)))),
        );
      return;
    }
    widget.onDeleted?.call(hob);
    if (mounted) showToast(context, s.hobDeleted(hob.displayName));
  }

  RelativeRect _menuPosition(Offset at) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    return RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size);
  }

  /// Runs a hob change. The list already shows it; when the server refuses,
  /// the hob goes back and a snackbar says so.
  Future<bool> _change(Future<void> Function() write) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = Strings.of(context).hobChangeFailed;
    try {
      await write();
      return true;
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failed)));
      return false;
    }
  }

  /// Hiding takes the hob out of sight, so the snackbar offers to undo it.
  Future<void> _setHidden(AppState app, Hob hob, bool hidden) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = Strings.of(context);
    if (hidden) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(s.hobHidden(hob.displayName)),
            action: SnackBarAction(
              label: s.undo,
              onPressed: () => _change(() => app.setHobHidden(hob, false)),
            ),
          ),
        );
    }
    await _change(() => app.setHobHidden(hob, hidden));
  }

  /// Picks a folder for [hob]: an existing one, none, or a new one by name.
  Future<void> _moveToFolder(AppState app, Hob hob, Offset at) async {
    final s = Strings.of(context);
    final folders = app.folders;
    final choices = <(_FolderChoice, IconData, String)>[
      for (final f in folders)
        (
          _FolderChoice(id: f.id, name: f.name),
          f.id == hob.sectionId ? Icons.folder : Icons.folder_outlined,
          f.name,
        ),
      if (hob.sectionId != null)
        (
          const _FolderChoice(id: null),
          Icons.inbox_outlined,
          s.removeFromFolder,
        ),
      (
        const _FolderChoice.create(),
        Icons.create_new_folder_outlined,
        s.newFolder,
      ),
    ];
    bool current(_FolderChoice c) => c.id != null && c.id == hob.sectionId;
    final choice = await showMenu<_FolderChoice>(
      context: context,
      position: _menuPosition(at),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        for (final (value, icon, label) in choices)
          PopupMenuItem(
            value: value,
            enabled: !current(value),
            child: _MenuRow(icon: icon, label: label),
          ),
      ],
    );
    if (choice == null || !mounted) return;
    if (!choice.create) {
      await _change(() => app.moveHobToFolder(hob, choice.id, choice.name));
      return;
    }
    final name = await showTextSheet(
      context,
      title: s.newFolderTitle,
      label: s.folderNameLabel,
      action: s.create,
      cancel: s.cancel,
      maxLength: 60,
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    await _change(() => app.moveHobToNewFolder(hob, name));
  }

  /// One folder: its header and, unless collapsed, its hobs. [dragIndex] is
  /// set for folders the user can drag to a new place and rename.
  Widget _section(AppState app, HobSection s, {int? dragIndex}) {
    final isCollapsed = app.collapsed.contains(s.key) && app.query.isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionHeader(
          title: s.title,
          count: s.hobs.length,
          collapsed: isCollapsed,
          unread: s.hobs.where(app.isUnread).length,
          onTap: () => app.toggleSection(s.key),
          dragIndex: dragIndex,
          onRename: dragIndex == null ? null : () => _renameSection(app, s),
        ),
        if (!isCollapsed)
          for (final b in s.hobs) _hobRow(app, b),
      ],
    );
  }

  Future<void> _renameSection(AppState app, HobSection section) async {
    final s = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = await showTextSheet(
      context,
      title: s.renameFolderTitle,
      label: s.folderNameLabel,
      initial: section.title,
      action: s.save,
      cancel: s.cancel,
      maxLength: 60,
    );
    if (name == null || name.trim().isEmpty || name.trim() == section.title) {
      return;
    }
    try {
      await app.renameSection(section.key, name);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.renameFolderFailed)));
    }
  }
}

enum _HobAction { pin, hide, move, delete }

/// A target of "Move to folder": folder [id] (null takes the hob out of its
/// folder), or a new folder the user names next.
class _FolderChoice {
  const _FolderChoice({required this.id, this.name}) : create = false;
  const _FolderChoice.create() : id = null, name = null, create = true;

  final String? id;
  final String? name;
  final bool create;
}

/// A folder's title row. Holding it picks the folder up to reorder it; the
/// folder menu and the drag handle appear only under a mouse pointer, so a
/// phone shows just the name and the count.
class _SectionHeader extends StatefulWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.collapsed,
    required this.unread,
    required this.onTap,
    this.icon = Icons.folder_outlined,
    this.dragIndex,
    this.onRename,
  });

  final String title;
  final IconData icon;
  final int count;
  final bool collapsed;
  final int unread;
  final VoidCallback onTap;

  /// Position among the draggable folders; null for a fixed header.
  final int? dragIndex;
  final VoidCallback? onRename;

  @override
  State<_SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends State<_SectionHeader> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = cs.onSurfaceVariant;
    final s = Strings.of(context);
    final index = w.dragIndex;
    final label = Semantics(
      header: true,
      expanded: !w.collapsed,
      child: InkWell(
        onTap: w.onTap,
        onSecondaryTap: w.onRename,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, index == null ? 16 : 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  w.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (w.collapsed && w.unread > 0) ...[
                _UnreadMark(color: HobsColors.of(context).lantern),
                const SizedBox(width: 8),
              ],
              Text(
                '${w.count}',
                style: theme.textTheme.labelMedium?.copyWith(color: muted),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: w.collapsed ? -0.25 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                child: Icon(Icons.expand_more, size: 18, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
    if (index == null) return label;
    return MouseRegion(
      onEnter: (e) {
        if (e.kind == PointerDeviceKind.mouse) setState(() => _hover = true);
      },
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        children: [
          // Holding the header picks the folder up, for touch screens.
          Expanded(
            child: ReorderableDelayedDragStartListener(
              index: index,
              child: label,
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 10, right: _hover ? 0 : 8),
            child: SizedBox(
              width: 32,
              height: 28,
              child: PopupMenuButton<void>(
                tooltip: s.folderOptions,
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: Icon(Icons.more_horiz, color: cs.outline),
                itemBuilder: (_) => [
                  PopupMenuItem(onTap: w.onRename, child: Text(s.renameFolder)),
                ],
              ),
            ),
          ),
          // The drag handle is for a mouse; fingers hold the header.
          if (_hover)
            ReorderableDragStartListener(
              index: index,
              child: Tooltip(
                message: s.moveFolder,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 10, 12, 0),
                    child: Icon(Icons.drag_handle, size: 18, color: muted),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The one mark of something unread: a small lantern dot.
class _UnreadMark extends StatelessWidget {
  const _UnreadMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _HobRow extends StatefulWidget {
  const _HobRow({
    required this.hob,
    this.hero = false,
    required this.selected,
    required this.unread,
    required this.working,
    required this.onTap,
    required this.onMenu,
    this.onSwipePin,
    this.onSwipeHide,
  });

  final Hob hob;
  final bool hero;
  final bool selected;
  final bool unread;
  final bool working;
  final VoidCallback onTap;

  /// Opens the hob's menu at [at] (global). [mouse] for a right-click.
  final void Function(Offset at, bool mouse) onMenu;

  /// Swiping the row right pins (or unpins) it; left hides (or shows) it.
  final VoidCallback? onSwipePin;
  final VoidCallback? onSwipeHide;

  @override
  State<_HobRow> createState() => _HobRowState();
}

class _HobRowState extends State<_HobRow> {
  /// Where the finger went down, so the menu opens under it.
  Offset? _down;

  @override
  Widget build(BuildContext context) {
    final hob = widget.hob;
    final selected = widget.selected;
    final unread = widget.unread;
    final working = widget.working;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final preview = plainPreview(
      hob.preview.isNotEmpty ? hob.preview : hob.description,
    );
    final row = Material(
      color: selected
          ? cs.secondaryContainer.withValues(alpha: 0.6)
          : Colors.transparent,
      child: Listener(
        onPointerDown: (e) => _down = e.position,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            final box = context.findRenderObject() as RenderBox?;
            widget.onMenu(
              _down ??
                  box?.localToGlobal(box.size.center(Offset.zero)) ??
                  Offset.zero,
              false,
            );
          },
          onSecondaryTapUp: (d) => widget.onMenu(d.globalPosition, true),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                HobHero(
                  name: hob.name,
                  enabled: widget.hero,
                  child: HobAvatar(hob: hob, size: 38, working: working),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    hob.displayName,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: unread
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (hob.pinned) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.push_pin_outlined,
                                    size: 13,
                                    color: cs.outline,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            working ? s.working : relativeAge(hob.lastActive),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: working
                                  ? HobsColors.of(context).working
                                  : cs.outline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              preview.isEmpty ? s.noMessagesYet : preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: preview.isEmpty
                                    ? cs.outline
                                    : unread
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                                fontStyle: preview.isEmpty
                                    ? FontStyle.italic
                                    : null,
                              ),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 8),
                            _UnreadMark(color: HobsColors.of(context).lantern),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final pin = widget.onSwipePin;
    final hide = widget.onSwipeHide;
    // One stop for a screen reader: who, its state, the latest line; tap
    // opens the chat, and the swipe actions are offered as actions.
    final spoken = Semantics(
      container: true,
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: [
        hob.displayName,
        if (hob.pinned) s.a11yPinned,
        if (unread) s.a11yUnread,
        if (working) s.working else relativeAge(hob.lastActive),
        preview.isEmpty ? s.noMessagesYet : preview,
      ].where((p) => p.isNotEmpty).join(', '),
      onTap: widget.onTap,
      customSemanticsActions: {
        CustomSemanticsAction(label: hob.pinned ? s.unpinHob : s.pinHob): ?pin,
        CustomSemanticsAction(label: hob.hidden ? s.unhideHob : s.hideHob):
            ?hide,
      },
      child: row,
    );
    if (pin == null || hide == null || _pointerPlatform) return spoken;
    // Phones and tablets: a swipe is the quick way to pin or hide. The row
    // springs back; the list reorders itself after the change.
    return Dismissible(
      key: ValueKey('swipe-${hob.name}'),
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.3,
        DismissDirection.endToStart: 0.3,
      },
      confirmDismiss: (direction) async {
        HapticFeedback.selectionClick();
        direction == DismissDirection.startToEnd ? pin() : hide();
        return false;
      },
      background: _SwipeAction(
        alignment: Alignment.centerLeft,
        color: cs.primaryContainer,
        foreground: cs.onPrimaryContainer,
        icon: hob.pinned ? Icons.push_pin : Icons.push_pin_outlined,
        label: hob.pinned ? s.unpinHob : s.pinHob,
      ),
      secondaryBackground: _SwipeAction(
        alignment: Alignment.centerRight,
        color: cs.surfaceContainerHighest,
        foreground: cs.onSurface,
        icon: hob.hidden
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
        label: hob.hidden ? s.unhideHob : s.hideHob,
      ),
      child: spoken,
    );
  }

  static bool get _pointerPlatform => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };
}

/// What a swipe on a Hob row will do, shown under the row as it slides.
class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.alignment,
    required this.color,
    required this.foreground,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final Color foreground;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final left = alignment == Alignment.centerLeft;
    return ColoredBox(
      color: color,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (left) Icon(icon, color: foreground, size: 20),
              if (left) const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: foreground),
              ),
              if (!left) const SizedBox(width: 8),
              if (!left) Icon(icon, color: foreground, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// One group chat in the list: the members' faces, the room name, and the
/// newest message once the app has the room open.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.room,
    required this.hobs,
    required this.preview,
    required this.lastActive,
    required this.selected,
    required this.unread,
    required this.working,
    required this.onTap,
  });

  final GroupRoom room;
  final List<Hob> hobs;
  final String? preview;
  final DateTime? lastActive;
  final bool selected;
  final bool unread;
  final bool working;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final line = preview == null
        ? '${s.groupMembers(room.members.length)} · '
              '${hobs.map((b) => b.displayName).join(', ')}'
        : plainPreview(preview!);
    return Material(
      color: selected
          ? cs.secondaryContainer.withValues(alpha: 0.6)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              GroupAvatars(hobs: hobs, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            room.name.isEmpty ? s.groupChats : room.name,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          working ? s.working : relativeAge(lastActive),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: working
                                ? HobsColors.of(context).working
                                : cs.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: unread
                                  ? cs.onSurface
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          _UnreadMark(color: HobsColors.of(context).lantern),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The connection state in words under the screen title, so the colored
/// mark never has to be decoded on its own.
class _ConnectionLine extends StatelessWidget {
  const _ConnectionLine({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hobs = HobsColors.of(context);
    final s = Strings.of(context);
    final (color, label) = switch (status) {
      ConnectionStatus.connected => (hobs.working, s.connected),
      ConnectionStatus.connecting => (hobs.lantern, s.connecting),
      ConnectionStatus.disconnected => (
        theme.colorScheme.error,
        s.disconnected,
      ),
    };
    // Connected is the normal state and needs no words; the line only
    // shows up when something is off, and slides away once it is fixed.
    final connected = status == ConnectionStatus.connected;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: connected
          ? const SizedBox(width: 0, height: 0)
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    status == ConnectionStatus.connecting
                        ? Icons.sync
                        : Icons.cloud_off_outlined,
                    size: 14,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// One "+" for everything that can be created from the list. Without group
/// chats on the server it goes straight to a new Hob.
class _NewButton extends StatelessWidget {
  const _NewButton({
    required this.groups,
    required this.onNewHob,
    required this.onNewGroup,
  });

  final bool groups;
  final VoidCallback onNewHob;
  final VoidCallback onNewGroup;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = Strings.of(context);
    final style = IconButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      fixedSize: const Size.square(40),
    );
    if (!groups) {
      return IconButton(
        tooltip: s.newHob,
        onPressed: onNewHob,
        style: style,
        icon: const Icon(Icons.add),
      );
    }
    return PopupMenuButton<String>(
      tooltip: s.create,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      style: style,
      icon: const Icon(Icons.add),
      onSelected: (v) => v == 'group' ? onNewGroup() : onNewHob(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'hob',
          child: _MenuRow(icon: Icons.person_add_alt_outlined, label: s.newHob),
        ),
        PopupMenuItem(
          value: 'group',
          child: _MenuRow(icon: Icons.forum_outlined, label: s.newGroupChat),
        ),
      ],
    );
  }
}

/// Filter pills: flat and quiet, the picked one in moss. The row fades out
/// at the right edge so it is clear there is more to scroll to.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.selected,
    required this.unread,
    required this.onSelected,
  });

  final List<(HobFilter, String)> filters;
  final HobFilter selected;
  final int unread;
  final ValueChanged<HobFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: _HobListState._filterBarHeight(context),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          colors: const [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 1 - 28 / rect.width.clamp(28, double.infinity), 1],
        ).createShader(rect),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 2, 28, 10),
          children: [
            for (final (f, label) in filters)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _filterChip(theme, cs, f, label),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(ThemeData theme, ColorScheme cs, HobFilter f, String l) {
    final on = f == selected;
    return ChoiceChip(
      label: f == HobFilter.unread && unread > 0
          ? _CountLabel(label: l, count: unread)
          : Text(l),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: on ? cs.onPrimary : cs.onSurfaceVariant,
        fontWeight: on ? FontWeight.w600 : FontWeight.w500,
      ),
      selected: on,
      onSelected: (_) => onSelected(f),
      side: BorderSide.none,
      color: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? cs.primary
            : cs.surfaceContainerHigh,
      ),
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      showCheckmark: false,
    );
  }
}

/// Hairline under the bar, shown only while the list is scrolled under it.
class _ScrollEdge extends StatelessWidget {
  const _ScrollEdge({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

/// Filter chip label with the number of waiting hobs next to it.
class _CountLabel extends StatelessWidget {
  const _CountLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 6),
        Container(
          constraints: const BoxConstraints(minWidth: 20),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: cs.tertiaryContainer,
          ),
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onTertiaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// The signed-in user's initial. Opens the account menu, where every action
/// carries its own icon and label.
class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final name = app.username.trim();
    final host = Uri.tryParse(app.serverUrl)?.host ?? '';
    // The connection's state as a dot on the avatar, always there: green
    // when connected, lantern while connecting, red when cut off.
    final hobs = HobsColors.of(context);
    final (dot, state) = switch (app.connection) {
      ConnectionStatus.connected => (hobs.working, s.connected),
      ConnectionStatus.connecting => (hobs.lantern, s.connecting),
      ConnectionStatus.disconnected => (cs.error, s.disconnected),
    };
    return PopupMenuButton<String>(
      tooltip: '${s.account}: $state',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (v) {
        if (v == 'logout') app.logout();
        if (v == 'settings') SettingsScreen.open(context);
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.onSurface,
                ),
              ),
              Text(
                host.isEmpty ? app.serverUrl : host,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    state,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'settings',
          child: _MenuRow(icon: Icons.settings_outlined, label: s.settings),
        ),
        PopupMenuItem(
          value: 'logout',
          child: _MenuRow(icon: Icons.logout, label: s.signOut),
        ),
      ],
      padding: EdgeInsets.zero,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
            child: name.isEmpty
                ? const Icon(Icons.person_outline, size: 18)
                : Text(
                    name.characters.first.toUpperCase(),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: AnimatedContainer(
              key: const ValueKey('connection-dot'),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                // A ring in the bar's color keeps it apart from the avatar.
                border: Border.all(
                  color: theme.scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;

  /// For a destructive item (Delete).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        // Folder names can be long: never wider than the menu.
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}
