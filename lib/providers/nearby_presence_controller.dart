// lib/providers/nearby_presence_controller.dart
// =============================================================================
// AZAMAN — NEARBY PRESENCE CONTROLLER (Part 6.6 state machine)
//
//   idle → checkingPrereqs → scanning → resolving
//        → foundOne | foundMany | none | blocked(reason) | error
//
// PRIVACY-FIRST GATES (all must hold before a scan starts):
//   1. server/build presence flag ON (AppConfig.presenceEnabled && gateway
//      reports available) — otherwise the feature is INVISIBLE and no request
//      is ever issued;
//   2. user preference `nearbyDiscovery` ON (default OFF);
//   3. app UNLOCKED through the existing MoneyAccessController — no Nearby UI
//      may surface above the lock;
//   4. an explicit user action (or an allowed lifecycle trigger) — this
//      controller never self-starts on cold start;
//   5. network available before any server resolution.
//
// STALE-EVENT PROTECTION mirrors NearbyLocationTracker: every scan bumps a
// generation counter, and a result whose generation is no longer current is
// dropped on arrival. A slow scan can therefore never overwrite a newer one.
//
// RSSI IS NOT DISTANCE. Nothing here converts dBm to metres, storeys or
// "inside the shop". Buckets are ordering hints only.
// =============================================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/providers/presence_preferences_provider.dart';
import 'package:azaman/services/connectivity_service.dart';
import 'package:azaman/services/presence/presence_config.dart';
import 'package:azaman/services/presence/presence_gateway.dart';
import 'package:azaman/services/presence/presence_models.dart';
import 'package:azaman/services/presence/presence_scanner.dart';

/// Why presence is currently unavailable to the customer.
enum PresenceBlockReason {
  /// Build/server flag is off — feature invisible, no requests issued.
  featureFlagOff,

  /// The customer switched Nearby discovery off.
  preferenceOff,

  /// The app is locked by MoneyAccessController.
  appLocked,

  /// This platform/build cannot scan.
  unsupported,

  bluetoothOff,
  permissionDenied,
  permissionPermanentlyDenied,

  /// No network — resolution is not attempted.
  offline,

  /// Scan budget exhausted (4 starts / 30 s, or 20 s minimum gap).
  throttled,
}

sealed class NearbyPresenceState {
  const NearbyPresenceState();
}

final class PresenceIdle extends NearbyPresenceState {
  const PresenceIdle();
}

final class PresenceCheckingPrereqs extends NearbyPresenceState {
  const PresenceCheckingPrereqs();
}

final class PresenceScanning extends NearbyPresenceState {
  const PresenceScanning();
}

final class PresenceResolving extends NearbyPresenceState {
  const PresenceResolving();
}

final class PresenceFoundOne extends NearbyPresenceState {
  final PresenceCandidate candidate;
  const PresenceFoundOne(this.candidate);
}

final class PresenceFoundMany extends NearbyPresenceState {
  final List<PresenceCandidate> candidates;
  const PresenceFoundMany(this.candidates);
}

final class PresenceNone extends NearbyPresenceState {
  /// True only when the customer explicitly asked (refresh) — an unsolicited
  /// empty state is never shown.
  final bool explicit;
  const PresenceNone({this.explicit = false});
}

final class PresenceBlocked extends NearbyPresenceState {
  final PresenceBlockReason reason;
  const PresenceBlocked(this.reason);
}

final class PresenceError extends NearbyPresenceState {
  final String message;
  const PresenceError(this.message);
}

class NearbyPresenceController extends StateNotifier<NearbyPresenceState> {
  NearbyPresenceController(
    this._read, {
    PresenceScanner? scanner,
    PresenceApiGateway? gateway,
    PresenceTuning tuning = PresenceTuning.standard,
    DateTime Function()? clock,
  }) : _scannerOverride = scanner,
       _gatewayOverride = gateway,
       _tuning = tuning,
       _clock = clock ?? DateTime.now,
       super(const PresenceIdle());

  final T Function<T>(ProviderListenable<T>) _read;
  final PresenceScanner? _scannerOverride;
  final PresenceApiGateway? _gatewayOverride;
  final PresenceTuning _tuning;
  final DateTime Function() _clock;

  PresenceScanner get _scanner =>
      _scannerOverride ?? _read(presenceScannerProvider);
  PresenceApiGateway get _gateway =>
      _gatewayOverride ?? _read(presenceApiGatewayProvider);

  /// Bumped on every scan start / cancel. Any completion whose generation is
  /// stale is discarded.
  int _generation = 0;

  /// Start times inside the rate-limit window.
  final List<DateTime> _starts = <DateTime>[];

  /// Branch ids dismissed (or chosen) in THIS session — suppresses re-prompting.
  final Set<String> _sessionDismissed = <String>{};

