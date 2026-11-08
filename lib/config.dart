import 'package:flutter/foundation.dart' show visibleForTesting;

// =============================================================================
// AZAMAN V4 — ENVIRONMENT CONFIGURATION
//
// Supports 3 environments via --dart-define:
//   flutter run --dart-define=ENV=dev
//   flutter run --dart-define=ENV=staging
//   flutter run --dart-define=ENV=prod
//
// Or override specific values:
//   flutter run --dart-define=API_HOST=192.168.1.100 --dart-define=API_PORT=3000
//
// Default: 'dev' environment (local backend when explicitly overridden).
// =============================================================================

class AppConfig {
  AppConfig._();

  static const String _env = String.fromEnvironment('ENV', defaultValue: 'dev');
  static const String _apiHost = String.fromEnvironment(
    'API_HOST',
    defaultValue: '',
  );
  static const String _apiPort = String.fromEnvironment(
    'API_PORT',
    defaultValue: '',
  );
  static const String _apiScheme = String.fromEnvironment(
    'API_SCHEME',
    defaultValue: '',
  );

  static String get environment => _env;
  static bool get isDevelopment => _env == 'dev';
  static bool get isStaging => _env == 'staging';
  static bool get isProduction => _env == 'prod';

  /// The saved-account half of Bills has a reviewable backend contract, but
  /// those routes are not in the deployed API yet. The client is written and
  /// switched OFF: `--dart-define=BILLS_API=true` turns it on the moment the
  /// routes ship, and until then production keeps the truthful empty state.
  static const bool billsApiEnabled = bool.fromEnvironment(
    'BILLS_API',
    defaultValue: false,
  );

  /// Nearby Presence — CLIENT BUILD GATE (Part 6.6 §F).
  ///
  /// This is NOT the authoritative server flag. The server owns
  /// `GlobalSettings.presenceEnabled`; that flag, not this constant, decides
  /// whether presence operations are actually accepted.
  ///
  /// This gate answers one narrower question: "was this binary compiled with
  /// a presence backend to talk to?" It defaults OFF and stays off in
  /// production until the presence APIs and the server flag are deployed and
  /// tested. While false the feature is INVISIBLE and issues no presence
  /// requests at all — it never falls back to fabricated candidates.
  static const bool presenceApiBuildEnabled = bool.fromEnvironment(
    'PRESENCE_API',
    defaultValue: false,
  );

  static bool? _presenceOverride;

  /// The effective gate: the compile-time flag, unless a test has overridden
  /// it. Production never sets the override, so the default stays OFF.
  static bool get presenceApiEnabled =>
      _presenceOverride ?? presenceApiBuildEnabled;

  /// Test-only: simulate the backend being switched on/off. Passing null
  /// restores the compile-time flag.
  @visibleForTesting
  static void setPresenceOverrideForTest(bool? value) =>
      _presenceOverride = value;

  static const bool _demoModeCompileTime = bool.fromEnvironment(
    'DEMO_MODE',
    defaultValue: false,
  );
  static bool? _demoModeOverride;
  static bool get demoMode => _demoModeOverride ?? _demoModeCompileTime;
  static void enableDemoMode() => _demoModeOverride = true;

  /// Test-only: clears the runtime demo override so the compile-time
  /// flag governs again — needed to exercise the router's real auth
  /// redirect (demo mode deliberately bypasses auth gating).
  @visibleForTesting
  static void clearDemoModeOverrideForTest() => _demoModeOverride = null;

  static String get apiUrl => '$baseUrl/api';

  static String get baseUrl {
    if (_apiHost.isNotEmpty) {
      final scheme = _apiScheme.isNotEmpty ? _apiScheme : 'http';
      final port = _apiPort.isNotEmpty ? ':$_apiPort' : ':3000';
      return '$scheme://$_apiHost$port';
    }

    switch (_env) {
      case 'prod':
        return 'https://azm-backend-9o0b.onrender.com';
      case 'staging':
        return 'https://staging-api.azaman.app';
      case 'dev':
      default:
        return 'http://localhost:3000';
    }
  }

  static String get socketUrl => baseUrl;

  static String get wsUrl {
    final base = baseUrl;
    if (base.startsWith('https')) return base.replaceFirst('https', 'wss');
    return base.replaceFirst('http', 'ws');
  }

  static Duration get requestTimeout => const Duration(seconds: 30);

  static int get socketReconnectDelayMs => isDevelopment ? 3000 : 2000;

  static bool get enableNetworkLogs => isDevelopment || isStaging;

  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '4.0.0',
  );

  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );

  static bool get sentryEnabled => sentryDsn.isNotEmpty;

  static const String _portalUrlOverride = String.fromEnvironment(
    'BUSINESS_PORTAL_URL',
    defaultValue: 'https://azm-business-portal.vercel.app',
  );

  static String get businessPortalUrl => _portalUrlOverride;
  static bool get hasBusinessPortalUrl => businessPortalUrl.isNotEmpty;
}
