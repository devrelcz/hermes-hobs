import 'dart:math';

import 'package:flutter/material.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

/// The app's surfaces over the current screen, one per kind of interaction:
///
/// - [SheetKind.bottom]: a short choice or a confirmation. Bottom sheet on
///   phones, a dialog on wide screens.
/// - [SheetKind.fullscreen]: a task of its own (a new Hob). Covers a phone,
///   a large dialog on wide screens.
/// - [SheetKind.side]: settings next to what they change. Bottom sheet on
///   phones, a side sheet from the right on wide screens.
///
/// Built on Wolt Modal Sheet, which picks the shape from the window width.
enum SheetKind { bottom, fullscreen, side }

/// From this width the window is wide enough for dialogs and side sheets.
const double wideSheetBreakpoint = 700;

bool isWideWindow(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideSheetBreakpoint;

WoltModalType _typeFor(
  BuildContext context,
  SheetKind kind, {
  required bool handle,
}) {
  final wide = isWideWindow(context);
  return switch (kind) {
    SheetKind.bottom when wide => const WoltDialogType(),
    SheetKind.bottom => WoltBottomSheetType(
      showDragHandle: handle,
      shapeBorder: _topRounded,
    ),
    SheetKind.fullscreen when wide => const _LargeDialogType(),
    SheetKind.fullscreen => const _FullscreenSheetType(),
    SheetKind.side when wide => const WoltSideSheetType(),
    SheetKind.side => WoltBottomSheetType(
      showDragHandle: handle,
      forceMaxHeight: true,
      shapeBorder: _topRounded,
    ),
  };
}

/// Room above a sheet's own content for the drag handle on phones.
const sheetHandleGap = 28.0;

const _topRounded = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

/// Shows a whole screen as a sheet of [kind], filling the sheet's height.
/// A screen with its own app bar brings its own close button, so it gets no
/// drag handle (the handle's touch area would cover that button); a list
/// without one asks for [dragHandle] and leaves [sheetHandleGap] above it.
/// With [guarded] the sheet only closes through the screen itself (its
/// close button and back gesture, which its PopScope can stop), never by a
/// stray tap on the barrier or a drag: it holds unsaved work.
Future<T?> showScreenSheet<T>(
  BuildContext context, {
  required SheetKind kind,
  required WidgetBuilder builder,
  bool guarded = false,
  bool dragHandle = false,
}) {
  final handle = dragHandle && !guarded && kind != SheetKind.fullscreen;
  return WoltModalSheet.show<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: !guarded,
    enableDrag: !guarded && kind != SheetKind.fullscreen,
    modalTypeBuilder: (context) => _typeFor(context, kind, handle: handle),
    pageListBuilder: (sheetContext) => [
      NonScrollingWoltModalSheetPage(
        hasTopBarLayer: false,
        child: Builder(builder: builder),
      ),
    ],
  );
}

/// Shows short content (a list of choices, a form of a few fields) as a
/// sheet of [kind] that is as tall as its content.
Future<T?> showContentSheet<T>(
  BuildContext context, {
  required SheetKind kind,
  required WidgetBuilder builder,
}) {
  return WoltModalSheet.show<T>(
    context: context,
    useRootNavigator: true,
    modalTypeBuilder: (context) => _typeFor(context, kind, handle: true),
    pageListBuilder: (sheetContext) => [
      WoltModalSheetPage(
        hasTopBarLayer: false,
        child: Builder(builder: builder),
      ),
    ],
  );
}

/// Whether [context] sits in one of the sheets above. Screens shown both as
/// a page and as a sheet use it to offer a close button instead of a back
/// arrow.
bool inSheet(BuildContext context) =>
    ModalRoute.of(context) is WoltModalSheetRoute;

/// Asks before something that cannot be taken back, or that costs money.
/// A bottom sheet on phones, a dialog on wide screens. True when confirmed.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
  IconData? icon,
}) async {
  final ok = await showContentSheet<bool>(
    context,
    kind: SheetKind.bottom,
    builder: (context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final accent = destructive ? cs.error : cs.primary;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          isWideWindow(context) ? 24 : sheetHandleGap,
          24,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: ShapeDecoration(
                    shape: const CircleBorder(),
                    color: destructive
                        ? cs.errorContainer
                        : cs.primaryContainer,
                  ),
                  child: Icon(
                    icon,
                    color: destructive
                        ? cs.onErrorContainer
                        : cs.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(title, style: theme.textTheme.titleLarge),
            if (message != null && message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: destructive ? cs.onError : cs.onPrimary,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.pop(context, false),
              child: Text(cancelLabel),
            ),
          ],
        ),
      );
    },
  );
  return ok == true;
}

