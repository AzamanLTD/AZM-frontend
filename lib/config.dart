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
  static const String _apiHost = String.fromEnvironment('API_HOST', defaultValue: '');
  static const String _apiPort = String.fromEnvironment('API_PORT', defaultValue: '');
  static const String _apiScheme = String.fromEnvironment('API_SCHEME', defaultValue: '');

  static String get environment => _env;
  static bool get isDevelopment => _env == 'dev';
  static bool get isStaging => _env == 'staging';
  static bool get isProduction => _env == 'prod';

  static const bool _demoModeCompileTime = bool.fromEnvironment('DEMO_MODE', defaultValue: false);
  static bool? _demoModeOverride;
  static bool get demoMode => _demoModeOverride ?? _demoModeCompileTime;
  static void enableDemoMode() => _demoModeOverride = true;

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
