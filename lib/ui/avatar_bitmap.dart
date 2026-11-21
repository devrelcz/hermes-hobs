import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../api/models.dart';
import 'hob_avatar.dart';

/// A Hob's face as PNG bytes, for places outside the widget tree (the large
/// icon of a notification). Rendered off screen through its own small
/// pipeline; cached per face. Null when it cannot be drawn (no view, a
/// headless test): callers go on without a picture.
class AvatarBitmaps {
  AvatarBitmaps._();

  static final Map<String, Future<Uint8List?>> _cache = {};

  static Future<Uint8List?> of(Hob hob, {double size = 96}) {
    final face = HobAvatar.faceOf(hob);
    final key =
        '${hob.name}|${face.shape}|${face.color}|${face.blobSeed}|'
        '${face.blobKind}|$size';
    return _cache[key] ??=
        _render(
          HobAvatar(hob: hob, size: size, face: face),
          Size.square(size),
        ).catchError((Object e) {
          debugPrint('avatar bitmap: $e');
          _cache.remove(key);
          return null;
        });
  }

  static Future<Uint8List?> _render(Widget widget, Size size) async {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return null;
    final view = views.first;
    const ratio = 2.0;
    final boundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(size),
        physicalConstraints: BoxConstraints.tight(size * ratio),
        devicePixelRatio: ratio,
      ),
      child: RenderPositionedBox(child: boundary),
    );
    final pipeline = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();
    final build = BuildOwner(focusManager: FocusManager());
    final root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: MediaQuery(
        // Still: the face's idle motion has no frames to run in here.
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: TickerMode(enabled: false, child: widget),
        ),
      ),
    ).attachToRenderTree(build);
    build
      ..buildScope(root)
      ..finalizeTree();
    pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }
}
