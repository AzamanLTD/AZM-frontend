import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:flutter_animate/flutter_animate.dart';


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
  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();

    // Main entrance animation: 800ms fade + scale
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _scaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    // Glow pulse: continuous 2s loop
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _animController.forward();
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

  Future<void> _checkAuthStatus() async {
    await Future.delayed(const Duration(seconds: 2));

    final versionResult = await versionGateService.check(AppConfig.appVersion);
    if (!mounted) return;

    if (versionResult.updateRequired) {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => ForceUpdateScreen(
          message: versionResult.message ?? 'A new version of Azaman is available. Please update to continue.',
          updateUrl: versionResult.updateUrl,
          minVersion: versionResult.minVersion,
        ),
      ));
      return;
    }

    final auth = ref.read(authProvider);
    // Demo mode: bypass auth and go straight to the app with seeded data
    if (AppConfig.demoMode) {
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
      // Set the auth guard so GoRouter lets us through
      AuthGuard.isAuthenticated = true;
      // Skip version gate, onboarding — go straight to the app
      ref.read(themeProvider).loadFromBackend();
      ref.read(settingsProvider).loadFromBackend();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => const MainNavigationWrapper()));
      return;
    }
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
              ref.read(themeProvider).loadFromBackend();
              ref.read(settingsProvider).loadFromBackend();
              await ref.read(platformConfigProvider.notifier).refresh();
              final needsOnboarding = await _checkOnboardingStatus();
              if (!mounted) return;
              if (needsOnboarding) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OnboardingScreen()));
              } else {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainNavigationWrapper()));
              }
              return;
            case AuthStatus.profileNotFound:
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No profile found for this account. Please sign up.')));
              return;
            case AuthStatus.unauthenticated:
            case AuthStatus.error:
            case AuthStatus.idle:
            case AuthStatus.loading:
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              return;
          }
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        }
      } catch (e) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      }
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Center: Logo + wordmark ────────────────────────────────
            Expanded(
              child: Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Logo with real pulsing glow ─────────────────────
                        AnimatedBuilder(
                          animation: _glowController,
                          builder: (_, __) {
                            final glow = _glowController.value;
                            return Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06 + glow * 0.10),
                                    blurRadius: 25 + glow * 15,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Hero(
                                tag: 'azaman_logo',
                                child: Image.asset(
                                  'assets/images/azaman_logo_black.png',
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        // ── Smaller wordmark with gold shimmer ───────────────
                        ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.black.withValues(alpha: 0.3),
                                Colors.black,
                                Colors.black.withValues(alpha: 0.3),
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ).createShader(bounds);
                          },
                          child: const Text(
                            'AZAMAN',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 4,
                            ),
                          ),
                        )
                        .animate(onPlay: (c) => c.repeat())
                        .shimmer(duration: 2200.ms, color: Colors.black.withValues(alpha: 0.15)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ── Bottom: indeterminate progress bar ──────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(80, 0, 80, 40),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.black.withValues(alpha: 0.06),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.black.withValues(alpha: 0.4 + _glowController.value * 0.2),
                      ),
                      minHeight: 3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Securing your session...',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.3),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}