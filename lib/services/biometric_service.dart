import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final LocalAuthentication _auth = LocalAuthentication();

  /// True if the device supports biometric checks.
  ///
  /// Phase H3 review-pass tightening: previously this returned
  /// `canCheckBiometrics || isDeviceSupported()`, which admits passcode-only
  /// devices (no enrolled fingerprint or face). The settings card titled
  /// "Biometric on financial actions" was therefore enabled on devices that
  /// had no biometrics at all, which is misleading. We now require
  /// `canCheckBiometrics` (which is true only when at least one biometric
  /// is enrolled). The auth prompt itself still allows passcode fallback
  /// via `biometricOnly: false`, so users with biometrics enrolled who
  /// later remove them can still authenticate via passcode — they just
  /// can't *enable* the feature without enrolling first.
  Future<bool> get isAvailable async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canCheck && supported;
    } catch (e) {
      return false;
    }
  }

  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('biometric_lock_enabled') ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_lock_enabled', enabled);
  }

  /// Show the system biometric prompt with an action-specific reason.
  ///
  /// [reason] is shown to the user inside the system dialog. It should
  /// answer "what am I authorising?" — e.g. "Authenticate to release crypto"
  /// or "Authenticate to send mobile money". Defaults to a generic app-unlock
  /// string when no reason is supplied (e.g., the launcher unlock flow).
  ///
  /// Phase H3: previously this hard-coded the reason. Every callsite was
  /// passing tailored copy that never reached `local_auth`, defeating the
  /// purpose of the per-action prompt as a security signal ("don't approve,
  /// you didn't ask to send money").
  ///
  /// Options notes:
  ///  - `biometricOnly: false` — Phase H3 design allows passcode/PIN
  ///    fallback so users without enrolled biometrics can still authorise.
  ///  - `stickyAuth: true` — high-stakes financial confirms shouldn't
  ///    silently cancel if a notification briefly backgrounds the app.
  ///    With sticky auth the prompt resumes when the user returns instead
  ///    of throwing them back to the slide-to-confirm with no feedback.
  ///  - `sensorOnly` was removed in `local_auth` 2.3+; the `useErrorDialogs`
  ///    default (true) gives the same UX the legacy flag was meant to gate.
  Future<bool> authenticate({String? reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason ?? 'Authenticate to access Azaman',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      return false;
    }
  }
}
