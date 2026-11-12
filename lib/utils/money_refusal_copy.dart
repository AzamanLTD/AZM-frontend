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

    case 'IDEMPOTENCY_PAYLOAD_CONFLICT':
      return 'An earlier payment with this reference already completed, so '
          'this one was not started. Check Activity for the completed payment.';
    case 'IDEMPOTENCY_KEY_REQUIRED':
      return 'This payment could not be started because the app did not send '
          'its reference. Nothing was sent.';
    case 'INSUFFICIENT_FUNDS':
      return 'Your GHS balance is too low for this amount, so nothing was '
          'moved. Top up or reduce the amount.';
    case 'INSUFFICIENT_BALANCE':
      return 'Your balance is too low for this amount, so nothing was moved. '
          'Top up or reduce the amount.';
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

// -----------------------------------------------------------------------------
// WP-L — refusal certainty authority.
//
// Screens need more than a sentence: they need to know whether the money is
// definitely still with the customer, possibly already moved, or undecided.
// Getting that classification wrong is how an app talks someone into paying
// twice, so it lives here with the copy and nowhere else.
// -----------------------------------------------------------------------------

/// What the customer may safely believe about their money.
enum RefusalCertainty {
  /// Refused before the economic step. Nothing moved; correcting and retrying
  /// is safe (with a fresh code where one was consumed).
  refusedBeforeMoney,

  /// An EARLIER operation under the same identity already COMMITTED. The new,
  /// mismatched request was refused, but money HAS moved for the original.
  priorOperationCommitted,

  /// Still processing. The original operation must be allowed to resolve;
  /// starting a second one risks a double charge.
  stillProcessing,

  /// The authority could not answer. Outcome genuinely unknown: never
  /// presented as a failure and never safe to blindly repeat.
  unknownOutcome,
}

/// A refusal rendered as customer copy plus a truthful next step.
class RefusalCopy {
  const RefusalCopy(this.message, this.nextStep, this.certainty);

  final String message;
  final String nextStep;
  final RefusalCertainty certainty;
}

