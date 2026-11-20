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

/// The hob: a little elf in a pointed cap with a bent tip, pointed ears and two
/// eyes, drawn on a 100x100 grid. Keep in sync with the glyph in
/// tool/generate_icons.sh.
class HobGlyphPainter extends CustomPainter {
  const HobGlyphPainter();

  static const _amberDark = Color(0xFFD88F00);
  static const _cream = Color(0xFFFBEBC8);
  static const _skin = Color(0xFFF2C98A);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final skin = Paint()..color = _skin;
    canvas
      ..drawPath(
        Path()..addPolygon(const [
          Offset(22, 66),
          Offset(8, 54),
          Offset(30, 60),
        ], true),
        skin,
      )
      ..drawPath(
        Path()..addPolygon(const [
          Offset(78, 66),
          Offset(92, 54),
          Offset(70, 60),
        ], true),
        skin,
      )
      ..drawCircle(const Offset(50, 66), 22, skin);
    final cap = Path()
      ..moveTo(22, 58)
      ..cubicTo(26, 36, 40, 20, 56, 14)
      ..cubicTo(68, 10, 80, 16, 84, 26)
      ..cubicTo(76, 22, 68, 24, 64, 32)
      ..cubicTo(70, 40, 76, 50, 78, 58)
      ..close();
    final eye = Paint()..color = SplashScreen.ink;
    canvas
      ..drawPath(cap, Paint()..color = SplashScreen.amber)
      ..drawCircle(const Offset(84, 27), 5, Paint()..color = _cream)
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(20, 52, 60, 11),
          const Radius.circular(5.5),
        ),
        Paint()..color = _amberDark,
      )
      ..drawCircle(const Offset(42, 71), 3.8, eye)
      ..drawCircle(const Offset(58, 71), 3.8, eye);
  }

  @override
  bool shouldRepaint(HobGlyphPainter oldDelegate) => false;
}
