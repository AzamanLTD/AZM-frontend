import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/version_gate_service.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/settings_provider.dart';
import 'package:azaman/providers/platform_config_provider.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/config.dart';
import 'package:go_router/go_router.dart' show GoRouterHelper;
import 'package:azaman/data/demo_seed_data.dart';
import 'package:azaman/router/auth_guard.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/foundation.dart';
import 'package:azaman/widgets/logo_trace_loader.dart';


class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Main entrance animation: 800ms fade + scale
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _animController.forward();
    // The auth waterfall modifies providers (demo seeding, session state)
    // — running it from inside initState modifies providers DURING the
    // build frame, which Riverpod rejects ("tried to modify a provider
    // while the widget tree was building"). The real /health await on web
    // used to push this out of the frame by accident; a native demo build
    // takes the synchronous path and throws. Post-frame is the correct
    // lifecycle seam (MainWrapper defers its socket/startup work the same
    // way).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkAuthStatus();
    });
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
  ///
  /// ONE NAVIGATION AUTHORITY: the exit is a ROUTER-MANAGED `go` to a
  /// registered destination — never an imperative pushReplacement. The
  /// old anonymous swap left GoRouter's declarative state pointing at '/'
  /// while the Navigator held an anonymous shell route; every later
  /// context.push re-instantiated this splash beneath the new screen,
  /// and its 2s floor then disposed the user's screen (pushReplacement
  /// completes the TOPMOST history entry — navigator.dart
  /// _pushReplacementEntry). go() rebuilds the whole declarative stack:
  /// router state and Navigator stay identical, back is honest, and no
  /// hidden splash instance can ever exist.
  Future<void> _exitTo(String location) async {
    await _brandingFloor;
    if (!mounted) return;
    context.go(location);
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
      await _exitTo(AzRoutes.shell);
      return;
    }

    // Version gate (only for non-demo mode)
    final versionResult = await versionGateService.check(AppConfig.appVersion);
    if (!mounted) return;

    if (versionResult.updateRequired) {
      final q = <String>[
        if (versionResult.message != null)
          'message=${Uri.encodeComponent(versionResult.message!)}',
        if (versionResult.updateUrl != null)
          'updateUrl=${Uri.encodeComponent(versionResult.updateUrl!)}',
        if (versionResult.minVersion != null)
          'minVersion=${Uri.encodeComponent(versionResult.minVersion!)}',
      ].join('&');
      await _exitTo('${AzRoutes.forceUpdate}${q.isEmpty ? '' : '?$q'}');
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
              await _exitTo(
                  needsOnboarding ? AzRoutes.onboarding : AzRoutes.shell);
              return;
            case AuthStatus.profileNotFound:
              // The snackbar must be shown BEFORE the go(): the root
              // ScaffoldMessenger survives the route change, but this
              // context does not (the login page is a different route).
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No profile found for this account. Please sign up.')));
              await _exitTo(AzRoutes.login);
              return;
            case AuthStatus.unauthenticated:
            case AuthStatus.error:
            case AuthStatus.idle:
            case AuthStatus.loading:
              await _exitTo(AzRoutes.login);
              return;
          }
        } else {
          await _exitTo(AzRoutes.login);
        }
      } catch (e) {
        await _exitTo(AzRoutes.login);
      }
    } else {
      await _exitTo(AzRoutes.login);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Center: LogoTraceLoader ──────────────────────────
                  LogoTraceLoader(
                    size: 120,
                    strokeWidth: 4,
                    color: Colors.black.withValues(alpha: 0.75),
                    loopDurationSeconds: 2.4,
                  ),
                  const SizedBox(height: 28),
                  // ── Azaman wordmark — refined ────────────────────────────
                  ShaderMask(
                    shaderCallback: (bounds) {
                      return LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black,
                          Colors.black.withValues(alpha: 0.35),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ).createShader(bounds);
                    },
                    child: const Text(
                      'AZAMAN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8,
                      ),
                    ),
                  )
                  .animate(onPlay: (c) => c.repeat())
                  .shimmer(duration: 2200.ms, color: Colors.black.withValues(alpha: 0.12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