  /// Fired for customer presence events only. Worker tests never use it.
  void Function(PresenceEvent event)? onCustomerEvent;

  PresenceTuning get tuning => _tuning;
  Set<String> get sessionDismissed =>
      Set<String>.unmodifiable(_sessionDismissed);
  bool get hasScanned => _starts.isNotEmpty;

  /// Whether the feature should be rendered at all. Drives the "completely
  /// invisible" requirement — no card, no request, no permission prompt.
  bool get isFeatureVisible {
    if (!AppConfig.presenceEnabled) return false;
    if (!_gateway.isAvailable) return false;
    return true;
  }

  // ── Throttle ─────────────────────────────────────────────────────────────

  /// Trims the window and returns whether another start is permitted now.
  bool _canStartNow(DateTime now) {
    _starts.removeWhere((t) => now.difference(t) >= _tuning.windowForRateLimit);
    if (_starts.length >= _tuning.maxStartsPerWindow) return false;
    if (_starts.isNotEmpty &&
        now.difference(_starts.last) < _tuning.minScanInterval) {
      return false;
    }
    return true;
  }

  // ── Prerequisites ────────────────────────────────────────────────────────

  /// Returns the blocking reason, or null when a scan may proceed.
  PresenceBlockReason? _prereqBlocker({required bool requirePreference}) {
    if (!AppConfig.presenceEnabled || !_gateway.isAvailable) {
      return PresenceBlockReason.featureFlagOff;
    }
    if (requirePreference) {
      final prefs = _read(presencePreferencesProvider);
      if (!prefs.nearbyDiscovery) return PresenceBlockReason.preferenceOff;
    }
    final money = _read(moneyAccessProvider);
    if (money.isLocked) return PresenceBlockReason.appLocked;
    return null;
  }

  bool _isOffline() {
    final connectivity = _read(connectivityProvider).valueOrNull;
    // Only an explicit `false` blocks; unknown is not proof of offline and the
    // network call itself fails closed.
    return connectivity == false;
  }

  // ── The scan cycle ───────────────────────────────────────────────────────

