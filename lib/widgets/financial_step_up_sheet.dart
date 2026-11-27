// =============================================================================
// AZAMAN — FINANCIAL STEP-UP SHEET (WP-J UI)
//
// The one place a customer types a step-up factor. Screens never build their
// own OTP field: [installFinancialStepUp] registers a single prompt that
// [ApiClient] calls when the backend answers 401 + 2FA_REQUIRED /
// PASSWORD_REQUIRED.
//
// The entered value leaves this widget exactly once, inside a
// [StepUpCredential], and is cleared from the controller on submit, on
// cancel and on dispose. It is never written to preferences, a queue, a log
// or a durable-operation snapshot.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/financial_step_up.dart';

/// Registers the global prompt. Call once, after the first frame, with a
/// [navigatorKey] that is attached to the app's MaterialApp.
void installFinancialStepUp(GlobalKey<NavigatorState> navigatorKey) {
  FinancialStepUp.install((challenge) async {
    final context = navigatorKey.currentContext;
    if (context == null) return null;
    return showFinancialStepUpSheet(context, challenge);
  });
}

/// Shows the step-up sheet and resolves with the credential, or null if the
/// customer dismissed it (no request is sent in that case).
Future<StepUpCredential?> showFinancialStepUpSheet(
  BuildContext context,
  StepUpChallenge challenge,
) {
  return showModalBottomSheet<StepUpCredential>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _FinancialStepUpSheet(challenge: challenge),
  );
}

class _FinancialStepUpSheet extends StatefulWidget {
  const _FinancialStepUpSheet({required this.challenge});

  final StepUpChallenge challenge;

  @override
  State<_FinancialStepUpSheet> createState() => _FinancialStepUpSheetState();
}

class _FinancialStepUpSheetState extends State<_FinancialStepUpSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _submitting = false;
  String? _error;

  bool get _isTotp => widget.challenge.factor == StepUpFactor.totp;
  int get _expectedLength => _isTotp ? 6 : 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitting) return; // duplicate taps must not spend a TOTP step
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = _isTotp
          ? 'Enter the 6-digit code from your authenticator.'
          : 'Enter your password.');
      return;
    }
    if (_isTotp && value.length != _expectedLength) {
      setState(() => _error = 'The authenticator code is 6 digits.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final credential = StepUpCredential(widget.challenge.factor, value);
    _controller.clear(); // never keep the secret in the field
    Navigator.of(context).pop(credential);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final attempts = widget.challenge.attemptsLeft;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_isTotp ? Icons.shield_outlined : Icons.lock_outline,
                    size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.challenge.factor.promptTitle,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (!_submitting)
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.challenge.message.isEmpty
                  ? 'Confirm this action to continue.'
                  : widget.challenge.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: !_submitting,
              obscureText: !_isTotp,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: _isTotp ? TextInputType.number : TextInputType.text,
              inputFormatters: _isTotp
                  ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)]
                  : null,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: _isTotp ? 'Authenticator code' : 'Password',
                hintText: _isTotp ? '123456' : null,
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            if (attempts != null) ...[
              const SizedBox(height: 8),
              Text(
                attempts <= 1
                    ? 'Only $attempts attempt left.'
                    : '$attempts attempts left.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Confirm'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Nothing is charged until Azaman confirms this step.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
