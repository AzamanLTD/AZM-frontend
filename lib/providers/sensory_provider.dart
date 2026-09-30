// =============================================================================
// SENSORY & MOTION PREFERENCES  (TASK-026)
//
// The user's right to turn the premium layer OFF.
//
// Why a dedicated provider instead of new fields on SettingsProvider?
//   * `settings_provider.dart` is load-bearing (Appendix 2) and is read on nearly
//     every frame by 30+ screens. Adding fields to it widens that blast radius for
//     no gain.
//   * The consumers of this gate are STATIC helpers (`AzamanHaptics`, `AzSound`)
//     that have no BuildContext. `AzSensory` below is the single static sink they
//     read, and it is written from exactly one place — this notifier.
//
// Defaults are deliberately conservative:
//   haptics          ON   — matches today's behaviour (246 raw calls already fire)
//   sound            ON, but SUCCESS-ONLY (tick / whoosh stay opt-in extras)
//   ambient motion   ON   — exactly one ambient loop is allowed, on Home only
//   reduce motion    null — null means "follow the OS"; true/false are explicit
//                           user overrides. null is NOT the same as false.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SensoryPreferences {
  final bool hapticsEnabled;
  final bool soundEnabled;

  /// When true, only success / coin / rip play. The UI tick and the transition
  /// whoosh stay silent. Default = true, because a tick on every tap is the
  /// fastest way to make an app's sound feel cheap.
  final bool soundSuccessOnly;

  /// Home's (and only Home's) ambient loop: the Level-5 sheen drift.
  /// Off means the app is completely still when untouched.
  final bool ambientMotionEnabled;

  /// null → follow the OS (`MediaQuery.disableAnimations`).
  final bool? forceReduceMotion;

  const SensoryPreferences({
    this.hapticsEnabled = true,
    this.soundEnabled = true,
    this.soundSuccessOnly = true,
    this.ambientMotionEnabled = true,
    this.forceReduceMotion,
  });

  /// The single answer to "should this screen reduce motion right now?".
  bool reducesMotion({required bool osDisableAnimations}) =>
      forceReduceMotion ?? osDisableAnimations;
}

/// Static sink read by context-free helpers. Written only by [SensoryProvider].
class AzSensory {
  const AzSensory._();

  static bool hapticsEnabled = true;
  static bool soundEnabled = true;
  static bool soundSuccessOnly = true;
  static bool ambientEnabled = true;
  static bool reduceMotionOverrideIsSet = false;
  static bool reduceMotionOverride = false;

  /// Idempotent, and safe to call before the provider has loaded (defaults apply).
  static void apply(SensoryPreferences p) {
    hapticsEnabled = p.hapticsEnabled;
    soundEnabled = p.soundEnabled;
    soundSuccessOnly = p.soundSuccessOnly;
    ambientEnabled = p.ambientMotionEnabled;
    final forced = p.forceReduceMotion;
    reduceMotionOverrideIsSet = forced != null;
    reduceMotionOverride = forced ?? false;
  }
}

class SensoryProvider extends ChangeNotifier {
  SensoryPreferences _prefs = const SensoryPreferences();
  bool _isLoaded = false;

  SensoryPreferences get prefs => _prefs;
  bool get isLoaded => _isLoaded;

  /// Preference keys. Prefixed `az_` so they can never collide with the
  /// `push_notifications` / `trade_alerts` family owned by SettingsProvider.
  static const kHaptics = 'az_haptics_enabled';
  static const kSound = 'az_sound_enabled';
  static const kSoundSuccessOnly = 'az_sound_success_only';
  static const kAmbient = 'az_ambient_motion_enabled';

  /// Sentinel storage for a tri-state boolean: -1 unset, 0 forced-off, 1 forced-on.
  static const kReduceOverride = 'az_reduce_motion_override';

  SensoryProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final reduceRaw = prefs.getInt(kReduceOverride) ?? -1;
    _prefs = SensoryPreferences(
      hapticsEnabled: prefs.getBool(kHaptics) ?? true,
      soundEnabled: prefs.getBool(kSound) ?? true,
      soundSuccessOnly: prefs.getBool(kSoundSuccessOnly) ?? true,
      ambientMotionEnabled: prefs.getBool(kAmbient) ?? true,
      forceReduceMotion: reduceRaw == -1 ? null : reduceRaw == 1,
    );
    AzSensory.apply(_prefs);
    _isLoaded = true;
    notifyListeners();
  }

  void _commit(SensoryPreferences next) {
    _prefs = next;
    AzSensory.apply(_prefs);
    notifyListeners();
  }

  Future<void> setHapticsEnabled(bool value) async {
    _commit(SensoryPreferences(
      hapticsEnabled: value,
      soundEnabled: _prefs.soundEnabled,
      soundSuccessOnly: _prefs.soundSuccessOnly,
      ambientMotionEnabled: _prefs.ambientMotionEnabled,
      forceReduceMotion: _prefs.forceReduceMotion,
    ));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kHaptics, value);
  }

  Future<void> setSoundEnabled(bool value) async {
    _commit(SensoryPreferences(
      hapticsEnabled: _prefs.hapticsEnabled,
      soundEnabled: value,
      soundSuccessOnly: _prefs.soundSuccessOnly,
      ambientMotionEnabled: _prefs.ambientMotionEnabled,
      forceReduceMotion: _prefs.forceReduceMotion,
    ));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kSound, value);
  }

  Future<void> setSoundSuccessOnly(bool value) async {
    _commit(SensoryPreferences(
      hapticsEnabled: _prefs.hapticsEnabled,
      soundEnabled: _prefs.soundEnabled,
      soundSuccessOnly: value,
      ambientMotionEnabled: _prefs.ambientMotionEnabled,
      forceReduceMotion: _prefs.forceReduceMotion,
    ));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kSoundSuccessOnly, value);
  }

  Future<void> setAmbientMotionEnabled(bool value) async {
    _commit(SensoryPreferences(
      hapticsEnabled: _prefs.hapticsEnabled,
      soundEnabled: _prefs.soundEnabled,
      soundSuccessOnly: _prefs.soundSuccessOnly,
      ambientMotionEnabled: value,
      forceReduceMotion: _prefs.forceReduceMotion,
    ));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAmbient, value);
  }

  /// Tri-state. `null` clears the override and returns control to the OS.
  Future<void> setForceReduceMotion(bool? value) async {
    _commit(SensoryPreferences(
      hapticsEnabled: _prefs.hapticsEnabled,
      soundEnabled: _prefs.soundEnabled,
      soundSuccessOnly: _prefs.soundSuccessOnly,
      ambientMotionEnabled: _prefs.ambientMotionEnabled,
      forceReduceMotion: value,
    ));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kReduceOverride, value == null ? -1 : (value ? 1 : 0));
  }
}

final sensoryProvider = ChangeNotifierProvider<SensoryProvider>((ref) {
  return SensoryProvider();
});
