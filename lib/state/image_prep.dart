import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// An image ready to upload: bytes the server accepts and their type.
class PreparedImage {
  PreparedImage(this.bytes, this.mime, this.name);

  final Uint8List bytes;
  final String mime;
  final String name;
}

/// Longest side sent to Hermes. Plenty for a vision model, a fraction of a
/// phone camera's 12–48 MP.
const maxImageSide = 2048;

/// Photos smaller than this keep their original bytes when the format is
/// one the server accepts.
const keepOriginalBelow = 1536 * 1024;

const _accepted = {'image/jpeg', 'image/png', 'image/gif', 'image/webp'};

/// Turns any image the platform can decode (HEIC included) into one Hermes
/// accepts (`png`, `jpeg`, `gif`, `webp`), downscaled to [maxImageSide] and
/// re-encoded as JPEG when it is large.
typedef ImagePreparer = Future<PreparedImage> Function(
  Uint8List bytes,
  String name,
  String? mime,
);

Future<PreparedImage> prepareImage(
  Uint8List bytes,
  String name,
  String? mime,
) async {
  final type = mime ?? sniffImageMime(bytes);
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final w = descriptor.width, h = descriptor.height;
  final longest = w > h ? w : h;
  final fits = longest <= maxImageSide;
  if (fits &&
      _accepted.contains(type) &&
      (bytes.length <= keepOriginalBelow || type == 'image/gif')) {
    descriptor.dispose();
    buffer.dispose();
    return PreparedImage(bytes, type!, name);
  }
  final scale = fits ? 1.0 : maxImageSide / longest;
  final codec = await descriptor.instantiateCodec(
    targetWidth: (w * scale).round(),
    targetHeight: (h * scale).round(),
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final iw = image.width, ih = image.height;
  image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  final jpeg = await compute(_encodeJpeg, (rgba!.buffer.asUint8List(), iw, ih));
  return PreparedImage(jpeg, 'image/jpeg', _withExtension(name, 'jpg'));
}

Uint8List _encodeJpeg((Uint8List, int, int) a) {
  final (rgba, w, h) = a;
  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: 85);
}

String _withExtension(String name, String ext) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return '${stem.isEmpty ? 'photo' : stem}.$ext';
}

/// Image type from the leading bytes; null when unknown.
String? sniffImageMime(Uint8List b) {
  bool at(int o, List<int> sig) {
    if (b.length < o + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[o + i] != sig[i]) return false;
    }
    return true;
  }

  if (at(0, [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (at(0, [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  if (at(4, [0x66, 0x74, 0x79, 0x70])) return 'image/heic';
  return null;
}
