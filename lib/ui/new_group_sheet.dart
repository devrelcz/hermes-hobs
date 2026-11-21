import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/group_models.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'group_chat_screen.dart' show GroupAvatars;
import 'hob_avatar.dart';
import 'sheets.dart';

/// Picks two to six Hobs and seats them in a new group chat: a full-screen
/// sheet on phones, a large dialog on wide windows. Returns the new room,
/// or null when the user backed out.
Future<GroupRoom?> showNewGroupDialog(BuildContext context) =>
    showScreenSheet<GroupRoom>(
      context,
      kind: SheetKind.fullscreen,
      builder: (_) => const _NewGroupDialog(),
    );

class _NewGroupDialog extends StatefulWidget {
  const _NewGroupDialog();

  @override
  State<_NewGroupDialog> createState() => _NewGroupDialogState();
}

class _NewGroupDialogState extends State<_NewGroupDialog> {
  static const _min = 2;
  static const _max = 6;

  final _picked = <String>[];
  final _name = TextEditingController();
  bool _nameEdited = false;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<Hob> _candidates(AppState app) {
    final seatable = app.seatableProfiles;
    return [
      for (final b in app.hobs)
        if (seatable == null || seatable.contains(b.name)) b,
    ]..sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
  }

  void _toggle(AppState app, Hob b) {
    setState(() {
      if (!_picked.remove(b.name)) {
        if (_picked.length >= _max) return;
        _picked.add(b.name);
      }
      if (!_nameEdited) _name.text = app.groupNameFor(_members(app));
    });
  }

  List<Hob> _members(AppState app) => [
    for (final n in _picked) ?app.hobNamed(n),
  ];

  Future<void> _create(AppState app) async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final room = await app.createGroup(_members(app), name: _name.text);
      if (mounted) Navigator.pop(context, room);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = AppState.describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hobs = _candidates(app);
    final members = _members(app);
    final canCreate = !_creating && _picked.length >= _min;
    final full = _picked.length >= _max;
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(s.groupPickTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: canCreate ? () => _create(app) : null,
              child: _creating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(s.create),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverList.list(
                  children: [
                    // The table so far: who sits at it, and its name.
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 56,
                            child: Center(
                              child: members.isEmpty
                                  ? Text(
                                      s.groupPickHint,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    )
                                  : GroupAvatars(hobs: members, size: 56),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _name,
                            enabled: !_creating,
                            maxLength: 80,
                            onChanged: (_) => _nameEdited = true,
                            decoration: InputDecoration(
                              labelText: s.groupNameLabel,
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            s.groupPickCount(_picked.length, _max),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!, style: TextStyle(color: cs.error)),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 112,
                    mainAxisExtent: 112,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: hobs.length,
                  itemBuilder: (context, i) {
                    final b = hobs[i];
                    final on = _picked.contains(b.name);
                    return _FaceTile(
                      key: ValueKey('pick-${b.name}'),
                      hob: b,
                      selected: on,
                      enabled: !_creating && (on || !full),
                      onTap: () => _toggle(app, b),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One Hob to pick: its face and name; picked ones get a moss ring and a
/// check.
class _FaceTile extends StatelessWidget {
  const _FaceTile({
    super.key,
    required this.hob,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Hob hob;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: hob.displayName,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? cs.primary : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: HobAvatar(hob: hob, size: 48),
                    ),
                    if (selected)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: cs.surface, width: 2),
                          ),
                          child: Icon(
                            Icons.check,
                            size: 14,
                            color: cs.onPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  hob.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
