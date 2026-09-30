// lib/services/az_sound.dart
// =============================================================================
// AZ SOUND  (TASK-020)
//
// Five named sounds, one gate, zero new packages.
//
// DESIGN
// ------
// `AzSound` is a façade over an [AzSoundBackend]. Two backends are defined:
//
//   SystemSoundBackend  — ships today. Uses Flutter's built-in SystemSound
//                         (`click` / `alert`). No package, no assets, no
//                         platform channel of our own. On Android/iOS those are
//                         the ONLY two sounds the OS exposes, so tick/rip/whoosh
//                         resolve to the closest system sound until real samples
//                         are wired in.
//   SilentSoundBackend  — the default until [AzSound.usePlatformSystemSounds] is
//                         called. Nothing plays on a fresh install before the
//                         shell has decided.
//   MediaSoundBackend   — asset-backed, and deliberately *not* shipped until an
//                         audio player is an approved dependency (A.3 rule 6).
//                         Its seam ([AzSoundMediaPlayer]) is defined here so the
//                         eventual wiring is a one-file change with no call-site
//                         churn.
//
// HONESTY RULES (F.5)
// -------------------
//   * Never play for a fabricated/demo event. A chime on a simulated payment is
//     the exact lie the money-truth contract forbids.
//   * Never play more than once per user action.
//   * Respect the user's gate (`AzSensory`) BEFORE touching the platform.
//   * Never throw. Audio is a garnish; a missing asset must be invisible.
// =============================================================================

import 'package:flutter/services.dart';

import 'package:azaman/providers/sensory_provider.dart';

/// The five sounds the product is allowed to make.
enum AzSoundId { tick, success, coin, rip, whoosh }

/// What is actually producing sound right now. Surfaced so screens, tests and
/// the sign-off can state the truth instead of assuming.
enum AzSoundBackendKind { silent, system, mediaAssets }

abstract class AzSoundBackend {
  AzSoundBackendKind get kind;
  Future<void> preload(Set<AzSoundId> ids);
  Future<void> play(AzSoundId id);
  void dispose();
}

/// Does nothing, forever. The default.
class SilentSoundBackend implements AzSoundBackend {
  const SilentSoundBackend();

  @override
  AzSoundBackendKind get kind => AzSoundBackendKind.silent;

  @override
  Future<void> preload(Set<AzSoundId> ids) async {}

  @override
  Future<void> play(AzSoundId id) async {}

  @override
  void dispose() {}
}

/// Zero-dependency backend: Flutter's built-in system sounds.
class SystemSoundBackend implements AzSoundBackend {
  const SystemSoundBackend();

  @override
  AzSoundBackendKind get kind => AzSoundBackendKind.system;

  /// The exact mapping, exposed as a pure function so it can be unit-tested
  /// without touching a platform channel.
  static SystemSoundType? systemTypeFor(AzSoundId id) {
    switch (id) {
      case AzSoundId.tick:
        return SystemSoundType.click;
      case AzSoundId.rip:
        return SystemSoundType.click;
      case AzSoundId.whoosh:
        return SystemSoundType.click;
      case AzSoundId.success:
        return SystemSoundType.alert;
      case AzSoundId.coin:
        return SystemSoundType.alert;
    }
  }

  @override
  Future<void> preload(Set<AzSoundId> ids) async {
    // System sounds are preloaded by the OS. Intentionally empty.
  }

  @override
  Future<void> play(AzSoundId id) async {
    final type = systemTypeFor(id);
    if (type == null) return;
    try {
      await SystemSound.play(type);
    } on PlatformException {
      // Some devices/emulators have no system-sound channel. Stay silent.
    } on MissingPluginException {
      // Unit tests and desktop: silent by design.
    }
  }

  @override
  void dispose() {}
}

/// The seam a real audio player plugs into.
///
/// No audio package is installed today (A.3 rule 6). When one is approved,
/// implement this interface in a single new file and pass it to
/// [AzSound.registerAssetBackend] from the app shell. No call site changes.
abstract class AzSoundMediaPlayer {
  Future<void> load(String assetPath);
  Future<void> play();
  Future<void> stop();
  void dispose();
}

/// Asset-backed backend. Activated only when a player is injected.
class MediaSoundBackend implements AzSoundBackend {
  final AzSoundMediaPlayer Function() _createPlayer;
  final Map<AzSoundId, AzSoundMediaPlayer> _players = {};

  MediaSoundBackend(this._createPlayer);

  @override
  AzSoundBackendKind get kind => AzSoundBackendKind.mediaAssets;

