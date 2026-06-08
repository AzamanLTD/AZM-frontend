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
import 'package:hugeicons_pro/hugeicons.dart';

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
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
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
                icon: HugeIconsSolid.security,
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
                      color: colors.textTertiary.withOpacity(0.4),
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
                        color: colors.accent.withOpacity(0.5),
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
                icon: HugeIconsSolid.fingerPrintScan,
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
                        color: colors.success.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        HugeIconsSolid.checkmarkCircle01,
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
        ],
      ),
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
          activeColor: colors.success,
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
          borderSide: BorderSide(color: colors.accent.withOpacity(0.5)),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? HugeIconsSolid.viewOff : HugeIconsSolid.view,
            color: colors.textTertiary,
            size: 20,
          ),
          onPressed: onToggleObscure,
        ),
      ),
    );
  }
}
