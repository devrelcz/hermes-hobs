import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/biometrics.dart';
import 'splash_screen.dart';

/// Icon matching the biometric the device offers.
IconData biometricIcon(BiometricKind? kind) => switch (kind) {
  BiometricKind.faceId || BiometricKind.face => Icons.face_outlined,
  BiometricKind.touchId || BiometricKind.fingerprint => Icons.fingerprint,
  _ => Icons.lock_open_outlined,
};

/// What to tell the user after a prompt that did not let them in; null when
/// they closed it themselves.
String? describeBiometricFailure(BiometricException e) {
  final s = Strings.current;
  return switch (e.failure) {
    BiometricFailure.cancelled => null,
    BiometricFailure.failed => s.biometricFailed,
    BiometricFailure.unavailable => s.biometricUnavailable,
  };
}

/// Covers the whole app (every route) while [AppState.locked]. Asks for the
/// biometric as soon as it shows; the password is always a way out.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;

  /// Built at paint time, so a language switch re-words it.
  String? Function()? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().unlock();
    } on BiometricException catch (e) {
      if (mounted) setState(() => _error = () => describeBiometricFailure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = Strings.of(context);
    final kind = app.biometricKind;
    final error = _error?.call();
    const ink = SplashScreen.ink;
    const amber = SplashScreen.amber;
    return Scaffold(
      backgroundColor: SplashScreen.moss,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: CustomPaint(
                      size: Size.square(120),
                      painter: HobGlyphPainter(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s.locked,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (app.username.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      app.username,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: amber,
                      foregroundColor: ink,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _busy ? null : _unlock,
                    icon: Icon(biometricIcon(kind)),
                    label: Text(s.unlockWith(kind ?? BiometricKind.generic)),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFFF8A80)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: _busy ? null : app.logout,
                    child: Text(s.signInWithPassword),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
