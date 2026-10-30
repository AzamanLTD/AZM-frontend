// AZAMAN — THE UNLOCK CHALLENGE SHEET
//
// What the member sees after tapping the lock. It offers ONLY challenges the
// backend says this account has, and it never claims success the server did not
// give: a refusal is shown with the server's own reason, including how many
// attempts remain. Nothing is stored here except the method choice, which is
// device-specific and account-scoped.
//
// Design credit and pin entry follow the same restrained sheet language as the
// rest of Home: one surface, one primary action, no decorative colour.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/app_unlock_gateway.dart';
import 'package:azaman/services/money_unlock.dart';
import 'package:azaman/services/money_unlock_flow.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// Opens the challenge sheet. Returns [MoneyUnlockOutcome.unlocked] ONLY when
/// the backend accepted the proof.
Future<MoneyUnlockResult> showMoneyUnlockSheet(
  BuildContext context, {
  required AppUnlockGateway gateway,
  required AppUnlockCapabilities capabilities,
  AppUnlockMethod? initialMethod,
  Object? userId,
}) async {
  final result = await showModalBottomSheet<MoneyUnlockResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MoneyUnlockSheet(
      gateway: gateway,
      capabilities: capabilities,
      initialMethod: initialMethod,
      userId: userId,
    ),
  );
  return result ?? const MoneyUnlockResult(MoneyUnlockOutcome.cancelled);
}

class _MoneyUnlockSheet extends ConsumerStatefulWidget {
  const _MoneyUnlockSheet({
    required this.gateway,
    required this.capabilities,
    required this.userId,
    this.initialMethod,
  });

  final AppUnlockGateway gateway;
  final AppUnlockCapabilities capabilities;
  final Object? userId;
  final AppUnlockMethod? initialMethod;

  @override
  ConsumerState<_MoneyUnlockSheet> createState() => _MoneyUnlockSheetState();
}

class _MoneyUnlockSheetState extends ConsumerState<_MoneyUnlockSheet> {
  late AppUnlockMethod? _method =
      widget.initialMethod ??
      (widget.capabilities.configured.isEmpty
          ? null
          : widget.capabilities.configured.first);
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;
  AppUnlockSmsChallenge? _challenge;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool get _isDemo => widget.gateway is DemoAppUnlockGateway;

  String _labelFor(AppUnlockMethod method) => switch (method) {
    AppUnlockMethod.deviceAuth => 'Device unlock',
    AppUnlockMethod.pin => 'Azaman PIN',
    AppUnlockMethod.totp => 'Authenticator code',
    AppUnlockMethod.sms => 'Text message code',
  };

  String _hintFor(AppUnlockMethod method) => switch (method) {
    AppUnlockMethod.deviceAuth => 'Your phone’s own screen lock',
    AppUnlockMethod.pin => '4 to 8 digits',
    AppUnlockMethod.totp => '6 digits from your authenticator',
    AppUnlockMethod.sms => '6 digits sent to your phone',
  };

  /// The server's own refusal codes, in words the member can act on.
  String _messageFor(AppUnlockRefusal refusal) {
    final left = refusal.attemptsLeft;
    final tail = left == null
        ? ''
        : ' $left ${left == 1 ? 'try' : 'tries'} left.';
    return switch (refusal.code) {
      'PIN_REQUIRED' || 'PIN_FORMAT_INVALID' => 'Enter your 4 to 8 digit PIN.',
      'PIN_NOT_CONFIGURED' => 'No Azaman PIN is set for this account.',
      'PIN_INVALID' => 'That PIN is not right.$tail',
      'PIN_LOCKED' => 'Too many wrong PINs. PIN unlock is locked for now.',
      'TOTP_REQUIRED' => 'Enter the 6 digit code.',
      'TOTP_NOT_CONFIGURED' =>
        'Two-factor is not set up yet, so there is no code to enter.',
      'TOTP_INVALID' => 'That code is not right.$tail',
      'TOTP_REPLAYED' => 'That code was already used. Wait for the next one.',
      'TOTP_LOCKED' =>
        'Too many wrong codes. Authenticator unlock is locked for now.',
      'PHONE_UNVERIFIED' => 'Verify your phone number first.',
      'SMS_SERVICE_UNAVAILABLE' ||
      'SMS_PROVIDER_UNSUPPORTED' ||
      'SMS_PROVIDER_MISCONFIGURED' =>
        'Text message unlock is not available right now.',
      'CHALLENGE_THROTTLED' => 'Please wait a moment before asking for a code.',
      'CHALLENGE_EXPIRED' => 'That code expired. Ask for a new one.',
      'CHALLENGE_LOCKED' => 'Too many wrong codes. Ask for a new one later.',
      'CODE_INVALID' => 'That code is not right.$tail',
      'CHALLENGE_REQUIRED' || 'CODE_REQUIRED' => 'Ask for a code first.',
      'CHALLENGE_INVALID' => 'That challenge is no longer valid.',
      'CAPABILITIES_UNAVAILABLE' ||
      'UNLOCK_UNAVAILABLE' ||
      'UNLOCK_CHALLENGE_FAILED' =>
        'Unlock is unavailable right now. Try again shortly.',
      _ => 'That did not work. Try again.',
    };
  }