/// A short note that something worked ("Saved"). Floats over the bottom of
/// the window and goes away by itself; errors keep using plain snackbars.
void showToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final width = MediaQuery.sizeOf(context).width;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: min(width - 32, 420),
        duration: const Duration(milliseconds: 2400),
        backgroundColor: cs.inverseSurface,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        content: Row(
          children: [
            Icon(icon, size: 20, color: cs.inversePrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onInverseSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}

/// A note that sits in the content, above what it is about, for a state
/// that lasts (the connection dropped). Not a popup: it stays until the
/// state is gone, and offers the one action that fixes it.
class InlineBanner extends StatelessWidget {
  const InlineBanner({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onTertiaryContainer,
                    ),
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onTertiaryContainer,
                  ),
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A phone-sized task: the sheet covers the whole screen and slides up.
/// The screen inside keeps its own safe areas (its app bar pads the top).
class _FullscreenSheetType extends WoltBottomSheetType {
  const _FullscreenSheetType()
    : super(
        shapeBorder: const RoundedRectangleBorder(),
        showDragHandle: false,
        forceMaxHeight: true,
      );

  @override
  BoxConstraints layoutModal(Size availableSize) =>
      BoxConstraints.tight(availableSize);

  @override
  Widget decoratePageContent(
    BuildContext context,
    Widget child,
    bool useSafeArea,
  ) => child;

  @override
  Widget decorateModal(BuildContext context, Widget modal, bool useSafeArea) =>
      modal;
}

/// The wide-screen form of a full-screen task: a tall dialog, not a
/// stretched phone screen.
class _LargeDialogType extends WoltDialogType {
  const _LargeDialogType();

  @override
  BoxConstraints layoutModal(Size availableSize) {
    final width = min(
      560.0,
      availableSize.width - 2 * WoltDialogType.minPadding,
    );
    final height = min(
      760.0,
      availableSize.height - 2 * WoltDialogType.minPadding,
    );
    return BoxConstraints.tight(Size(width, height));
  }

  @override
  Offset positionModal(Size availableSize, Size modalContentSize, _) => Offset(
    (availableSize.width - modalContentSize.width) / 2,
    (availableSize.height - modalContentSize.height) / 2,
  );
}

/// Asks for one line of text (a folder or group name, a link) in a bottom
/// sheet on phones, a dialog on wide windows. [validate] returns why the
/// text cannot be used, or null. Returns the text, or null when cancelled.
Future<String?> showTextSheet(
  BuildContext context, {
  required String title,
  String? label,
  String? hint,
  String initial = '',
  required String action,
  required String cancel,
  int maxLength = 80,
  TextInputType? keyboardType,
  bool sentences = true,
  String? Function(String text)? validate,
  Key? fieldKey,
}) => showContentSheet<String>(
  context,
  kind: SheetKind.bottom,
  builder: (_) => _TextSheet(
    title: title,
    label: label,
    hint: hint,
    initial: initial,
    action: action,
    cancel: cancel,
    maxLength: maxLength,
    keyboardType: keyboardType,
    sentences: sentences,
    validate: validate,
    fieldKey: fieldKey,
  ),
);

class _TextSheet extends StatefulWidget {
  const _TextSheet({
    required this.title,
    required this.label,
    required this.hint,
    required this.initial,
    required this.action,
    required this.cancel,
    required this.maxLength,
    required this.keyboardType,
    required this.sentences,
    required this.validate,
    required this.fieldKey,
  });

  final String title;
  final String? label;
  final String? hint;
  final String initial;
  final String action;
  final String cancel;
  final int maxLength;
  final TextInputType? keyboardType;
  final bool sentences;
  final String? Function(String text)? validate;
  final Key? fieldKey;

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _text.text.trim();
    final problem = widget.validate?.call(v);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        isWideWindow(context) ? 24 : sheetHandleGap,
        24,
        16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            key: widget.fieldKey,
            controller: _text,
            autofocus: true,
            maxLength: widget.maxLength,
            keyboardType: widget.keyboardType,
            autocorrect: widget.sentences,
            textCapitalization: widget.sentences
                ? TextCapitalization.sentences
                : TextCapitalization.none,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              errorText: _error,
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(widget.cancel),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: _submit,
                  child: Text(widget.action),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
