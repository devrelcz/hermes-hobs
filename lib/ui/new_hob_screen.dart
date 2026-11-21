import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'hob_avatar.dart';
import 'sheets.dart';

/// A page that asks for a new Hob's name, handle and description and creates
/// it, laid out like the Hob profile. A full-screen sheet on phones, a large
/// dialog on wide screens.
class NewHobScreen extends StatefulWidget {
  const NewHobScreen({super.key});

  /// Opens the sheet. Returns the new Hob, or null when the user backed out.
  static Future<Hob?> open(BuildContext context) => showScreenSheet<Hob>(
    context,
    kind: SheetKind.fullscreen,
    guarded: true,
    builder: (_) => const NewHobScreen(),
  );

  @override
  State<NewHobScreen> createState() => _NewHobScreenState();
}

class _NewHobScreenState extends State<NewHobScreen> {
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _description = TextEditingController();
  final _handleFocus = FocusNode();

  /// The handle is made from the name, made unique, and stays out of sight
  /// until the user asks to edit it. From then on it is theirs.
  bool _customHandle = false;

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
    _handleFocus.dispose();
    super.dispose();
  }

  /// The handle the Hob will get.
  String _slugFor(AppState app) =>
      _customHandle ? _handle.text.trim() : app.freeHobNameFor(_name.text);

  String get _shape => HobAvatar.blobShape(_seed ?? '', null);

  /// Anything typed or picked that leaving the page would throw away.
  bool get _dirty =>
      _name.text.trim().isNotEmpty ||
      (_customHandle && _handle.text.trim().isNotEmpty) ||
      _description.text.trim().isNotEmpty ||
      _seed != null;

  /// Why the handle cannot be used, or null when it can. A made-up handle
  /// is always free; only one the user typed can clash.
  String? _handleProblem(AppState app, Strings s, String slug) {
    if (!_customHandle || slug.isEmpty) return null;
    if (!AppState.hobNamePattern.hasMatch(slug)) return s.hobHandleInvalid;
    if (app.hobNameTaken(slug)) return s.hobHandleTaken;
    return null;
  }

  void _nameChanged(String text) => setState(() => _error = null);

  void _editHandle(String current) {
    setState(() {
      _handle.text = current;
      _customHandle = true;
    });
    // The name field still has focus: hand it over once the field exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleFocus.requestFocus();
    });
  }

  void _randomizeFace() {
    final r = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    setState(
      () => _seed = [for (var i = 0; i < 8; i++) chars[r.nextInt(36)]].join(),
    );
  }

  Future<void> _create(AppState app, String slug) async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final hob = await app.createHob(
        name: slug,
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

  Future<void> _askDiscard() async {
    final s = Strings.of(context);
    final navigator = Navigator.of(context);
    final discard = await showConfirmSheet(
      context,
      title: s.discardChangesTitle,
      confirmLabel: s.discardChanges,
      cancelLabel: s.keepEditing,
      destructive: true,
    );
    if (discard && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final slug = _slugFor(app);
    final problem = _handleProblem(app, s, slug);
    final canCreate = !_creating && slug.isNotEmpty && problem == null;
    final title = _name.text.trim();
    final preview = Hob(
      name: slug,
      displayName: title.isEmpty ? slug : title,
      shape: _shape,
    );
    return PopScope(
      canPop: !_dirty && !_creating,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_creating) _askDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: inSheet(context) ? const CloseButton() : null,
          title: Text(s.newHob),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: canCreate ? () => _create(app, slug) : null,
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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Center(
                  child: HobAvatar(
                    hob: preview,
                    size: 88,
                    face: HobAvatar.resolve(
                      name: slug.isEmpty ? 'hob' : slug,
                      shape: _shape,
                    ),
                  ),
                ),
                // Name and handle grow in under the face as the name is
                // typed, instead of leaving an empty gap before.
                AnimatedSize(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (title.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                      ],
                      if (slug.isNotEmpty)
                        Center(
                          child: _customHandle
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Text(
                                    '@$slug',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              // The made-up handle is shown where the Hob's
                              // identity is; tapping it opens the field.
                              : Tooltip(
                                  message: s.editHobHandle,
                                  child: TextButton.icon(
                                    onPressed: _creating
                                        ? null
                                        : () => _editHandle(slug),
                                    style: TextButton.styleFrom(
                                      foregroundColor: cs.onSurfaceVariant,
                                      textStyle: theme.textTheme.bodyMedium,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    iconAlignment: IconAlignment.end,
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 16,
                                    ),
                                    label: Text('@$slug'),
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
                Center(
                  child: TextButton.icon(
                    onPressed: _creating ? null : _randomizeFace,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(s.randomizeFace),
                  ),
                ),
                // Create sits in the bar at the top, so a refusal shows up
                // here, where the eye is, not under the fields.
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: cs.onErrorContainer),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
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
                    counterText: '',
                  ),
                ),
                if (_customHandle) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _handle,
                    focusNode: _handleFocus,
                    enabled: !_creating,
                    maxLength: 64,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() => _error = null),
                    decoration: InputDecoration(
                      labelText: s.hobHandleLabel,
                      counterText: '',
                      prefixText: '@',
                      helperText: s.hobHandleHelp,
                      helperMaxLines: 3,
                      errorText: problem,
                      errorMaxLines: 3,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _description,
                  enabled: !_creating,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: s.hobDescriptionLabel,
                    hintText: s.hobDescriptionHint,
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  s.newHobHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
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
