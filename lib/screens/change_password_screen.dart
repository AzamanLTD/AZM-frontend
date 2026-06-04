// =============================================================================
// AZAMAN — CHANGE PASSWORD  (Phase F)
//
// Wired against the new backend endpoint added in this PR:
//
//   POST /api/security/change-password
//   body: { currentPassword: string, newPassword: string }
//   auth: Bearer token (protect middleware)
//
// Returns 200 { success, message } on success. Common error codes:
//   400 — validation (password too short, mismatch, same as current,
//          SSO-only account)
//   401 — current password wrong
//   404 — user not found (stale token)
//
// UX is a single screen with three obscured-text fields, a strength hint,
// and a primary "Update Password" button that resolves into a clean
// success snackbar + auto-pop on success. Errors render inline above the
// form so they aren't dismissed mid-correction.
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState
    extends ConsumerState<ChangePasswordScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentCtrl.text;
    final next = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (next.length < 8) {
      setState(() =>
          _error = 'New password must be at least 8 characters long.');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }
    if (next == current) {
      setState(() =>
          _error = 'New password must be different from your current password.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await apiClient.post(
        '/security/change-password',
        {
          'currentPassword': current,
          'newPassword': next,
        },
      );

      final data = jsonDecode(response.body);

      if (data is Map<String, dynamic> && data['success'] == true) {
        if (!mounted) return;
        AzamanHaptics.commit();
        final colors = ref.read(themeProvider).colors;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message']?.toString() ?? 'Password updated successfully.',
            ),
            backgroundColor: colors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      } else {
        setState(() => _error =
            (data is Map<String, dynamic>)
                ? (data['message']?.toString() ?? 'Could not update password.')
                : 'Could not update password.');
      }
    } on ApiException catch (e) {
      // Surface the backend message verbatim — it carries the right
      // copy for "current password wrong", "must be 8+", "SSO-only", etc.
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Change Password',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          // Header lockup
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accentSurface,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_reset_rounded,
                color: colors.accent, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'Choose a new password',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use at least 8 characters. We recommend mixing letters, '
            'numbers, and symbols.',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colors.danger.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.danger.withOpacity(0.45)),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: colors.danger, fontSize: 13),
              ),
            ),

          _passwordField(
            colors,
            label: 'Current password',
            controller: _currentCtrl,
            obscure: _obscureCurrent,
            onToggle: () =>
                setState(() => _obscureCurrent = !_obscureCurrent),
          ),
          const SizedBox(height: 14),
          _passwordField(
            colors,
            label: 'New password',
            controller: _newCtrl,
            obscure: _obscureNew,
            onToggle: () => setState(() => _obscureNew = !_obscureNew),
          ),
          const SizedBox(height: 14),
          _passwordField(
            colors,
            label: 'Confirm new password',
            controller: _confirmCtrl,
            obscure: _obscureConfirm,
            onToggle: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.isDark ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.isDark ? Colors.black : Colors.white,
                      ),
                    )
                  : Text(
                      'Update Password',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colors.isDark ? Colors.black : Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField(
    AzamanColors colors, {
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: colors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
        prefixIcon: Icon(Icons.lock_outline, color: colors.textTertiary),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: colors.textTertiary,
            size: 20,
          ),
          onPressed: onToggle,
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
    );
  }
}
