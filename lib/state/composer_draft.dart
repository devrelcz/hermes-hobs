import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';

import '../api/attachments.dart';
import '../api/hermes_http.dart';
import '../l10n/strings.dart';
import 'image_prep.dart';

/// Largest file the app attaches, like the dashboard's browser client.
const maxAttachmentBytes = 16 * 1024 * 1024;

/// Uploads attachments to a Hob's profile the way the dashboard does:
///
/// - images: `POST /api/chat/image-upload?profile=` with
///   `{data_url, filename}` -> `{path, mime_type}` (the profile's
///   `cache/images/`, the only place `prompt.submit.attachments` accepts);
/// - files: multipart `POST /api/chat/file-upload?profile=` (field `file`)
///   -> `{path, staged_upload}`, later handed to `file.attach`.
class AttachmentUploader {
  AttachmentUploader(this.http, this.profile, {this.prepare = prepareImage});

  final HermesHttp http;
  final String profile;
  final ImagePreparer prepare;

  Future<ChatAttachment> uploadImage(
    Uint8List bytes,
    String name,
    String? mime, {
    void Function(double progress)? onProgress,
    UploadCancel? cancel,
    void Function(PreparedImage prepared)? onPrepared,
  }) async {
    final p = await prepare(bytes, name, mime);
    if (cancel?.cancelled ?? false) throw const UploadCancelled();
    onPrepared?.call(p);
    final body = utf8.encode(
      jsonEncode({
        'data_url': 'data:${p.mime};base64,${base64Encode(p.bytes)}',
        'filename': p.name,
      }),
    );
    final res = await http.upload(
      '/api/chat/image-upload',
      query: {'profile': profile},
      body: body,
      contentType: 'application/json',
      onProgress: (s, t) => onProgress?.call(t == 0 ? 1 : s / t),
      cancel: cancel,
    );
    final path = res is Map ? res['path'] : null;
    if (path is! String || path.isEmpty) {
      throw HermesHttpException(500, Strings.current.uploadNoPath);
    }
    return ChatAttachment(
      kind: AttachmentKind.image,
      name: p.name,
      path: path,
      mime: (res as Map)['mime_type']?.toString() ?? p.mime,
      preview: p.bytes,
    );
  }

  Future<ChatAttachment> uploadFile(
    Uint8List bytes,
    String name,
    String? mime, {
    void Function(double progress)? onProgress,
    UploadCancel? cancel,
  }) async {
    final boundary = 'hobs-${_random()}';
    final type = mime ?? lookupMimeType(name) ?? 'application/octet-stream';
    final safe = name.replaceAll(RegExp(r'["\r\n]'), '_');
    final head = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="file"; filename="$safe"\r\n'
      'Content-Type: $type\r\n\r\n',
    );
    final tail = utf8.encode('\r\n--$boundary--\r\n');
    final body = BytesBuilder(copy: false)
      ..add(head)
      ..add(bytes)
      ..add(tail);
    final res = await http.upload(
      '/api/chat/file-upload',
      query: {'profile': profile},
      body: body.takeBytes(),
      contentType: 'multipart/form-data; boundary=$boundary',
      onProgress: (s, t) => onProgress?.call(t == 0 ? 1 : s / t),
      cancel: cancel,
    );
    final path = res is Map ? res['path'] : null;
    if (path is! String || path.isEmpty) {
      throw HermesHttpException(500, Strings.current.uploadNoPath);
    }
    final staged = (res as Map)['staged_upload'];
    return ChatAttachment(
      kind: AttachmentKind.file,
      name: name,
      path: path,
      mime: type,
      stagedUpload: staged is Map ? Map<String, dynamic>.from(staged) : null,
    );
  }

  static String _random() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }
}

enum UploadPhase { preparing, uploading, done, failed }

/// One attachment in the composer, from picking until it is sent.
class DraftAttachment {
  DraftAttachment._(this.kind, this.name, {this.preview, this.url});

  static int _ids = 0;
  final int id = _ids++;
  final AttachmentKind kind;
  String name;

  /// Local thumbnail bytes (images).
  Uint8List? preview;
  final String? url;

  UploadPhase phase = UploadPhase.preparing;

  /// 0..1 while uploading.
  double progress = 0;

  /// Why the upload failed, in the current language.
  String? get error => errorText?.call();

  /// Kept as a builder, not text, so a language switch re-words it.
  String Function()? errorText;
  ChatAttachment? uploaded;
  UploadCancel? _cancel;
  Future<void> Function()? _start;

  bool get busy =>
      phase == UploadPhase.preparing || phase == UploadPhase.uploading;
}

/// The composer's attachments for one Hob: they upload as soon as they are
/// picked (with progress, cancel and retry) and go out with the next send.
/// [prefill] carries text shared from another app into the input field.
class ComposerDraft extends ChangeNotifier {
  ComposerDraft(this._uploader);

