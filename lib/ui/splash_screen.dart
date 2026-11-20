import 'package:flutter/material.dart';

/// Shown while the stored session is being restored. Matches the native launch
/// screens (the Hobs glyph on moss) so startup reads as one continuous splash.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const moss = Color(0xFF2F6B4A);
  static const ink = Color(0xFF2C2C2A);
  static const amber = Color(0xFFFFAC02);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: moss,
      body: Center(
        child: CustomPaint(size: Size.square(160), painter: HobGlyphPainter()),
      ),
    );
  }
}

/// The hob: a little elf with a fringe of dark hair under a pointed cap whose
/// tip curls over to a pompom, a darker band round the cap, pointed ears and
/// two eyes, drawn on a 100x100 grid. Keep in sync with the glyph in
/// tool/generate_icons.sh.
class HobGlyphPainter extends CustomPainter {
  const HobGlyphPainter();

  static const _amberDark = Color(0xFFCC8700);
  static const _cream = Color(0xFFFBEBC8);
  static const _skin = Color(0xFFF8C77E);
  static const _hair = Color(0xFF1E5636);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final skin = Paint()..color = _skin;
    final hair = Path()
      ..moveTo(23, 73)
      ..cubicTo(23, 52, 34, 45, 50, 45)
      ..cubicTo(66, 45, 77, 52, 77, 73)
      ..close();
    final leftEar = Path()
      ..moveTo(8.5, 57.5)
      ..cubicTo(14, 59, 21, 61, 28, 63)
      ..lineTo(29, 77)
      ..cubicTo(20, 75, 12, 67, 8.5, 57.5)
      ..close();
    final rightEar = Path()
      ..moveTo(91.5, 57.5)
      ..cubicTo(86, 59, 79, 61, 72, 63)
      ..lineTo(71, 77)
      ..cubicTo(80, 75, 88, 67, 91.5, 57.5)
      ..close();
    // The chin is the lower half of a circle; the top edge sweeps up into a
    // lock of the fringe left of center.
    final face = Path()
      ..moveTo(27.5, 68)
      ..arcToPoint(
        const Offset(72.5, 68),
        radius: const Radius.circular(22.5),
        clockwise: false,
      )
      ..cubicTo(71, 61, 63, 56.5, 53, 56.8)
      ..cubicTo(48.5, 57, 44.8, 56.5, 43, 53.3)
      ..cubicTo(40, 58, 31, 61, 27.5, 68)
      ..close();
    final cap = Path()
      ..moveTo(21, 60.5)
      ..quadraticBezierTo(17.6, 60.5, 17.7, 56)
      ..cubicTo(18, 44, 26, 32, 37, 23)
      ..cubicTo(45, 16, 54, 12.5, 62, 12.2)
      ..cubicTo(72, 12, 79, 20, 81, 29)
      ..cubicTo(76, 25, 69, 25, 65, 27)
      ..cubicTo(62, 28.5, 62.5, 31.5, 64.5, 33.5)
      ..cubicTo(71, 41, 77, 49, 78.6, 56)
      ..quadraticBezierTo(79.4, 60.5, 76, 60.5)
      ..cubicTo(66, 47, 34, 47, 21, 60.5)
      ..close();
    final band = Path()
      ..moveTo(0, 46)
      ..quadraticBezierTo(50, 33, 100, 46)
      ..lineTo(100, 100)
      ..lineTo(0, 100)
      ..close();
    final eye = Paint()..color = SplashScreen.ink;
    canvas
      ..drawPath(hair, Paint()..color = _hair)
      ..drawPath(leftEar, skin)
      ..drawPath(rightEar, skin)
      ..drawPath(face, skin)
      ..drawPath(cap, Paint()..color = SplashScreen.amber)
      ..save()
      ..clipPath(cap)
      ..drawPath(band, Paint()..color = _amberDark)
      ..restore()
      ..drawCircle(const Offset(83.5, 33), 7, Paint()..color = _cream)
      ..drawCircle(const Offset(40, 69), 3.5, eye)
      ..drawCircle(const Offset(61, 69), 3.5, eye);
  }

  @override
  bool shouldRepaint(HobGlyphPainter oldDelegate) => false;
}
