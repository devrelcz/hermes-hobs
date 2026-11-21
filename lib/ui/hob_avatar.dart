import 'dart:math' as math;

import 'package:blobatar_flutter/blobatar_flutter.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';
import 'theme.dart';

/// What an avatar draws: resolved from a hob's stored `shape` and `color`
/// the way the dashboard resolves them.
class HobFace {
  const HobFace({
    required this.shape,
    required this.color,
    this.lightEyes = false,
    this.blobSeed,
    this.blobKind,
  });

  /// One of the shapes [_AvatarPainter] knows; anything else is a circle.
  final String shape;
  final Color color;

  /// Dark bodies get light eyes.
  final bool lightEyes;

  /// Set for a generated "blobatar" face: the seed it grows from. It brings
  /// its own colors, so [shape] and [color] are not drawn.
  final String? blobSeed;

  /// The silhouette a blobatar is pinned to; null lets the seed decide.
  final String? blobKind;

  @override
  bool operator ==(Object other) =>
      other is HobFace &&
      other.shape == shape &&
      other.color == color &&
      other.lightEyes == lightEyes &&
      other.blobSeed == blobSeed &&
      other.blobKind == blobKind;

  @override
  int get hashCode => Object.hash(shape, color, lightEyes, blobSeed, blobKind);
}

/// Hob avatar as the dashboard draws it: a colored shape with two eyes.
///
/// Shape and color come from `ui_meta['hermes-bots']` (`shape`, `color`).
/// Without them both are derived from the hob name with the dashboard's own
/// formulas, so a hob has the same face here and on the web.
class HobAvatar extends StatelessWidget {
  const HobAvatar({
    super.key,
    required this.hob,
    this.size = 36,
    this.working = false,
    this.face,
  });

  final Hob hob;
  final double size;

  /// Draw this face instead of the hob's own (editor preview).
  final HobFace? face;

  /// Shows the green presence dot.
  final bool working;

  /// Shapes a name can turn into, in the dashboard's order.
  static const _autoShapes = [
    'circle',
    'squircle',
    'pill',
    'triangle',
    'hexagon',
    'cloud',
    'drop',
  ];

  /// Shapes the editor offers, in the dashboard's order.
  static const pickableShapes = [
    'circle',
    'blob',
    'squircle',
    'pill',
    'triangle',
    'hexagon',
    'cloud',
    'drop',
  ];

  /// Names the dashboard draws as one of the shapes above.
  static const _aliases = {
    'teardrop': 'drop',
    'tetrahedron': 'triangle',
    'wedge': 'triangle',
    'hex': 'hexagon',
    'icosahedron': 'hexagon',
    'dodecahedron': 'hexagon',
  };

  /// Blobatar silhouettes with the trait value the dashboard pins each to.
  static const blobKinds = {
    'round': .11,
    'organic': .35,
    'boxy': .54,
    'capsule': .65,
    'nub': .745,
    'cloud': .825,
    'droplet': .8875,
    'hexagon': .9325,
    'sun': .965,
    'triangle': .99,
  };

  static bool isBlob(String? shape) =>
      shape == 'blobatar' || (shape?.startsWith('blobatar:') ?? false);

  /// The seed a stored blobatar shape carries (`blobatar:<seed>:<kind>`);
  /// empty when the face follows the hob's name.
  static String blobSeedOf(String? shape) =>
      isBlob(shape) ? (shape!.split(':').elementAtOrNull(1) ?? '') : '';

  /// The silhouette a stored blobatar shape is pinned to, or null.
  static String? blobKindOf(String? shape) {
    final kind = isBlob(shape) ? shape!.split(':').elementAtOrNull(2) : null;
    return blobKinds.containsKey(kind) ? kind : null;
  }

  /// The stored value for a blobatar with this [seed] and [kind].
  static String blobShape(String seed, String? kind) => kind != null
      ? 'blobatar:$seed:$kind'
      : (seed.isEmpty ? 'blobatar' : 'blobatar:$seed');

  /// The dashboard's swatches, stored the way it stores them.
  static final List<String> palette = [
    for (var i = 0; i < 12; i++) 'hsl(${i * 30} 68% 58%)',
  ];

