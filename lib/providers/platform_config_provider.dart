// lib/providers/platform_config_provider.dart
// =============================================================================
// AZAMAN V2 — PLATFORM CONFIG PROVIDER  (Phase ADMIN-CONTROL-2-FE)
//
// Riverpod StateNotifierProvider wrapping PlatformConfigService.
//
// State is PlatformConfig.defaults until the first refresh() completes.
// refresh() is called from splash_screen.dart after auth check, before
// navigation — so every screen that reads this provider sees live values.
//
// Usage:
//   // Read current config (rebuild on change):
//   final config = ref.watch(platformConfigProvider);
//
//   // Trigger a refresh (e.g. on app resume):
//   ref.read(platformConfigProvider.notifier).refresh();
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/platform_config_service.dart';

// ── Notifier ──────────────────────────────────────────────────────────────────

class PlatformConfigNotifier extends StateNotifier<PlatformConfig> {
  final PlatformConfigService _service;

  PlatformConfigNotifier(this._service) : super(PlatformConfig.defaults);

  /// Fetches live fee config from the backend and updates state.
  /// Non-fatal — if the fetch fails, state stays at current value (defaults
  /// or last successful fetch).
  Future<void> refresh() async {
    final config = await _service.fetch();
    if (mounted) state = config;
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// The singleton platform config provider.
/// Consumers read fee rates through this — they automatically rebuild when
/// admin updates a fee and refresh() is called.
final platformConfigProvider =
    StateNotifierProvider<PlatformConfigNotifier, PlatformConfig>((ref) {
  return PlatformConfigNotifier(PlatformConfigService());
});
