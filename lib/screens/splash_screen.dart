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
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => const MainNavigationWrapper()));
      return;
    }

    // Version gate (only for non-demo mode)
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
                  // ── Triangle background behind logo ──────────────────────
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Triangle plate — slightly bigger than the logo
                      CustomPaint(
                        size: const Size(156, 156),
                        painter: _TrianglePlatePainter(),
                      ),
                      // ── Center: LogoTraceLoader ──────────────────────────
                      LogoTraceLoader(
                        size: 120,
                        strokeWidth: 4,
                        color: Colors.black.withValues(alpha: 0.75),
                        loopDurationSeconds: 2.4,
                      ),
                    ],
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


// =============================================================================
// Triangle Plate — subtle background behind the logo on the splash screen.
// Slightly bigger than the logo so it frames it nicely.
// =============================================================================
class _TrianglePlatePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // Equilateral-ish triangle pointing up, inscribed in the plate
    final r = w * 0.46;
    final p1 = Offset(cx, cy - r * 0.72);                    // top
    final p2 = Offset(cx - r * 0.87, cy + r * 0.52);         // bottom-left
    final p3 = Offset(cx + r * 0.87, cy + r * 0.52);         // bottom-right

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();

    // Soft fill
    final fillPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.04)
      ..isAntiAlias = true;
    canvas.drawPath(path, fillPaint);

    // Subtle stroke
    final strokePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..isAntiAlias = true;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePlatePainter old) => false;
}