  /// The dashboard's color for the default profile and for nameless hobs.
  static const _fallbackColor = Color(0xFF8B5CF6);

  /// The dashboard's string hash: `h * 31 + unit`, wrapped to 32 bits.
  static int _hash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0xFFFFFFFF;
    }
    return h;
  }

  static HobFace faceOf(Hob hob) => resolve(
    name: hob.name,
    shape: hob.shape,
    color: hob.color,
    custom: hob.meta['custom'] == true,
  );

  /// The face for a stored [shape] and [color]; null takes the one derived
  /// from [name]. The default profile keeps its fixed face until the user
  /// picks one ([custom]).
  static HobFace resolve({
    required String name,
    String? shape,
    String? color,
    bool custom = false,
  }) {
    if (name.trim().toLowerCase() == 'default' && !custom) {
      return const HobFace(shape: 'squircle', color: _fallbackColor);
    }
    final parsed = parseColor(color);
    final seed = blobSeedOf(shape);
    return HobFace(
      blobSeed: !isBlob(shape)
          ? null
          : (seed.isNotEmpty ? seed : (name.isNotEmpty ? name : 'agent')),
      blobKind: blobKindOf(shape),
      shape: pickedShape(shape) ?? autoShape(name),
      color: parsed ?? autoColor(name),
      // The dashboard only measures colors written as hex.
      lightEyes:
          parsed != null && color!.trim().startsWith('#') && _isDark(parsed),
    );
  }

  static String shapeFor(Hob hob) => faceOf(hob).shape;

  static Color colorFor(Hob hob) => faceOf(hob).color;

  /// The drawable shape a stored `shape` value names, or null when the name
  /// decides (nothing stored, or a shape this app cannot draw).
  static String? pickedShape(String? stored) {
    final s = _aliases[stored] ?? stored;
    return pickableShapes.contains(s) ? s : null;
  }

  /// The shape a hob gets from its name when none is picked.
  static String autoShape(String name) =>
      _autoShapes[_hash(name) % _autoShapes.length];

  /// The color a hob gets from its name when none is picked.
  static Color autoColor(String name) {
    final n = name.trim();
    if (n.isEmpty || n == 'default') return _fallbackColor;
    return HSLColor.fromAHSL(
      1,
      (_hash(n) % 360).toDouble(),
      .68,
      .58,
    ).toColor();
  }

  static final _hex = RegExp(r'^#([0-9a-fA-F]{6})$');
  static final _hsl = RegExp(
    r'^hsl\(\s*([\d.]+)(?:deg)?[\s,]+([\d.]+)%[\s,]+([\d.]+)%\s*\)$',
  );

  /// Reads a stored color: `#RRGGBB` or `hsl(H S% L%)`.
  static Color? parseColor(String? value) {
    final c = value?.trim() ?? '';
    final hex = _hex.firstMatch(c);
    if (hex != null) return Color(int.parse(hex[1]!, radix: 16) | 0xFF000000);
    final hsl = _hsl.firstMatch(c);
    if (hsl == null) return null;
    final h = double.tryParse(hsl[1]!), s = double.tryParse(hsl[2]!);
    final l = double.tryParse(hsl[3]!);
    if (h == null || s == null || l == null) return null;
    return HSLColor.fromAHSL(
      1,
      h % 360,
      (s / 100).clamp(0, 1),
      (l / 100).clamp(0, 1),
    ).toColor();
  }

  static bool _isDark(Color c) =>
      (.2126 * c.r + .7152 * c.g + .0722 * c.b) * 255 < 110;

  @override
  Widget build(BuildContext context) {
    final face = this.face ?? faceOf(hob);
    final dot = size * 0.3;
    // A face is decoration: the Hob's name always stands next to it (or in
    // its button's tooltip), so screen readers skip it.
    return ExcludeSemantics(child: _face(context, face, dot));
  }

  Widget _face(BuildContext context, HobFace face, double dot) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (face.blobSeed != null)
            Blobatar(
              name: face.blobSeed!,
              size: size,
              traitOverrides: face.blobKind == null
                  ? null
                  : {'shape': blobKinds[face.blobKind]!},
            )
          else
            CustomPaint(size: Size.square(size), painter: _AvatarPainter(face)),
          if (working)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: HobsColors.of(context).working,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints a face in the dashboard's 40-unit box: the body around (20, 20),
