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
import 'placeholders.dart';
import 'sheets.dart';

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
  const AttachButton({
    super.key,
    required this.draft,
    required this.enabled,
    this.allowLinks = true,
    this.maxItems,
  });

  final ComposerDraft draft;
  final bool enabled;
  final bool allowLinks;
  final int? maxItems;

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
        if (allowLinks) _item(_Pick.link, Icons.link, s.addLink),
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
            Flexible(
              child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
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
    bool canAdd() {
      final limit = maxItems;
      if (limit == null || draft.items.length < limit) return true;
      messenger.showSnackBar(SnackBar(content: Text(s.groupAttachmentLimits)));
      return false;
    }

    if (!canAdd()) return;
    try {
      switch (p) {
        case _Pick.camera || _Pick.gallery:
          final xs = p == _Pick.camera
              ? await pickers.photo()
              : await pickers.gallery();
          for (final (i, x) in xs.indexed) {
            if (!context.mounted || !canAdd()) return;
            final bytes = await x.readAsBytes();
            if (!context.mounted) return;
            draft.addImage(
              bytes,
              _photoName(x.name, i, xs.length),
              mime: x.mimeType,
            );
          }
        case _Pick.files:
          for (final x in await pickers.files()) {
            if (!context.mounted || !canAdd()) return;
            final size = await x.length();
            if (!context.mounted) return;
            if (size > draft.maxFileBytes) {
              draft.addFailed(
                x.name,
                s.attachmentTooLarge(draft.maxFileMegabytes),
              );
              continue;
            }
            final bytes = await x.readAsBytes();
            if (!context.mounted) return;
            draft.addFile(bytes, x.name, mime: x.mimeType);
          }
        case _Pick.link:
          if (!context.mounted) return;
          final url = await showTextSheet(
            context,
            title: s.addLink,
            hint: s.linkHint,
            action: s.add,
            cancel: s.cancel,
            maxLength: 2000,
            keyboardType: TextInputType.url,
            sentences: false,
            fieldKey: const ValueKey('link-field'),
            validate: (v) {
              final uri = Uri.tryParse(v);
              final ok =
                  uri != null &&
                  (uri.scheme == 'http' || uri.scheme == 'https') &&
                  uri.host.isNotEmpty;
              return ok ? null : s.linkInvalid;
            },
          );
          if (context.mounted && url != null) draft.addUrl(url);
        case _Pick.paste:
          final bytes = await pickers.clipboardImage();
          if (!context.mounted) return;
          if (bytes == null || bytes.isEmpty) {
            messenger.showSnackBar(
              SnackBar(content: Text(s.noImageInClipboard)),
            );
            return;
          }
          draft.addImage(bytes, 'pasted-image.png');
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(s.pickFailed(e))));
      }
    }
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

/// A message's attachments: images as a grid (one large, several in rows
/// of square tiles, "+N" past six), files and links as cards with their
/// type. Tapping an image opens the gallery at it.
class MessageAttachments extends StatelessWidget {
  const MessageAttachments({
    super.key,
    required this.attachments,
    required this.profile,
  });

  final List<ChatAttachment> attachments;

  /// The Hob's profile (images are read from its home).
  final String profile;

  static const _maxTiles = 6;

  @override
  Widget build(BuildContext context) {
    final images = [
      for (final a in attachments)
        if (a.kind == AttachmentKind.image) a,
    ];
    final others = [
      for (final a in attachments)
        if (a.kind != AttachmentKind.image) a,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (images.isNotEmpty) _grid(context, images),
        if (images.isNotEmpty && others.isNotEmpty) const SizedBox(height: 6),
        for (final a in others)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _FileCard(
              attachment: a,
              onTap: a.kind == AttachmentKind.url
                  ? () => _open(context, a.url!)
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _grid(BuildContext context, List<ChatAttachment> images) {
    void show(int i) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            GalleryViewer(images: images, initial: i, profile: profile),
      ),
    );
    Widget tile(int i, double w, double h, {int more = 0}) => Semantics(
      button: true,
      image: true,
      label: images[i].name,
      child: GestureDetector(
        onTap: () => show(i),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AttachmentImage(
                  attachment: images[i],
                  profile: profile,
                  cacheWidth: (w * 3).round(),
                ),
                if (more > 0)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: Center(
                      child: Text(
                        '+$more',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
        if (images.length == 1) {
          final w = width.clamp(0.0, 280.0);
          return tile(0, w, w * 0.75);
        }
        const gap = 4.0;
        final cols = images.length == 2 || images.length == 4 ? 2 : 3;
        final side = ((width.clamp(0.0, 300.0) - gap * (cols - 1)) / cols)
            .floorToDouble();
        final shown = images.length.clamp(0, _maxTiles);
        return SizedBox(
          width: side * cols + gap * (cols - 1),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < shown; i++)
                tile(
                  i,
                  side,
                  side,
                  more: i == shown - 1 ? images.length - shown : 0,
                ),
            ],
          ),
        );
      },
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

/// A file or link: an icon for its type, the name, and what it is.
class _FileCard extends StatelessWidget {
  const _FileCard({required this.attachment, this.onTap});

  final ChatAttachment attachment;
  final VoidCallback? onTap;

  static (IconData, String) _kind(ChatAttachment a, Strings s) {
    if (a.kind == AttachmentKind.url) {
      return (Icons.link, Uri.tryParse(a.url ?? '')?.host ?? s.linkLabel);
    }
    final dot = a.name.lastIndexOf('.');
    final ext = dot > 0 ? a.name.substring(dot + 1).toLowerCase() : '';
    final icon = switch (ext) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'doc' ||
      'docx' ||
      'odt' ||
      'rtf' ||
      'txt' ||
      'md' => Icons.description_outlined,
      'xls' || 'xlsx' || 'ods' || 'csv' => Icons.table_chart_outlined,
      'ppt' || 'pptx' || 'odp' || 'key' => Icons.slideshow_outlined,
      'zip' || 'tar' || 'gz' || '7z' || 'rar' => Icons.folder_zip_outlined,
      'mp3' || 'wav' || 'm4a' || 'ogg' => Icons.audio_file_outlined,
      'mp4' || 'mov' || 'webm' => Icons.video_file_outlined,
      'json' ||
      'yaml' ||
      'yml' ||
      'py' ||
      'js' ||
      'ts' ||
      'dart' ||
      'sh' => Icons.code,
      _ => Icons.insert_drive_file_outlined,
    };
    return (icon, ext.isEmpty ? s.fileLabel : ext.toUpperCase());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = Strings.of(context);
    final (icon, what) = _kind(attachment, s);
    return Tooltip(
      message: attachment.url ?? attachment.path ?? attachment.name,
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, size: 20, color: cs.onSecondaryContainer),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          attachment.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          what,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
          return const SkeletonPulse(
            child: SkeletonBox(height: double.infinity, radius: 0),
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

/// The images of one message, full screen: swipe between them, pinch to
/// zoom, "2 / 5" in the bar.
class GalleryViewer extends StatefulWidget {
  const GalleryViewer({
    super.key,
    required this.images,
    required this.initial,
    required this.profile,
  });

  final List<ChatAttachment> images;
  final int initial;
  final String profile;

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.images.length;
    final current = widget.images[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(current.name, overflow: TextOverflow.ellipsis),
            if (n > 1)
              Text(
                '${_index + 1} / $n',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: n,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: AttachmentImage(
              attachment: widget.images[i],
              profile: widget.profile,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
