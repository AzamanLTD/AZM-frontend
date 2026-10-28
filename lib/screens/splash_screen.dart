import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'dart:convert';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/version_gate_service.dart';
import 'package:azaman/screens/auth/login_screen.dart';
import 'package:azaman/screens/onboarding_screen.dart';
import 'package:azaman/screens/force_update_screen.dart';
import 'package:azaman/main.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/settings_provider.dart';
import 'package:azaman/providers/platform_config_provider.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/config.dart';
import 'package:azaman/data/demo_seed_data.dart';
import 'package:azaman/router/auth_guard.dart';
import 'package:flutter/foundation.dart';
import 'package:azaman/experience/launch/azaman_intro.dart';


class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  final _storage = const FlutterSecureStorage();

  /// The entrance is the app's first impression, so the splash does not cut
  /// away from it mid-reveal: it waits for the lockup to settle, which lands
  /// a fraction after the branding floor.
  final Completer<void> _introRevealed = Completer<void>();

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<bool> _checkOnboardingStatus() async {
    try {
      final apiClient = ApiClient();
      final response = await apiClient.get('/users/onboarding');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final completed = data['data']?['completed'] ?? true;
        return !completed;
      }
    } catch (_) {}
    return false;
  }

  /// §9 startup audit: the two-second branding floor used to run SERIALLY
  /// before the waterfall, so a cold start paid 2s + every network round
  /// trip on top. It now runs CONCURRENTLY with the auth/version/onboarding
  /// work — the splash still holds for its branding beat, but the network
  /// is never idled behind it: startup is max(2s, waterfall), not 2s+waterfall.
  late final Future<void> _brandingFloor =
      Future<void>.delayed(const Duration(seconds: 2));

  /// Every splash exit goes through here, so the branding floor elapses
  /// while the network work runs — never before it.
  Future<void> _exitTo(WidgetBuilder builder) async {
    await Future.wait([_brandingFloor, _introRevealed.future]);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: builder));
  }

  Future<void> _checkAuthStatus() async {

    // ── Auto-demo fallback for web ──────────────────────────────────────
    if (!AppConfig.demoMode && kIsWeb) {
      try {
        await apiClient.get('/health', requireAuth: false)
            .timeout(const Duration(seconds: 3));
        debugPrint('[Splash] Backend reachable, staying in live mode');
      } catch (_) {
        debugPrint('[Splash] Backend unreachable, enabling demo mode');
        AppConfig.enableDemoMode();
      }
    }

    // Demo mode: skip version gate + auth, go straight to the app with seeded data
    if (AppConfig.demoMode) {
      final auth = ref.read(authProvider);
      auth.setUser(User(
        id: DemoSeedData.demoUserId,
        username: DemoSeedData.demoUsername,
        email: 'pyrax@demo.azaman.app',
        token: DemoSeedData.demoToken,
        role: 'USER',
        azmBalance: 12450.00,
        availableBalance: 12450.00,
        kycStatus: KycStatus.verified,
      ));
      AuthGuard.isAuthenticated = true;
      ref.read(themeProvider).loadFromBackend();
      ref.read(settingsProvider).loadFromBackend();
      await _exitTo((_) => const MainNavigationWrapper());
      return;
    }

    // Version gate (only for non-demo mode)
    final versionResult = await versionGateService.check(AppConfig.appVersion);
    if (!mounted) return;

    if (versionResult.updateRequired) {
      await _exitTo((_) => ForceUpdateScreen(
        message: versionResult.message ?? 'A new version of Azaman is available. Please update to continue.',
        updateUrl: versionResult.updateUrl,
        minVersion: versionResult.minVersion,
      ));
      return;
    }

    final auth = ref.read(authProvider);
    final isAuthenticated = await auth.checkAuthStatus();
    if (!mounted) return;

    if (isAuthenticated) {
      try {
        final token = await _storage.read(key: 'auth_token');
        final userId = await _storage.read(key: 'user_id');
        final userRole = await _storage.read(key: 'user_role') ?? 'user';

        if (userId != null && token != null) {
          final status = await auth.setSessionFromLogin(User(
            id: userId, username: 'Loading…', email: '', token: token, role: userRole,
          ));
          if (!mounted) return;

          switch (status) {
            case AuthStatus.authenticated:
              // §9 startup audit: theme, settings, platform config and the
              // onboarding probe are four INDEPENDENT GETs — they used to
              // run as a serial waterfall (four round-trips added to every
              // cold start). One Future.wait, one round-trip.
              final results = await Future.wait<Object?>([
                ref.read(themeProvider).loadFromBackend(),
                ref.read(settingsProvider).loadFromBackend(),
                ref.read(platformConfigProvider.notifier).refresh(),
                _checkOnboardingStatus(),
              ]);
              if (!mounted) return;
              final needsOnboarding = results[3] == true;
              await _exitTo(needsOnboarding
                  ? (_) => const OnboardingScreen()
                  : (_) => const MainNavigationWrapper());
              return;
            case AuthStatus.profileNotFound:
              await _exitTo((_) => const LoginScreen());
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No profile found for this account. Please sign up.')));
              return;
            case AuthStatus.unauthenticated:
            case AuthStatus.error:
            case AuthStatus.idle:
            case AuthStatus.loading:
              await _exitTo((_) => const LoginScreen());
              return;
          }
        } else {
          await _exitTo((_) => const LoginScreen());
        }
      } catch (e) {
        await _exitTo((_) => const LoginScreen());
      }
    } else {
      await _exitTo((_) => const LoginScreen());
    }
  }

  void _onIntroRevealed() {
    if (!_introRevealed.isCompleted) _introRevealed.complete();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      // Match the intro's own canvas so there is never a white flash before
      // the first frame paints.
      backgroundColor: isDark ? Colors.black : const Color(0xFFF4F5F6),
      body: AzamanIntro(onRevealed: _onIntroRevealed),
    );
  }

}

