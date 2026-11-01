// =============================================================================
// AZAMAN — PHONE VERIFICATION (P8)
//
// The primary phone step after account creation. Two stages, one screen:
//
//   1. enter a number  → POST /security/phone/send-otp
//   2. enter the code  → POST /security/phone/verify-otp
//
// Three rules this screen keeps:
//
//   * It never says "we sent you a code" unless the backend actually sent one.
//     When the response carries `testOtp`, that IS the code — no SMS left the
//     building — so the screen shows a test-delivery banner with the code
//     instead of pointing at a phone that stayed silent.
//   * "Verified" appears only after the server's 200. There is no local flag,
//     no optimistic state, and going back does not un-verify.
//   * Verification is about the NUMBER the user controls. It is not proof that
//     a MoMo wallet belongs to them, and the copy never implies it is.
//
// Leaving without verifying is allowed and costs nothing: the phone is gated
// at the financial action that needs it, not used as a toll booth here.
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/services/contact_service.dart' show kDefaultDialCode;
import 'package:azaman/services/phone_verification_service.dart';

class PhoneVerificationScreen extends ConsumerStatefulWidget {
  const PhoneVerificationScreen({super.key, this.service});

  /// Injectable for tests; defaults to the app singleton.
  final PhoneVerificationService? service;

  @override
  ConsumerState<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

enum _Stage { number, code, done }

class _PhoneVerificationScreenState
    extends ConsumerState<PhoneVerificationScreen> {
  final _numberController = TextEditingController();
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();

  _Stage _stage = _Stage.number;
  bool _busy = false;
  String? _error;
  String? _info;
  String? _testCode;
  int _resendIn = 0;
  Timer? _ticker;

  PhoneVerificationService get _service =>
      widget.service ?? PhoneVerificationService.instance;

  @override
  void dispose() {
    _ticker?.cancel();
    _numberController.dispose();
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _ticker?.cancel();
    setState(() => _resendIn = 30);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _send() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _testCode = null;
    });

    final result = await _service.sendOtp(_numberController.text);
    if (!mounted) return;

    switch (result.status) {
      case OtpSendStatus.sent:
      case OtpSendStatus.testMode:
        setState(() {
          _busy = false;
          _stage = _Stage.code;
          _testCode = result.status == OtpSendStatus.testMode
              ? result.testCode
              : null;
          // The honest line depends on whether anything was actually sent.
          _info = result.status == OtpSendStatus.testMode
              ? 'Test delivery: no SMS was sent.'
              : 'Code sent. Enter it below.';
        });
        _startResendCooldown();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _codeFocus.requestFocus();
        });
        break;
      case OtpSendStatus.invalidNumber:
      case OtpSendStatus.throttled:
      case OtpSendStatus.failed:
        setState(() {
          _busy = false;
          _error = result.message;
        });
        break;
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await _service.verifyOtp(
      _numberController.text,
      _codeController.text,
    );
    if (!mounted) return;

    switch (result.status) {
      case OtpVerifyStatus.verified:
        setState(() {
          _busy = false;
          _stage = _Stage.done;
          _info = null;
          _error = null;
        });
        break;
      case OtpVerifyStatus.rejected:
        setState(() {
          _busy = false;
          _error = result.message ?? 'That code did not work.';
        });
        break;
      case OtpVerifyStatus.invalidNumber:
      case OtpVerifyStatus.failed:
        setState(() {
          _busy = false;
          // A network failure is not a wrong code; keep what they typed.
          _error = result.message;
        });
        break;
    }
  }

  void _finish() {
    if (context.canPop()) {
      context.pop(true);
    } else {
      context.go(AzRoutes.shell);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () {
            if (_stage == _Stage.code) {
              setState(() {
                _stage = _Stage.number;
                _error = null;
              });
            } else {
              _finish();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_stage == _Stage.done)
                Expanded(child: _verifiedBody(colors))
              else ...[
                Text(
                  _stage == _Stage.number
                      ? 'Add your phone number'
                      : 'Enter your code',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _stage == _Stage.number
                      ? 'We use it to secure your account and to reach you about '
                            'money that is moving. You can change it later.'
                      : 'We sent a 6-digit code to '
                            '${_formatForDisplay(_numberController.text)}.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                if (_stage == _Stage.number)
                  _numberField(colors)
                else
                  _codeField(colors),
                if (_testCode != null) ...[
                  const SizedBox(height: 16),
                  _testBanner(colors, _testCode!),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _errorLine(colors, _error!),
                ],
                if (_info != null && _testCode == null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _info!,
                    style: TextStyle(color: colors.textTertiary, fontSize: 13),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : (_stage == _Stage.number ? _send : _verify),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _stage == _Stage.number
                                ? 'Send code'
                                : 'Verify number',
                          ),
                  ),
                ),
                if (_stage == _Stage.code) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: _busy || _resendIn > 0 ? null : _send,
                      child: Text(
                        _resendIn > 0
                            ? 'Resend code in ${_resendIn}s'
                            : 'Resend code',
                        style: TextStyle(
                          color: _resendIn > 0
                              ? colors.textTertiary
                              : colors.accent,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : _finish,
                      child: Text(
                        'Do this later',
                        style: TextStyle(color: colors.textTertiary),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _numberField(AzamanColors colors) {
    return TextField(
      controller: _numberController,
      keyboardType: TextInputType.phone,
      autofocus: true,
      enabled: !_busy,
      style: TextStyle(color: colors.textPrimary, fontSize: 18),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9 +()\-]')),
        LengthLimitingTextInputFormatter(20),
      ],
      decoration: InputDecoration(
        prefixText: '$kDefaultDialCode ',
        prefixStyle: TextStyle(color: colors.textTertiary, fontSize: 18),
        hintText: '24 412 3456',
        hintStyle: TextStyle(color: colors.textTertiary),
        filled: true,
        fillColor: colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
      ),
      onSubmitted: (_) => _send(),
    );
  }

  Widget _codeField(AzamanColors colors) {
    return TextField(
      controller: _codeController,
      focusNode: _codeFocus,
      keyboardType: TextInputType.number,
      enabled: !_busy,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 26,
        letterSpacing: 10,
        fontWeight: FontWeight.w700,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      decoration: InputDecoration(
        hintText: '000000',
        hintStyle: TextStyle(color: colors.textTertiary, letterSpacing: 10),
        filled: true,
        fillColor: colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
      ),
      onSubmitted: (_) => _verify(),
    );
  }

  Widget _testBanner(AzamanColors colors, String code) {
    return Container(
      key: const Key('phone-test-delivery-banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined, size: 16, color: colors.warning),
              const SizedBox(width: 8),
              Text(
                'Test delivery: no SMS was sent',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Your code is $code',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorLine(AzamanColors colors, String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 16, color: colors.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: colors.danger, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _verifiedBody(AzamanColors colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.verified, size: 56, color: colors.success),
        const SizedBox(height: 18),
        Text(
          'Number verified',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _formatForDisplay(_numberController.text),
          style: TextStyle(color: colors.textSecondary, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Text(
          'This confirms the number, not who owns any wallet linked to it.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _finish,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  /// Show the number the way it will be stored, without leaking assumptions.
  String _formatForDisplay(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return raw;
    if (raw.trim().startsWith('+')) return raw.trim();
    final local = digits.startsWith('0') ? digits.substring(1) : digits;
    return '$kDefaultDialCode $local';
  }
}
