// =============================================================================
// AZAMAN — THE INTRO SEEN FLAG (local only)
//
// The public first-launch intro is device state, not account state. It lives
// in SharedPreferences under one key and is NOTHING to do with the backend's
// `onboardingCompleted` / `onboardingStep`, which belong to the authenticated
// setup. Keeping them in different stores is the whole point: a tap on "Skip"
// must be unable to look like "setup finished" from the server's side.
//
// Failure rule: if the flag cannot be read (corrupt store, platform channel
// missing), the app treats the intro as NOT seen. Showing a two-tap tour to a
// returning user is a mild annoyance; silently skipping the tour for every
// new install is a product decision nobody made.
// =============================================================================
import 'package:shared_preferences/shared_preferences.dart';

/// The one key. Named for the product, never for the mechanism.
const String kIntroSeenPrefKey = 'azaman_intro_seen';

class IntroStore {
  const IntroStore();

  /// True only when the flag was written. Unreadable means unseen.
  Future<bool> hasSeenIntro() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(kIntroSeenPrefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Records that the intro has been seen (finished OR skipped).
  ///
  /// Returns false when the write failed, so a caller that cares can tell the
  /// difference between "recorded" and "will be shown again next launch".
  Future<bool> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(kIntroSeenPrefKey, true);
    } catch (_) {
      return false;
    }
  }
}
