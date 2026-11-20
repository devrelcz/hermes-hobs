import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/hermes_rpc.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/share_inbox.dart';
import 'hob_avatar.dart';
import 'chat_screen.dart';
import 'format.dart';
import 'settings_screen.dart';
import 'share_target_sheet.dart';
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
    if (wide) {
      setState(() => _selected = hob.name);
      app.setOpenHob(hob.name);
      return;
    }
    app.setOpenHob(hob.name);
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ChatScreen(hob: hob)));
    if (!mounted) return;
    app.setOpenHob(null);
    app.refreshHobs(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    _maybeOfferShare(app);
    return LayoutBuilder(
      builder: (context, c) {
        final wide = _wide = c.maxWidth >= _splitBreakpoint;
        Hob? selected;
        for (final b in app.hobs) {
          if (b.name == _selected) selected = b;
        }
        final list = _HobList(
          selected: wide ? _selected : null,
          onOpen: (b) => _open(b, wide),
        );
        if (!wide) return list;
        return Row(
          children: [
            SizedBox(width: 340, child: list),
            const VerticalDivider(width: 1),
            Expanded(
              child: selected == null
                  ? const _EmptyDetail()
                  : ChatScreen(
                      key: ValueKey(selected.name),
                      hob: selected,
                      embedded: true,
                    ),
            ),
          ],
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
  const _HobList({required this.onOpen, this.selected});

  final void Function(Hob hob) onOpen;
  final String? selected;

  @override
  State<_HobList> createState() => _HobListState();
}

class _HobListState extends State<_HobList> {
  final _search = TextEditingController();

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
    final unread = app.hobs.where(app.isUnread).length;
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.hobsTitle),
            _ConnectionLine(status: app.connection),
          ],
        ),
        actions: [
          _AccountButton(app: app),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: app.setQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: s.searchHobs,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: app.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _search.clear();
                          app.setQuery('');
                        },
                      ),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final (f, label) in _filters(s))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: f == HobFilter.unread && unread > 0
                          ? _CountLabel(label: label, count: unread)
                          : Text(label),
                      selected: app.filter == f,
                      onSelected: (_) => app.setFilter(f),
                      visualDensity: VisualDensity.compact,
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: app.refreshHobs,
              child: _buildBody(app, theme, s, sections),
            ),
          ),
        ],
      ),
    );
  }

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
    if (sections.isEmpty) {
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
          for (final b in sections.expand((s) => s.hobs)) _hobRow(app, b),
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _hobRow(AppState app, Hob b) => _HobRow(
    hob: b,
    selected: b.name == widget.selected,
    unread: app.isUnread(b),
    working: app.isWorking(b),
    onTap: () => widget.onOpen(b),
  );

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
      builder: (_) => _RenameDialog(initial: section.title),
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

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

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
      title: Text(s.renameFolderTitle),
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
          child: Text(s.save),
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
    this.dragIndex,
    this.onRename,
  });

  final String title;
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
            Icon(Icons.folder_outlined, size: 16, color: muted),
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

class _HobRow extends StatelessWidget {
  const _HobRow({
    required this.hob,
    required this.selected,
    required this.unread,
    required this.working,
    required this.onTap,
  });

  final Hob hob;
  final bool selected;
  final bool unread;
  final bool working;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
      child: InkWell(
        onTap: onTap,
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
    final connected = status == ConnectionStatus.connected;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: connected ? theme.colorScheme.onSurfaceVariant : color,
            fontWeight: connected ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
      ],
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
        if (v == 'settings') {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        }
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
      icon: CircleAvatar(
        radius: 16,
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
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }
}
