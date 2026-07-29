import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/biometric_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';


class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends ConsumerState<SecuritySettingsScreen> {
  bool _twoFactorEnabled = false;
  bool _showQrSetup = false;
  final _verificationCodeController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  bool _pinSet = false;
  bool _obscurePin = true;
  bool _obscurePinConfirm = true;
  bool _loading2fa = false;
  bool _loadingPin = false;

  String _qrData = '';
  String _secret = '';

  // Phase H3 — biometric lock state. Loaded from SharedPreferences via
  // BiometricService.isEnabled. Toggling fires the system biometric prompt
  // first; we only persist the new value if the prompt succeeds. This
  // prevents a malicious app-switcher from silently turning the lock OFF
  // (and thus removing the financial-action gate) without the user proving
  // ownership of the device.
  bool _biometricLockEnabled = false;
  bool _biometricAvailable = false;
  bool _loadingBiometric = false;

  // Session management
  List<Map<String, dynamic>> _sessions = [];
  bool _loadingSessions = false;
  bool _loadingExport = false;

  @override
  void initState() {
    super.initState();
    // Fetch current 2FA status from user profile
    // Note: If the User model adds isTwoFactorEnabled in the future,
    // uncomment the line below. For now we default to false.
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   final user = ref.read(authProvider).user;
    //   if (user != null) setState(() => _twoFactorEnabled = user.isTwoFactorEnabled);
    // });
    _loadBiometricState();
    _loadSessions();
  }

