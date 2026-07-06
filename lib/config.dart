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
// Default: 'dev' environment (localhost:3000)
// =============================================================================

class AppConfig {
  AppConfig._();

  // Read from --dart-define at compile time
  static const String _env = String.fromEnvironment('ENV', defaultValue: 'dev');
  static const String _apiHost = String.fromEnvironment('API_HOST', defaultValue: '');
  static const String _apiPort = String.fromEnvironment('API_PORT', defaultValue: '');
  static const String _apiScheme = String.fromEnvironment('API_SCHEME', defaultValue: '');

  /// Current environment name
  static String get environment => _env;

  /// Whether we're in development mode (enables mocks, verbose logging)
  static bool get isDevelopment => _env == 'dev';

  /// Whether we're in staging mode
  static bool get isStaging => _env == 'staging';

  /// Whether we're in production mode
  static bool get isProduction => _env == 'prod';

  /// The resolved API base URL (includes /api suffix)
  static String get apiUrl => '$baseUrl/api';

  /// The resolved base URL (no /api suffix — used for socket connections)
  static String get baseUrl {
    // If user provided explicit overrides, use those
    if (_apiHost.isNotEmpty) {
      final scheme = _apiScheme.isNotEmpty ? _apiScheme : 'http';
      final port = _apiPort.isNotEmpty ? ':$_apiPort' : ':3000';
      return '$scheme://$_apiHost$port';
    }

    // Otherwise fall back to environment defaults
    switch (_env) {
      case 'prod':
        return 'https://api.azaman.app';
      case 'staging':
        return 'https://staging-api.azaman.app';
      case 'dev':
      default:
        // Default to the live Render-deployed backend so iOS Simulator
        // and Android Emulator can reach the API out-of-the-box.
        // To run against a local backend on your machine, override with:
        //   flutter run --dart-define=API_HOST=<your-LAN-IP> --dart-define=API_PORT=3000
        return 'https://azaman-backend-9d3u.onrender.com';
    }
  }

  /// Socket.IO URL (same as baseUrl, no /api path)
  static String get socketUrl => baseUrl;

  /// WebSocket URL for raw WS connections (if needed)
  static String get wsUrl {
    final base = baseUrl;
    if (base.startsWith('https')) {
      return base.replaceFirst('https', 'wss');
    }
    return base.replaceFirst('http', 'ws');
  }

  /// Request timeout duration
  static Duration get requestTimeout {
    if (isDevelopment) return const Duration(seconds: 30);
    return const Duration(seconds: 15);
  }

  /// Socket reconnection delay
  static int get socketReconnectDelayMs {
    if (isDevelopment) return 3000;
    return 2000;
  }

  /// Whether to show verbose network logs
  static bool get enableNetworkLogs => isDevelopment || isStaging;

  /// App version string (can be overridden by --dart-define)
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '4.0.0',
  );

  /// Sentry DSN for crash/error reporting (F-05). Empty by default, which
  /// disables Sentry entirely — pass it at build time to enable:
  ///   flutter run --dart-define=SENTRY_DSN=https://xxxx@oyyy.ingest.sentry.io/zzz
  /// Keeping it as a dart-define (not hardcoded) means dev/CI builds report
  /// nothing unless explicitly opted in.
  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );

  /// Whether Sentry should be active this run.
  static bool get sentryEnabled => sentryDsn.isNotEmpty;

  /// URL for the Azaman Business Portal (web dashboard for vendor-side
  /// operations -- KYB, product catalog, invoices, etc). The app treats the
  /// portal as a reference-only surface: we link OUT to it, we never embed
  /// it or duplicate its functionality in-app.
  ///
  /// NOTE: no production URL for the deployed portal exists anywhere in
  /// either repo yet (checked AZM-businessPortal's README/render config --
  /// nothing committed). Override at build time once it's deployed:
  ///   flutter run --dart-define=BUSINESS_PORTAL_URL=https://your-real-url
  /// Until then this intentionally resolves to an empty string, and any UI
  /// offering the link-out hides itself rather than pointing at a guessed,
  /// possibly-dead domain.
  static const String _portalUrlOverride = String.fromEnvironment(
    'BUSINESS_PORTAL_URL',
    defaultValue: '',
  );

  static String get businessPortalUrl => _portalUrlOverride;

  static bool get hasBusinessPortalUrl => businessPortalUrl.isNotEmpty;
}
