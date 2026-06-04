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
import 'package:azaman/models/user_model.dart';
import 'package:azaman/config.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Premium splash animation: 800ms fade+scale on the logo
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();

    _checkAuthStatus();
  }

  /// Check if the user has completed onboarding
  Future<bool> _checkOnboardingStatus() async {
    try {
      final apiClient = ApiClient();
      final response = await apiClient.get('/users/onboarding');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final completed = data['data']?['completed'] ?? true;
        return !completed; // Returns true if onboarding is NOT completed
      }
    } catch (_) {
      // If check fails, don't block the user — assume onboarding done
    }
    return false;
  }

  Future<void> _checkAuthStatus() async {
    await Future.delayed(const Duration(seconds: 2));

    // ── Phase Q15: Version gate check ──────────────────────────────────────
    // Must run BEFORE auth so even unauthenticated users get blocked on
    // outdated builds. Fails-open: if /health is unreachable, proceed normally.
    final versionResult = await versionGateService.check(AppConfig.appVersion);
    if (!mounted) return;

    if (versionResult.updateRequired) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ForceUpdateScreen(
            message: versionResult.message ??
                'A new version of Azaman is available. Please update to continue.',
            updateUrl: versionResult.updateUrl,
            minVersion: versionResult.minVersion,
          ),
        ),
      );
      return;
    }
    // ── End version gate ───────────────────────────────────────────────────

    // Check if user has valid authentication with backend
    final auth = ref.read(authProvider);
    final isAuthenticated = await auth.checkAuthStatus();

    if (!mounted) return;

    if (isAuthenticated) {
      // We have a valid JWT — but per the Phantom-User bug fix we MUST
      // wait for the canonical DB profile (`/auth/me/:id`) to resolve
      // BEFORE deciding which screen to land on.
      try {
        final token = await _storage.read(key: 'auth_token');
        final userId = await _storage.read(key: 'user_id');
        final userRole = await _storage.read(key: 'user_role') ?? 'user';

        if (userId != null && token != null) {
          // Seed the auth machine with the JWT, then await full hydration.
          // setSessionFromLogin returns the resolved AuthStatus.
          final status = await auth.setSessionFromLogin(User(
            id: userId,
            username: 'Loading…',
            email: '',
            token: token,
            role: userRole,
          ));

          if (!mounted) return;

          switch (status) {
            case AuthStatus.authenticated:
              // Sync theme + settings from backend (cross-device persistence)
              ref.read(themeProvider).loadFromBackend();
              ref.read(settingsProvider).loadFromBackend();
              // Check if onboarding is completed
              final needsOnboarding = await _checkOnboardingStatus();
              if (!mounted) return;
              if (needsOnboarding) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                );
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const MainNavigationWrapper()),
                );
              }
              return;
            case AuthStatus.profileNotFound:
              // Firebase / JWT identity exists, but no DB record →
              // force the user back to the auth flow to register.
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'No profile found for this account. Please sign up.'),
                ),
              );
              return;
            case AuthStatus.unauthenticated:
            case AuthStatus.error:
            case AuthStatus.idle:
            case AuthStatus.loading:
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
              return;
          }
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      } catch (e) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
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
      backgroundColor: const Color(0xFF0B0E11),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD4AF37).withOpacity(0.15),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.currency_exchange,
                    size: 80,
                    color: Color(0xFFD4AF37),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'AZAMAN',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}