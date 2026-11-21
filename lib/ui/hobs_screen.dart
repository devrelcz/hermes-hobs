import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
import 'settings_screen.dart';
import 'share_target_sheet.dart';
import 'sheets.dart';
import 'theme.dart';

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

  /// A share from another app: once the Hob list is visible (signed in,
  /// unlocked), ask which Hob gets it and open that chat with it in the
  /// composer.
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
          selected: wide ? _selected : null,
          selectedGroup: wide ? _selectedGroup : null,
          onOpen: (b) => _open(b, wide),
          onOpenGroup: (r) => _openGroup(r, wide),
          onNewGroup: () => _newGroup(wide),
          onNewHob: () => _newHob(wide),
          onDeleted: (hob) {
            if (_selected == hob.name) setState(() => _selected = null);
          },
        );
        if (!wide) return list;
        // Both panes are Scaffolds. Under one outer Scaffold neither is a
        // root one, so a snackbar shows once across the window instead of
        // once in each pane.
        return Scaffold(
          body: Row(
            children: [
              SizedBox(width: 340, child: list),
              const VerticalDivider(width: 1),
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
        );
      },
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              Strings.of(context).pickHob,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
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
  });

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
        toolbarHeight: 64,
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
          preferredSize: const Size.fromHeight(_filterBarHeight + 57),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
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
          onRefresh: app.refreshHobs,
          child: _buildBody(app, theme, s, sections),
        ),
      ),
    );
  }

  static const _filterBarHeight = 44.0;

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
      return const Center(child: CircularProgressIndicator());
    }
    if (app.hobsError != null && app.hobs.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Center(child: Text(app.hobsError!, textAlign: TextAlign.center)),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: app.refreshHobs,
              child: Text(s.retry),
            ),
          ),
        ],
      );
    }
    final hidden = app.hiddenHobs;
    final rooms = app.visibleGroups;
    final groupSection = rooms.isEmpty ? null : _groups(app, rooms);
    if (sections.isEmpty && groupSection == null && hidden.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Center(child: Text(app.hobs.isEmpty ? s.noHobs : s.noMatches)),
        ],
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
    selected: b.name == widget.selected,
    unread: app.isUnread(b),
    working: app.isWorking(b),
    onTap: () => widget.onOpen(b),
    onMenu: (at, mouse) => _hobMenu(app, b, at, mouse: mouse),
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
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _RenameDialog(initial: '', title: s.newFolderTitle, action: s.create),
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
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(
        initial: section.title,
        title: s.renameFolderTitle,
        action: s.save,
      ),
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

/// Asks for a folder name: renaming a folder or naming a new one.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
    required this.initial,
    required this.title,
    required this.action,
  });

  final String initial;
  final String title;
  final String action;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
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
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: s.folderNameLabel),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _name.text),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w600,
    );
    final s = Strings.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final label = InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 14, dragIndex == null ? 16 : 4, 6),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 18,
              color: muted,
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 16, color: muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: style,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (collapsed && unread > 0) ...[
              Icon(
                Icons.circle,
                size: 7,
                color: HobsColors.of(context).lantern,
              ),
              const SizedBox(width: 8),
            ],
            Text('$count', style: style),
          ],
        ),
      ),
    );
    final index = dragIndex;
    if (index == null) return label;
    return Row(
      children: [
        // Holding the header picks the folder up, for touch screens.
        Expanded(
          child: ReorderableDelayedDragStartListener(
            index: index,
            child: label,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: 32,
            height: 24,
            child: PopupMenuButton<void>(
              tooltip: s.folderOptions,
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: Icon(Icons.more_horiz, color: muted),
              itemBuilder: (_) => [
                PopupMenuItem(onTap: onRename, child: Text(s.renameFolder)),
              ],
            ),
          ),
        ),
        ReorderableDragStartListener(
          index: index,
          child: Tooltip(
            message: s.moveFolder,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 10, 0),
                child: Icon(Icons.drag_handle, size: 18, color: muted),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HobRow extends StatefulWidget {
  const _HobRow({
    required this.hob,
    required this.selected,
    required this.unread,
    required this.working,
    required this.onTap,
    required this.onMenu,
  });

  final Hob hob;
  final bool selected;
  final bool unread;
  final bool working;
  final VoidCallback onTap;

  /// Opens the hob's menu at [at] (global). [mouse] for a right-click.
  final void Function(Offset at, bool mouse) onMenu;

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
    return Material(
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
                HobAvatar(hob: hob, size: 38, working: working),
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
                                  : (unread ? cs.primary : cs.outline),
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
                                color: unread
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: HobsColors.of(context).lantern,
                            ),
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
                                : (unread ? cs.primary : cs.outline),
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
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: HobsColors.of(context).lantern,
                          ),
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
      height: _HobListState._filterBarHeight,
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
    return PopupMenuButton<String>(
      tooltip: s.account,
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
      icon: CircleAvatar(
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
