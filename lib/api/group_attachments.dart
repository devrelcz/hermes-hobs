import 'dart:convert';
import 'dart:typed_data';

import 'hermes_rpc.dart';

const maxGroupAttachmentBytes = 15000000;
const maxGroupAttachments = 8;
const maxGroupMessageAttachmentBytes = 25000000;

const groupAttachmentUpload = 'groups.attachment.upload';
const groupAttachmentDownload = 'groups.attachment.download';

final _attachmentId = RegExp(r'^att_[0-9a-f]{32}$');
final _invalidName = RegExp(r'[/\\\x00-\x1f\x7f]');
final _mimeType = RegExp(
  r'^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$',
);

/// The gateway's manifest. It contains a room-scoped ID and display metadata.
class GroupAttachment {
  const GroupAttachment._(this.id, this.kind, this.name, this.mime, this.size);

  final String id;
  final String kind;
  final String name;
  final String mime;
  final int size;

  static GroupAttachment? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['attachment_id'];
    final kind = value['kind'];
    final name = value['name'];
    final mime = value['mime'];
    final size = value['size'];
    if (id is! String ||
        !_attachmentId.hasMatch(id) ||
        (kind != 'image' && kind != 'pdf' && kind != 'file') ||
        name is! String ||
        name.trim().isEmpty ||
        name.runes.length > 255 ||
        name == '.' ||
        name == '..' ||
        _invalidName.hasMatch(name) ||
        mime is! String ||
        mime.length > 127 ||
        !_mimeType.hasMatch(mime) ||
        size is! int ||
        size < 1 ||
        size > maxGroupAttachmentBytes) {
      return null;
    }
    return GroupAttachment._(id, kind as String, name, mime, size);
  }

  Map<String, Object> toJson() => {
    'attachment_id': id,
    'kind': kind,
    'name': name,
    'mime': mime,
    'size': size,
  };
}

class GroupAttachmentApi {
  const GroupAttachmentApi(this.rpc, this.profile, this.roomId);

  final HermesRpc rpc;
  final String profile;
  final String roomId;

  Future<GroupAttachment> upload(
    Uint8List bytes,
    String name,
    String mime,
    String kind,
  ) async {
    if (bytes.isEmpty || bytes.length > maxGroupAttachmentBytes) {
      throw const FormatException('Invalid attachment size');
    }
    final response = await rpc.request(groupAttachmentUpload, {
      'profile': profile,
      'room_id': roomId,
      'upload_id': uuidV4(),
      'kind': kind,
      'name': name,
      'mime': mime,
      'data_base64': base64Encode(bytes),
    });
    final attachment = GroupAttachment.fromJson(response);
    if (attachment == null ||
        attachment.size != bytes.length ||
        attachment.kind != kind ||
        attachment.mime != mime) {
      throw const FormatException('Invalid attachment receipt');
    }
    return attachment;
  }

  Future<Uint8List> download(String eventId, GroupAttachment attachment) async {
    final response = await rpc.request(groupAttachmentDownload, {
      'profile': profile,
      'room_id': roomId,
      'event_id': eventId,
      'attachment_id': attachment.id,
    });
    final received = GroupAttachment.fromJson(response);
    final encoded = response is Map ? response['data_base64'] : null;
    if (received == null ||
        received.id != attachment.id ||
        received.name != attachment.name ||
        received.size != attachment.size ||
        received.mime != attachment.mime ||
        received.kind != attachment.kind ||
        encoded is! String ||
        encoded.length != ((attachment.size + 2) ~/ 3) * 4) {
      throw const FormatException('Invalid downloaded attachment');
    }
    final bytes = base64Decode(encoded);
    if (bytes.length != attachment.size) {
      throw const FormatException('Invalid downloaded attachment size');
    }
    return bytes;
  }
}