/// the eyes on fixed spots, each with a small highlight.
class _AvatarPainter extends CustomPainter {
  _AvatarPainter(this.face);

  final HobFace face;

  static const _steps = 52;

  /// Radius of the body at [angle], for the shapes the dashboard traces
  /// around the center.
  double _radius(double angle) {
    final c = math.cos(angle).abs(), s = math.sin(angle).abs();
    switch (face.shape) {
      case 'blob':
        return 16 + 1.7 * math.sin(3 * angle) + .7 * math.cos(5 * angle);
      case 'squircle':
        return 16.2 / math.pow(math.pow(c, 5) + math.pow(s, 5), 1 / 5);
      case 'pill':
        return 16 / math.pow(math.pow(c, 8) + math.pow(s / .72, 8), 1 / 8);
      case 'triangle':
        const third = math.pi * 2 / 3;
        final t = ((angle + math.pi / 2 + math.pi * 2) % (math.pi * 2)) / third;
        return 13.5 / math.max(.42, math.cos((t % 1 - .5) * 1.9));
      case 'hexagon':
        const sixth = math.pi / 3;
        final nearest = sixth * (angle / sixth).round();
        return 16.2 * math.cos(sixth / 2) / math.cos(angle - nearest);
      default:
        return 16.2;
    }
  }

  Path _body() {
    final p = Path();
    switch (face.shape) {
      case 'cloud':
        p
          ..moveTo(11, 32)
          ..arcToPoint(
            const Offset(10, 17.1),
            radius: const Radius.circular(7.5),
          )
          ..arcToPoint(
            const Offset(29, 12.5),
            radius: const Radius.circular(9.5),
          )
          ..arcToPoint(const Offset(30, 32), radius: const Radius.circular(7))
          ..close();
      case 'drop':
        p
          ..moveTo(20, 3)
          ..cubicTo(20, 3, 6, 20, 6, 27)
          ..arcTo(
            Rect.fromCenter(
              center: const Offset(20, 27),
              width: 28,
              height: 27,
            ),
            math.pi,
            -math.pi,
            false,
          )
          ..cubicTo(34, 20, 20, 3, 20, 3)
          ..close();
      default:
        for (var i = 0; i < _steps; i++) {
          final a = i / _steps * math.pi * 2 - math.pi / 2;
          final r = _radius(a);
          final x = 20 + r * math.cos(a), y = 20 + r * math.sin(a);
          i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
        }
        p.close();
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40);
    canvas.drawPath(_body(), Paint()..color = face.color);
    final eye = Paint()
      ..color = face.lightEyes
          ? const Color.fromRGBO(232, 220, 195, .95)
          : const Color.fromRGBO(0, 0, 0, .85);
    final glint = Paint()
      ..color = face.lightEyes
          ? const Color.fromRGBO(0, 0, 0, .6)
          : const Color.fromRGBO(255, 255, 255, .85);
    final y = face.shape == 'cloud' ? 22.0 : 17.2;
    for (final x in const [15.4, 24.6]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: 4.4, height: 4.6),
        eye,
      );
      canvas.drawCircle(Offset(x - .6, y - .7), .65, glint);
    }
  }

  @override
  bool shouldRepaint(_AvatarPainter old) => old.face != face;
}

/// A Hob's face that flies from the list into its chat's header when the
/// chat opens over the list (phones). Off with reduced motion, and wherever
/// the list and the chat share one screen (wide windows), where two faces
/// of the same Hob are on screen at once.
class HobHero extends StatelessWidget {
  const HobHero({
    super.key,
    required this.name,
    required this.enabled,
    required this.child,
  });

  final String name;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled || MediaQuery.disableAnimationsOf(context)) return child;
    return Hero(tag: 'hob-face:$name', child: child);
  }
}
