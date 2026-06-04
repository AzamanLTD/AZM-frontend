import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:azaman/config.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/sso_service.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/screens/auth/login_screen.dart';
import 'package:azaman/main.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  final _storage = const FlutterSecureStorage();

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // Validation
    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all required fields.');
      return;
    }

    if (password != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Use the API client for consistent error handling
      final response = await apiClient.post(
        '/auth/register',
        {
          'username': username,
          'email': email,
          'password': password,
        },
        requireAuth: false,
      );

      final data = jsonDecode(response.body);
      
      if (data['success'] == true) {
        // Registration successful, now automatically log in
        setState(() => _errorMessage = null);
        
        // Try to log in with the new credentials
        final loginResponse = await apiClient.post(
          '/auth/login',
          {
            'email': email,
            'password': password,
          },
          requireAuth: false,
        );

        final loginData = jsonDecode(loginResponse.body);
        
        if (loginData['success'] == true) {
          // Token can be at root level, nested under "data", or under "user"
          final String rawToken = (loginData['token'] ??
                  loginData['data']?['token'] ??
                  loginData['user']?['token'] ??
                  '')
              .toString();
          // User object can be at root level or nested under "data"
          final Map<String, dynamic> u = loginData['user'] is Map<String, dynamic>
              ? loginData['user'] as Map<String, dynamic>
              : (loginData['data']?['user'] is Map<String, dynamic>
                  ? loginData['data']!['user'] as Map<String, dynamic>
                  : <String, dynamic>{});
          double _d(dynamic v) =>
              v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0.0);
          
          final newUser = User(
            id: u['id'] is int ? u['id'].toString() : u['id']?.toString() ?? '0',
            username: u['username'] ?? '',
            email: u['email'] ?? '',
            token: rawToken,
            role: u['role'] ?? 'USER',
            azmBalance: _d(u['azmBalance']),
            availableBalance: _d(u['availableBalance']),
          );

          await _storage.write(key: 'auth_token', value: newUser.token);
          await _storage.write(key: 'user_id', value: newUser.id);
          await _storage.write(key: 'user_role', value: newUser.role.toLowerCase());

          final auth = ref.read(authProvider);
          auth.setUser(newUser);

          if (!mounted) return;
          
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loginData['message'] ?? 'Registration successful!'),
              backgroundColor: const Color(0xFF02C076),
            ),
          );
          
          // Navigate to main app
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => MainWrapper()),
          );
        } else {
          // Registration successful but auto-login failed
          setState(() => _errorMessage = 'Registration successful! Please log in.');
          await Future.delayed(const Duration(seconds: 1));
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      } else {
        // Handle registration error
        setState(() => _errorMessage = data['message'] ?? 'Registration failed.');
      }
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.toString());
    } catch (e) {
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text(
          'Create Account',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Icon(Icons.currency_exchange, size: 64, color: colors.accent),
              const SizedBox(height: 16),
              Text(
                'Join Azaman P2P',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create your account to start trading',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: colors.textSecondary),
              ),
              const SizedBox(height: 32),

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
                controller: _usernameController,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Username',
                  labelStyle: TextStyle(color: colors.textTertiary),
                  prefixIcon: Icon(Icons.person_outline, color: colors.textTertiary),
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
                controller: _emailController,
                style: TextStyle(color: colors.textPrimary),
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: colors.textTertiary),
                  prefixIcon: Icon(Icons.email_outlined, color: colors.textTertiary),
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
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: colors.textTertiary),
                  prefixIcon: Icon(Icons.lock_outline, color: colors.textTertiary),
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
                  helperText: 'Minimum 6 characters',
                  helperStyle: TextStyle(color: colors.textTertiary, fontSize: 12),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _confirmPasswordController,
                style: TextStyle(color: colors.textPrimary),
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  labelStyle: TextStyle(color: colors.textTertiary),
                  prefixIcon: Icon(Icons.lock_outline, color: colors.textTertiary),
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
              const SizedBox(height: 32),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
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
                          'Create Account',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: colors.isDark ? Colors.black : Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // ── SSO (Phase F) ────────────────────────────────────────────
              //
              // Same SsoService that the login screen uses. Backend treats
              // /api/auth/sso as register-or-login: existing email returns
              // login session; unseen email auto-creates the account. So
              // exposing the SSO buttons here is functionally identical
              // to wiring them on the login screen.
              Row(
                children: [
                  Expanded(child: Divider(color: colors.divider)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'or sign up with',
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
                colors: colors,
                label: 'Continue with Apple',
                icon: Icons.apple,
                iconColor: Colors.white,
                bgColor: Colors.black,
                borderColor: Colors.white.withOpacity(0.15),
                onTap: () => _signUpWithSso(SsoProvider.apple),
              ),
              const SizedBox(height: 12),
              _ssoButton(
                colors: colors,
                label: 'Continue with Google',
                icon: Icons.g_mobiledata,
                iconColor: const Color(0xFF4285F4),
                bgColor: Colors.white,
                borderColor: Colors.transparent,
                onTap: () => _signUpWithSso(SsoProvider.google),
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                      );
                    },
                    child: Text(
                      'Log In',
                      style: TextStyle(
                        color: colors.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              Text(
                'By creating an account, you agree to our Terms of Service and Privacy Policy.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── SSO HANDLER (Phase F) ─────────────────────────────────────────────
  // Mirrors LoginScreen — backend's /api/auth/sso auto-creates accounts
  // for unseen emails so a single handler covers sign-up + sign-in.
  Future<void> _signUpWithSso(SsoProvider provider) async {
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
      // Phase H review pass: navigate first, snackbar second so the toast
      // is enqueued on the destination ScaffoldMessenger (this screen is
      // about to be disposed by pushReplacement).
      final colors = ref.read(themeProvider).colors;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MainWrapper()),
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
          'wiring is in place — sign up with email and password for now, '
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
    required AzamanColors colors,
    required String label,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
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
            Icon(icon, size: 22, color: iconColor),
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