  Future<void> _loadBiometricState() async {
    final svc = BiometricService();
    final available = await svc.isAvailable;
    final enabled = await svc.isEnabled;
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricLockEnabled = enabled;
    });
  }

  Future<void> _onToggleBiometric(bool value) async {
    if (_loadingBiometric) return;
    final svc = BiometricService();
    setState(() => _loadingBiometric = true);
    try {
      if (value) {
        // Turning ON: prove ownership before flipping the bit. If the user
        // has biometrics available but skipped enrollment, authenticate()
        // falls back to the device passcode — both are acceptable proof.
        final ok = await svc.authenticate(
          reason: 'Authenticate to enable biometric lock',
        );
        if (!ok) {
          if (mounted) {
            AzamanHaptics.warn();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Authentication failed. Biometric lock not enabled.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        await svc.setEnabled(true);
        if (mounted) {
          AzamanHaptics.commit();
          setState(() => _biometricLockEnabled = true);
        }
      } else {
        // Turning OFF: also gate behind authenticate(). A pickpocket who
        // already has the unlocked phone shouldn't be able to disable the
        // lock and then drain funds.
        final ok = await svc.authenticate(
          reason: 'Authenticate to disable biometric lock',
        );
        if (!ok) {
          if (mounted) {
            AzamanHaptics.warn();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Authentication failed. Biometric lock remains on.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        await svc.setEnabled(false);
        if (mounted) {
          AzamanHaptics.toggle();
          setState(() => _biometricLockEnabled = false);
        }
      }
    } finally {
      if (mounted) setState(() => _loadingBiometric = false);
    }
  }

  @override
  void dispose() {
    _verificationCodeController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

  void _onToggle2fa(bool value) async {
    if (value) {
      // Enable: call setup endpoint to get QR code
      setState(() { _loading2fa = true; });
      final token = ref.read(authProvider).user?.token;
      try {
        final apiClient = ApiClient();
        final res = await apiClient.post('/security/2fa/setup', {});
        if (res.statusCode == 200 || res.statusCode == 201) {
          final body = jsonDecode(res.body);
          final data = body['data'] ?? body;
          setState(() {
            _twoFactorEnabled = true;
            _showQrSetup = true;
            _qrData = data['qrCodeDataURL'] ?? data['otpauthUrl'] ?? '';
            _secret = data['secret'] ?? '';
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to setup 2FA (${res.statusCode})'),
              backgroundColor: ref.read(themeProvider).colors.danger,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error: $e'),
            backgroundColor: ref.read(themeProvider).colors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } finally {
        if (mounted) setState(() => _loading2fa = false);
      }
    } else {
      // Disable: show code input to confirm disable
      setState(() {
        _twoFactorEnabled = false;
        _showQrSetup = false;
        _verificationCodeController.clear();
      });
      _disable2fa();
    }
    HapticFeedback.mediumImpact();
  }

  Future<void> _disable2fa() async {
    final code = _verificationCodeController.text.trim();
    if (code.length != 6) {
      // Just toggle off the UI; they'll need to verify next time
      return;
    }
    final token = ref.read(authProvider).user?.token;
    try {
      final apiClient = ApiClient();
      final res = await apiClient.post('/security/2fa/disable', {'token': code});
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('2FA disabled successfully'),
            backgroundColor: ref.read(themeProvider).colors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Disable 2FA error: $e');
    }
  }

  Future<void> _verifyCode() async {
    final code = _verificationCodeController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Enter a valid 6-digit code'),
          backgroundColor: ref.read(themeProvider).colors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    setState(() => _loading2fa = true);
    final token = ref.read(authProvider).user?.token;
    
    try {
      final apiClient = ApiClient();
      final res = await apiClient.post('/security/2fa/verify', {'token': code});
      
      if (res.statusCode == 200) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('2FA enabled successfully'),
            backgroundColor: ref.read(themeProvider).colors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _showQrSetup = false);
      } else {
        final errBody = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errBody['message'] ?? 'Verification failed'),
            backgroundColor: ref.read(themeProvider).colors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Network error: $e'),
          backgroundColor: ref.read(themeProvider).colors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading2fa = false);
    }
  }

  Future<void> _savePin() async {
    final pin = _pinController.text.trim();
    final confirm = _pinConfirmController.text.trim();

    if (pin.length != 4 || confirm.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('PIN must be 4 digits'),
          backgroundColor: ref.read(themeProvider).colors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (pin != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('PINs do not match'),
          backgroundColor: ref.read(themeProvider).colors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _loadingPin = true);
    final token = ref.read(authProvider).user?.token;

    try {
      final apiClient = ApiClient();
      final res = await apiClient.post('/security/pin/set', {'pin': pin});

      if (res.statusCode == 200 || res.statusCode == 201) {
        HapticFeedback.heavyImpact();
        setState(() => _pinSet = true);
        _pinController.clear();
        _pinConfirmController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Azaman PIN set successfully'),
            backgroundColor: ref.read(themeProvider).colors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final errBody = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errBody['message'] ?? 'Failed to set PIN'),
            backgroundColor: ref.read(themeProvider).colors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Network error: $e'),
          backgroundColor: ref.read(themeProvider).colors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingPin = false);
    }
  }

  void _removePin() {
    setState(() => _pinSet = false);
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Azaman PIN removed'),
        backgroundColor: ref.read(themeProvider).colors.warning,
        behavior: SnackBarBehavior.floating,
      ),
    );
    // Note: backend PIN removal could be wired here if endpoint exists
  }

  @override

  // ── SESSION MANAGEMENT ──────────────────────────────────────────────────────
  Future<void> _loadSessions() async {
    setState(() => _loadingSessions = true);
    try {
      final res = await apiClient.get('/security/sessions');
      final data = jsonDecode(res.body);
      setState(() => _sessions = List<Map<String, dynamic>>.from(data['sessions'] ?? []));
    } catch (e) {
      debugPrint('[Security] session load error: $e');
    } finally {
      setState(() => _loadingSessions = false);
    }
  }

  Future<void> _revokeSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ref.watch(themeProvider).colors.card,
        title: Text('Revoke Session?', style: TextStyle(color: ref.watch(themeProvider).colors.textPrimary)),
        content: Text('This will sign out that device immediately.',
            style: TextStyle(color: ref.watch(themeProvider).colors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Revoke', style: TextStyle(color: ref.watch(themeProvider).colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await apiClient.post('/security/sessions/$sessionId/revoke', {});
      AzamanHaptics.confirm();
      _loadSessions();
    } catch (e) {
      debugPrint('[Security] revoke session error: $e');
    }
  }

  Future<void> _revokeAllSessions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ref.watch(themeProvider).colors.card,
        title: Text('Sign Out Everywhere?', style: TextStyle(color: ref.watch(themeProvider).colors.textPrimary)),
        content: Text('This will sign out ALL devices including this one. You\'ll need to log in again.',
            style: TextStyle(color: ref.watch(themeProvider).colors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sign Out All', style: TextStyle(color: ref.watch(themeProvider).colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await apiClient.post('/security/sessions/revoke-all', {});
      AzamanHaptics.confirm();
      _loadSessions();
    } catch (e) {
      debugPrint('[Security] revoke all error: $e');
    }
  }

  // ── GDPR DATA EXPORT ───────────────────────────────────────────────────────
  Future<void> _exportData() async {
    setState(() => _loadingExport = true);
    try {
      final res = await apiClient.get('/security/data-export');
      final data = jsonDecode(res.body);

      // Show summary dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: ref.watch(themeProvider).colors.card,
            title: Text('Your Data Export', style: TextStyle(color: ref.watch(themeProvider).colors.textPrimary)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text('Here\'s a summary of your data:', style: TextStyle(color: ref.watch(themeProvider).colors.textSecondary)),
                  const SizedBox(height: 12),
                  ...(data['summary'] as List<dynamic>?)?.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(item['table'] ?? '', style: TextStyle(color: ref.watch(themeProvider).colors.textSecondary, fontSize: 13)),
                        Text('${item['count']} records', style: TextStyle(color: ref.watch(themeProvider).colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )) ?? [],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () {
                  // Copy full JSON to clipboard
                  Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)));
                  AzamanHaptics.confirm();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Data copied to clipboard', style: TextStyle(color: ref.watch(themeProvider).colors.textPrimary))),
                  );
                },
                child: Text('Copy Full JSON', style: TextStyle(color: ref.watch(themeProvider).colors.accent)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('[Security] data export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e', style: TextStyle(color: ref.watch(themeProvider).colors.textPrimary))),
        );
      }
    } finally {
      setState(() => _loadingExport = false);
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
          'Security',
          style: TextStyle(color: colors.textPrimary),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _sectionHeader('Two-Factor Authentication', colors),
          _buildCard(
            colors,
            children: [
              _toggleRow(
                colors,
                icon: Icons.security,
                title: 'Google Authenticator',
                subtitle: 'Add an extra layer of security',
                value: _twoFactorEnabled,
                onChanged: _onToggle2fa,
              ),
              if (_twoFactorEnabled && _showQrSetup) ...[
                const SizedBox(height: 4),
                Divider(color: colors.divider, height: 1),
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: _qrData.isNotEmpty ? _qrData : 'otpauth://totp/Azaman?secret=$_secret&issuer=Azaman',
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Scan this QR code in Google Authenticator',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _verificationCodeController,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 12,
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    hintStyle: TextStyle(
                      color: colors.textTertiary.withValues(alpha: 0.4),
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 12,
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _verifyCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor:
                          colors.isDark ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Verify & Enable',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colors.isDark ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),

          const SizedBox(height: 28),
          _sectionHeader('Biometric Lock', colors),
          _buildCard(
            colors,
            children: [
              _toggleRow(
                colors,
                icon: Icons.fingerprint,
                title: _biometricAvailable
                    ? 'Biometric on financial actions'
                    : 'Biometric not available on this device',
                subtitle: _biometricAvailable
                    ? 'Require Face ID / Touch ID / device passcode before slide-to-confirm fires'
                    : 'Enroll a fingerprint or face in your device settings to enable',
                value: _biometricLockEnabled,
                onChanged: (!_biometricAvailable || _loadingBiometric)
                    ? null
                    : _onToggleBiometric,
              ),
            ],
          ),

          const SizedBox(height: 28),
          _sectionHeader('Azaman PIN', colors),
          _buildCard(
            colors,
            children: [
              if (!_pinSet) ...[
                _pinField(
                  colors,
                  label: 'New 4-digit PIN',
                  controller: _pinController,
                  obscure: _obscurePin,
                  onToggleObscure: () =>
                      setState(() => _obscurePin = !_obscurePin),
                ),
                const SizedBox(height: 12),
                _pinField(
                  colors,
                  label: 'Confirm PIN',
                  controller: _pinConfirmController,
                  obscure: _obscurePinConfirm,
                  onToggleObscure: () => setState(
                      () => _obscurePinConfirm = !_obscurePinConfirm),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _savePin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor:
                          colors.isDark ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Set PIN',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colors.isDark ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colors.success.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle_outline,
                        color: colors.success,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Azaman PIN active',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Used for transaction authorization',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _removePin,
                      child: Text(
                        'Remove',
                        style: TextStyle(
                          color: colors.danger,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),

          // ── ACTIVE SESSIONS ──────────────────────────────────────────────────
          _sectionHeader('Active Sessions', colors),
          _buildCard(
            colors,
            children: [
              if (_loadingSessions)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_sessions.isEmpty) ...[
                _infoRow(colors, icon: Icons.devices, text: 'No active sessions found. Pull to refresh.'),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loadSessions,
                  child: Text('Refresh', style: TextStyle(color: colors.accent)),
                ),
              ] else ...[
                ..._sessions.map((s) => _sessionTile(colors, s)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _revokeAllSessions,
                    icon: Icon(Icons.logout, color: colors.danger, size: 18),
                    label: Text('Sign Out All Devices', style: TextStyle(color: colors.danger)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.danger.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),

          // ── PRIVACY & DATA (GDPR) ────────────────────────────────────────────
          _sectionHeader('Privacy & Data', colors),
          _buildCard(
            colors,
            children: [
              _actionRow(
                colors,
                icon: Icons.download_outlined,
                title: 'Export My Data',
                subtitle: 'Download all your data (GDPR)',
                onTap: _loadingExport ? null : _exportData,
                isLoading: _loadingExport,
              ),
              Divider(color: colors.divider, height: 1),
              _infoRow(
                colors,
                icon: Icons.shield_outlined,
                text: 'Your data is portable. Export includes your profile, transactions, trades, messages, and more.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sessionTile(AzamanColors colors, Map<String, dynamic> session) {
    final isCurrent = session['isCurrent'] == true;
    final device = session['device'] ?? 'Unknown device';
    final ip = session['ip'] ?? '';
    final created = session['createdAt'] ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: isCurrent ? colors.success.withValues(alpha: 0.1) : colors.accentSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isCurrent ? Icons.phone_iphone : Icons.devices,
              color: isCurrent ? colors.success : colors.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      device.length > 30 ? '${device.substring(0, 30)}...' : device,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('This device', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: colors.success)),
                      ),
                    ],
                  ],
                ),
                if (ip.isNotEmpty)
                  Text(ip, style: TextStyle(fontSize: 11, color: colors.textTertiary)),
                if (created.isNotEmpty)
                  Text(created, style: TextStyle(fontSize: 11, color: colors.textTertiary)),
              ],
            ),
          ),
          if (!isCurrent)
            IconButton(
              icon: Icon(Icons.close, color: colors.danger, size: 20),
              onPressed: () => _revokeSession(session['id']?.toString() ?? ''),
            ),
        ],
      ),
    );
  }

  Widget _actionRow(
    AzamanColors colors, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: colors.accentSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: isLoading
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colors.accent))
                : Icon(icon, color: colors.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: colors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(AzamanColors colors, {required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(icon, color: colors.textTertiary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: colors.textTertiary),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: colors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildCard(AzamanColors colors, {required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _toggleRow(
    AzamanColors colors, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.accentSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: colors.accent, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: colors.textTertiary),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: colors.success,
        ),
      ],
    );
  }

  Widget _pinField(
    AzamanColors colors, {
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggleObscure,
  }) {
    return TextField(
      controller: controller,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: 16,
      ),
      keyboardType: TextInputType.number,
      maxLength: 4,
      textAlign: TextAlign.center,
      obscureText: obscure,
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        labelStyle: TextStyle(
          color: colors.textTertiary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.accent.withValues(alpha: 0.5)),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: colors.textTertiary,
            size: 20,
          ),
          onPressed: onToggleObscure,
        ),
      ),
    );
  }
}
