// =============================================================================
// AZAMAN — MONEY REFUSAL AUTHORITY (WP-L)
//
// ONE authority. Every customer-facing money refusal resolves here, and every
// helper below is a thin delegate so nothing can disagree with anything else.
//
// Three rules, each enforced by a test:
//   1. Never imply a GHS conversion exists when its backing is unavailable.
//   2. Never imply permanent failure when the backend outcome is undecided.
//   3. Never imply payment happened when the backend refused it.
//
// Certainty is not a guess: each code is classified from the backend behaviour
// that proves it, cited inline. Backend candidate 6a6f233 verified for route
// ordering; e35bad2 verified identically for the same mounts.
// =============================================================================

/// What the customer may safely believe about their money.
enum RefusalCertainty {
  /// Refused before the economic handler ran. Provable because the refusing
  /// middleware is mounted ahead of both the idempotency claim and the
  /// controller — or because the failure throws inside a transaction that
  /// rolls back.
  refusedBeforeMoney,

  /// An EARLIER operation under the same identity already COMMITTED. The new,
  /// mismatched request was refused, but money HAS moved for the original.
  priorOperationCommitted,

  /// A claim exists and the original operation is still resolving.
  stillProcessing,

  /// Undecided. Never presented as a failure, never safe to blindly repeat.
  unknownOutcome,
}

/// A refusal rendered as customer copy plus a truthful next step.
class RefusalCopy {
  const RefusalCopy(this.message, this.nextStep, this.certainty);

  final String message;
  final String nextStep;
  final RefusalCertainty certainty;

  /// A fresh submission is only safe when this request provably sent nothing.
  /// Every other certainty demands the customer resolve the existing
  /// operation first.
  bool get retryIsSafe => certainty == RefusalCertainty.refusedBeforeMoney;

  /// The single block of text a screen shows.
  String get display => '$message $nextStep';
}

// -----------------------------------------------------------------------------
// THE canonical mapping.
// -----------------------------------------------------------------------------

