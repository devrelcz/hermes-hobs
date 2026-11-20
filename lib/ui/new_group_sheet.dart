import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/group_models.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'hob_avatar.dart';

/// Picks two to six Hobs and seats them in a new group chat. Returns the new
/// room, or null when the user backed out.
Future<GroupRoom?> showNewGroupDialog(BuildContext context) =>
    showDialog<GroupRoom>(
      context: context,
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
    final hobs = _candidates(app);
    final canCreate = !_creating && _picked.length >= _min;
    return AlertDialog(
      title: Text(s.groupPickTitle),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                s.groupPickHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final b in hobs)
                    CheckboxListTile(
                      key: ValueKey('pick-${b.name}'),
                      value: _picked.contains(b.name),
                      onChanged:
                          _creating ||
                              (!_picked.contains(b.name) &&
                                  _picked.length >= _max)
                          ? null
                          : (_) => _toggle(app, b),
                      secondary: HobAvatar(hob: b, size: 30),
                      title: Text(b.displayName),
                      subtitle: b.description.isEmpty
                          ? null
                          : Text(
                              b.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      controlAffinity: ListTileControlAffinity.trailing,
                      dense: true,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: TextField(
                controller: _name,
                enabled: !_creating,
                maxLength: 80,
                onChanged: (_) => _nameEdited = true,
                decoration: InputDecoration(labelText: s.groupNameLabel),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: canCreate ? () => _create(app) : null,
          child: _creating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(s.create),
        ),
      ],
    );
  }
}
