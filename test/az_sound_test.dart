import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/sensory_provider.dart';
import 'package:azaman/services/az_sound.dart';

/// Records what the façade asked for, so the *gate* can be tested without a
/// platform channel or an asset.
class _RecordingBackend implements AzSoundBackend {
  final List<AzSoundId> played = [];
  Set<AzSoundId> preloaded = {};

  @override
  AzSoundBackendKind get kind => AzSoundBackendKind.mediaAssets;

  @override
  Future<void> preload(Set<AzSoundId> ids) async => preloaded = ids;

  @override
  Future<void> play(AzSoundId id) async => played.add(id);

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingBackend recorder;

  setUp(() {
    recorder = _RecordingBackend();
    AzSound.registerAssetBackend(recorder);
    AzSound.resetDebounceForTest();
    AzSensory.apply(const SensoryPreferences());
  });

  tearDown(() {
    AzSound.registerAssetBackend(const SilentSoundBackend());
    AzSensory.apply(const SensoryPreferences());
  });

  test('the user gate wins over everything', () async {
    AzSensory.apply(const SensoryPreferences(
      soundEnabled: false,
      soundSuccessOnly: false,
    ));
    await AzSound.success();
    await AzSound.coin();
    await AzSound.tick();
    expect(recorder.played, isEmpty);
  });

  test('success-only mode silences garnish but keeps real events', () async {
    AzSensory.apply(const SensoryPreferences(
      soundEnabled: true,
      soundSuccessOnly: true,
    ));
    await AzSound.tick();
    await AzSound.whoosh();
    expect(recorder.played, isEmpty, reason: 'tick/whoosh are garnish');

    await AzSound.success();
    await AzSound.coin();
    await AzSound.rip();
    expect(recorder.played,
        [AzSoundId.success, AzSoundId.coin, AzSoundId.rip]);
  });

  test('full sound mode plays everything, including an essential tick', () async {
    AzSensory.apply(const SensoryPreferences(
      soundEnabled: true,
      soundSuccessOnly: false,
    ));
    await AzSound.tick();
    await AzSound.whoosh();
    AzSound.resetDebounceForTest();
    await AzSound.tick(essential: true);
    expect(recorder.played, [AzSoundId.tick, AzSoundId.whoosh, AzSoundId.tick]);
  });

  test('a repeat inside minRepeatGap is dropped (no double-tick)', () async {
    AzSensory.apply(const SensoryPreferences(
      soundEnabled: true,
      soundSuccessOnly: false,
    ));
    await AzSound.tick();
    await AzSound.tick(); // immediate second call — must be swallowed
    expect(recorder.played, [AzSoundId.tick]);

    AzSound.resetDebounceForTest();
    await AzSound.tick();
    expect(recorder.played, [AzSoundId.tick, AzSoundId.tick]);
  });

  test('different ids never block each other', () async {
    AzSensory.apply(const SensoryPreferences(
      soundEnabled: true,
      soundSuccessOnly: false,
    ));
    await AzSound.tick();
    await AzSound.whoosh();
    expect(recorder.played, [AzSoundId.tick, AzSoundId.whoosh]);
  });

  test('system backend maps all five ids to a real system sound', () {
    for (final id in AzSoundId.values) {
      expect(SystemSoundBackend.systemTypeFor(id), isNotNull,
          reason: '$id must resolve to click or alert');
    }
    expect(SystemSoundBackend.systemTypeFor(AzSoundId.tick),
        SystemSoundType.click);
    expect(SystemSoundBackend.systemTypeFor(AzSoundId.success),
        SystemSoundType.alert);
    expect(SystemSoundBackend.systemTypeFor(AzSoundId.coin),
        SystemSoundType.alert);
  });

  test('ensureReady preloads every id exactly once', () async {
    await AzSound.ensureReady();
    await AzSound.ensureReady();
    expect(recorder.preloaded.length, AzSoundId.values.length);
  });

  test('a missing asset is skipped, not thrown', () async {
    final backend = MediaSoundBackend(() => _FailingPlayer());
    await backend.preload(AzSoundId.values.toSet());
    expect(backend.loadedIds, isEmpty);
    await backend.play(AzSoundId.success); // must not throw
    backend.dispose();
  });

  test('media backend records only the ids it could load', () async {
    final backend = MediaSoundBackend(() => _OkPlayer());
    await backend.preload({AzSoundId.tick, AzSoundId.success});
    expect(backend.loadedIds, {AzSoundId.tick, AzSoundId.success});
    backend.dispose();
  });
}

class _FailingPlayer implements AzSoundMediaPlayer {
  @override
  Future<void> load(String assetPath) async => throw Exception('asset missing');
  @override
  Future<void> play() async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}

class _OkPlayer implements AzSoundMediaPlayer {
  @override
  Future<void> load(String assetPath) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}
