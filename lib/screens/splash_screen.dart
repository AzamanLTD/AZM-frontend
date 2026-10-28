import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/intro_store.dart';
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
import 'package:flutter/foundation.dart';
import 'package:azaman/experience/launch/azaman_intro.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key, this.introStore});

  /// Injected for tests; production reads the device flag.
  final IntroStore? introStore;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  final _storage = const FlutterSecureStorage();

  /// The entrance is the app's first impression, so the splash never cuts
  /// away from it mid-reveal: the exit waits for the lockup to settle.
  final Completer<void> _introRevealed = Completer<void>();

  @override
  void initState() {
    super.initState();

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
  ///
  /// The floor now COVERS the entrance: the lockup settles at
  /// [AzamanIntro.revealMs], so the floor is that plus a frame of grace
  /// rather than a flat 2s that could cut the reveal off.
  late final Future<void> _brandingFloor = Future<void>.delayed(
    const Duration(milliseconds: AzamanIntro.revealMs + 120),
  );

  /// Deadman switch for the reveal. The lockup normally reports through
  /// [AzamanIntro.onRevealed]; if that callback never arrives (a platform
  /// with tickers disabled, a build that swaps the intro out) the splash must
  /// still be able to leave. This can only ever run LATE, never early, so the
  /// "never cut the reveal" guarantee holds either way.
  late final Future<void> _revealFloor = Future<void>.delayed(
    const Duration(milliseconds: AzamanIntro.revealMs + 600),
  );

  void _onIntroRevealed() {
    if (!_introRevealed.isCompleted) _introRevealed.complete();
  }

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
    await Future.wait([
      _brandingFloor,
      Future.any([_introRevealed.future, _revealFloor]),
    ]);
    if (!mounted) return;
    context.go(location);
  }

  Future<void> _checkAuthStatus() async {
    // ── Auto-demo fallback for web ──────────────────────────────────────
    if (!AppConfig.demoMode && kIsWeb) {
      try {
        await apiClient
            .get('/health', requireAuth: false)
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
      auth.setUser(
        User(
          id: DemoSeedData.demoUserId,
          username: DemoSeedData.demoUsername,
          email: 'pyrax@demo.azaman.app',
          token: DemoSeedData.demoToken,
          role: 'USER',
          azmBalance: 12450.00,
          availableBalance: 12450.00,
          kycStatus: KycStatus.verified,
        ),
      );
      AuthGuard.isAuthenticated = true;
      ref.read(themeProvider).loadFromBackend();
      ref.read(settingsProvider).loadFromBackend();
      await _exitTo(AzRoutes.shell);
      return;
    }

    // THE PUBLIC INTRO, BEFORE ANY AUTH WORK (P7). A device that has not
    // seen the tour goes there first: the splash is the only boot resolver,
    // so this is the one place the decision can be made. The flag is LOCAL
    // and unrelated to the authenticated setup; a returning user never sees
    // it again, and a corrupt/unreadable flag shows it (see IntroStore).
    final introStore = widget.introStore ?? const IntroStore();
    final seenIntro = await introStore.hasSeenIntro();
    if (!mounted) return;
    if (!seenIntro) {
      await _exitTo(AzRoutes.intro);
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
          final status = await auth.setSessionFromLogin(
            User(
              id: userId,
              username: 'Loading…',
              email: '',
              token: token,
              role: userRole,
            ),
          );
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
                needsOnboarding ? AzRoutes.onboarding : AzRoutes.shell,
              );
              return;
            case AuthStatus.profileNotFound:
              // The snackbar must be shown BEFORE the go(): the root
              // ScaffoldMessenger survives the route change, but this
              // context does not (the login page is a different route).
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'No profile found for this account. Please sign up.',
                  ),
                ),
              );
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
