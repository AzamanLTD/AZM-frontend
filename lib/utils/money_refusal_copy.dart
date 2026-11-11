// =============================================================================
// AZAMAN — MONEY REFUSAL COPY (WP-L)
//
// Exact, non-misleading customer copy for money refusals that previously fell
// through to a generic "Something went wrong".
//
// Three rules, each enforced by a test:
//   1. Never imply a GHS conversion exists when its backing is unavailable.
//   2. Never imply permanent failure when the backend outcome is ambiguous.
//   3. Never imply payment happened when the backend refused it.
// =============================================================================

/// The customer-facing sentence for a money refusal [code], or null when the
/// code is not one of the explicitly handled refusals (callers then keep
/// their existing generic copy).
String? moneyRefusalMessage(String? code) {
  switch (code) {
    case 'NATIVE_GHS_SHORTFALL_BACKING_UNAVAILABLE':
      return 'This payout needs cedis that Azaman cannot fund yet, so no '
          'conversion was made and nothing was sent. Your balance is '
          'unchanged — try a smaller amount or another destination.';

    case 'TOTP_REPLAYED':
      return 'That authenticator code was already used for another action. '
          'Wait for the next code and try again. Nothing was sent.';

    case 'TOTP_CLAIM_STORE_UNAVAILABLE':
      return 'We could not confirm your code, so this action is not finished. '
          'Check your history before trying again — it may already have gone '
          'through.';

    case 'IDEMPOTENCY_IN_PROGRESS':
      return 'A previous attempt of this exact payment is still resolving. '
          'Nothing new was started. Check your history before trying again — '
          'a second payment could charge you twice.';
    case 'TOTP_INVALID':
      return 'That authenticator code is not valid. Enter the current code '
          'from your authenticator app.';
    case 'TOTP_LOCKED':
      return 'Too many incorrect codes. Two-factor confirmation is locked '
          'for now. Nothing was sent.';
    case 'PASSWORD_REQUIRED':
      return 'Confirm this payment with your account password. '
          'Nothing has been sent yet.';
    case '2FA_REQUIRED':
      return 'Confirm this payment with your authenticator code. '
          'Nothing has been sent yet.';
    case 'USDC_INSUFFICIENT_BALANCE':
      return 'Your USDC balance is too low for this payout. Nothing was sent.';

    case 'NATIVE_GHS_QUOTE_INTENT_CHANGED':
    case 'NATIVE_GHS_QUOTE_INTENT_MISMATCH':
      return 'The rate changed while you were confirming. Nothing was sent — '
          'review the new quote before continuing.';

    case 'NATIVE_GHS_QUOTE_INVALID':
      return 'That quote is no longer valid. Request a fresh quote. Nothing '
          'was sent.';

    default:
      return null;
  }
}

/// True when [code] describes an outcome the client cannot know, as opposed to
/// a definite refusal. Ambiguous outcomes must never be presented as failures
/// or as successes.
bool isAmbiguousMoneyRefusal(String? code) =>
    code == 'TOTP_CLAIM_STORE_UNAVAILABLE';

/// True when [code] is a definite, pre-economic refusal: nothing was sent and
/// no money moved.
bool isDefiniteMoneyRefusal(String? code) =>
    code == 'NATIVE_GHS_SHORTFALL_BACKING_UNAVAILABLE' ||
    code == 'USDC_INSUFFICIENT_BALANCE' ||
    code == 'NATIVE_GHS_QUOTE_INVALID' ||
    code == 'NATIVE_GHS_QUOTE_INTENT_CHANGED' ||
    code == 'NATIVE_GHS_QUOTE_INTENT_MISMATCH';


/// WP-L — resolve a refusal code from any thrown value and return the exact
/// customer copy, or null when the value carries no known code.
///
/// Reads `ApiException.code` when available and falls back to a `"code":"X"`
/// scan of the message body, which is how the backend's envelope reaches
/// screens that only ever see `e.toString()`.
String? moneyErrorText(Object error) {
  String? code;
  try {
    final dynamic e = error;
    // ignore: avoid_dynamic_calls
    final dynamic c = e.code;
    if (c is String && c.isNotEmpty) code = c;
  } catch (_) {}
  code ??= _codeFromText(error.toString());
  if (code == null) return null;
  return moneyRefusalMessage(code);
}

String? _codeFromText(String text) {
  final m = RegExp(r'"code"\s*:\s*"([A-Z0-9_]+)"').firstMatch(text);
  return m?.group(1);
}
