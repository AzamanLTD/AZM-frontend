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
      backgroundColor: const Color(0xFF0B0E11),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Logo with pulsing glow ──────────────────────────────
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (_, __) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Logo — Hero tagged for morph to login screen
                        Hero(
                          tag: 'azaman_logo',
                          child: Image.asset(
                            'assets/images/azaman_logo.png',
                            width: 100,
                            height: 100,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 28),
                // ── "AZAMAN" text with shimmer ───────────────────────────
                ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white.withOpacity(0.3),
                        Colors.white,
                        Colors.white.withOpacity(0.3),
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
                      letterSpacing: 6,
                    ),
                  ),
                )
                .animate(onPlay: (c) => c.repeat())
                .fadeIn(duration: 400.ms, delay: 400.ms)
                .shimmer(duration: 2000.ms, color: const Color(0xFFD4AF37).withOpacity(0.4)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}