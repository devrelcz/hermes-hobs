import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'hob_avatar.dart';
import 'model_picker.dart';
import 'sheets.dart';
import 'theme.dart';

/// A hob's profile: its face, title, description, model and SOUL.md, editable like in
/// the dashboard's "Edit profile" dialog. Opened by tapping a hob's avatar.
class HobDetailScreen extends StatefulWidget {
  const HobDetailScreen({super.key, required this.hob});

  final Hob hob;

  /// A side sheet on wide screens, a tall bottom sheet on phones. It only
  /// closes through its own close button, which asks about unsaved edits.
  static Future<void> open(BuildContext context, Hob hob) =>
      showScreenSheet<void>(
        context,
        kind: SheetKind.side,
        guarded: true,
        builder: (_) => HobDetailScreen(hob: hob),
      );

  @override
  State<HobDetailScreen> createState() => _HobDetailScreenState();
}

class _HobDetailScreenState extends State<HobDetailScreen> {
  /// The hob the form was filled from; edits are compared against it.
  late Hob _hob = widget.hob;

  late final _title = TextEditingController(text: _hob.customTitle);
  late final _description = TextEditingController(text: _hob.description);
  final _provider = TextEditingController();
  final _model = TextEditingController();
  final _soul = TextEditingController();

  /// Stored values; null draws the one derived from the hob's name.
  late String? _shape = _hob.shape;
  late String? _color = _hob.color;

