import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/config.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/sso_service.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/main.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/screens/auth/signup_screen.dart';
import 'package:azaman/widgets/google_logo.dart';
import 'package:flutter_animate/flutter_animate.dart';


class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _influencerController = TextEditingController();
  bool _passwordVisible = false;

  bool _isLoading = false;
  String? _errorMessage;
  final _storage = const FlutterSecureStorage();

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  int _step = 0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic));
    _fadeController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _influencerController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _advanceStep() {
    _fadeController.reverse().then((_) {
      setState(() => _step = 1);
      _fadeController.forward();
    });
  }

  void _goBackStep() {
    _fadeController.reverse().then((_) {
      setState(() => _step = 0);
      _fadeController.forward();
    });
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Use the API client for consistent error handling
      final response = await apiClient.post(
        '/auth/login',
        {
          'email': email,
          'password': password,
        },
        requireAuth: false, // Don't need auth token for login
      );

      final data = jsonDecode(response.body);
      
      // Validate response structure matches API contract
      if (data['success'] == true) {
        // Token can be at root level, nested under "data", or under "user"
        final String rawToken = (data['token'] ??
                data['data']?['token'] ??
                data['user']?['token'] ??
                '')
            .toString();
        // User object can be at root level or nested under "data"
        final Map<String, dynamic> u = data['user'] is Map<String, dynamic>
            ? data['user'] as Map<String, dynamic>
            : (data['data']?['user'] is Map<String, dynamic>
                ? data['data']!['user'] as Map<String, dynamic>
                : <String, dynamic>{});
        double _d(dynamic v) =>
            v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0.0);
        
        final loggedInUser = User(
          id: u['id'] is int ? u['id'].toString() : u['id']?.toString() ?? '0',
          username: u['username'] ?? '',
          email: u['email'] ?? '',
          token: rawToken,
          role: u['role'] ?? 'USER', // Backend returns uppercase 'USER' or 'ADMIN'
          azmBalance: _d(u['azmBalance']),
          availableBalance: _d(u['availableBalance']),
        );

        await _storage.write(key: 'auth_token', value: loggedInUser.token);
        await _storage.write(key: 'user_id', value: loggedInUser.id);
        await _storage.write(key: 'user_role', value: loggedInUser.role.toLowerCase());

        final auth = ref.read(authProvider);

        // Phantom-User fix: await the canonical /auth/me/:id hydration
        // before navigating, so the dashboard sees the authoritative
        // role + balances and never the stale login payload.
        final status = await auth.setSessionFromLogin(loggedInUser);

        if (!mounted) return;

        switch (status) {
          case AuthStatus.authenticated:
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => const MainNavigationWrapper()),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Login Successful!'),
                backgroundColor: const Color(0xFF02C076),
              ),
            );
            break;

          case AuthStatus.profileNotFound:
            // JWT is valid but the backend has no DB record — force the
            // user into a registration / setup flow rather than landing
            // them in a broken dashboard.
            setState(() => _errorMessage =
                'No profile linked to this account. Please sign up to continue.');
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SignUpScreen()),
            );
            break;

          case AuthStatus.unauthenticated:
            setState(() => _errorMessage =
                'Session was rejected by the server. Please try again.');
            break;

          case AuthStatus.error:
            setState(() => _errorMessage = auth.error ??
                'Could not load your profile. Please try again.');
            break;

          case AuthStatus.idle:
          case AuthStatus.loading:
            // Should never happen after await, but guard anyway.
            setState(() => _errorMessage = 'Unexpected state. Please retry.');
            break;
        }
      } else {
        // Handle backend error response
        setState(() => _errorMessage = data['message'] ?? 'Authentication failed.');
      }
    } on ApiException catch (e) {
      // Handle API errors gracefully
      setState(() => _errorMessage = e.toString());
    } catch (e) {
      // Handle general errors
      setState(() => _errorMessage = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AnimatedBuilder(
              animation: _fadeController,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: child,
                  ),
                );
              },
              child: _step == 0 ? _buildAuthStep(colors) : _buildInfluencerStep(colors),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthStep(AzamanColors colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Logo with Hero morph from splash — sits at the TOP of the login
        Center(
          child: Hero(
            tag: 'azaman_logo',
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 100.0, end: 80.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, size, _) {
                return Image.asset(
                  'assets/images/azaman_logo.png',
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Welcome to Azaman',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ).animate().fadeIn(delay: 300.ms, duration: 400.ms).slideY(begin: 0.05, end: 0),
        const SizedBox(height: 6),
        Text(
          'Sign in to continue',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: colors.textSecondary),
        ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
        const SizedBox(height: 40),

        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: colors.danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.danger.withOpacity(0.4)),
            ),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: colors.danger),
              textAlign: TextAlign.center,
            ),
          ),

        TextField(
          controller: _emailController,
          style: TextStyle(color: colors.textPrimary),
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email',
            labelStyle: TextStyle(color: colors.textTertiary),
            prefixIcon: Icon(Icons.mail_outline, color: colors.textTertiary),
            filled: true,
            fillColor: colors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.accent.withOpacity(0.5)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passwordController,
          style: TextStyle(color: colors.textPrimary),
          obscureText: !_passwordVisible,
          decoration: InputDecoration(
            labelText: 'Password',
            labelStyle: TextStyle(color: colors.textTertiary),
            prefixIcon: Icon(Icons.lock_outline, color: colors.textTertiary),
            suffixIcon: IconButton(
              icon: Icon(
                _passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: colors.textTertiary,
                size: 20,
              ),
              onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
            ),
            filled: true,
            fillColor: colors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.accent.withOpacity(0.5)),
            ),
          ),
        ),
        const SizedBox(height: 28),

        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      color: colors.isDark ? Colors.black : Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'Login',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: colors.isDark ? Colors.black : Colors.white,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 18),

        Row(
          children: [
            Expanded(child: Divider(color: colors.divider)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'or continue with',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(child: Divider(color: colors.divider)),
          ],
        ),
        const SizedBox(height: 18),

        _ssoButton(
          label: 'Continue with Apple',
          icon: Icons.apple,
          iconColor: Colors.white,
          bgColor: Colors.black,
          borderColor: Colors.white.withOpacity(0.15),
          onTap: () => _signInWithSso(SsoProvider.apple),
        ),
        const SizedBox(height: 12),
        _ssoButton(
          label: 'Continue with Google',
          leading: const GoogleLogo(size: 22),
          bgColor: Colors.white,
          borderColor: Colors.transparent,
          onTap: () => _signInWithSso(SsoProvider.google),
        ),

        const SizedBox(height: 28),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Don't have an account? ",
              style: TextStyle(color: colors.textSecondary),
            ),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SignUpScreen(),
                  ),
                );
              },
              child: Text(
                "Sign Up",
                style: TextStyle(
                  color: colors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        Center(
          child: TextButton(
            onPressed: _advanceStep,
            child: Text(
              'Have an influencer code? Tap here',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 12,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfluencerStep(AzamanColors colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accentSurface,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.mic_none_outlined,
            size: 36,
            color: colors.accent,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Where did you hear\nabout Azaman?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Enter an influencer referral code if you\nhave one — or skip to continue.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: colors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _influencerController,
          style: TextStyle(color: colors.textPrimary),
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'Influencer Code',
            hintStyle: TextStyle(color: colors.textTertiary),
            prefixIcon: Icon(Icons.tag, color: colors.textTertiary),
            filled: true,
            fillColor: colors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.accent.withOpacity(0.5)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: () {
              final code = _influencerController.text.trim();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    code.isEmpty
                        ? 'Continuing without code'
                        : 'Code "$code" applied',
                  ),
                  backgroundColor: colors.success,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Text(
              'Continue',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: colors.isDark ? Colors.black : Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _goBackStep,
          child: Text(
            'Back to sign in',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  // ─── SSO HANDLER (Phase F) ─────────────────────────────────────────────
  //
  // Wired to the canonical backend endpoint POST /api/auth/sso via SsoService.
  // The service handles the full round-trip: provider idToken → backend
  // verification → JWT issuance → AuthProvider hydration. We only need to
  // decide what to render on the four outcomes:
  //
  //   * SsoNotConfiguredException — show a friendly explanatory modal. The
  //     native Firebase Auth + provider plugins aren't compiled into this
  //     build yet (see lib/services/sso_service.dart for the exact follow-up
  //     wiring). Surfaced as a *modal*, not a snackbar — the user has to
  //     understand SSO isn't ready, snackbar would be too easy to miss.
  //
  //   * SsoException — surface the message inline (the same red banner that
  //     email/password login uses).
  //
  //   * Other — generic network error message inline.
  //
  //   * Success — push MainNavigationWrapper, mirror the email/password flow.
  Future<void> _signInWithSso(SsoProvider provider) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final svc = ref.read(ssoServiceProvider);
      final SsoResult result = provider == SsoProvider.google
          ? await svc.signInWithGoogle(ref)
          : await svc.signInWithApple(ref);

      if (!mounted) return;
      // Phase H review pass: capture the messenger BEFORE pushReplacement
      // disposes this screen's ScaffoldMessenger, then show the snackbar
      // on the inbound MainNavigationWrapper's messenger so the user
      // actually sees it.
      final colors = ref.read(themeProvider).colors;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigationWrapper()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: colors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on SsoNotConfiguredException catch (e) {
      _showSsoNotConfiguredDialog(e.provider);
    } on SsoException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'SSO failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSsoNotConfiguredDialog(SsoProvider provider) {
    final colors = ref.read(themeProvider).colors;
    final providerLabel =
        provider == SsoProvider.google ? 'Google' : 'Apple';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: colors.accent),
            const SizedBox(width: 10),
            Text(
              '$providerLabel Sign-In',
              style: TextStyle(color: colors.textPrimary, fontSize: 17),
            ),
          ],
        ),
        content: Text(
          '$providerLabel Sign-In requires a build with the Firebase Auth '
          'SDK and the $providerLabel provider plugin configured. The '
          'wiring is in place — sign in with email and password for now, '
          'and SSO will activate once the next build ships.',
          style: TextStyle(color: colors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: TextStyle(
                color: colors.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ssoButton({
    required String label,
    IconData? icon,
    Color? iconColor,
    Widget? leading,
    required Color bgColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    assert(icon != null || leading != null);
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: bgColor.computeLuminance() > 0.5
              ? Colors.black87
              : Colors.white,
          side: BorderSide(color: borderColor, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading ?? Icon(icon!, size: 22, color: iconColor),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: bgColor.computeLuminance() > 0.5
                    ? Colors.black87
                    : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