  /// The one place asset paths are written down.
  static const Map<AzSoundId, String> assetPaths = {
    AzSoundId.tick: 'assets/audio/az_tick.mp3',
    AzSoundId.success: 'assets/audio/az_success.mp3',
    AzSoundId.coin: 'assets/audio/az_coin.mp3',
    AzSoundId.rip: 'assets/audio/az_rip.mp3',
    AzSoundId.whoosh: 'assets/audio/az_whoosh.mp3',
  };

  /// Loads every sound it can and silently skips every one it cannot. A missing
  /// asset is a content gap, not a crash — and skipping is visible in
  /// `AzSound.loadedIds`, so the sign-off can be honest about it.
  @override
  Future<void> preload(Set<AzSoundId> ids) async {
    for (final id in ids) {
      if (_players.containsKey(id)) continue;
      final path = assetPaths[id];
      if (path == null) continue;
      final player = _createPlayer();
      try {
        await player.load(path);
        _players[id] = player;
      } catch (_) {
        player.dispose(); // asset absent or unreadable — stay silent for this id
      }
    }
  }

  Set<AzSoundId> get loadedIds => _players.keys.toSet();

  @override
  Future<void> play(AzSoundId id) async {
    final player = _players[id];
    if (player == null) return;
    try {
      await player.play();
    } catch (_) {
      // Never surface an audio failure.
    }
  }

  @override
  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
  }
}

/// The façade every screen calls. Static by design: sound fires from callbacks
/// that have no guaranteed BuildContext, exactly like haptics.
class AzSound {
  const AzSound._();

  static AzSoundBackend _backend = const SilentSoundBackend();
  static bool _preloaded = false;

  /// The minimum gap between two plays of the SAME sound. A double-tap must not
  /// produce a double tick — that is the single most common way app sound reads
  /// as cheap.
  static const Duration minRepeatGap = Duration(milliseconds: 60);

  static final Map<AzSoundId, DateTime> _lastPlayed = {};

  static AzSoundBackendKind get backendKind => _backend.kind;

  /// True when a real sound can play. Screens may use this to decide whether to
  /// show a "sound" affordance at all.
  static bool get isAudible => _backend.kind != AzSoundBackendKind.silent;

  /// Ids the active backend actually loaded (media backend only).
  static Set<AzSoundId> get loadedIds =>
      _backend is MediaSoundBackend ? (_backend as MediaSoundBackend).loadedIds : const {};

  /// Called ONCE from the app shell. Safe to call repeatedly.
  static void usePlatformSystemSounds() {
    _swap(const SystemSoundBackend());
  }

  /// Swap in an asset backend (or a test double).
  static void registerAssetBackend(AzSoundBackend backend) {
    _swap(backend);
  }

  static void _swap(AzSoundBackend next) {
    _backend.dispose();
    _backend = next;
    _preloaded = false;
    _lastPlayed.clear();
  }

  /// Warms the backend. Non-blocking by design — never await this on a build path.
  static Future<void> ensureReady() async {
    if (_preloaded) return;
    _preloaded = true;
    try {
      await _backend.preload(AzSoundId.values.toSet());
    } catch (_) {
      // A preload failure must never break a screen.
    }
  }

  /// The gate. Order matters: user preference first, then de-duplication, then
  /// the platform. [essential] sounds (success / coin / rip) are the ones the
  /// user opted into with "success sounds only"; tick and whoosh are garnish.
  static Future<void> _play(AzSoundId id, {required bool essential}) async {
    if (!AzSensory.soundEnabled) return;
    if (AzSensory.soundSuccessOnly && !essential) return;

    final now = DateTime.now();
    final last = _lastPlayed[id];
    if (last != null && now.difference(last) < minRepeatGap) return;
    _lastPlayed[id] = now;

    try {
      await _backend.play(id);
    } catch (_) {
      // Silence is always an acceptable outcome.
    }
  }

  // ── The five sounds ────────────────────────────────────────────────────────
  /// Interface garnish — silenced by "success sounds only".
  static Future<void> tick({bool essential = false}) =>
      _play(AzSoundId.tick, essential: essential);

  /// A real, completed success (never a demo/simulated one). See F.5.
  static Future<void> success() => _play(AzSoundId.success, essential: true);

  /// Money received or settled — pairs with `AzamanHaptics.moneyLanded()`.
  static Future<void> coin() => _play(AzSoundId.coin, essential: true);

  /// Paper tear — restaurant ticket, retail receipt, escrow unseal.
  static Future<void> rip() => _play(AzSoundId.rip, essential: true);

  /// Scene change air. Rare by design; never on a tab switch.
  static Future<void> whoosh() => _play(AzSoundId.whoosh, essential: false);

  /// Test-only: clears the debounce table so a test can play the same sound twice.
  static void resetDebounceForTest() => _lastPlayed.clear();
}