/// Resolve a backend refusal [code] into copy, certainty and next step.
///
/// Returns null for anything not proven here — including every unrecognised
/// 5xx and provider timeout. A null result means "this client cannot say
/// anything true about the money", so callers keep their own honest,
/// non-committal fallback.
RefusalCopy? refusalCopyFor(String? code) {
  switch (code) {
    // ── A PRIOR operation with this identity already COMMITTED ─────────────
    // middleware/idempotency.js — returned only when existing.status ===
    // COMMITTED and the request fingerprint differs (verified on 6a6f233).
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
    // A claim exists and is IN_PROGRESS.
    case 'IDEMPOTENCY_IN_PROGRESS':
      return const RefusalCopy(
        'A payment with these exact details is still being processed. Nothing '
            'new was started.',
        'Open Activity to follow the original payment. Checking is safe; '
            'sending it again is not.',
        RefusalCertainty.stillProcessing,
      );

    // ── Refused BEFORE idempotency and before the economic handler ─────────
    // require2FA() is mounted ahead of idempotency() and the controller on
    // every audited mount (savingsRoutes, vaultRoutes, friendRoutes,
    // walletRoutes, withdrawalRoutes, marketplaceRoutes, p2pRoutes,
    // escrowRoutes, tradeRoutes, financeRoutes, dineInRoutes, checked on
    // 6a6f233). A claim-store outage is refused inside that same middleware
    // (require2FA.js, TOTP_CODES.UNAVAILABLE -> sendTotpUnavailable), so the
    // request cannot have reached the economic code — this is a definite
    // pre-economic refusal, NOT an unknown outcome.
    case '2FA_REQUIRED':
      return const RefusalCopy(
        'Confirm this payment with your authenticator code. Nothing has been '
            'sent yet.',
        'Nothing was sent. Confirm with a fresh authenticator code to '
            'continue.',
        RefusalCertainty.refusedBeforeMoney,
      );
    case 'PASSWORD_REQUIRED':
      return const RefusalCopy(
        'Confirm this payment with your account password. Nothing has been '
            'sent yet.',
        'Nothing was sent. Confirm with your password to continue.',
        RefusalCertainty.refusedBeforeMoney,
      );
    case 'TOTP_INVALID':
      return const RefusalCopy(
        'That authenticator code is not valid. Nothing was sent.',
        'Nothing was sent. Confirm with a fresh authenticator code to '
            'continue.',
        RefusalCertainty.refusedBeforeMoney,
      );
    case 'TOTP_REPLAYED':
      return const RefusalCopy(
        'That authenticator code was already used for another action. Nothing '
            'was sent.',
        'Nothing was sent. Confirm with a fresh authenticator code to '
            'continue.',
        RefusalCertainty.refusedBeforeMoney,
      );
    case 'TOTP_LOCKED':
      return const RefusalCopy(
        'Too many incorrect codes, so two-factor confirmation is locked for '
            'now. Nothing was sent.',
        'Nothing was sent. Wait for the lock to clear, then confirm with a '
            'fresh authenticator code.',
        RefusalCertainty.refusedBeforeMoney,
      );
    case 'TOTP_CLAIM_STORE_UNAVAILABLE':
      return const RefusalCopy(
        'We could not check your authenticator code just now, so this request '
            'was not carried out. Nothing was sent.',
        'Nothing was sent. Try once more in a moment with a fresh '
            'authenticator code.',
        RefusalCertainty.refusedBeforeMoney,
      );

    // Rejected before any claim is created.
    case 'IDEMPOTENCY_KEY_REQUIRED':
      return const RefusalCopy(
        'This payment could not be started because the app did not send its '
            'reference. Nothing was sent.',
        'Nothing was sent. This is an app problem rather than a payment '
            'problem — retrying the same action is safe.',
        RefusalCertainty.refusedBeforeMoney,
      );

    // ── Thrown BEFORE the transaction, or inside one that rolls back ───────
    // nativeGhsWithdrawalService: checked before prisma.$transaction and
    // before any quote is consumed.
    case 'NATIVE_GHS_SHORTFALL_BACKING_UNAVAILABLE':
      return const RefusalCopy(
        'This payout needs cedis that Azaman cannot fund yet, so no conversion '
            'was made and nothing was sent. Your balance is unchanged.',
        'Nothing was converted and nothing was sent. Withdraw from your '
            'existing GHS balance, or try a smaller amount.',
        RefusalCertainty.refusedBeforeMoney,
      );

    case 'NATIVE_GHS_QUOTE_INTENT_CHANGED':
      return const RefusalCopy(
        'The exchange rate moved before this could complete, so the quoted '
            'amount no longer applies. Nothing was sent.',
        'Nothing was sent. Request a fresh quote and confirm the new amount '
            'before continuing.',
        RefusalCertainty.refusedBeforeMoney,
      );
    case 'NATIVE_GHS_QUOTE_INTENT_MISMATCH':
    case 'NATIVE_GHS_QUOTE_INVALID':
      return const RefusalCopy(
        'That quote is no longer valid for this amount. Nothing was sent.',
        'Nothing was sent. Request a fresh quote and confirm the new amount '
            'before continuing.',
        RefusalCertainty.refusedBeforeMoney,
      );

    // Atomic balance claims that lose their conditional decrement throw inside
    // the transaction, so the whole transaction rolls back:
    //   INSUFFICIENT_FUNDS        — savingsController atomic GHS claim
    //   INSUFFICIENT_BALANCE      — vaultService break claim
    //   USDC_INSUFFICIENT_BALANCE — nativeGhsWithdrawalService USDC CAS debit
    //                               (both verified present on 6a6f233)
    case 'INSUFFICIENT_FUNDS':
      return const RefusalCopy(
        'Your GHS balance is too low for this amount, so nothing was moved.',
        'Nothing was sent. Top up or reduce the amount, then try again.',
        RefusalCertainty.refusedBeforeMoney,
      );
    case 'INSUFFICIENT_BALANCE':
      return const RefusalCopy(
        'Your balance is too low for this amount, so nothing was moved.',
        'Nothing was sent. Top up or reduce the amount, then try again.',
        RefusalCertainty.refusedBeforeMoney,
      );
    case 'USDC_INSUFFICIENT_BALANCE':
      return const RefusalCopy(
        'You do not have enough USDC for this amount, so nothing was converted '
            'or sent.',
        'Nothing was sent. Top up USDC or reduce the amount, then try again.',
        RefusalCertainty.refusedBeforeMoney,
      );
  }
  // Unproven: no message, no certainty, no permission.
  return null;
}

// -----------------------------------------------------------------------------
// Delegates. These exist so older call sites keep working; they carry no
// opinion of their own.
// -----------------------------------------------------------------------------

/// The customer sentence for [code], or null when the code is not proven.
String? moneyRefusalMessage(String? code) => refusalCopyFor(code)?.message;

/// True only for outcomes the client genuinely cannot decide: an indexed claim
/// still in flight, or an explicitly unknown outcome. A claim-store outage is
/// NOT ambiguous — it is refused before the economic handler ever runs.
bool isAmbiguousMoneyRefusal(String? code) {
  final copy = refusalCopyFor(code);
  if (copy == null) return false;
  return copy.certainty == RefusalCertainty.stillProcessing ||
      copy.certainty == RefusalCertainty.unknownOutcome;
}

/// True only when the backend has proven this request sent nothing.
bool isDefiniteMoneyRefusal(String? code) =>
    refusalCopyFor(code)?.certainty == RefusalCertainty.refusedBeforeMoney;

/// Resolve a thrown error into its [RefusalCopy].
RefusalCopy? refusalCopyFrom(Object error) => refusalCopyFor(_codeOf(error));

/// The customer sentence for a thrown error, or null when unproven.
String? moneyErrorText(Object error) => refusalCopyFrom(error)?.message;

/// The backend code carried by [error], if it carries one at all.
String? _codeOf(Object error) {
  try {
    final dynamic e = error;
    // ignore: avoid_dynamic_calls
    final dynamic c = e.code;
    if (c is String && c.isNotEmpty) return c;
  } catch (_) {}
  return _codeFromText(error.toString());
}

String? _codeFromText(String text) {
  final m = RegExp(r'"code"\s*:\s*"([A-Z0-9_]+)"').firstMatch(text);
  return m?.group(1);
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
