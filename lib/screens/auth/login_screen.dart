import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/sso_service.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/screens/auth/signup_screen.dart';
import 'package:azaman/widgets/google_logo.dart';
import 'package:azaman/data/demo_seed_data.dart';
import 'package:azaman/router/auth_guard.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:go_router/go_router.dart' show GoRouterHelper;
import 'package:azaman/config.dart';
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

  // One page, three deliberate steps: provider choice → email form →
  // influencer code. Each step owns its own back affordance.
  static const int _stepProviders = 0;
  static const int _stepEmail = 1;
  static const int _stepInfluencer = 2;
  int _step = _stepProviders;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
        );
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

  /// Fades out, swaps the step, fades back in. Guarded so a double tap or an
  /// in-flight sign-in can never land the UI on a half-transitioned step.
  void _transitionTo(int step) {
    if (_step == step || _isLoading) return;
    _fadeController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _step = step;
        _errorMessage = null;
      });
      _fadeController.forward();
    });
  }

  void _openEmailStep() => _transitionTo(_stepEmail);
  void _openProviderStep() => _transitionTo(_stepProviders);
  void _openInfluencerStep() => _transitionTo(_stepInfluencer);
  void _goBackStep() => _transitionTo(_stepProviders);

  void _openSignUp() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SignUpScreen()),
    );
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
        {'email': email, 'password': password},
        requireAuth: false, // Don't need auth token for login
      );

      final data = jsonDecode(response.body);

      // Validate response structure matches API contract
      if (data['success'] == true) {
        // Token can be at root level, nested under "data", or under "user"
        final String rawToken =
            (data['token'] ??
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
        double d(dynamic v) => v is num
            ? v.toDouble()
            : (double.tryParse(v?.toString() ?? '') ?? 0.0);

        final loggedInUser = User(
          id: u['id'] is int ? u['id'].toString() : u['id']?.toString() ?? '0',
          username: u['username'] ?? '',
          email: u['email'] ?? '',
          token: rawToken,
          role:
              u['role'] ??
              'USER', // Backend returns uppercase 'USER' or 'ADMIN'
          azmBalance: d(u['azmBalance']),
          availableBalance: d(u['availableBalance']),
        );

        final refreshToken =
            (data['refreshToken'] ?? data['data']?['refreshToken'])?.toString();
        await _storage.write(key: 'auth_token', value: loggedInUser.token);
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await _storage.write(key: 'refresh_token', value: refreshToken);
        }
        await _storage.write(key: 'user_id', value: loggedInUser.id);
        await _storage.write(
          key: 'user_role',
          value: loggedInUser.role.toLowerCase(),
        );

        final auth = ref.read(authProvider);

        // Phantom-User fix: await the canonical /auth/me/:id hydration
        // before navigating, so the dashboard sees the authoritative
        // role + balances and never the stale login payload.
        final status = await auth.setSessionFromLogin(loggedInUser);

        if (!mounted) return;

        switch (status) {
          case AuthStatus.authenticated:
            // ONE NAVIGATION AUTHORITY: the shell is the router-owned
            // '/home' page. The snackbar is shown BEFORE the go() — the
            // root ScaffoldMessenger survives the route change, this
            // screen's context does not.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Login Successful!'),
                backgroundColor: const Color(0xFF02C076),
              ),
            );
            context.go(AzRoutes.shell);
            break;

          case AuthStatus.profileNotFound:
            // JWT is valid but the backend has no DB record — force the
            // user into a registration / setup flow rather than landing
            // them in a broken dashboard.
            setState(
              () => _errorMessage =
                  'No profile linked to this account. Please sign up to continue.',
            );
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SignUpScreen()),
            );
            break;

          case AuthStatus.unauthenticated:
            setState(
              () => _errorMessage =
                  'Session was rejected by the server. Please try again.',
            );
            break;

          case AuthStatus.error:
            setState(
              () => _errorMessage =
                  auth.error ??
                  'Could not load your profile. Please try again.',
            );
            break;

          case AuthStatus.idle:
          case AuthStatus.loading:
            // Should never happen after await, but guard anyway.
            setState(() => _errorMessage = 'Unexpected state. Please retry.');
            break;
        }
      } else {
        // Handle backend error response
        setState(
          () => _errorMessage = data['message'] ?? 'Authentication failed.',
        );
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

  void _enterDemoMode() {
    AppConfig.enableDemoMode();
    final user = User(
      id: DemoSeedData.demoUserId,
      username: DemoSeedData.demoUsername,
      email: 'kwesi.mensah@demo.azaman.app',
      token: DemoSeedData.demoToken,
      role: 'USER',
      azmBalance: 12450.00,
      availableBalance: 12450.00,
    );
    ref.read(authProvider).setUser(user);
    AuthGuard.isAuthenticated = true;
    if (!mounted) return;
    // ONE NAVIGATION AUTHORITY: go to the router-owned shell.
    context.go(AzRoutes.shell);
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
              child: switch (_step) {
                _stepEmail => _buildEmailStep(colors),
                _stepInfluencer => _buildInfluencerStep(colors),
                _ => _buildProviderStep(colors),
              },
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // P4 LOGIN — PROVIDER FIRST.
  //
  // The page a user lands on is the provider choice: brand, a heading, Apple,
  // Google, and one quiet secondary route into the email form. The form is its
  // own step with its own back affordance, never the main event it used to be.
  // ===========================================================================
  Widget _buildProviderStep(AzamanColors colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Hero(
            tag: 'azaman_logo',
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 100.0, end: 84.0),
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
        const SizedBox(height: 26),
        Text(
              'Welcome to Azaman',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.4,
                color: colors.textPrimary,
              ),
            )
            .animate()
            .fadeIn(delay: 200.ms, duration: 400.ms)
            .slideY(begin: 0.05, end: 0),
        const SizedBox(height: 8),
        Text(
          'Sign in, or create your account in a few seconds.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.35,
            color: colors.textSecondary,
          ),
        ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
        const SizedBox(height: 40),

        if (_errorMessage != null) _errorBanner(colors),

        // APPLE FIRST — the platform convention, and the quieter of the two
        // brand marks on a light surface.
        _ssoButton(
          key: const Key('login-continue-apple'),
          label: 'Continue with Apple',
          icon: Icons.apple,
          iconColor: Colors.white,
          bgColor: Colors.black,
          borderColor: Colors.white.withValues(alpha: 0.15),
          onTap: () => _signInWithSso(SsoProvider.apple),
        ),
        const SizedBox(height: 12),
        _ssoButton(
          key: const Key('login-continue-google'),
          label: 'Continue with Google',
          leading: const GoogleLogo(size: 22),
          bgColor: Colors.white,
          borderColor: colors.isDark
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.black.withValues(alpha: 0.08),
          onTap: () => _signInWithSso(SsoProvider.google),
        ),

        const SizedBox(height: 14),

        // THE SECONDARY ROUTE. Quiet, same width, clearly a different way in
        // rather than a third provider.
        SizedBox(
          height: 50,
          child: TextButton.icon(
            key: const Key('login-continue-email'),
            onPressed: _isLoading ? null : _openEmailStep,
            style: TextButton.styleFrom(
              foregroundColor: colors.textPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(
              Icons.mail_outline,
              size: 20,
              color: colors.textSecondary,
            ),
            label: Text(
              'Continue with email',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),

        const SizedBox(height: 26),

        // Wrap, not Row: the pair stays centred and reflows instead of
        // overflowing on a narrow phone or with enlarged accessibility text.
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'New to Azaman? ',
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
            GestureDetector(
              onTap: _openSignUp,
              child: Text(
                'Create an account',
                style: TextStyle(
                  color: colors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 26),
        Divider(color: colors.divider, height: 1),
        const SizedBox(height: 18),

        // ── Demo mode entry ──────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _enterDemoMode,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: BorderSide(
                color: colors.accent.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            icon: Icon(
              Icons.play_circle_outline,
              size: 22,
              color: colors.accent,
            ),
            label: Text(
              'Try Demo (No Account Needed)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            'Explore the full Azaman experience with seeded demo data. No signup required.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: colors.textTertiary),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _openInfluencerStep,
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

  // ===========================================================================
  // THE EMAIL FORM — its own step, with a back affordance. Nothing is
  // pre-selected or half-filled: the user chose this route deliberately.
  // ===========================================================================
  Widget _buildEmailStep(AzamanColors colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            key: const Key('login-email-back'),
            onPressed: _isLoading ? null : _goBackStep,
            tooltip: 'Back',
            icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in with email',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.4,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Use the email and password on your Azaman account.',
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 26),

        if (_errorMessage != null) _errorBanner(colors),

        TextField(
          key: const Key('login-email-field'),
          controller: _emailController,
          style: TextStyle(color: colors.textPrimary),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
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
              borderSide: BorderSide(
                color: colors.accent.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('login-password-field'),
          controller: _passwordController,
          style: TextStyle(color: colors.textPrimary),
          obscureText: !_passwordVisible,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _login(),
          decoration: InputDecoration(
            labelText: 'Password',
            labelStyle: TextStyle(color: colors.textTertiary),
            prefixIcon: Icon(Icons.lock_outline, color: colors.textTertiary),
            suffixIcon: IconButton(
              icon: Icon(
                _passwordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: colors.textTertiary,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _passwordVisible = !_passwordVisible),
            ),
            filled: true,
            fillColor: colors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: colors.accent.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            key: const Key('login-email-submit'),
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
                    'Sign in',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: colors.isDark ? Colors.black : Colors.white,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _openProviderStep,
            child: Text(
              'Use Apple or Google instead',
              style: TextStyle(color: colors.textTertiary, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Wrap, not Row: the pair stays centred and reflows instead of
        // overflowing on a narrow phone or with enlarged accessibility text.
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'New to Azaman? ',
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
            GestureDetector(
              onTap: _openSignUp,
              child: Text(
                'Create an account',
                style: TextStyle(
                  color: colors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The shared inline error surface (provider failures, validation, network).
  Widget _errorBanner(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.danger.withValues(alpha: 0.4)),
      ),
      child: Text(
        _errorMessage!,
        style: TextStyle(color: colors.danger),
        textAlign: TextAlign.center,
      ),
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
          child: Icon(Icons.mic_none_outlined, size: 36, color: colors.accent),
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
              borderSide: BorderSide(
                color: colors.accent.withValues(alpha: 0.5),
              ),
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
          onPressed: _openProviderStep,
          child: Text(
            'Back to sign in',
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
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
  //   * SsoCancelledException — the user closed the provider sheet: reset the
  //     spinner, no banner, no dialog.
  //
  //   * SsoNotConfiguredException — this build genuinely cannot do the
  //     provider (missing OAuth client, provider disabled, Apple not enabled).
  //     Surfaced as a *modal* carrying the service's specific reason, because
  //     a snackbar is too easy to miss for something the user may hand to
  //     support.
  //
  //   * SsoException — surface the message inline (the same red banner that
  //     email/password login uses).
  //
  //   * Other — generic network error message inline.
  //
  //   * Success — go to the router-owned shell, mirror the email/password flow.
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
      // on the shell's messenger so the user
      // actually sees it.
      final colors = ref.read(themeProvider).colors;
      // ONE NAVIGATION AUTHORITY: go to the router-owned shell. The
      // snackbar is shown BEFORE the go() — the root ScaffoldMessenger
      // survives the route change; using this screen's context after
      // the go() would look up a deactivated ancestor.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: colors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (context.mounted) context.go(AzRoutes.shell);
    } on SsoCancelledException {
      // The user closed the provider sheet. That is a decision, not a fault:
      // drop the spinner and show nothing at all.
      if (mounted) setState(() => _isLoading = false);
    } on SsoNotConfiguredException catch (e) {
      _showSsoNotConfiguredDialog(e.provider, e.reason);
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

  void _showSsoNotConfiguredDialog(SsoProvider provider, String reason) {
    final colors = ref.read(themeProvider).colors;
    final providerLabel = provider == SsoProvider.google ? 'Google' : 'Apple';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          '$reason\n\nYou can sign in with email instead, or keep using '
          'Azaman with the other provider.',
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
    Key? key,
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
      key: key,
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
