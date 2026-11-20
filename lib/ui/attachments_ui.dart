import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/attachments.dart';
import '../api/hermes_http.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/composer_draft.dart';
import '../state/image_prep.dart';

/// Device pickers behind the composer's "+" menu. Tests swap it out.
class AttachmentPickers {
  const AttachmentPickers();

  static AttachmentPickers current = const AttachmentPickers();

  bool get hasCamera =>
      !kIsWeb &&
      (Platform.isIOS || Platform.isAndroid) &&
      ImagePicker().supportsImageSource(ImageSource.camera);

  /// iOS and macOS read images from the system pasteboard; Android pastes
  /// them through the keyboard (content insertion in the text field).
  bool get canPasteImage => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  Future<List<XFile>> photo() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: maxImageSide.toDouble(),
      maxHeight: maxImageSide.toDouble(),
      imageQuality: 85,
    );
    return [?x];
  }

  Future<List<XFile>> gallery() => ImagePicker().pickMultiImage(
    maxWidth: maxImageSide.toDouble(),
    maxHeight: maxImageSide.toDouble(),
    imageQuality: 85,
  );

  Future<List<XFile>> files() => openFiles();

  Future<Uint8List?> clipboardImage() => Pasteboard.image;
}

enum _Pick { camera, gallery, files, link, paste }

/// The composer's "+" button: camera, gallery, files, link, paste.
class AttachButton extends StatelessWidget {
  const AttachButton({super.key, required this.draft, required this.enabled});

  final ComposerDraft draft;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final pickers = AttachmentPickers.current;
    return PopupMenuButton<_Pick>(
      key: const ValueKey('attach'),
      enabled: enabled,
      tooltip: s.addAttachment,
      icon: const Icon(Icons.add_circle_outline),
      onSelected: (p) => _pick(context, p),
      itemBuilder: (_) => [
        if (pickers.hasCamera)
          _item(_Pick.camera, Icons.photo_camera_outlined, s.takePhoto),
        _item(_Pick.gallery, Icons.photo_library_outlined, s.choosePhotos),
        _item(_Pick.files, Icons.attach_file, s.chooseFiles),
        _item(_Pick.link, Icons.link, s.addLink),
        if (pickers.canPasteImage)
          _item(_Pick.paste, Icons.content_paste, s.pasteImage),
      ],
    );
  }

  PopupMenuItem<_Pick> _item(_Pick v, IconData icon, String label) =>
      PopupMenuItem(
        value: v,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      );

  /// The picker hands out temporary names (`image_picker_<uuid>.jpg`).
  static String _photoName(String name, int i, int count) {
    if (!name.startsWith('image_picker')) return name;
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot) : '.jpg';
    return count > 1 ? 'photo-${i + 1}$ext' : 'photo$ext';
  }

  Future<void> _pick(BuildContext context, _Pick p) async {
    final s = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final pickers = AttachmentPickers.current;
    try {
      switch (p) {
        case _Pick.camera || _Pick.gallery:
          final xs = p == _Pick.camera
              ? await pickers.photo()
              : await pickers.gallery();
          for (final (i, x) in xs.indexed) {
            draft.addImage(
              await x.readAsBytes(),
              _photoName(x.name, i, xs.length),
              mime: x.mimeType,
            );
          }
        case _Pick.files:
          for (final x in await pickers.files()) {
            if (await x.length() > maxAttachmentBytes) {
              draft.addFailed(
                x.name,
                s.attachmentTooLarge(maxAttachmentBytes ~/ (1024 * 1024)),
              );
              continue;
            }
            draft.addFile(await x.readAsBytes(), x.name, mime: x.mimeType);
          }
        case _Pick.link:
          if (!context.mounted) return;
          final url = await showDialog<String>(
            context: context,
            builder: (_) => const LinkDialog(),
          );
          if (url != null) draft.addUrl(url);
        case _Pick.paste:
          final bytes = await pickers.clipboardImage();
          if (bytes == null || bytes.isEmpty) {
            messenger.showSnackBar(
              SnackBar(content: Text(s.noImageInClipboard)),
            );
            return;
          }
          draft.addImage(bytes, 'pasted-image.png');
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.pickFailed(e))));
    }
  }
}

/// Asks for a web address; returns it when valid.
class LinkDialog extends StatefulWidget {
  const LinkDialog({super.key});

  @override
  State<LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<LinkDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _text.text.trim();
    final uri = Uri.tryParse(v);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      setState(() => _error = Strings.of(context).linkInvalid);
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return AlertDialog(
      title: Text(s.addLink),
      content: TextField(
        key: const ValueKey('link-field'),
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(hintText: s.linkHint, errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(s.add)),
      ],
    );
  }
}

/// The attachments waiting in the composer: thumbnails and chips with upload
/// progress; tap a failed one to retry, the cross removes (and cancels) it.
class DraftStrip extends StatelessWidget {
  const DraftStrip({super.key, required this.draft});

  final ComposerDraft draft;