  /// Starts one customer discovery scan.
  ///
  /// [explicit] marks a customer-initiated action (affects the empty state
  /// only). Returns true when a scan actually ran.
  Future<bool> requestScan({bool explicit = false}) async {
    if (!mounted) return false;
    state = const PresenceCheckingPrereqs();

    final blocked = _prereqBlocker(requirePreference: true);
    if (blocked != null) {
      _emit(PresenceBlocked(blocked), blocked);
      return false;
    }
    if (_isOffline()) {
      _emit(
        const PresenceBlocked(PresenceBlockReason.offline),
        PresenceBlockReason.offline,
      );
      return false;
    }
    final now = _clock();
    if (!_canStartNow(now)) {
      _emit(
        const PresenceBlocked(PresenceBlockReason.throttled),
        PresenceBlockReason.throttled,
      );
      return false;
    }
    _starts.add(now);

    final generation = ++_generation;
    state = const PresenceScanning();
    onCustomerEvent?.call(
      PresenceEvent(type: PresenceEventType.scanStarted, occurredAt: _clock()),
    );

    PresenceScanOutcome outcome;
    try {
      outcome = await _scanner.scan(
        purpose: PresenceScanPurpose.customerDiscovery,
        tuning: _tuning,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return false;
      state = PresenceError('$e');
      return false;
    }
    // STALE GUARD: a newer scan started (or we cancelled) while this one ran.
    if (!mounted || generation != _generation) return false;

    return _applyOutcome(outcome, explicit: explicit);
  }

  Future<bool> _applyOutcome(
    PresenceScanOutcome outcome, {
    required bool explicit,
  }) async {
    switch (outcome) {
      case ScanNone():
        _emit(const PresenceNone(), null, explicit: explicit);
        return true;

      case ScanBluetoothOff():
        _emit(
          const PresenceBlocked(PresenceBlockReason.bluetoothOff),
          PresenceBlockReason.bluetoothOff,
        );
        return false;

      case ScanPermissionDenied():
        _emit(
          const PresenceBlocked(PresenceBlockReason.permissionDenied),
          PresenceBlockReason.permissionDenied,
        );
        return false;

      case ScanPermissionPermanentlyDenied():
        _emit(
          const PresenceBlocked(
            PresenceBlockReason.permissionPermanentlyDenied,
          ),
          PresenceBlockReason.permissionPermanentlyDenied,
        );
        return false;

      case ScanUnsupported():
        _emit(
          const PresenceBlocked(PresenceBlockReason.unsupported),
          PresenceBlockReason.unsupported,
        );
        return false;

      case ScanFailed(:final reason):
        state = PresenceError(reason);
        return false;

      case ScanFound(:final observations):
        // Eligibility: enough samples to be evidence, not one stray packet.
        final eligible = observations
            .where((o) => o.sampleCount >= _tuning.minSamplesPerBeacon)
            .toList(growable: false);
        if (eligible.isEmpty) {
          _emit(const PresenceNone(), null, explicit: explicit);
          return true;
        }
        state = const PresenceResolving();
        try {
          final challenge = await _gateway.requestChallenge();
          if (!mounted) return false;
          final result = await _gateway.resolve(
            challengeToken: challenge.token,
            observations: eligible,
          );
          if (!mounted) return false;
          return _applyCandidates(result.candidates, explicit: explicit);
        } on PresenceUnavailableException {
          _emit(
            const PresenceBlocked(PresenceBlockReason.featureFlagOff),
            PresenceBlockReason.featureFlagOff,
          );
          return false;
        } catch (e) {
          if (!mounted) return false;
          state = PresenceError('$e');
          return false;
        }
    }
  }

  bool _applyCandidates(List<PresenceCandidate> raw, {required bool explicit}) {
    // Session dismissal memory: never re-prompt a store the customer already
    // dismissed or chose in this session.
    final candidates = raw
        .where((c) => !_sessionDismissed.contains(c.branchId))
        .toList(growable: false);

    if (candidates.isEmpty) {
      _emit(const PresenceNone(), null, explicit: explicit);
      return true;
    }
    if (candidates.length == 1) {
      state = PresenceFoundOne(candidates.first);
      onCustomerEvent?.call(
        PresenceEvent(
          type: PresenceEventType.candidateShown,
          occurredAt: _clock(),
          branchId: candidates.first.branchId,
        ),
      );
      return true;
    }
    state = PresenceFoundMany(candidates);
    onCustomerEvent?.call(
      PresenceEvent(
        type: PresenceEventType.candidateShown,
        occurredAt: _clock(),
      ),
    );
    return true;
  }

  /// Records that the customer made a choice (or said "not here").
  void rememberChoice(String branchId, {required bool chosen}) {
    _sessionDismissed.add(branchId);
    if (chosen) {
      onCustomerEvent?.call(
        PresenceEvent(
          type: PresenceEventType.candidateChosen,
          occurredAt: _clock(),
          branchId: branchId,
        ),
      );
    } else {
      onCustomerEvent?.call(
        PresenceEvent(
          type: PresenceEventType.candidateDismissed,
          occurredAt: _clock(),
          branchId: branchId,
        ),
      );
    }
    state = const PresenceIdle();
  }

  /// Cancels any in-flight scan and invalidates its result.
  void cancel() {
    _generation++;
    if (mounted) state = const PresenceIdle();
  }

  /// Clears session memory (e.g. on sign-out).
  void clearSessionMemory() {
    _sessionDismissed.clear();
    _starts.clear();
  }

  void _emit(
    NearbyPresenceState next,
    PresenceBlockReason? reason, {
    bool explicit = false,
  }) {
    if (!mounted) return;
    if (explicit && next is PresenceNone) {
      state = const PresenceNone(explicit: true);
      return;
    }
    state = next;
    if (reason == PresenceBlockReason.throttled) {
      onCustomerEvent?.call(
        PresenceEvent(
          type: PresenceEventType.scanThrottled,
          occurredAt: _clock(),
        ),
      );
    }
  }

  // ── Worker test ──────────────────────────────────────────────────────────

  /// Staff-mode diagnostic. Uses the SAME scanner seam, but with
  /// [PresenceScanPurpose.workerTest], and NEVER emits customer events.
  ///
  /// Returns the raw outcome so the worker screen can show exactly what the
  /// scanner reported. Nothing here touches sessions, orders or payments.
  Future<PresenceScanOutcome> runWorkerTest() async {
    const outcomeUnsupported = ScanUnsupported();
    if (!AppConfig.presenceEnabled || !_gateway.isAvailable) {
      return outcomeUnsupported;
    }
    try {
      return await _scanner.scan(
        purpose: PresenceScanPurpose.workerTest,
        tuning: _tuning,
      );
    } catch (e) {
      return ScanFailed('$e');
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}

final nearbyPresenceControllerProvider =
    StateNotifierProvider<NearbyPresenceController, NearbyPresenceState>((ref) {
      return NearbyPresenceController(ref.read);
    });

/// A hook for the OS app-settings screen. Null until a platform
/// implementation is wired at bootstrap, so the UI never renders a dead
/// "Open settings" button. Deliberately a provider (not a package dependency)
/// — this wave adds no plugins.
final presenceOpenSettingsProvider = Provider<Future<void> Function()?>(
  (ref) => null,
);
