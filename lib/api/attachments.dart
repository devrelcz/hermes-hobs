import 'dart:typed_data';

import 'group_attachments.dart';
import 'hermes_rpc.dart';

/// What a chat attachment is, as the dashboard composer models it.
enum AttachmentKind { image, file, url }

/// One attachment of a message: in the composer (after upload) or parsed
/// back out of the transcript.
///
/// The dashboard keeps attachments as references inside the user text:
/// `@image:<path>`, `@file:<path>`, `@url:<url>` lines (see
/// [parseAttachmentRefs]). Images additionally travel as
/// `prompt.submit {attachments: [{path, mime}]}` on the canonical gateway.
class ChatAttachment {
  ChatAttachment({
    required this.kind,
    required this.name,
    this.path,
    this.url,
    this.mime,
    this.preview,
    this.stagedUpload,
    this.groupAttachment,
  });

  final AttachmentKind kind;

  /// File name (or the URL itself) shown on the chip.
  final String name;

  /// Path on the Hermes host (uploaded images and files).
  final String? path;

  /// Target of a link attachment.
  final String? url;
  final String? mime;

  /// Local bytes for the thumbnail of an image sent from this device.
  final Uint8List? preview;

  /// Receipt of `POST /api/chat/file-upload`, handed to `file.attach`.
  final Map<String, dynamic>? stagedUpload;
  final GroupAttachment? groupAttachment;

  /// Line the dashboard puts in front of the user text for this attachment.
  /// Images travel separately; files get their ref from `file.attach`.
  String? get refLine => switch (kind) {
    AttachmentKind.url => '@url:${formatRefValue(url ?? name)}',
    _ => null,
  };
}

/// Text the dashboard sends when a turn has images but no words.
const imageOnlyPrompt = 'What do you see in this image?';

final _needsQuoting = RegExp(r'''[\s()\[\]{}<>"'`]''');

/// Quotes a reference value so the server reads it back whole
/// (`agent.context_references.format_reference_value`).
String formatRefValue(String value) {
  if (!_needsQuoting.hasMatch(value)) return value;
  for (final q in const ['`', '"', "'"]) {
    if (!value.contains(q)) return '$q$value$q';
  }
  return value;
}

String _unquote(String v) {
  if (v.length >= 2) {
    final q = v[0];
    if ((q == '`' || q == '"' || q == "'") && v.endsWith(q)) {
      return v.substring(1, v.length - 1);
    }
  }
  return v;
}

String baseName(String path) {
  final clean = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  final i = clean.lastIndexOf('/');
  return i < 0 ? clean : clean.substring(i + 1);
}

final _refLine = RegExp(
  r'^@(image|file|url|folder):(`[^`\n]+`|"[^"\n]+"|'
  "'[^'\\n]+'"
  r'|\S+)$',
);
final _imageHint = RegExp(r'^\[Image attached at: ([^\n\]]+)\]$');

/// Splits a transcript user row into its caption and attachments.
///
/// Reference lines can sit before the text (files, links) or after it
/// (images); every line that is one whole reference becomes an attachment.
/// The placeholder caption the dashboard sends for an image-only turn is
/// dropped.
({String text, List<ChatAttachment> attachments}) parseAttachmentRefs(
  String raw,
) {
  final atts = <ChatAttachment>[];
  final kept = <String>[];
  for (final line in raw.split('\n')) {
    final t = line.trim();
    final m = _refLine.firstMatch(t);
    final hint = m == null ? _imageHint.firstMatch(t) : null;
    if (m != null) {
      final value = _unquote(m.group(2)!);
      switch (m.group(1)) {
        case 'image':
          atts.add(
            ChatAttachment(
              kind: AttachmentKind.image,
              name: baseName(value),
              path: value,
            ),
          );
        case 'url':
          atts.add(
            ChatAttachment(kind: AttachmentKind.url, name: value, url: value),
          );
        default:
          // `@file:path:12-20` names a line range; the chip shows the file.
          atts.add(
            ChatAttachment(
              kind: AttachmentKind.file,
              name: baseName(value),
              path: value,
            ),
          );
      }
    } else if (hint != null) {
      final p = hint.group(1)!.trim();
      atts.add(
        ChatAttachment(kind: AttachmentKind.image, name: baseName(p), path: p),
      );
    } else {
      kept.add(line);
    }
  }
  if (atts.isEmpty) return (text: raw, attachments: atts);
  var text = kept.join('\n').trim();
  if (text == imageOnlyPrompt &&
      atts.any((a) => a.kind == AttachmentKind.image)) {
    text = '';
  }
  return (text: text, attachments: atts);
}

/// The params of one `prompt.submit` carrying [attachments].
class PreparedTurn {
  PreparedTurn(this.text, this.images);

  final String text;

  /// Canonical gateway: `[{path, mime}]` for `prompt.submit.attachments`.
  final List<Map<String, String>> images;
}

/// Hands the uploaded attachments to the session the way the dashboard does,
/// right before `prompt.submit`:
///
/// - files: `file.attach {session_id, name, staged_upload}` returns the
///   `@file:` ref line the text carries;
/// - links: an `@url:` ref line;
/// - images: on the canonical gateway they ride on the submit as
///   `attachments`; the legacy dispatcher queues them with `image.attach`.
///
/// [scoped] adds the routing params (`profile`) the session verbs need.
Future<PreparedTurn> prepareTurn(
  HermesRpc rpc, {
  required String sessionId,
  required String text,
  required List<ChatAttachment> attachments,
  required Map<String, dynamic> Function(Map<String, dynamic>) scoped,
}) async {
  final refs = <String>[];
  final images = <Map<String, String>>[];
  for (final a in attachments) {
    switch (a.kind) {
      case AttachmentKind.url:
        refs.add(a.refLine!);
      case AttachmentKind.file:
        final res = await rpc.request(
          'file.attach',
          scoped({
            'session_id': sessionId,
            'name': a.name,
            if (a.stagedUpload != null)
              'staged_upload': a.stagedUpload
            else
              'path': a.path,
          }),
        );
        final ref = res is Map ? res['ref_text'] : null;
        if (res is! Map || res['attached'] == false || ref is! String) {
          throw RpcException(
            -1,
            (res is Map ? res['message']?.toString() : null) ??
                'Could not attach ${a.name}',
          );
        }
        refs.add(ref);
      case AttachmentKind.image:
        final path = a.path;
        if (path == null) continue;
        if (rpc.canonical) {
          images.add({'path': path, 'mime': a.mime ?? 'image/jpeg'});
        } else {
          final res = await rpc.request('image.attach', {
            'session_id': sessionId,
            'path': path,
          });
          if (res is Map && res['attached'] == false) {
            throw RpcException(
              -1,
              res['message']?.toString() ?? 'Could not attach ${a.name}',
            );
          }
        }
    }
  }
  final body = text.trim();
  var out = [refs.join('\n'), body].where((s) => s.isNotEmpty).join('\n\n');
  if (out.isEmpty && attachments.any((a) => a.kind == AttachmentKind.image)) {
    out = imageOnlyPrompt;
  }
  return PreparedTurn(out, images);
}
