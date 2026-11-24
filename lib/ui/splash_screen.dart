import 'package:flutter/material.dart';

/// Shown while the stored session is being restored. Matches the native launch
/// screens (the Hobs glyph on moss) so startup reads as one continuous splash.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const moss = Color(0xFF2F6B4A);
  static const ink = Color(0xFF232723);
  static const amber = Color(0xFFFFAC02);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: moss,
      body: Center(child: HobGlyph(size: 160)),
    );
  }
}

/// The shared HobCrew mark, rendered from the same SVG as the native icons.
class HobGlyph extends StatelessWidget {
  const HobGlyph({super.key, this.size});

  final double? size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo/hobs-glyph.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
  }
}
