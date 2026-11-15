import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:azaman/services/step_up_service.dart';

/// §WP-H G — asks for the proof that earns a capability for ONE action.
///
/// The sheet states the action in words ("GHS 125.50 to 0244123456") because the
/// grant is bound to exactly that: a code produced here cannot authorise a
/// different amount, recipient or route. Nothing is sent from this widget; it
/// returns the proof and [ApiClient] performs the exchange and the single replay.
///
/// Returns null when the user cancels, which leaves the original refusal intact.
Future<StepUpProof?> showStepUpSheet(
  BuildContext context,
  StepUpChallenge challenge,
) {
  return showModalBottomSheet<StepUpProof>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StepUpSheet(challenge: challenge),
  );
}

class _StepUpSheet extends StatefulWidget {
  const _StepUpSheet({required this.challenge});

  final StepUpChallenge challenge;

  @override
  State<_StepUpSheet> createState() => _StepUpSheetState();
}

class _StepUpSheetState extends State<_StepUpSheet> {
  final TextEditingController _input = TextEditingController();
  bool _usePassword = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _input.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Enter your code to continue.');
      return;
    }
    if (!_usePassword && value.length != 6) {
      setState(() => _error = 'The 6-digit code is incomplete.');
      return;
    }
    Navigator.of(context).pop(
      _usePassword ? StepUpProof.password(value) : StepUpProof.totp(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Confirm this action',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              widget.challenge.summary,
              key: const ValueKey('step-up-summary'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'This verification is bound to this exact action and works once.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('step-up-input'),
              controller: _input,
              autofocus: true,
              obscureText: _usePassword,
              keyboardType:
                  _usePassword ? TextInputType.text : TextInputType.number,
              inputFormatters: _usePassword
                  ? null
                  : <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
              decoration: InputDecoration(
                hintText: _usePassword ? 'Password' : '6-digit code',
                errorText: _error,
                filled: true,
                fillColor: colors.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 6),
            TextButton(
              key: const ValueKey('step-up-toggle-method'),
              onPressed: () => setState(() {
                _usePassword = !_usePassword;
                _error = null;
                _input.clear();
              }),
              child: Text(
                _usePassword ? 'Use a 6-digit code' : 'Use my password',
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    key: const ValueKey('step-up-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('step-up-confirm'),
                    onPressed: _submit,
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