  @override
  Widget build(BuildContext context) {
    if (draft.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 6),
        itemCount: draft.items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _DraftTile(
          key: ValueKey('draft-${draft.items[i].id}'),
          item: draft.items[i],
          draft: draft,
        ),
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({super.key, required this.item, required this.draft});

  final DraftAttachment item;
  final ComposerDraft draft;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = Strings.of(context);
    final failed = item.phase == UploadPhase.failed;
    final Widget body;
    if (item.kind == AttachmentKind.image) {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 58,
          height: 58,
          child: item.preview != null
              ? Image.memory(
                  item.preview!,
                  fit: BoxFit.cover,
                  cacheWidth: 160,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _placeholder(cs),
                )
              : _placeholder(cs),
        ),
      );
    } else {
      body = Container(
        height: 58,
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.kind == AttachmentKind.url
                  ? Icons.link
                  : Icons.insert_drive_file_outlined,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }
    return Tooltip(
      message: failed ? (item.error ?? '') : item.name,
      child: GestureDetector(
        onTap: failed ? () => draft.retry(item) : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 6),
              child: body,
            ),
            if (item.busy || failed)
              Positioned(
                left: 0,
                top: 6,
                right: 6,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: failed ? 0.45 : 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: failed
                      ? Icon(
                          Icons.refresh,
                          color: cs.onError,
                          semanticLabel: s.tryAgain,
                        )
                      : SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                            value:
                                item.phase == UploadPhase.uploading &&
                                    item.progress > 0
                                ? item.progress
                                : null,
                          ),
                        ),
                ),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: Material(
                color: cs.inverseSurface,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => draft.remove(item),
                  child: Tooltip(
                    message: s.removeAttachment,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: cs.onInverseSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) => ColoredBox(
    color: cs.surfaceContainerHigh,
    child: Icon(Icons.image_outlined, color: cs.onSurfaceVariant),
  );
}

/// Attachments of a sent message: image thumbnails (tap for full screen),
/// file chips and links.
class MessageAttachments extends StatelessWidget {
  const MessageAttachments({
    super.key,
    required this.attachments,
    required this.profile,
  });

  final List<ChatAttachment> attachments;

  /// The Hob's profile (images are read from its home).
  final String profile;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final a in attachments)
          if (a.kind == AttachmentKind.image)
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => ImageViewer(attachment: a, profile: profile),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: AttachmentImage(
                    attachment: a,
                    profile: profile,
                    cacheWidth: 360,
                  ),
                ),
              ),
            )
          else
            ActionChip(
              avatar: Icon(
                a.kind == AttachmentKind.url
                    ? Icons.link
                    : Icons.insert_drive_file_outlined,
                size: 16,
              ),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(a.name, overflow: TextOverflow.ellipsis),
              ),
              backgroundColor: cs.surface,
              visualDensity: VisualDensity.compact,
              tooltip: a.url ?? a.path,
              onPressed: a.kind == AttachmentKind.url
                  ? () => _open(context, a.url!)
                  : null,
            ),
      ],
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = Strings.of(context).linkOpenFailed;
    final uri = Uri.tryParse(url);
    var ok = false;
    try {
      ok =
          uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}

/// Bytes of server-side images, shared by every thumbnail of the session.
class RemoteImageCache {
  static final Map<String, Future<Uint8List>> _cache = {};
  static const _max = 60;

  static Future<Uint8List> load(HermesHttp http, String path, String profile) {
    final key = '$profile|$path';
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit;
    if (_cache.length >= _max) _cache.remove(_cache.keys.first);
    final f = http.getBytes(
      '/api/fs/download',
      query: {'path': path, 'profile': profile},
    );
    // A failed read is retried next time instead of being cached.
    f.catchError((Object _) {
      _cache.remove(key);
      return Uint8List(0);
    });
    return _cache[key] = f;
  }
}

/// An attachment image: the local bytes when this device sent it, otherwise
/// read from the Hob's home (`GET /api/fs/download`).
class AttachmentImage extends StatelessWidget {
  const AttachmentImage({
    super.key,
    required this.attachment,
    required this.profile,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final ChatAttachment attachment;
  final String profile;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget broken() => ColoredBox(
      color: cs.surfaceContainerHigh,
      child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
    );
    final local = attachment.preview;
    if (local != null) {
      return Image.memory(
        local,
        fit: fit,
        cacheWidth: cacheWidth,
        errorBuilder: (_, _, _) => broken(),
      );
    }
    final http = context.read<AppState>().http;
    final path = attachment.path;
    if (http == null || path == null) return broken();
    return FutureBuilder<Uint8List>(
      future: RemoteImageCache.load(http, path, profile),
      builder: (context, snap) {
        if (snap.hasError) return broken();
        if (!snap.hasData) {
          return ColoredBox(
            color: cs.surfaceContainerHigh,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return Image.memory(
          snap.data!,
          fit: fit,
          cacheWidth: cacheWidth,
          errorBuilder: (_, _, _) => broken(),
        );
      },
    );
  }
}

/// Full-screen, zoomable image.
class ImageViewer extends StatelessWidget {
  const ImageViewer({
    super.key,
    required this.attachment,
    required this.profile,
  });

  final ChatAttachment attachment;
  final String profile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(attachment.name, overflow: TextOverflow.ellipsis),
      ),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: AttachmentImage(
            attachment: attachment,
            profile: profile,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