  /// Null while loading. [_setupFailed] when the profile could not be read.
  HobSetup? _saved;
  bool _setupFailed = false;
  List<ModelProvider> _providers = const [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _description, _provider, _model, _soul]) {
      c.addListener(_changed);
    }
    _loadSetup();
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _provider, _model, _soul]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSetup() async {
    final app = context.read<AppState>();
    // The provider list is a convenience: without it the fields are free text.
    final providers = app.modelProviders().catchError(
      (_) => const <ModelProvider>[],
    );
    try {
      final setup = await app.hobSetup(_hob);
      final list = await providers;
      if (!mounted) return;
      _provider.text = setup.provider;
      _model.text = setup.model;
      _soul.text = setup.soul;
      setState(() {
        _providers = list;
        _saved = setup;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _setupFailed = true);
    }
  }

  bool get _faceDirty => _shape != _hob.shape || _color != _hob.color;

  bool get _appearanceDirty =>
      _title.text.trim() != _hob.customTitle || _faceDirty;

  bool get _descriptionDirty =>
      _description.text.trim() != _hob.description.trim();

  bool get _modelDirty {
    final saved = _saved;
    return saved != null &&
        (_provider.text.trim() != saved.provider ||
            _model.text.trim() != saved.model);
  }

  bool get _soulDirty {
    final saved = _saved;
    return saved != null && _soul.text.trim() != saved.soul.trim();
  }

  bool get _dirty =>
      _appearanceDirty || _descriptionDirty || _modelDirty || _soulDirty;

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    final app = context.read<AppState>();
    final s = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final provider = _provider.text.trim();
    final model = _model.text.trim();
    if (_modelDirty && provider.isEmpty != model.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(s.modelRequired)));
      return;
    }
    setState(() => _saving = true);
    var done = true;
    try {
      final hob = app.hobNamed(_hob.name) ?? _hob;
      if (_appearanceDirty) {
        await app.saveHobAppearance(
          hob,
          title: _title.text,
          shape: _shape,
          color: _color,
        );
      }
      if (_descriptionDirty) {
        await app.saveHobDescription(hob, _description.text);
      }
      if (_modelDirty) {
        final question = await app.saveHobModel(
          hob,
          provider: provider,
          model: model,
        );
        if (question != null) {
          if (!mounted) return;
          if (await confirmExpensiveModel(context, question)) {
            await app.saveHobModel(
              hob,
              provider: provider,
              model: model,
              confirmed: true,
            );
          } else {
            done = false;
          }
        }
        if (done) {
          _saved = HobSetup(
            provider: provider,
            model: model,
            soul: _saved!.soul,
          );
        }
      }
      if (_soulDirty) {
        await app.saveHobSoul(hob, _soul.text);
        _saved = HobSetup(
          provider: _saved!.provider,
          model: _saved!.model,
          soul: _soul.text,
        );
      }
    } catch (e) {
      done = false;
      messenger.showSnackBar(
        SnackBar(content: Text(s.hobSaveFailed(AppState.describeError(e)))),
      );
    }
    await app.refreshHobs(silent: true);
    final fresh = app.hobNamed(_hob.name) ?? _hob;
    if (done) {
      if (mounted) showToast(context, s.hobSaved(fresh.displayName));
      if (mounted) navigator.pop();
      return;
    }
    // Something stayed unsaved: keep the form, compared to what is stored now.
    if (mounted) {
      setState(() {
        _hob = fresh;
        _saving = false;
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
    final theme = Theme.of(context);
    final s = Strings.of(context);
    HobFace face(String? shape) => HobAvatar.resolve(
      name: _hob.name,
      shape: shape,
      color: _color,
      custom: _hob.meta['custom'] == true || _faceDirty,
    );
    final title = _title.text.trim();
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _askDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: inSheet(context) ? const CloseButton() : null,
          title: Text(s.hobProfile),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _dirty && !_saving ? _save : null,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(s.save),
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
                  child: HobAvatar(hob: _hob, size: 88, face: face(_shape)),
                ),
                const SizedBox(height: 12),
                Text(
                  title.isEmpty ? _hob.name : title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  '@${_hob.name}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                _Section(
                  title: s.appearance,
                  children: [
                    _FieldLabel(s.blobFaceLabel),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final kind in [null, ...HobAvatar.blobKinds.keys])
                          _ShapeTile(
                            label: kind == null
                                ? s.blobFaceLabel
                                : '${s.blobFaceLabel}: $kind',
                            selected:
                                HobAvatar.isBlob(_shape) &&
                                HobAvatar.blobKindOf(_shape) == kind,
                            onTap: () => setState(
                              () => _shape = HobAvatar.blobShape(
                                HobAvatar.blobSeedOf(_shape),
                                kind,
                              ),
                            ),
                            child: HobAvatar(
                              hob: _hob,
                              size: 34,
                              face: face(
                                HobAvatar.blobShape(
                                  HobAvatar.blobSeedOf(_shape),
                                  kind,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (HobAvatar.isBlob(_shape))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _randomizeFace,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(s.randomizeFace),
                        ),
                      ),
                    const SizedBox(height: 16),
                    _FieldLabel(s.shapeLabel),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ShapeTile(
                          label: s.byName,
                          selected: _shape == null,
                          onTap: () => setState(() => _shape = null),
                          child: Text(
                            s.autoLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final shape in HobAvatar.pickableShapes)
                          _ShapeTile(
                            label: shape,
                            selected: HobAvatar.pickedShape(_shape) == shape,
                            onTap: () => setState(() => _shape = shape),
                            child: HobAvatar(
                              hob: _hob,
                              size: 30,
                              face: face(shape),
                            ),
                          ),
                      ],
                    ),
                    // A blobatar brings its own colors.
                    if (!HobAvatar.isBlob(_shape)) ...[
                      const SizedBox(height: 16),
                      _FieldLabel(s.colorLabel),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _Swatch(
                            label: s.byName,
                            color: null,
                            selected: HobAvatar.parseColor(_color) == null,
                            onTap: () => setState(() => _color = null),
                          ),
                          for (final c in _swatches())
                            _Swatch(
                              label: c,
                              color: HobAvatar.parseColor(c),
                              selected:
                                  HobAvatar.parseColor(_color) ==
                                  HobAvatar.parseColor(c),
                              onTap: () => setState(() => _color = c),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
                _Section(
                  title: s.profileSection,
                  children: [
                    TextField(
                      controller: _title,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: s.hobTitleLabel,
                        hintText: _hob.name,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _description,
                      minLines: 3,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: s.hobDescriptionLabel,
                        hintText: s.hobDescriptionHint,
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
                if (_setupFailed)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      s.setupLoadFailed,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else if (_saved == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  _Section(title: s.modelSection, children: _modelFields(s)),
                  _Section(
                    title: s.soulSection,
                    trailing: TextButton.icon(
                      onPressed: _editSoul,
                      icon: const Icon(Icons.open_in_full, size: 18),
                      label: Text(s.editSoul),
                    ),
                    children: [
                      _SoulPreview(text: _soul.text, onTap: _editSoul),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens SOUL.md on the whole screen; what comes back is saved with the
  /// rest of the profile.
  Future<void> _editSoul() async {
    final edited = await showScreenSheet<String>(
      context,
      kind: SheetKind.fullscreen,
      builder: (_) => _SoulEditor(
        initial: _soul.text,
        hobName: _title.text.trim().isEmpty ? _hob.name : _title.text.trim(),
      ),
    );
    if (edited != null && mounted) _soul.text = edited;
  }

  /// A new face: a fresh seed, the silhouette stays.
  void _randomizeFace() {
    final r = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final seed = [for (var i = 0; i < 8; i++) chars[r.nextInt(36)]].join();
    setState(
      () => _shape = HobAvatar.blobShape(seed, HobAvatar.blobKindOf(_shape)),
    );
  }

  /// The palette, led by the hob's own color when it is not one of them.
  List<String> _swatches() {
    final own = HobAvatar.parseColor(_hob.color);
    final known = HobAvatar.palette.map(HobAvatar.parseColor);
    return [
      if (own != null && !known.contains(own)) _hob.color!,
      ...HobAvatar.palette,
    ];
  }

  List<Widget> _modelFields(Strings s) {
    final provider = _provider.text.trim();
    final model = _model.text.trim();
    if (_providers.isEmpty) {
      return [
        TextField(
          controller: _provider,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: s.providerLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          autocorrect: false,
          decoration: InputDecoration(labelText: s.modelLabel),
        ),
      ];
    }
    final known = _providers.where((p) => p.slug == provider).firstOrNull;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return [
      // One field for provider and model: it opens a searchable list of
      // every model of the signed-in providers.
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await pickProfileModel(
            context,
            providers: [
              for (final p in _providers)
                if (p.authenticated || p.slug == provider) p,
            ],
            current: provider.isEmpty
                ? null
                : ModelChoice(provider: provider, model: model),
          );
          if (picked == null) return;
          _provider.text = picked.provider;
          _model.text = picked.model;
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: s.modelLabel,
            suffixIcon: const Icon(Icons.unfold_more),
          ),
          child: provider.isEmpty
              ? Text(s.inheritModel)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      model.isEmpty ? s.modelLabel : model,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      known?.label ?? provider,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
      ),
      // A provider that lists no models takes a model id by hand.
      if (provider.isNotEmpty && (known?.models ?? const []).isEmpty) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          autocorrect: false,
          decoration: InputDecoration(labelText: s.modelLabel),
        ),
      ],
    ];
  }
}

/// One part of the profile in a soft card, its title above it.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// The start of SOUL.md, read-only; tapping it opens the full editor.
class _SoulPreview extends StatelessWidget {
  const _SoulPreview({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final empty = text.trim().isEmpty;
    return InkWell(
      key: const ValueKey('soul-preview'),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Text(
        empty ? Strings.of(context).soulEmpty : text.trim(),
        maxLines: 8,
        overflow: TextOverflow.ellipsis,
        style: empty
            ? theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)
            : theme.textTheme.bodySmall?.copyWith(
                fontFamily: HobsTheme.monoFamily,
                height: 1.5,
                color: cs.onSurface,
              ),
      ),
    );
  }
}

/// SOUL.md on the whole screen: monospace, room to read and write. Done
/// hands the text back to the profile, which saves it with the rest.
class _SoulEditor extends StatefulWidget {
  const _SoulEditor({required this.initial, required this.hobName});

  final String initial;
  final String hobName;

  @override
  State<_SoulEditor> createState() => _SoulEditorState();
}

class _SoulEditorState extends State<_SoulEditor> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.soulSection),
            Text(
              widget.hobName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _text.text),
              child: Text(s.done),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: TextField(
              controller: _text,
              autofocus: true,
              expands: true,
              maxLines: null,
              minLines: null,
              autocorrect: false,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: HobsTheme.monoFamily,
                height: 1.55,
              ),
              decoration: InputDecoration(hintText: s.soulHint),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ShapeTile extends StatelessWidget {
  const _ShapeTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = BorderRadius.circular(14);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: selected ? cs.secondaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: border,
            side: BorderSide(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: border,
            onTap: onTap,
            child: SizedBox.square(dimension: 52, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

/// One color of the palette; a null [color] is "derived from the name".
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = color;
    final onFill = fill == null
        ? cs.onSurfaceVariant
        : (fill.computeLuminance() < 0.25
              ? Colors.white
              : const Color(0xFF2C2C2A));
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 26,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: Border.all(
                color: selected ? cs.primary : cs.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(Icons.check, size: 18, color: onFill)
                : (fill == null
                      ? Icon(
                          Icons.auto_awesome_outlined,
                          size: 18,
                          color: onFill,
                        )
                      : null),
          ),
        ),
      ),
    );
  }
}
