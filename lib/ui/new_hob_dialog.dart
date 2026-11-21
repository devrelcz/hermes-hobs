import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'hob_avatar.dart';

/// Asks for a new Hob's name, handle and description and creates it. Returns
/// the new Hob, or null when the user backed out.
Future<Hob?> showNewHobDialog(BuildContext context) => showDialog<Hob>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _NewHobDialog(),
);

class _NewHobDialog extends StatefulWidget {
  const _NewHobDialog();

  @override
  State<_NewHobDialog> createState() => _NewHobDialogState();
}

class _NewHobDialogState extends State<_NewHobDialog> {
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _description = TextEditingController();

  /// The handle follows the name until the user types one of their own.
  bool _handleEdited = false;

  /// Null until "Another face" is tapped: then the face no longer follows
  /// the handle.
  String? _seed;

  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _description.dispose();
    super.dispose();
  }

  String get _slug => _handle.text.trim();

  String get _shape => HobAvatar.blobShape(_seed ?? '', null);

  /// Why the handle cannot be used, or null when it can.
  String? _handleProblem(AppState app, Strings s) {
    if (_slug.isEmpty) return null;
    if (!AppState.hobNamePattern.hasMatch(_slug)) return s.hobHandleInvalid;
    if (app.hobNameTaken(_slug)) return s.hobHandleTaken;
    return null;
  }

  void _nameChanged(String text) {
    setState(() {
      if (!_handleEdited) _handle.text = AppState.hobNameFor(text);
      _error = null;
    });
  }

  void _randomizeFace() {
    final r = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    setState(
      () => _seed = [for (var i = 0; i < 8; i++) chars[r.nextInt(36)]].join(),
    );
  }

  Future<void> _create(AppState app) async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final hob = await app.createHob(
        name: _slug,
        title: _name.text,
        description: _description.text,
        shape: _shape,
      );
      if (mounted) Navigator.pop(context, hob);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = Strings.of(context).hobCreateFailed(AppState.describeError(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final problem = _handleProblem(app, s);
    final canCreate = !_creating && _slug.isNotEmpty && problem == null;
    final title = _name.text.trim();
    final preview = Hob(
      name: _slug,
      displayName: title.isEmpty ? _slug : title,
      shape: _shape,
    );
    return AlertDialog(
      title: Text(s.newHob),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  HobAvatar(
                    hob: preview,
                    size: 56,
                    face: HobAvatar.resolve(
                      name: _slug.isEmpty ? 'hob' : _slug,
                      shape: _shape,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _creating ? null : _randomizeFace,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(s.randomizeFace),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                enabled: !_creating,
                autofocus: true,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                onChanged: _nameChanged,
                decoration: InputDecoration(
                  labelText: s.newHobNameLabel,
                  hintText: s.newHobNameHint,
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _handle,
                enabled: !_creating,
                maxLength: 64,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {
                  _handleEdited = true;
                  _error = null;
                }),
                decoration: InputDecoration(
                  labelText: s.hobHandleLabel,
                  prefixText: '@',
                  helperText: s.hobHandleHelp,
                  helperMaxLines: 3,
                  errorText: problem,
                  errorMaxLines: 3,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _description,
                enabled: !_creating,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: s.hobDescriptionLabel,
                  hintText: s.hobDescriptionHint,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                s.newHobHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
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
