// lib/widgets/security/second_factor.dart
// =============================================================================
// The second factor a money action carries: the account password, or the
// current authenticator code when two-factor is on. The backend's require2FA
// reads `password` or `totpToken` from the request body and answers a missing
// factor with 401 `PASSWORD_REQUIRED` / `2FA_REQUIRED`, a wrong one with a
// plain 401.
//
// [withSecondFactor] asks once, sends, and follows the server: a challenge
// for the other factor re-asks with that one (the account changed since the
// profile loaded), a refused factor re-asks with the reason, cancel returns
// null, and every other error is the caller's, unchanged.
//
// The factor lives only for the request. It is never logged (toString hides
// it) and never persisted: the durable operation journal scrubs `password`
// and `totpToken` before it stores or fingerprints a request.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/azaman_sheet.dart';

enum SecondFactorKind { password, authenticator }

@immutable
class SecondFactor {
  const SecondFactor.password(this.value) : kind = SecondFactorKind.password;
  const SecondFactor.authenticator(this.value)
    : kind = SecondFactorKind.authenticator;

  final SecondFactorKind kind;
  final String value;

  /// The request fields require2FA reads.
  Map<String, String> toWire() => kind == SecondFactorKind.password
      ? {'password': value}
      : {'totpToken': value};

  @override
  String toString() => 'SecondFactor(${kind.name}, ••••)';
}

/// The factor to ask for first: the authenticator when the profile says
/// two-factor is on, otherwise the password (the server corrects a stale
/// profile with a challenge).
SecondFactorKind secondFactorKindFor(User? user) =>
    user?.isTwoFactorEnabled == true
    ? SecondFactorKind.authenticator
    : SecondFactorKind.password;

/// The factor the server asked for, when [error] is require2FA's challenge.
SecondFactorKind? secondFactorChallenge(Object error) {
  if (error is ApiException && error.statusCode == 401) {
    if (error.code == '2FA_REQUIRED') return SecondFactorKind.authenticator;
    if (error.code == 'PASSWORD_REQUIRED') return SecondFactorKind.password;
  }
  return null;
}

/// A wrong password or code: require2FA's plain 401 (not a challenge, not an
/// expired session, which the API client refreshes itself).
bool isSecondFactorRefused(Object error) =>
    error is ApiException &&
    error.statusCode == 401 &&
    error.code != 'TOKEN_EXPIRED' &&
    secondFactorChallenge(error) == null;

/// Asks for one factor. Null when dismissed.
Future<SecondFactor?> showSecondFactorSheet(
  BuildContext context, {
  required SecondFactorKind kind,
  required String title,
  required String actionLabel,
  String? detail,
  String? errorText,
}) {
  return AzamanSheet.showWhisper<SecondFactor>(
    context,
    maxHeightFraction: 0.6,
    builder: (ctx) => SecondFactorPrompt(
      kind: kind,
      title: title,
      actionLabel: actionLabel,
      detail: detail,
      errorText: errorText,
      onSubmit: (f) => Navigator.of(ctx).pop(f),
    ),
  );
}

/// Runs [attempt] behind a second factor (see the file header).
Future<T?> withSecondFactor<T>(
  BuildContext context, {
  required SecondFactorKind initial,
  required String title,
  required String actionLabel,
  String? detail,
  required Future<T> Function(SecondFactor factor) attempt,
  Future<SecondFactor?> Function({
    required SecondFactorKind kind,
    String? errorText,
  })?
  ask,
  int maxPrompts = 4,
}) async {
  Future<SecondFactor?> prompt({
    required SecondFactorKind kind,
    String? errorText,
  }) => ask != null
      ? ask(kind: kind, errorText: errorText)
      : showSecondFactorSheet(
          context,
          kind: kind,
          title: title,
          actionLabel: actionLabel,
          detail: detail,
          errorText: errorText,
        );

  var kind = initial;
  String? errorText;
  for (var i = 0; i < maxPrompts; i++) {
    final factor = await prompt(kind: kind, errorText: errorText);
    if (factor == null) return null;
    try {
      return await attempt(factor);
    } catch (e) {
      final asked = secondFactorChallenge(e);
      if (asked != null && asked != kind) {
        kind = asked;
        errorText = asked == SecondFactorKind.authenticator
            ? 'Your account uses an authenticator. Enter its current code.'
            : 'Confirm with your password instead.';
        continue;
      }
      if (asked != null || isSecondFactorRefused(e)) {
        errorText = kind == SecondFactorKind.password
            ? 'That password did not match. Try again.'
            : 'That code did not work. Enter the current one.';
        continue;
      }
      rethrow;
    }
  }
  return null;
}

/// The prompt itself: one field (an obscured password, or six digits from
/// the authenticator with one-time-code autofill) and the action button.
class SecondFactorPrompt extends StatefulWidget {
  const SecondFactorPrompt({
    super.key,
    required this.kind,
    required this.title,
    required this.actionLabel,
    required this.onSubmit,
    this.detail,
    this.errorText,
  });

  final SecondFactorKind kind;
  final String title;
  final String actionLabel;
  final String? detail;
  final String? errorText;
  final ValueChanged<SecondFactor> onSubmit;

  @override
  State<SecondFactorPrompt> createState() => _SecondFactorPromptState();
}

class _SecondFactorPromptState extends State<SecondFactorPrompt> {
  final _field = TextEditingController();
  bool _obscured = true;

  bool get _isCode => widget.kind == SecondFactorKind.authenticator;

  bool get _ready => _isCode ? _field.text.length == 6 : _field.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _field.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_ready) return;
    widget.onSubmit(
      _isCode
          ? SecondFactor.authenticator(_field.text)
          : SecondFactor.password(_field.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 22, 22, 18 + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.detail ??
                (_isCode
                    ? 'Enter the 6-digit code from your authenticator app.'
                    : 'Confirm with your Azaman password.'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('second-factor-field'),
            controller: _field,
            autofocus: true,
            obscureText: !_isCode && _obscured,
            keyboardType: _isCode
                ? TextInputType.number
                : TextInputType.visiblePassword,
            autofillHints: _isCode
                ? const [AutofillHints.oneTimeCode]
                : const [AutofillHints.password],
            inputFormatters: _isCode
                ? [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ]
                : null,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: _isCode
                ? const TextStyle(
                    fontSize: 22,
                    letterSpacing: 8,
                    fontFeatures: [FontFeature.tabularFigures()],
                  )
                : null,
            decoration: InputDecoration(
              hintText: _isCode ? '000000' : 'Password',
              errorText: widget.errorText,
              errorMaxLines: 2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              suffixIcon: _isCode
                  ? null
                  : IconButton(
                      tooltip: _obscured ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscured = !_obscured),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              key: const ValueKey('second-factor-submit'),
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              onPressed: _ready ? _submit : null,
              child: Text(
                widget.actionLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