  Future<void> _submit() async {
    final method = _method;
    if (method == null || _busy) return;
    final value = _input.text.trim();
    if (method != AppUnlockMethod.sms && value.isEmpty) {
      setState(() => _error = 'Enter your ${_hintFor(method).toLowerCase()}.');
      return;
    }
    if (method == AppUnlockMethod.sms && _challenge == null) {
      await _sendCode();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (method) {
        case AppUnlockMethod.pin:
          await widget.gateway.verifyPin(value);
        case AppUnlockMethod.totp:
          await widget.gateway.verifyTotp(value);
        case AppUnlockMethod.sms:
          await widget.gateway.verifySmsChallenge(
            challengeId: _challenge!.challengeId,
            code: value,
          );
        case AppUnlockMethod.deviceAuth:
          break;
      }
      if (!mounted) return;
      // Remembering the choice is a convenience, and it can never stand
      // between the member and an unlock the server already granted (the
      // notifier swallows storage failures itself).
      await ref
          .read(moneyUnlockPreferenceProvider.notifier)
          .remember(widget.userId, method);
      if (!mounted) return;
      AzamanHaptics.confirm();
      // Unlocked is only ever reported from here — after the server said yes.
      Navigator.of(
        context,
      ).pop(const MoneyUnlockResult(MoneyUnlockOutcome.unlocked));
    } on AppUnlockRefusal catch (refusal) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(refusal);
      });
      AzamanHaptics.selection();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'That did not work. Try again.';
      });
    }
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challenge = await widget.gateway.sendSmsChallenge();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _challenge = challenge;
      });
    } on AppUnlockRefusal catch (refusal) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(refusal);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'We could not send a code. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final methods = widget.capabilities.configured;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        key: const ValueKey('money-unlock-sheet'),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Unlock your money',
              style: AzText.title.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              _isDemo
                  ? 'Demo build: the demo PIN is 1234.'
                  : 'Your cards stay where they are. Only the figures open.',
              style: AzText.caption.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: 16),
            if (methods.isEmpty)
              Text(
                _emptyStateMessage(),
                key: const ValueKey('money-unlock-empty-state'),
                style: AzText.body.copyWith(color: colors.textSecondary),
              )
            else ...[
              if (methods.length > 1) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final method in methods)
                      _MethodChip(
                        label: _labelFor(method),
                        selected: method == _method,
                        onTap: () => setState(() {
                          _method = method;
                          _input.clear();
                          _challenge = null;
                          _error = null;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (_method == AppUnlockMethod.sms && _challenge != null)
                Text(
                  'Code sent to ${_challenge!.maskedPhone}',
                  key: const ValueKey('money-unlock-sms-sent'),
                  style: AzText.caption.copyWith(color: colors.textSecondary),
                ),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey('money-unlock-input'),
                controller: _input,
                autofocus: true,
                obscureText: _method != AppUnlockMethod.totp,
                obscuringCharacter: '•',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                style: AzText.money(colors.textPrimary, size: 20),
                decoration: InputDecoration(
                  hintText: _hintFor(_method ?? AppUnlockMethod.pin),
                  hintStyle: AzText.bodyS.copyWith(color: colors.textTertiary),
                  filled: true,
                  fillColor: colors.softSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const ValueKey('money-unlock-error'),
                  style: AzText.caption.copyWith(color: colors.danger),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('money-unlock-submit'),
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    _busy
                        ? 'Checking…'
                        : (_method == AppUnlockMethod.sms && _challenge == null
                              ? 'Send code'
                              : 'Unlock'),
                    style: AzText.label.copyWith(color: colors.onAccent),
                  ),
                ),
              ),
              if (_method == AppUnlockMethod.sms && _challenge != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  key: const ValueKey('money-unlock-resend'),
                  onPressed: _busy ? null : _sendCode,
                  child: Text(
                    'Send a new code',
                    style: AzText.caption.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('money-unlock-cancel'),
              onPressed: () => Navigator.of(
                context,
              ).pop(const MoneyUnlockResult(MoneyUnlockOutcome.cancelled)),
              child: Text(
                'Not now',
                style: AzText.caption.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _emptyStateMessage() {
    if (widget.capabilities.smsUnavailableReason == 'PHONE_UNVERIFIED') {
      return 'This device has no screen lock, and your account has no unlock '
          'method yet. Add a PIN in Security settings, then unlock.';
    }
    return 'No unlock method is set up for this account yet. Add an Azaman PIN '
        'in Security settings, then try again.';
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ProviderScope.containerOf(
      context,
    ).read(themeProvider).colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.softSurface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? colors.accent : colors.border),
        ),
        child: Text(
          label,
          style: AzText.caption.copyWith(
            color: selected ? colors.onAccent : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