/// Full refusal authority for a backend [code], or null when the code is not
/// one this client can speak about truthfully.
RefusalCopy? refusalCopyFor(String? code) {
  final message = moneyRefusalMessage(code);
  if (message == null) return null;
  // WP-L — every classification below is proven by backend source, cited on
  // the branch of the switch that uses it. There is deliberately NO broad
  // default: an unlisted code returns null so no screen can attach a
  // reassuring "nothing was sent" to an outcome nobody has proven.
  switch (code) {
    // ── A PRIOR operation with this identity already COMMITTED ─────────────
    // middleware/idempotency.js:284-290 — returned only when
    // existing.status === COMMITTED and the fingerprint differs. Money has
    // already moved for the earlier operation.
    case 'IDEMPOTENCY_PAYLOAD_CONFLICT':
      return const RefusalCopy(
        'An earlier payment with this reference already completed. These '
            'details differ from it, so this new payment was not started.',
        'Open Activity to find the completed payment before you send anything '
            'else. If you cannot find it, contact support with the time of the '
            'earlier attempt. Do not start a new payment until that one is '
            'identified.',
        RefusalCertainty.priorOperationCommitted,
      );

    // ── Still processing ──────────────────────────────────────────────────
    // middleware/idempotency.js:311 — a claim exists and is IN_PROGRESS.
    case 'IDEMPOTENCY_IN_PROGRESS':
      return RefusalCopy(
        message,
        'Open Activity to follow the original payment. Checking is safe; '
            'sending it again is not.',
        RefusalCertainty.stillProcessing,
      );

    // ── Refused BEFORE idempotency and before the economic handler ─────────
    // require2FA() is mounted ahead of idempotency() and the controller on all
    // 19 require2FA mounts audited at backend e35bad2 (friendRoutes:78,
    // savingsRoutes:33, vaultRoutes:28, walletRoutes:133/228,
    // withdrawalRoutes:40/61/71/92, financeRoutes:55, tradeRoutes:50,
    // p2pRoutes:32, escrowRoutes:24, marketplaceRoutes:48,
    // bankBeneficiaryRoutes:24/32/37/39, dineInRoutes:32). A step-up refusal
    // therefore cannot have created a claim or reached economic code — not even
    // a claim-store outage, which is refused inside this same middleware.
    case '2FA_REQUIRED':
    case 'PASSWORD_REQUIRED':
    case 'TOTP_INVALID':
    case 'TOTP_REPLAYED':
    case 'TOTP_LOCKED':
    case 'TOTP_CLAIM_STORE_UNAVAILABLE':
      return RefusalCopy(
        message,
        'Nothing was sent. Confirm with a fresh authenticator code to '
            'continue.',
        RefusalCertainty.refusedBeforeMoney,
      );

    // middleware/idempotency.js:211 — rejected before any claim is created.
    case 'IDEMPOTENCY_KEY_REQUIRED':
      return RefusalCopy(
        message,
        'Nothing was sent. This is an app problem rather than a payment '
            'problem — retrying the same action is safe.',
        RefusalCertainty.refusedBeforeMoney,
      );

    // src/services/nativeGhsWithdrawalService.js:262-266 — thrown BEFORE
    // prisma.$transaction and before any quote is consumed.
    case 'NATIVE_GHS_SHORTFALL_BACKING_UNAVAILABLE':
      return RefusalCopy(
        message,
        'Nothing was converted and nothing was sent. Withdraw from your '
            'existing GHS balance, or try a smaller amount.',
        RefusalCertainty.refusedBeforeMoney,
      );

    // nativeGhsWithdrawalService.js:334 and the quote guards around it. A
    // stale quote refusal either precedes the transaction or throws inside it,
    // which rolls back — either way no economic effect survives.
    case 'NATIVE_GHS_QUOTE_INTENT_CHANGED':
    case 'NATIVE_GHS_QUOTE_INTENT_MISMATCH':
    case 'NATIVE_GHS_QUOTE_INVALID':
      return RefusalCopy(
        message,
        'Nothing was sent. Request a fresh quote and confirm the new amount '
            'before continuing.',
        RefusalCertainty.refusedBeforeMoney,
      );

    // The codes the backend actually returns when a balance claim loses:
    // controllers/savingsController.js:389 (INSUFFICIENT_FUNDS, atomic
    // conditional decrement inside prisma.$transaction) and
    // services/vaultService.js:623 (INSUFFICIENT_BALANCE). Both throw inside
    // the transaction, so the decrement rolls back.
    case 'INSUFFICIENT_FUNDS':
    case 'INSUFFICIENT_BALANCE':
      return RefusalCopy(
        message,
        'Nothing was sent. Top up or reduce the amount, then try again.',
        RefusalCertainty.refusedBeforeMoney,
      );
  }
  // Unmapped, including every unrecognised 5xx and provider timeout: no
  // classification, so no screen may call it safe or call it failed.
  return null;
}

/// Resolve a thrown error (ApiException or text) into a [RefusalCopy].
RefusalCopy? refusalCopyFrom(Object error) {
  String? code;
  try {
    final dynamic e = error;
    // ignore: avoid_dynamic_calls
    final dynamic c = e.code;
    if (c is String && c.isNotEmpty) code = c;
  } catch (_) {}
  code ??= _codeFromText(error.toString());
  return refusalCopyFor(code);
}

/// WP-H is not implemented. This is the GENERIC, truthful "we cannot tell you
/// right now" state a screen may show when an authority cannot answer — it is
/// deliberately NOT keyed to a backend code, because no such code is live yet.
/// Never present it as a failure and never invite an immediate retry.
RefusalCopy preparedAuthorityUnavailableCopy() => const RefusalCopy(
      'We cannot confirm this action right now. Nothing has been confirmed '
      'either way.',
      'Check Activity before trying again. If nothing appears, contact '
          'support with your reference.',
      RefusalCertainty.unknownOutcome,
    );
