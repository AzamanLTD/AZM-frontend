// =============================================================================
// AZAMAN — DEMO GUARD
//
// Single switch for preview/demo adapters. Delegates to the EXISTING
// `AppConfig.demoMode` (lib/config.dart) so there is exactly one demo flag in
// the app; demo gateway adapters are only ever constructed behind this guard,
// via `ProviderScope(overrides: [...])`, never inside production provider
// bodies.
// =============================================================================

import 'package:flutter/foundation.dart';

import 'package:azaman/config.dart';

abstract final class DemoGuard {
  static bool? _testOverride;

  /// True when demo adapters may be constructed.
  static bool get enabled => _testOverride ?? AppConfig.demoMode;

  /// Tests only. Pass `null` to restore delegation to [AppConfig.demoMode].
  @visibleForTesting
  static void override(bool? value) => _testOverride = value;

  /// Throws in debug builds when demo code is reached while the guard is off.
  /// Use at the top of every demo adapter constructor.
  static void assertEnabled(String adapterName) {
    assert(
      enabled,
      '$adapterName is a demo adapter and must only be constructed behind '
      'DemoGuard.enabled (AppConfig.demoMode).',
    );
  }
}