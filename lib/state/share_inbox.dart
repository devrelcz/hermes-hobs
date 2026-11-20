import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../api/attachments.dart';
import 'composer_draft.dart';

enum SharedKind { image, file, text, url }

/// One thing another app shared with Hobs.
class SharedItem {
  const SharedItem(this.kind, this.value, {this.mime});

  final SharedKind kind;

  /// File path (image, file) or the text / URL itself.
  final String value;
  final String? mime;
}

/// What arrives from the system share sheet / share intent.
abstract class ShareSource {
  /// Shares received while the app runs.
  Stream<List<SharedItem>> get incoming;

  /// The share that launched the app, if any.
  Future<List<SharedItem>> initial();

  /// Tells the platform the share was handled.
  void reset();
}

/// `receive_sharing_intent`: Android intents and the iOS Share Extension
/// (which hands items over through the app group).
class PluginShareSource implements ShareSource {
  static bool get supported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  Stream<List<SharedItem>> get incoming =>
      ReceiveSharingIntent.instance.getMediaStream().map(_convert);

  @override
  Future<List<SharedItem>> initial() async =>
      _convert(await ReceiveSharingIntent.instance.getInitialMedia());

  @override
  void reset() => ReceiveSharingIntent.instance.reset();

  static List<SharedItem> _convert(List<SharedMediaFile> files) => [
    for (final f in files)
      SharedItem(
        switch (f.type) {
          SharedMediaType.image => SharedKind.image,
          SharedMediaType.text => SharedKind.text,
          SharedMediaType.url => SharedKind.url,
          _ => SharedKind.file,
        },
        f.path,
        mime: f.mimeType,
      ),
  ];
}

final _webUrl = RegExp(r'^https?://\S+$', caseSensitive: false);

/// Holds a share until the user picks the Hob it goes to. It waits while
/// the app is locked or signed out: the UI offers it only once the Hob list
/// is on screen.
class ShareInbox extends ChangeNotifier {
  ShareInbox({ShareSource? source})
    : _source =
          source ?? (PluginShareSource.supported ? PluginShareSource() : null);

  final ShareSource? _source;
  StreamSubscription<List<SharedItem>>? _sub;

  /// The share waiting for a Hob; null when there is none.
  List<SharedItem>? pending;

  Future<void> start() async {
    final source = _source;
    if (source == null) return;
    _sub = source.incoming.listen(_receive, onError: (_) {});
    try {
      _receive(await source.initial());
    } catch (_) {
      // No share at launch (or the platform cannot tell).
    }
  }

  void _receive(List<SharedItem> items) {
    final useful = items.where((i) => i.value.trim().isNotEmpty).toList();
    if (useful.isEmpty) return;
    pending = useful;
    notifyListeners();
  }

  /// The user closed the Hob picker.
  void dismiss() {
    pending = null;
    _source?.reset();
    notifyListeners();
  }

  /// Puts the pending share into [draft]: images and files start uploading,
  /// links become link attachments, text goes into the input field. Nothing
  /// is sent.
  Future<void> deliverTo(ComposerDraft draft) async {
    final items = pending;
    pending = null;
    _source?.reset();
    notifyListeners();
    if (items == null) return;
    final texts = <String>[];
    for (final i in items) {
      switch (i.kind) {
        case SharedKind.url:
          draft.addUrl(i.value.trim());
        case SharedKind.text:
          final t = i.value.trim();
          // Android shares a browser page as plain text holding its URL.
          if (_webUrl.hasMatch(t)) {
            draft.addUrl(t);
          } else {
            texts.add(t);
          }
        case SharedKind.image || SharedKind.file:
          final path = i.value.startsWith('file://')
              ? Uri.parse(i.value).toFilePath()
              : i.value;
          final name = baseName(path);
          final mime = i.mime ?? lookupMimeType(path);
          try {
            final bytes = await File(path).readAsBytes();
            final image =
                i.kind == SharedKind.image ||
                (mime != null && mime.startsWith('image/'));
            if (image) {
              draft.addImage(bytes, name, mime: mime);
            } else {
              draft.addFile(bytes, name, mime: mime);
            }
          } catch (_) {
            // The shared file vanished; drop it.
          }
      }
    }
    if (texts.isNotEmpty) draft.appendText(texts.join('\n\n'));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
