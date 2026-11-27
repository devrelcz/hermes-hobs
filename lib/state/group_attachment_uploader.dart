import 'dart:typed_data';

import 'package:mime/mime.dart';

import '../api/attachments.dart';
import '../api/group_attachments.dart';
import '../api/hermes_http.dart';
import '../l10n/strings.dart';
import 'composer_draft.dart';
import 'image_prep.dart';

class GroupAttachmentUploader implements ComposerAttachmentUploader {
  const GroupAttachmentUploader(this.api);

  final GroupAttachmentApi api;

  @override
  Future<ChatAttachment> uploadImage(
    Uint8List bytes,
    String name,
    String? mime, {
    void Function(double progress)? onProgress,
    UploadCancel? cancel,
    void Function(PreparedImage prepared)? onPrepared,
  }) async {
    final prepared = await prepareImage(
      bytes,
      name,
      sniffImageMime(bytes) ?? mime,
    );
    if (cancel?.cancelled == true) throw const UploadCancelled();
    onPrepared?.call(prepared);
    return _upload(
      prepared.bytes,
      prepared.name,
      prepared.mime,
      'image',
      cancel: cancel,
      preview: prepared.bytes,
    );
  }

  @override
  Future<ChatAttachment> uploadFile(
    Uint8List bytes,
    String name,
    String? mime, {
    void Function(double progress)? onProgress,
    UploadCancel? cancel,
  }) {
    final supplied = mime?.toLowerCase();
    final guessed = lookupMimeType(name, headerBytes: bytes);
    final type = supplied == null || supplied == 'application/octet-stream'
        ? guessed ?? 'application/octet-stream'
        : supplied;
    if (type.startsWith('image/') || sniffImageMime(bytes) != null) {
      return uploadImage(bytes, name, type, cancel: cancel);
    }
    final kind = type == 'application/pdf' ? 'pdf' : 'file';
    return _upload(bytes, name, type, kind, cancel: cancel);
  }

  Future<ChatAttachment> _upload(
    Uint8List bytes,
    String name,
    String mime,
    String kind, {
    UploadCancel? cancel,
    Uint8List? preview,
  }) async {
    if (cancel?.cancelled == true) throw const UploadCancelled();
    try {
      final attachment = await api.upload(bytes, name, mime, kind);
      return ChatAttachment(
        kind: kind == 'image' ? AttachmentKind.image : AttachmentKind.file,
        name: attachment.name,
        mime: attachment.mime,
        preview: preview,
        groupAttachment: attachment,
      );
    } catch (_) {
      throw HermesHttpException(
        500,
        Strings.current.groupAttachmentUploadFailed,
      );
    }
  }
}
