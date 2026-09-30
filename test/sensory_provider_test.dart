import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/sensory_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AzSensory.apply(const SensoryPreferences());
  });

  group('SensoryPreferences.reducesMotion', () {
    test('follows the OS when no override is set', () {
      const p = SensoryPreferences();
      expect(p.reducesMotion(osDisableAnimations: true), isTrue);
      expect(p.reducesMotion(osDisableAnimations: false), isFalse);
    });

    test('an explicit override wins in both directions', () {
      const forcedOn = SensoryPreferences(forceReduceMotion: true);
      expect(forcedOn.reducesMotion(osDisableAnimations: false), isTrue);

      const forcedOff = SensoryPreferences(forceReduceMotion: false);
      expect(forcedOff.reducesMotion(osDisableAnimations: true), isFalse);
    });
  });

  group('AzSensory static sink', () {
    test('apply() mirrors every field', () {
      AzSensory.apply(const SensoryPreferences(
        hapticsEnabled: false,
        soundEnabled: false,
        soundSuccessOnly: false,
        ambientMotionEnabled: false,
        forceReduceMotion: true,
      ));
      expect(AzSensory.hapticsEnabled, isFalse);
      expect(AzSensory.soundEnabled, isFalse);
      expect(AzSensory.soundSuccessOnly, isFalse);
      expect(AzSensory.ambientEnabled, isFalse);
      expect(AzSensory.reduceMotionOverrideIsSet, isTrue);
      expect(AzSensory.reduceMotionOverride, isTrue);
    });

    test('a null override records "not set" rather than false', () {
      AzSensory.apply(const SensoryPreferences(forceReduceMotion: null));
      expect(AzSensory.reduceMotionOverrideIsSet, isFalse);
      expect(AzSensory.reduceMotionOverride, isFalse);
    });
  });

  group('persistence', () {
    test('defaults are haptics-on, sound-ON-but-success-only, ambient-on',
        () async {
      final provider = SensoryProvider();
      await Future<void>.delayed(Duration.zero); // let _load() settle
      expect(provider.prefs.hapticsEnabled, isTrue);
      expect(provider.prefs.soundEnabled, isTrue);
      expect(provider.prefs.soundSuccessOnly, isTrue);
      expect(provider.prefs.ambientMotionEnabled, isTrue);
      expect(provider.prefs.forceReduceMotion, isNull);
      expect(AzSensory.hapticsEnabled, isTrue);
    });

    test('setters persist and update the static sink', () async {
      final provider = SensoryProvider();
      await Future<void>.delayed(Duration.zero);

      await provider.setHapticsEnabled(false);
      expect(AzSensory.hapticsEnabled, isFalse);

      await provider.setForceReduceMotion(true);
      expect(AzSensory.reduceMotionOverrideIsSet, isTrue);
      expect(AzSensory.reduceMotionOverride, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SensoryProvider.kHaptics), isFalse);
      expect(prefs.getInt(SensoryProvider.kReduceOverride), 1);

      await provider.setForceReduceMotion(null);
      expect(prefs.getInt(SensoryProvider.kReduceOverride), -1);
    });
  });
}
