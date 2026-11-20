import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Which biometric the device offers, so the UI can name it the way the
/// platform does (Face ID and Touch ID on Apple, plain words on Android).
enum BiometricKind { faceId, touchId, fingerprint, face, generic }

/// Why an authentication did not let the user in.
enum BiometricFailure {
  /// The user (or the system) closed the prompt. Nothing to report.
  cancelled,

  /// The face or finger did not match. Try again.
  failed,

  /// Biometrics cannot be used right now: none enrolled, locked out after
  /// too many attempts, or the hardware is gone. The password is the way in.
  unavailable,
}

class BiometricException implements Exception {
  const BiometricException(this.failure);
  final BiometricFailure failure;

  @override
  String toString() => 'BiometricException(${failure.name})';
}

/// Thin wrapper over `local_auth`, so tests can swap in a fake and the rest
/// of the app never sees platform exceptions.
class Biometrics {
  Biometrics({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// The biometric this device can use right now, or null when there is none
  /// enrolled (or the platform has no support at all).
  Future<BiometricKind?> available() async {
    try {
      if (!await _auth.canCheckBiometrics) return null;
      final types = await _auth.getAvailableBiometrics();
      if (types.isEmpty) return null;
      final apple =
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS;
      if (types.contains(BiometricType.face)) {
        return apple ? BiometricKind.faceId : BiometricKind.face;
      }
      if (types.contains(BiometricType.fingerprint)) {
        return apple ? BiometricKind.touchId : BiometricKind.fingerprint;
      }
      return BiometricKind.generic;
    } catch (_) {
      // No plugin (tests, unsupported platform) or the check itself failed.
      return null;
    }
  }

  /// Shows the system prompt with [reason]. Completes normally when the user
  /// is verified; throws [BiometricException] otherwise. The device passcode
  /// is allowed as a fallback, like the system's own lock screen.
  Future<void> authenticate(String reason) async {
    bool ok;
    try {
      ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      throw BiometricException(switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.authInProgress ||
        LocalAuthExceptionCode.userRequestedFallback =>
          BiometricFailure.cancelled,
        LocalAuthExceptionCode.timeout => BiometricFailure.failed,
        _ => BiometricFailure.unavailable,
      });
    } on PlatformException {
      throw const BiometricException(BiometricFailure.unavailable);
    } on MissingPluginException {
      throw const BiometricException(BiometricFailure.unavailable);
    }
    if (!ok) throw const BiometricException(BiometricFailure.failed);
  }
}