  AttachmentUploader? _uploader;
  final List<DraftAttachment> items = [];

  /// Text for the input field (share sheet); the chat view takes it once.
  String? prefill;

  bool _disposed = false;

  set uploader(AttachmentUploader? u) => _uploader = u;

  /// Adds shared text for the input field.
  void appendText(String text) {
    prefill = [?prefill, text].join('\n\n');
    _notify();
  }

  /// The text waiting for the input field, once.
  String? takePrefill() {
    final p = prefill;
    prefill = null;
    return p;
  }

  bool get isEmpty => items.isEmpty;
  bool get uploading => items.any((a) => a.busy);
  bool get hasFailed => items.any((a) => a.phase == UploadPhase.failed);

  /// Every attachment is uploaded (or there are none).
  bool get ready => !uploading && !hasFailed;

  void addImage(Uint8List bytes, String name, {String? mime}) {
    final a = DraftAttachment._(
      AttachmentKind.image,
      name,
      preview: _thumbable(mime ?? sniffImageMime(bytes)) ? bytes : null,
    );
    a._start = () => _run(
      a,
      (u, c) => u.uploadImage(
        bytes,
        name,
        mime,
        cancel: c,
        onProgress: (p) => _progress(a, p),
        onPrepared: (p) {
          a.name = p.name;
          a.preview = p.bytes;
          a.phase = UploadPhase.uploading;
          _notify();
        },
      ),
    );
    _add(a);
  }

  void addFile(Uint8List bytes, String name, {String? mime}) {
    if (bytes.length > maxAttachmentBytes) {
      return addFailed(
        name,
        () => Strings.current.attachmentTooLarge(
          maxAttachmentBytes ~/ (1024 * 1024),
        ),
      );
    }
    final a = DraftAttachment._(AttachmentKind.file, name);
    a._start = () => _run(a, (u, c) {
      a.phase = UploadPhase.uploading;
      return u.uploadFile(
        bytes,
        name,
        mime,
        cancel: c,
        onProgress: (p) => _progress(a, p),
      );
    });
    _add(a);
  }

  /// A file that cannot be attached (too large): shown with its reason.
  void addFailed(String name, String Function() error) {
    items.add(
      DraftAttachment._(AttachmentKind.file, name)
        ..phase = UploadPhase.failed
        ..errorText = error,
    );
    _notify();
  }

  void addUrl(String url) {
    final a = DraftAttachment._(AttachmentKind.url, url, url: url)
      ..phase = UploadPhase.done
      ..uploaded = ChatAttachment(
        kind: AttachmentKind.url,
        name: url,
        url: url,
      );
    items.add(a);
    _notify();
  }

  void _add(DraftAttachment a) {
    items.add(a);
    _notify();
    a._start!();
  }

  bool _thumbable(String? mime) => const {
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
  }.contains(mime);

  void _progress(DraftAttachment a, double p) {
    a.phase = UploadPhase.uploading;
    a.progress = p;
    _notify();
  }

  Future<void> _run(
    DraftAttachment a,
    Future<ChatAttachment> Function(AttachmentUploader u, UploadCancel c) job,
  ) async {
    final u = _uploader;
    final cancel = a._cancel = UploadCancel();
    a
      ..phase = UploadPhase.preparing
      ..progress = 0
      ..errorText = null;
    _notify();
    if (u == null) {
      a
        ..phase = UploadPhase.failed
        ..errorText = () => Strings.current.chatNotReady;
      _notify();
      return;
    }
    try {
      final res = await job(u, cancel);
      if (cancel.cancelled) return;
      a
        ..uploaded = res
        ..phase = UploadPhase.done
        ..progress = 1;
    } on UploadCancelled {
      return;
    } catch (e) {
      if (cancel.cancelled) return;
      a
        ..phase = UploadPhase.failed
        ..errorText = () => Strings.current.uploadFailed(
          e is HermesHttpException ? e.message : e,
        );
    }
    _notify();
  }

  /// Uploads the failed attachment again.
  void retry(DraftAttachment a) {
    if (a.phase != UploadPhase.failed || a._start == null) return;
    a._start!();
  }

  /// Drops [a] from the draft, aborting its upload.
  void remove(DraftAttachment a) {
    a._cancel?.cancel();
    items.remove(a);
    _notify();
  }

  /// The uploaded attachments for a send; empties the draft.
  List<ChatAttachment> take() {
    final out = [
      for (final a in items)
        if (a.uploaded != null) a.uploaded!,
    ];
    items.clear();
    _notify();
    return out;
  }

  void clear() {
    for (final a in items) {
      a._cancel?.cancel();
    }
    items.clear();
    prefill = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final a in items) {
      a._cancel?.cancel();
    }
    super.dispose();
  }
}
