import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/strings.dart';
import '../state/pairing.dart';

/// Scans a Hermes server's pairing QR code and pops with the [PairingCode]
/// it carries; pops with nothing when the user backs out.
///
/// Frames are read on the device and never stored or sent anywhere.
class PairScanScreen extends StatefulWidget {
  const PairScanScreen({super.key});

  /// The scanner is offered where the device has a camera to point at a
  /// screen: on phones and tablets.
  static bool get canScan =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Opens the scanner over [context].
  static Future<PairingCode?> open(BuildContext context) =>
      Navigator.of(context).push<PairingCode>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const PairScanScreen(),
        ),
      );

  @override
  State<PairScanScreen> createState() => _PairScanScreenState();
}

class _PairScanScreenState extends State<PairScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// Set once a code was accepted: the camera keeps reporting it.
  bool _done = false;

  /// Why the last code was refused. Built at paint time.
  String Function(Strings s)? _refused;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    PairingFailure? failure;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      try {
        final code = PairingCode.parse(raw);
        _done = true;
        Navigator.of(context).pop(code);
        return;
      } on PairingException catch (e) {
        // A newer format says more than "not a pairing code".
        if (failure != PairingFailure.newerVersion) failure = e.failure;
      }
    }
    if (failure == null || !mounted) return;
    final shown = failure;
    setState(
      () => _refused = (s) => shown == PairingFailure.newerVersion
          ? s.scanNewerVersion
          : s.scanNotPairing,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final refused = _refused?.call(s);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(s.scanTitle),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, _) {
              if (state.torchState == TorchState.unavailable) {
                return const SizedBox.shrink();
              }
              final on = state.torchState == TorchState.on;
              return IconButton(
                icon: Icon(on ? Icons.flash_on : Icons.flash_off),
                tooltip: on ? s.scanTorchOff : s.scanTorchOn,
                onPressed: _controller.toggleTorch,
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _Message(
              icon: Icons.no_photography_outlined,
              text: error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? s.scanNoPermission
                  : s.scanNoCamera,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.all(20),
              child: Material(
                color: refused != null
                    ? theme.colorScheme.errorContainer
                    : Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      refused ?? s.scanInstruction,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: refused != null
                            ? theme.colorScheme.onErrorContainer
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    ),
  );
}
