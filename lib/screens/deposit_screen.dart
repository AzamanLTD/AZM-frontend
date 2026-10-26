// =============================================================================
// AZAMAN — ADD CASH  (deposit redesign, 2026-10)
//
// The deposit surface redesigned as ONE composed product sheet:
//
//   [X] Add Cash            ← the single authoritative close affordance
//   GH₵ 0                   ← odometer amount, huge, the visual anchor
//   [50][100][200][500]     ← quick amounts
//   1 2 3 / 4 5 6 / 7 8 9 / . 0 ⌫   ← custom keypad
//   [network] Name / 024 … / ˅      ← ONE payment-method row → selector sheet
//   [ Add Cash ]            ← CTA, bottom safe area
// Crypto receiving lives on the separate full-page Receive destination.
//
// The canonical `/deposit` route (NEW-A) is unchanged: the rise transition at
// route level is what makes this surface arrive from the bottom, and a
// deliberate downward pull dismisses it (see _DepositScreenState).
//
// ── FINANCIAL CONTRACT (do not weaken) ────────────────────────────────────────
// The visual layer changed completely in the 2026-10 redesign; the financial
// layer did NOT:
//   • /deposit/validate-name confirmation before mutation
//   • /deposit/fiat/initiate/moolre via postFinancial with a durable
//     FinancialOperationRef (one key per logical initiation, retried safely)
//   • the OTP branch (requiresOtp=true → /deposit/fiat/initiate/moolre/otp)
//   • socket confirmation (SocketService.onDepositSuccess)
//   • demo-mode auto-confirmation
//   • ?amount= pre-fill + ?memo= trace (Susu reminder deep links)
// The UI may change; this contract may not.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/launcher_drafts.dart';
import 'package:azaman/widgets/launcher_exit_prompt.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:share_plus/share_plus.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/deposit_settlement_monitor.dart';
import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/deposit_recovery_service.dart';
import 'package:azaman/services/deposit_continuations.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/utils/amount_input.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/amount_keypad.dart';
import 'package:azaman/widgets/animated_qr_dust.dart';
import 'package:azaman/widgets/momo_network.dart';
import 'package:azaman/widgets/odometer_number.dart';
import 'package:azaman/widgets/pull_down_dismissible_surface.dart';
import 'package:azaman/widgets/scale_tap.dart';
import 'package:azaman/screens/saved_wallets_screen.dart' show AddPayoutSheet;

// =============================================================================
// DEPOSIT SCREEN — the Add Cash surface
// =============================================================================

class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({
    super.key,
    this.initialTab = DepositTab.fiat,
    this.prefillAmount,
    this.memo,
    this.restoredDraft,
  });

  final DepositTab initialTab;

  /// Pre-fill amount for the Fiat tab. Set when the screen is reached via a
  /// deep link such as `/deposit?amount=12.34&memo=susu:abc`, most often the
  /// Susu T-24h reminder notification (Req 12.3 / 12.4). The value must be a
  /// positive decimal with at most two fractional digits, otherwise we
  /// ignore it and leave the input blank.
  final String? prefillAmount;

  /// Opaque memo string (e.g. `susu:<susuId>`). Logged into the resulting
  /// deposit's metadata server-side so operators can trace deposits back to
  /// the cycle that prompted them. Not surfaced visually.
  final String? memo;

  /// §C continuation — editable inputs restored from a five-minute
  /// launcher draft. LOCAL convenience only; a draft is NEVER a pending
  /// deposit. The saved-account pick is re-matched by id against the
  /// LIVE account list when the panel loads.
  final Map<String, dynamic>? restoredDraft;

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

enum DepositTab { crypto, fiat }

class _DepositScreenState extends ConsumerState<DepositScreen> {
  /// §C — live handle into the fiat panel so the draft capture reads the
  /// panel's actual amount state without hoisting it.
  final GlobalKey<_FiatDepositPanelState> _fiatPanelKey =
      GlobalKey<_FiatDepositPanelState>();

  /// §C.1 — meaningful unsubmitted input on the launcher's surface (the
  /// fiat panel's amount). Empty closes are silent; a meaningful close
  /// offers Keep for 5 minutes / Discard / Stay.
  bool get _hasMeaningfulDraftInput {
    final panel = _fiatPanelKey.currentState;
    if (panel == null) return false;
    // A deposit in flight is ALWAYS meaningful: real money may be moving
    // under its reference, and closing must offer Keep so the draft
    // carries the user's way back onto that one transaction.
    return panel._amountRaw.isNotEmpty || panel.hasInFlightDeposit;
  }

  Map<String, dynamic> _captureDraft() => {
        'amountRaw': _fiatPanelKey.currentState?._amountRaw ?? '',
        if (_fiatPanelKey.currentState?._selectedAccountId != null)
          'accountId': _fiatPanelKey.currentState!._selectedAccountId,
        // Deposit lifecycle (PR #202 item 1) — persist the reference of
        // a deposit still in flight so a session interruption can be
        // reconciled on resume. Never persisted once confirmed.
        if (_fiatPanelKey.currentState?.hasInFlightDeposit == true)
          'pendingReference': _fiatPanelKey.currentState!.inFlightReference,
      };

  Future<void> _attemptClose() async {
    // REVIEW GAP 1 — initial-submit race: while POST /deposit/fiat/
    // initiate/moolre is in flight the form looks "meaningful" (amount
    // is set) but a durable provider reference does not exist yet, so a
    // draft saved in this window could resume into a fresh instruction
    // for a transaction that may already have committed. Every close
    // gesture is guarded until the initiation's outcome can be safely
    // represented: on success the reference exists (and the close draft
    // carries it); on failure the form is honestly reusable again.
    // No new idempotency identity is minted here — the guard only holds
    // the surface open until the SAME operation resolves.
    final panel = _fiatPanelKey.currentState;
    // REVIEW FOLLOW-UP P1 — the guard now holds through BOTH windows:
    // the initiate request itself, and the continuation persistence it
    // hands off to. Closing before the local record is confirmed could
    /// lose the only pointer to a submitted operation.
    if (panel != null &&
        (panel.isInitiating || panel.isPersistingContinuation)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            panel.isInitiating
                ? 'Setting up your deposit — hold on a moment.'
                : 'Saving your deposit receipt — hold on a moment.',
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return; // no draft, no close — the operation owns the window
    }
    if (_hasMeaningfulDraftInput) {
      final user = ref.read(authProvider).user;
      await guardLauncherClose(
        context: context,
        ref: ref,
        userId: user?.id,
        surface: LauncherSurface.addCash,
        hasMeaningfulInput: _hasMeaningfulDraftInput,
        capture: _captureDraft,
        doClose: _closeSurface,
      );
      return;
    }
    _closeSurface();
  }

  void _closeSurface() {
    AzamanHaptics.navigation();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    // LAST REVIEW — settlement resolution must survive this surface's
    // own result view AND its absence: watching the monitor from build
    // (the legal lifecycle point) keeps it alive whenever Add Cash is
    // open; MainWrapper keeps it alive for the rest of the session.
    ref.watch(depositSettlementMonitorProvider);

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: PullDownDismissibleSurface(
          onDismiss: _attemptClose,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AddCashHeader(colors: colors, onClose: _attemptClose),
              Expanded(
                child: _FiatDepositPanel(
                  key: _fiatPanelKey,
                  prefillAmount: widget.prefillAmount,
                  memo: widget.memo,
                  restoredAmount: widget.restoredDraft?['amountRaw']?.toString(),
                  restoredAccountId:
                      widget.restoredDraft?['accountId']?.toString(),
                  restoredPendingReference: widget
                      .restoredDraft?['pendingReference']?.toString(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER — [X] Add Cash. The X is the ONE close affordance: no back arrow,
// no duplicate close controls.
// ─────────────────────────────────────────────────────────────────────────────

class _AddCashHeader extends StatelessWidget {
  const _AddCashHeader({required this.colors, required this.onClose});

  final AzamanColors colors;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Close Add Cash',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.softSurface,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.close, size: 18, color: colors.textPrimary),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Add Cash',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FIAT | CRYPTO SWITCH — a restrained two-way switch. The selected side
// carries the accent underline; there is no heavy segmented container. The
// TabController keeps the selection stable across rebuilds, and TabBarView
// keeps the Crypto panel lazy: landing on Fiat does NOT fetch the Polygon
// deposit address.
// ─────────────────────────────────────────────────────────────────────────────

// =============================================================================
// FIAT PANEL — odometer amount, quick pills, keypad, method row, CTA.
// =============================================================================

class _FiatDepositPanel extends ConsumerStatefulWidget {
  const _FiatDepositPanel({
    super.key,
    this.prefillAmount,
    this.memo,
    this.restoredAmount,
    this.restoredAccountId,
    this.restoredPendingReference,
  });

  final String? prefillAmount;
  final String? memo;

  /// §C draft resume — the launcher draft's amount. Applied exactly like
  /// the deep-link prefill: through the same validator, never raw-trusted.
  final String? restoredAmount;

  /// §C draft resume — the draft's explicit account id. Re-matched against
  /// the LIVE saved-accounts list when it loads; a deleted account is
  /// honestly unselected instead of restored as stale data.
  final String? restoredAccountId;

  /// §C draft resume — the payment reference of a deposit that was still
  /// IN FLIGHT when the surface closed. Unlike amount/account this is not
  /// a preference: real money may be moving under that reference. The
  /// panel reconciles it against the backend's durable ledger state
  /// (see [_recoverInterruptedDeposit]) instead of assuming anything.
  final String? restoredPendingReference;

  @override
  ConsumerState<_FiatDepositPanel> createState() => _FiatDepositPanelState();
}

class _FiatDepositPanelState extends ConsumerState<_FiatDepositPanel>
    with AutomaticKeepAliveClientMixin {
  // ── Amount state machine ────────────────────────────────────────────────
  // The keypad writes into a raw digits string; the odometer renders it.
  // Invariants, enforced here (the ONLY place that can produce an amount):
  //   • '' renders as 0 and parses to "no amount"
  //   • at most one decimal point
  //   • at most two fractional digits
  //   • no leading-zero buildup ('0' + '5' → '5')
  //   • no negative values (no sign key exists)
  //   • at most 7 integer digits (GH₵ 9,999,999.99 covers every product cap)
  String _amountRaw = '';

  // The user's EXPLICIT payment-method choice (survives selector open/close
  // and every rebuild). Auto-selection (primary account / lone account) is
  // derived, never silently stored.
  String? _selectedAccountId;
  bool _isSubmitting = false;

  // r42: one key per LOGICAL deposit initiation, reused across retries
  // (a lost response may mean the initiation already committed); retired
  // on any answered non-409 outcome.
  // r42 OPERATION-INSTANCE MODEL: the action id names the operation TYPE.
  // Each genuinely new deposit initiation gets a fresh durable instance;
  // the ref is this flow's retry handle — a re-tap after a lost response
  // retries the SAME instance (same key), and a materially different body
  // begins a genuinely new instance without disturbing the old one.
  static const _initiateActionId = 'deposit.fiat.moolre.initiate';
  final _initiateRef = FinancialOperationRef();
  Map<String, dynamic>? _depositResult;

  // ── Moolre on-ramp (2026-06-23) ──────────────────────────────────────────
  // Name-validation dialog + OTP branch (Moolre TP14 returns requiresOtp).
  String? _resolvedName;
  // The account whose number actually produced [_resolvedName]. The name
  // may only be shown for, or charged against, THIS account — a stale name
  // from a previously selected account must never survive a selection
  // change (release-level review blocker 3).
  String? _validatedAccountId;
  bool _isValidatingName = false;
  bool _requiresOtp = false;
  String? _pendingReference;

  /// REVIEW FOLLOW-UP P1 — the continuation write that makes a
  /// SUBMITTED deposit durably recoverable. True while the write is in
  /// flight, and while it has failed and awaits its explicit retry:
  /// the surface must not close — and no new deposit may start — until
  /// the local recovery record is confirmed. The backend reference is
  /// the user's only way back onto an instruction they already gave.
  bool _persistingContinuation = false;
  bool _continuationPersistFailed = false;

  /// REVIEW FOLLOW-UP (owner identity) — the identity that STARTED the
  /// financial operation owns its continuation records for the
  /// operation's whole lifetime (initiate → OTP confirm → recovery →
  /// resolution). An account switch while a request is in flight must
  /// NEVER reassign a submitted operation to whichever user is active
  /// when the response lands: A's reference is saved under A's storage
  /// key even if B is on screen. Captured at initiation; a resumed
  /// draft's recovery captures the CURRENT user, because a user-scoped
  /// draft can only be re-opened by its owner.
  String? _operationOwnerUserId;
  bool _operationOwnerCaptured = false;

  /// The storage owner for this screen's continuation lifecycle. Falls
  /// back to the session user only BEFORE any operation was captured
  /// (fresh screen, no pending operation).
  String? get _continuationOwner => _operationOwnerCaptured
      ? _operationOwnerUserId
      : ref.read(authProvider).user?.id;

  /// Capture the operation's owner at the moment the financial request
  /// starts — the ONLY time the session user is consulted for this
  /// operation's identity.
  void _captureOperationOwner() {
    _operationOwnerUserId = ref.read(authProvider).user?.id;
    _operationOwnerCaptured = true;
  }

  // ── LAST REVIEW: pending-result cancellation semantics ────────────────
  //
  // No cancellation contract exists with the provider: a local screen
  // reset can NEVER end a submitted instruction. The operation's
  // reference and owner must therefore outlive the form/result state
  // the reset clears:
  //
  //   • durably — the continuation record (saved under the operation
  //     owner's key the moment its reference is durable) plus the
  //     settlement monitor, which resolves the ACTIVE user's stored
  //     continuation for an event's EXACT reference even after this
  //     surface is gone;
  //   • on this surface — [_trackedOperations]: every operation this
  //     screen minted, keyed by exact reference → the owner captured at
  //     ITS initiation. A settlement for THAT reference is confirmed to
  //     the user and resolved under the RIGHT owner (an account switch
  //     mid-flow never re-binds a settled operation), even after the
  //     user backed out of its result view or started another deposit.
  //
  // Entries leave ONLY on authoritative settlement (duplicate events are
  // no-ops); an unresolved operation stays tracked exactly as long as its
  // continuation record stays stored. Product policy: concurrent pending
  // operations are SUPPORTED — each carries its own reference and is
  // independently tracked and resolved; the notification centre lists
  // every "Deposits in progress" row.
  final Map<String, String> _trackedOperations = {};

  /// Record a submitted operation under the owner captured at ITS
  /// initiation. Called at every durable-reference moment.
  void _trackOperation(String reference, String owner) {
    final ref_ = reference.trim();
    if (ref_.isEmpty || owner.trim().isEmpty) return;
    _trackedOperations[ref_] = owner.trim();
  }

  /// The screen's settlement listener — stored as a field so dispose can
  /// remove exactly this handler (SocketService's seam is multi-listener:
  /// the continuation monitor's handler must survive this surface).
  void _onSocketSettlement(
    double amountGhs,
    double amountUsdc,
    String provider,
    String reference,
  ) {
    if (!mounted) return;
    final eventRef = reference.trim();
    if (eventRef.isEmpty) return;
    final owner = _trackedOperations.remove(eventRef);
    if (owner == null || owner.isEmpty) {
      // Not an operation this surface minted (or already settled — a
      // duplicate event is a no-op). The settlement monitor owns the
      // stored-continuation half; an untracked reference is not ours to
      // confirm or resolve.
      return;
    }
    // Resolution under the operation's CAPTURED owner: a settlement for
    // A's deposit resolves A's continuation even if another account is
    // active now. Exact-reference only — deposit B's record is never
    // touched by deposit A's event, and the service's terminal
    // resolution makes this idempotent.
    ref
        .read(depositContinuationsProvider.notifier)
        .resolve(owner, eventRef);
    final colors = ref.read(themeProvider).colors;
    final visibleRef =
        _depositResult?['reference']?.toString() ?? _pendingReference ?? '';
    if (visibleRef == eventRef && _depositResult != null) {
      if (!_depositConfirmed) {
        setState(() => _depositConfirmed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Deposit confirmed — GH₵ ${amountGhs.toStringAsFixed(2)} credited to your wallet',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: colors.success,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      // The operation completed while its result view was NOT on screen
      // (the user backed out, started another deposit, or is mid-OTP):
      // honest status for a pending operation the surface still tracks.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ Your earlier deposit $eventRef completed — your wallet was funded.',
          ),
          backgroundColor: colors.success,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  final _otpController = TextEditingController();
  bool _isConfirmingOtp = false;
  bool _depositConfirmed = false;

  // Deposit lifecycle (PR #202 item 1) — true while the restored draft's
  // pending reference is being reconciled against the backend ledger.
  // While true no NEW initiation can start: the user must never be able
  // to double-instruct while an earlier instruction may still be live.
  bool _recovering = false;

  // REVIEW GAP 2 — fail-closed recovery: a lookup failure or an
  // unresolved status is NOT evidence the earlier instruction did not
  // commit. While true the earlier reference is preserved, the CTA is
  // blocked, and an explicit unresolved banner offers a re-check. The
  // form is never silently usable again until the SAME operation is
  // authoritatively resolved (settled/failed) by the ledger.
  bool _recoveryUnresolved = false;

  /// REVIEW GAP 1 — true only while the INITIAL initiate request is in
  /// flight and no durable reference exists yet (the exact window in
  /// which a close draft cannot honestly represent the operation).
  /// The OTP confirm is NOT this window: its reference already exists
  /// and is safely representable.
  bool get isInitiating => _isSubmitting && !hasInFlightDeposit;

  /// REVIEW FOLLOW-UP P1 — the close guard holds through this window
  /// exactly as it does through the initiation window: a durable
  /// backend reference whose local continuation record is unconfirmed
  /// (or failed) is a lost way back, and no draft may claim otherwise.
  bool get isPersistingContinuation =>
      _persistingContinuation || _continuationPersistFailed;

  /// The payment reference a draft should carry: the deposit that is
  /// still in flight (OTP pending or prompt sent), never a confirmed or
  /// reset one. A deposit in flight makes a close MEANINGFUL — the draft
  /// keeps the user's way back onto that one transaction.
  String? get inFlightReference => _depositConfirmed
      ? null
      : (_pendingReference ?? _depositResult?['reference']?.toString());

  bool get hasInFlightDeposit => (inFlightReference ?? '').isNotEmpty;

  /// FIX 3 — the moment a durable provider reference exists the deposit
  /// is a SUBMITTED operation: its way-back survives form-draft expiry
  /// in the separate continuation lifecycle. Saved at initiate success
  /// (idempotent upsert) and removed only on AUTHORITATIVE resolution.
  /// REVIEW FOLLOW-UP P1 — the save is AWAITED inside the submit and
  /// OTP-confirm windows and the close guard holds until it completes.
  /// On failure the exact returned reference is retained, the state
  /// stays safe and recoverable, an explicit retry re-runs the SAME
  /// save, and no new deposit is initiated in its place. The
  /// continuation is never claimed saved when it is not.
  Future<void> _saveContinuation(String reference) async {
    // OWNER BINDING (review follow-up) — the INITIATING identity, never
    // the currently-active one. A response that lands after an account
    // switch must not store A's reference under B's key.
    final uid = _continuationOwner?.trim();
    if (uid == null || uid.isEmpty) {
      // FAIL CLOSED — no owner can be established for an operation the
      // backend has already accepted. Never silently treat the
      // way-back as saved: the exact reference is retained, the
      // persistence-failure state engages, and the retry guard stays
      // armed until an owner can be established and the write lands.
      _markContinuationPersistFailed();
      return;
    }
    setState(() => _persistingContinuation = true);
    try {
      await ref
          .read(depositContinuationsProvider.notifier)
          .save(uid, reference);
      if (mounted) {
        setState(() {
          _persistingContinuation = false;
          _continuationPersistFailed = false;
        });
      }
    } catch (_) {
      _markContinuationPersistFailed();
    }
  }

  /// The single fail-closed transition for an unpersisted submitted
  /// operation: exact reference retained, close guard held, explicit
  /// retry offered for the SAME save. Never claims the write happened.
  void _markContinuationPersistFailed() {
    if (!mounted) return;
    final colors = ref.read(themeProvider).colors;
    setState(() {
      _persistingContinuation = false;
      _continuationPersistFailed = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "We couldn't save this deposit's receipt on your device "
          'yet. Tap Save receipt to keep your way back to it.',
        ),
        backgroundColor: colors.accentSurface,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Save receipt',
          textColor: colors.accent,
          onPressed: _retryContinuationSave,
        ),
      ),
    );
  }

  /// REVIEW FOLLOW-UP P1 — retry the SAME operation's local save. The
  /// reference is never re-minted and the provider is never
  /// re-instructed.
  void _retryContinuationSave() {
    final active = inFlightReference ?? _pendingReference;
    if (active == null || active.isEmpty) return;
    // FINAL REVIEW — the retry NEVER captures (or replaces) the owner.
    // Ownership is established exactly once, before the initiate
    // request leaves, and is REQUIRED for that request to be sent at
    // all — an accepted operation therefore always carries a captured
    // owner. Should one somehow be missing, the save below fails
    // closed and the exact reference is retained WITHOUT being
    // assigned to whatever account happens to be active now: no
    // trusted ownership evidence, no storage under B's key.
    _saveContinuation(active);
  }

  /// Authoritative resolution only (settled or failed by the ledger, or
  /// socket-confirmed). Never called for a discarded local FORM draft.
  /// LAST REVIEW — the owner is an explicit argument: each operation
  /// resolves under the identity that CAPTURED it, never under whoever
  /// happens to be active when the settlement lands.
  void _resolveContinuationOwned(String? owner, String reference) {
    // OWNER BINDING — only the initiating owner's authoritative
    // resolution removes THEIR stored continuation; it can never
    // delete (or resolve under) a different account's records.
    final uid = owner?.trim();
    if (uid == null || uid.isEmpty) return;
    ref
        .read(depositContinuationsProvider.notifier)
        .resolve(uid, reference);
  }

  @override
  bool get wantKeepAlive => true;

  /// Map the canonical saved-account provider (MTN | TELECEL | AIRTELTIGO,
  /// VODAFONE legacy still accepted) to the enum the backend's
  /// `initiateMoolreFiatDeposit` MOMO set accepts
  /// (MTN_MOMO | TELECEL_CASH | AIRTELTIGO). Telecel is the Vodafone Ghana
  /// rebrand — the backend treats VODAFONE and TELECEL as the same channel —
  /// so both map to TELECEL_CASH. The same enum is accepted by
  /// `/deposit/validate-name`, so one mapping serves both calls.
  String _backendProvider(String provider) {
    if (provider == 'MTN_MOMO' ||
        provider == 'VODAFONE_CASH' ||
        provider == 'AIRTELTIGO') {
      return provider;
    }
    switch (provider) {
      case 'MTN':
        return 'MTN_MOMO';
      case 'TELECEL':
      case 'VODAFONE': // legacy
        return 'TELECEL_CASH';
      case 'AIRTELTIGO':
        return 'AIRTELTIGO';
      default:
        return '${provider}_MOMO';
    }
  }

  /// §C resume — validate and apply the draft's amount. Same rules as
  /// the deep-link prefill: strictly positive, at most two fractional
  /// digits; anything else is dropped and the input stays empty.
  void _applyRestoredAmount() {
    final raw = widget.restoredAmount?.trim();
    if (raw == null || raw.isEmpty) return;
    final ok = RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(raw);
    final v = double.tryParse(raw);
    if (ok && v != null && v > 0) {
      _amountRaw = raw;
    }
  }

  @override
  void initState() {
    super.initState();
    // Phase 4 (Susu Sprint, 2026-05-31) — Req 12.4 / 12.6: pre-fill the
    // amount when the screen was opened with `?amount=…`. Validate the value
    // has at most two fractional digits and is strictly > 0; anything else
    // is dropped silently and the input stays empty so the user notices and
    // re-enters.
    final raw = widget.prefillAmount?.trim();
    if (raw != null && raw.isEmpty && (widget.restoredAmount ?? '').isNotEmpty) {
      // §C resume: no deep-link prefill — restore the draft amount
      // through the SAME validator. A malformed stored value is dropped
      // exactly like a malformed deep link.
      _applyRestoredAmount();
    } else if (raw != null && raw.isNotEmpty) {
      final ok = RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(raw);
      final v = double.tryParse(raw);
      if (ok && v != null && v > 0) {
        _amountRaw = raw;
      }
    }
    // §C resume — the draft's EXPLICIT account choice. _currentAccount
    // re-matches it against the live list on every read; a deleted
    // account falls through to the honest derived selection.
    final restoredAccount = widget.restoredAccountId;
    if (restoredAccount != null && restoredAccount.isNotEmpty) {
      _selectedAccountId = restoredAccount;
    }
    // §C resume — a deposit that was still IN FLIGHT when the surface
    // closed. Reconcile against the backend's durable ledger state
    // (demo mode has no backend to ask and never recovers).
    final restoredReference = widget.restoredPendingReference?.trim();
    if (!AppConfig.demoMode &&
        restoredReference != null &&
        restoredReference.isNotEmpty) {
      _recoverInterruptedDeposit(restoredReference);
    }
    // LAST REVIEW — settlement resolution must survive the result view:
    // the monitor (session-long, activated in build()) resolves the
    // ACTIVE user's stored continuations for an event's exact
    // reference; this surface's own handler only adds the visible
    // confirmation and the per-operation owner binding for operations
    // IT minted. The two share the socket seam — neither displaces the
    // other.
    SocketService.instance.onDepositSuccess(_onSocketSettlement);
  }

  @override
  void dispose() {
    // Multi-listener seam: remove ONLY this surface's handler — the
    // continuation monitor's listener must keep resolving stored
    // continuations after this surface is gone.
    SocketService.instance.removeDepositSuccessListener(_onSocketSettlement);
    _otpController.dispose();
    super.dispose();
  }

  // ── Interrupted-deposit recovery (PR #202 item 1) ────────────────────
  //
  // The draft's pending reference is resolved against the backend's
  // durable ledger (GET /finance/transactions, then Backend F's
  // GET /deposit/fiat/status/:id when present — see
  // DepositRecoveryService). Every branch maps to an honest UI state;
  // none of them re-instructs the provider or claims what did not
  // happen. A late settlement still arrives on the socket listener
  // registered in initState — the recovered operation is tracked by its
  // EXACT reference (and its durable continuation is resolved by the
  // settlement monitor), so a settlement confirms and resolves it even
  // from a different view.
  Future<void> _recoverInterruptedDeposit(String reference) async {
    // OWNER BINDING — a resumed draft is user-scoped, so the user
    // re-opening it IS its owner; the recovery and any later
    // authoritative resolution stay bound to that identity. Idempotent:
    // a re-check after an account switch never rebinds the draft.
    if (!_operationOwnerCaptured) _captureOperationOwner();
    // The recovered operation's owner for THIS sweep: every resolution
    // below happens under exactly this identity, independent of whoever
    // is active when a late settlement lands (the settlement monitor +
    // the tracked-operation binding own that half).
    final recoveredOwner = _continuationOwner;
    setState(() {
      _recovering = true;
      // A deliberate re-check clears the banner until it lands again.
      _recoveryUnresolved = false;
    });
    DepositRecoveryOutcome? outcome;
    try {
      outcome =
          await DepositRecoveryService(apiClient).recover(reference);
    } catch (_) {
      outcome = null; // network/refused: no claim, fresh form
    }
    if (!mounted) return;
    final colors = ref.read(themeProvider).colors;
    switch (outcome?.status) {
      case DepositRecoveryStatus.settled:
        setState(() {
          _recovering = false;
          _recoveryUnresolved = false;
          _depositResult = {'reference': reference};
          _depositConfirmed = true;
        });
        // FIX 3 — settled while away: the submitted operation leaves the
        // continuation lifecycle for good — under ITS owner.
        _resolveContinuationOwned(recoveredOwner, reference);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '✓ Your deposit completed while you were away — your wallet was funded.',
            ),
            backgroundColor: colors.success,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case DepositRecoveryStatus.pending:
      case DepositRecoveryStatus.frozen:
        // The instruction may still be live at the provider. Restore
        // the in-flight view so the user cannot double-instruct under a
        // new quote; the socket listener confirms a late settlement on
        // its own.
        final frozen = outcome!.status == DepositRecoveryStatus.frozen;
        // The instruction may still be live: track it by exact
        // reference so a late socket settlement confirms and resolves
        // THIS operation (never a newer one) even from another view.
        if (recoveredOwner != null) _trackOperation(reference, recoveredOwner);
        setState(() {
          _recovering = false;
          _recoveryUnresolved = false;
          _pendingReference = reference;
          _depositResult = {
            'reference': reference,
            'instructions': frozen
                ? 'This deposit is under dispute review. It will resolve '
                      'through the dispute flow — do not send another '
                      'payment for it.'
                : 'Approve the prompt on your phone to complete the '
                      'deposit. If you already approved it, this page '
                      'will confirm automatically.',
          };
        });
      case DepositRecoveryStatus.failed:
        setState(() {
          _recovering = false;
          _recoveryUnresolved = false;
        });
        // FIX 3 — the ledger said it failed: authoritatively resolved
        // under the operation's owner.
        _resolveContinuationOwned(recoveredOwner, reference);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your last deposit did not go through. You can start a new one.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      case DepositRecoveryStatus.unknown:
      case null:
        // REVIEW GAP 2 — FAIL CLOSED. A lookup failure or a no-match is
        // NOT evidence that the earlier instruction did not commit (the
        // ledger may lag; the request may have died mid-flight). The
        // reference is preserved, the CTA stays blocked, and the
        // unresolved banner offers a re-check of the SAME operation.
        // No success or failure is claimed on an unavailable lookup,
        // and no new initiation may start until the ledger answers.
        if (recoveredOwner != null) _trackOperation(reference, recoveredOwner);
        setState(() {
          _recovering = false;
          _recoveryUnresolved = true;
          _pendingReference = reference;
        });
    }
  }

  /// REVIEW GAP 2 — the banner's explicit re-check. Reconciles the SAME
  /// reference (never a new idempotency identity) against the ledger.
  void _retryRecovery() {
    final ref = _pendingReference;
    if (ref == null || ref.isEmpty) return;
    _recoverInterruptedDeposit(ref);
  }

  // ── Amount input state machine ──────────────────────────────────────────

  void _onKeypadKey(String key) {
    if (_isSubmitting || _isValidatingName || _persistingContinuation) {
      return;
    }
    setState(() => _amountRaw = AmountInput.applyKey(_amountRaw, key));
  }

  /// The amount as the user entered it, or null when there is no amount.
  /// Every invalid-state rule (single decimal point, two fractional digits,
  /// leading zeros, 7-digit integer cap) is enforced by the pure
  /// [AmountInput] state machine — the same code the unit tests exercise.
  double? get _amountValue => AmountInput.value(_amountRaw);

  /// The odometer string: grouped integer part, fraction exactly as typed.
  /// Empty input displays as '0'.
  String get _amountDisplay => AmountInput.display(_amountRaw);

  // ── Payment-method selection ─────────────────────────────────────────────

  /// The account that actually backs this deposit. Priority:
  ///   1. the user's explicit choice (if it still exists),
  ///   2. the primary account,
  ///   3. the ONLY account when exactly one exists,
  ///   4. null — never an arbitrary first account.
  SavedMomoAccount? _currentAccount(List<SavedMomoAccount> accounts) {
    if (_selectedAccountId != null) {
      for (final a in accounts) {
        if (a.id == _selectedAccountId) return a;
      }
    }
    SavedMomoAccount? primary;
    for (final a in accounts) {
      if (a.isPrimary) {
        primary = a;
        break;
      }
    }
    if (primary != null) return primary;
    if (accounts.length == 1) return accounts.single;
    return null;
  }

  // ── Financial flow (unchanged contract) ───────────────────────────────────

  /// Resolve the registered account name via Moolre, show a confirmation
  /// dialog, then proceed to the deposit. Name validation is best-effort —
  /// if it fails we proceed without it rather than block the deposit.
  Future<void> _validateAndConfirm() async {
    final account = _currentAccount(
      ref.read(savedMomoProvider).valueOrNull ?? const <SavedMomoAccount>[],
    );
    if (account == null) return;

    // Clear any name from a PREVIOUS validation before this one resolves —
    // the result below belongs to THIS account and no other.
    setState(() {
      _isValidatingName = true;
      _resolvedName = null;
      _validatedAccountId = null;
    });
    try {
      final resp = await apiClient.post('/deposit/validate-name', {
        'phoneNumber': account.phoneNumber,
        'provider': _backendProvider(account.provider),
      });
      final body = jsonDecode(resp.body);
      if (resp.statusCode == 200 && body['data'] != null) {
        if (mounted) {
          setState(() {
            _resolvedName = body['data'] as String?;
            _validatedAccountId = account.id;
          });
        }
      }
    } catch (_) {
      // Name validation is optional — proceed without it if it fails.
    } finally {
      if (mounted) setState(() => _isValidatingName = false);
    }

    // The payment-method row is disabled while validation is in flight, but
    // defense-in-depth: if the selection is no longer the account that was
    // validated, abort. The newly selected account must be validated on its
    // own — a name resolved for account A can never confirm or charge
    // account B.
    if (_currentAccount(
          ref.read(savedMomoProvider).valueOrNull ?? const <SavedMomoAccount>[],
        )?.id !=
        account.id) {
      if (mounted) {
        setState(() {
          _resolvedName = null;
          _validatedAccountId = null;
        });
      }
      return;
    }

    if (_resolvedName != null && mounted) {
      final colors = ref.read(themeProvider).colors;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            'Confirm account',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: Text(
            'Paying to: $_resolvedName\nIs this correct?',
            style: TextStyle(color: colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.textTertiary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Confirm', style: TextStyle(color: colors.accent)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await _initiateDeposit(account);
  }

  /// [validatedAccount] is the exact account whose registered name the
  /// user confirmed (or that failed name-validation best-effort) — the
  /// deposit initiates against THIS snapshot, never a re-resolved
  /// "current" selection that might have changed in between.
  Future<void> _initiateDeposit([SavedMomoAccount? validatedAccount]) async {
    // Deposit lifecycle: no second instruction while the restored one
    // is being reconciled — an earlier instruction may still be live.
    if (_recovering) return;
    // REVIEW GAP 2 — an unresolved earlier deposit blocks a new one
    // outright: the same operation must be authoritatively resolved
    // first. The user is told why, honestly.
    if (_recoveryUnresolved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Confirm your earlier deposit first — tap "Check again" on '
            'the notice above.',
          ),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final amount = _amountValue;
    if (amount == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    final account =
        validatedAccount ??
        _currentAccount(
          ref.read(savedMomoProvider).valueOrNull ?? const <SavedMomoAccount>[],
        );
    if (account == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a payment account')));
      return;
    }
    // Belt and suspenders: a name that was resolved for a different account
    // must never reach the user or the wire.
    if (_resolvedName != null && _validatedAccountId != account.id) {
      setState(() {
        _resolvedName = null;
        _validatedAccountId = null;
      });
      await _validateAndConfirm();
      return;
    }

    setState(() => _isSubmitting = true);
    // OWNER BINDING (review follow-up) — capture the identity that is
    // starting this financial operation BEFORE the request leaves. The
    // response may land after an account switch; its continuation
    // records stay bound to THIS identity for the operation's lifetime.
    _captureOperationOwner();
    // FINAL REVIEW — a financial mutation REQUIRES a capturable owner.
    // The continuation lifecycle is user-scoped: an initiation this
    // device cannot attribute to an authenticated identity could never
    // honestly become anyone's continuation record, and the backend
    // must never be asked to accept an instruction whose local way-back
    // no account can own. Block BEFORE the wire, with honest feedback.
    final ownerId = _operationOwnerUserId?.trim();
    if (ownerId == null || ownerId.isEmpty) {
      // No operation exists — release the captured (empty) state so a
      // later sign-in starts clean.
      _operationOwnerCaptured = false;
      _operationOwnerUserId = null;
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your session ended. Sign in again to start a deposit.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    try {
      // All saved accounts in this picker are Mobile Money (MTN / Telecel /
      // AirtelTigo), so every deposit routes through the Moolre PIN-push
      // on-ramp.
      final body = <String, dynamic>{
        'amountGhs': amount,
        'provider': _backendProvider(account.provider),
        'phoneNumber': account.phoneNumber,
        // Susu memo trace (Req 12.4) — persisted into the deposit's
        // metadata server-side so operators can tie a deposit back to the
        // cycle reminder that prompted it.
        if (widget.memo != null && widget.memo!.isNotEmpty) 'memo': widget.memo,
      };
      // r42: initiating a fiat deposit is a protected mutation — one key
      // per LOGICAL initiation (the OTP confirmation is a separate route),
      // reused across retries of the same initiation.
      final response = await apiClient.postFinancial(
        '/deposit/fiat/initiate/moolre',
        body,
        operationType: _initiateActionId,
        ref: _initiateRef,
      );
      final data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        AzamanHaptics.commit();
        if (data['requiresOtp'] == true) {
          final freshRef = data['data']?['reference']?.toString();
          // FIX 3 + REVIEW FOLLOW-UP P1 — the reference just became
          // durable: the submitted operation enters the continuation
          // lifecycle immediately, independent of every form-draft
          // clock. The save is awaited BEFORE the guard releases — the
          // OTP screen only becomes reachable once the local way-back
          // is confirmed (or explicitly flagged for retry).
          if ((freshRef ?? '').isNotEmpty) await _saveContinuation(freshRef!);
          if (!mounted) return;
          if (freshRef != null) {
            _trackOperation(freshRef, _operationOwnerUserId ?? '');
          }
          setState(() {
            _isSubmitting = false;
            _requiresOtp = true;
            _pendingReference = freshRef;
          });
        } else {
          setState(() {
            _depositResult = (data['data'] is Map<String, dynamic>)
                ? data['data'] as Map<String, dynamic>
                : data as Map<String, dynamic>;
            _isSubmitting = false;
          });
          // FIX 3 + REVIEW FOLLOW-UP P1 — same durable-reference
          // moment, no-OTP branch: the await holds the persistence
          // window under the close guard (via
          // _persistingContinuation) until the record is confirmed.
          final freshRef = inFlightReference;
          if ((freshRef ?? '').isNotEmpty) await _saveContinuation(freshRef!);
          if (freshRef != null) {
            _trackOperation(freshRef, _operationOwnerUserId ?? '');
          }
          // In demo mode there's no real Moolre prompt to approve —
          // auto-confirm after a short delay so the user sees the full
          // deposit success flow.
          if (AppConfig.demoMode) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && _depositResult != null && !_depositConfirmed) {
                setState(() => _depositConfirmed = true);
              }
            });
          }
        }
      } else {
        setState(() => _isSubmitting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                data['message']?.toString() ?? 'Failed to initiate deposit',
              ),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        String msg;
        if (e is SocketException || e is TimeoutException) {
          msg = 'Connection failed. Check your internet and retry.';
        } else if (e is ApiException) {
          msg = e.message;
        } else {
          msg = 'Something went wrong. Please try again.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
        );
      }
    }
  }

  /// Confirm a Moolre deposit that came back requiresOtp=true.
  Future<void> _confirmOtp() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) return;
    setState(() => _isConfirmingOtp = true);
    try {
      final resp = await apiClient.post('/deposit/fiat/initiate/moolre/otp', {
        'reference': _pendingReference,
        'otpCode': otp,
      });
      final body = jsonDecode(resp.body);
      if (resp.statusCode == 200 && body['success'] == true) {
        AzamanHaptics.commit();
        setState(() {
          _isConfirmingOtp = false;
          _requiresOtp = false;
          _depositResult = {'reference': _pendingReference};
        });
        // FIX 3 + REVIEW FOLLOW-UP P1 — keep the continuation record
        // warm under the confirmed reference until the socket/ledger
        // settles it (idempotent). Awaited: a confirm whose local
        // record is unconfirmed must not hand the surface back
        // unguarded.
        final confirmedRef = _pendingReference;
        if ((confirmedRef ?? '').isNotEmpty) {
          await _saveContinuation(confirmedRef!);
        }
      } else {
        setState(() => _isConfirmingOtp = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                body['message']?.toString() ?? 'OTP verification failed',
              ),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isConfirmingOtp = false);
      if (mounted) {
        final msg = (e is ApiException)
            ? e.message
            : (e is SocketException || e is TimeoutException)
            ? 'Connection failed. Check your internet and retry.'
            : 'Something went wrong. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
        );
      }
    }
  }

  void _reset() {
    // LAST REVIEW — an honest LOCAL return, not a cancellation: no
    // cancellation contract exists with the provider. Every branch that
    // reaches here leaves the operation's way back intact — the
    // durable continuation record under the owner's key (so the
    // settlement monitor can resolve it from ANY view) and the exact-
    // reference tracked-operation binding (so a settlement confirms to
    // the user under the RIGHT owner). Concurrent pending operations
    // are the defined product policy: the next initiation simply adds
    // its own independently tracked reference.
    setState(() {
      // The CURRENT form/result state is cleared: the next operation
      // captures a fresh owner at its own initiation. Previously
      // submitted operations stay tracked above.
      _operationOwnerUserId = null;
      _operationOwnerCaptured = false;
      _depositResult = null;
      _requiresOtp = false;
      _pendingReference = null;
      _resolvedName = null;
      _validatedAccountId = null;
      _depositConfirmed = false;
      _otpController.clear();
      _amountRaw = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = ref.watch(themeProvider).colors;

    return _requiresOtp
        ? _buildOtpEntry(colors)
        : _depositResult != null
        ? _buildResult(colors)
        : _buildForm(colors);
  }

  // ── Resting form: the composed Add Cash instrument ──────────────────────

  Widget _buildForm(AzamanColors colors) {
    final accountsAsync = ref.watch(savedMomoProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        final bottomInset = MediaQuery.of(context).padding.bottom;

        return Column(
          children: [
            // REVIEW GAP 2 — the explicit fail-closed state. The earlier
            // deposit could not be resolved against the ledger (lookup
            // failed or no row yet): the reference is preserved, nothing
            // is claimed, and the CTA below stays blocked until the SAME
            // operation is authoritatively resolved.
            if (_recoveryUnresolved || _recovering) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(20, compact ? 6 : 14, 20, 0),
                child: _RecoveryUnresolvedBanner(
                  colors: colors,
                  reference: _pendingReference,
                  checking: _recovering,
                  onRetry: _recovering ? null : _retryRecovery,
                ),
              ),
            ],
            // ── Phantom-style top-left amount composition (UI-correction
            // Phase A): the amount and the selected payment method form the
            // primary interaction at the top; keypad and CTA anchor the
            // bottom. Nothing centers the amount anymore.
            Padding(
              padding: EdgeInsets.fromLTRB(24, compact ? 6 : 14, 24, 0),
              child: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          AzMoney.ghsSymbol,
                          style: AzText.money(
                            colors.textSecondary,
                            size: compact ? 24 : 30,
                            tracking: -0.5,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // The amount is the visual anchor. Empty input
                      // renders as 0; only changed slots roll.
                      OdometerNumber(
                        value: _amountDisplay,
                        style: AzText.money(
                          colors.textPrimary,
                          size: compact ? 52 : 64,
                        ),
                        semanticsLabel: '${AzMoney.ghsSymbol} $_amountDisplay',
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Payment method — ONE row, directly under the amount (NOT
            // below the keypad): the amount and the method it will be
            // charged to read as one composed instrument.
            Padding(
              padding: EdgeInsets.fromLTRB(20, compact ? 10 : 14, 20, 0),
              child: accountsAsync.when(
                loading: () => const _MethodRowSkeleton(),
                error: (e, _) => _MethodErrorRow(
                  colors: colors,
                  onRetry: () => ref.invalidate(savedMomoProvider),
                ),
                data: (accounts) {
                  final account = _currentAccount(accounts);
                  // No payment-method changes while a validation or a
                  // submission is in flight — a mid-validation switch is
                  // exactly the race that would confirm one account's name
                  // and charge another (release-level review blocker 3).
                  final bool locked = _isSubmitting ||
                      _isValidatingName ||
                      _persistingContinuation;
                  if (accounts.isEmpty) {
                    return _AddMethodRow(
                      colors: colors,
                      onTap: locked ? null : () => _openAddAccountSheet(),
                    );
                  }
                  if (account == null) {
                    return _ChooseMethodRow(
                      colors: colors,
                      onTap: locked
                          ? null
                          : () => _showPaymentSelector(colors, accounts),
                    );
                  }
                  return _SelectedMethodRow(
                    colors: colors,
                    account: account,
                    onTap: locked
                        ? null
                        : () => _showPaymentSelector(colors, accounts),
                  );
                },
              ),
            ),

            // Quick amounts — replace the current amount, roll the odometer.
            Padding(
              padding: EdgeInsets.fromLTRB(24, compact ? 10 : 14, 24, 0),
              child: Wrap(
                alignment: WrapAlignment.start,
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final amt in const [50, 100, 200, 500])
                    _QuickAmountPill(
                      colors: colors,
                      amount: amt,
                      selected: _amountRaw == amt.toString(),
                      onTap: () {
                        if (_isSubmitting ||
                            _isValidatingName ||
                            _persistingContinuation) {
                          return;
                        }
                        AzamanHaptics.toggle();
                        setState(() => _amountRaw = amt.toString());
                      },
                    ),
                ],
              ),
            ),

            // Breathing room: everything below (keypad + CTA) stays anchored
            // to the bottom of the surface.
            const Expanded(child: SizedBox(width: double.infinity)),

            // The keypad stays fixed while the amount changes — it never
            // scrolls independently and never moves under the CTA.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: AmountKeypad(
                onKey: _onKeypadKey,
                enabled: !_isSubmitting &&
                    !_isValidatingName &&
                    !_persistingContinuation,
                rowHeight: compact ? 46 : 54,
              ),
            ),

            // CTA — bottom safe area, never obscured by the keypad.
            Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 12 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PrimaryButton(
                    colors: colors,
                    label: _continuationPersistFailed
                        ? 'Save receipt'
                        : _persistingContinuation
                        ? 'Saving your deposit…'
                        : _recovering
                        ? 'Checking last deposit…'
                        : _recoveryUnresolved
                        ? 'Confirm your earlier deposit first'
                        : _isValidatingName
                        ? 'Checking account…'
                        : _isSubmitting
                        ? 'Sending prompt…'
                        : 'Add Cash',
                    // REVIEW FOLLOW-UP P1 — while the continuation is
                    // unconfirmed the CTA is the retry for the SAME
                    // save; a failed local write never becomes a fresh
                    // deposit.
                    onTap: _continuationPersistFailed
                        ? _retryContinuationSave
                        : (_recovering ||
                              _recoveryUnresolved ||
                              _isSubmitting ||
                              _isValidatingName ||
                              _persistingContinuation ||
                              _amountValue == null ||
                              _currentAccount(
                                    accountsAsync.valueOrNull ??
                                        const <SavedMomoAccount>[],
                                  ) ==
                                  null)
                        ? null
                        : _validateAndConfirm,
                    isBusy: _recovering ||
                        _isSubmitting ||
                        _isValidatingName ||
                        _persistingContinuation,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: _ctaHint(
                      colors,
                      accounts:
                          accountsAsync.valueOrNull ??
                          const <SavedMomoAccount>[],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _ctaHint(
    AzamanColors colors, {
    required List<SavedMomoAccount> accounts,
  }) {
    final hasAccount = _currentAccount(accounts) != null;
    final String text;
    if (accounts.isEmpty) {
      text = 'Add a mobile money account to continue.';
    } else if (!hasAccount) {
      text = 'Choose a payment method to continue.';
    } else if (_amountValue == null) {
      text = 'Enter an amount to continue.';
    } else {
      text = 'Approve to complete the deposit.';
    }
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: colors.textTertiary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
    );
  }

  void _openAddAccountSheet() {
    AzamanHaptics.navigation();
    AddPayoutSheet.show(
      context,
      onSaved: () {
        if (!mounted) return;
        ref.invalidate(savedMomoProvider);
      },
      initialTab: 'mobileMoney',
    );
  }

  Future<void> _showPaymentSelector(
    AzamanColors colors,
    List<SavedMomoAccount> accounts,
  ) async {
    AzamanHaptics.navigation();
    final maxHeight = MediaQuery.of(context).size.height * 0.72;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // UI-correction Phase A sheet grammar: card surface, translucent
      // page-coloured barrier, 28dp top radius.
      backgroundColor: colors.card,
      barrierColor: colors.background.withValues(alpha: 0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => _PaymentSelectorSheet(
        colors: colors,
        accounts: accounts,
        selectedId: _selectedAccountId ?? _currentAccount(accounts)?.id,
        maxHeight: maxHeight,
        onSelect: (account) {
          // The selection lands in parent state IMMEDIATELY (the check
          // changes on the very same frame, behind the still-open sheet);
          // the sheet itself then closes after a tiny acknowledgement
          // delay — see _PaymentSelectorSheet. No _isSubmitting /
          // _isValidatingName race: this can only be reached while both
          // are false, and a submission cannot start beneath the sheet's
          // modal barrier.
          setState(() => _selectedAccountId = account.id);
        },
        onAdd: () {
          Navigator.pop(sheetCtx);
          _openAddAccountSheet();
        },
      ),
    );
  }

  // ── Result ────────────────────────────────────────────────────────────
  Widget _buildResult(AzamanColors colors) {
    final reference = _depositResult?['reference'] ?? '';
    final instructions =
        _depositResult?['instructions']?.toString() ??
        'Follow the prompt on your device to complete payment.';
    final account = _currentAccount(
      ref.read(savedMomoProvider).valueOrNull ?? const <SavedMomoAccount>[],
    );
    final networkName = account != null
        ? MomoNetwork.of(account.provider).displayName
        : '';
    final amount = _depositResult?['amountGhs']?.toString() ?? _amountDisplay;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeading(
            colors: colors,
            eyebrow: 'Deposit status',
            title: 'Prompt sent',
            body: 'Approve it on your phone to complete the deposit.',
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: _depositConfirmed
                ? Column(
                    key: const ValueKey("confirmed"),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Lottie.asset(
                        "assets/animations/success.json",
                        width: 110,
                        height: 110,
                        repeat: false,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Deposit Confirmed!",
                        style: TextStyle(
                          color: colors.success,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Your wallet has been funded.",
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey("waiting"),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulsingDots(color: colors.accent),
                      const SizedBox(height: 14),
                      Text(
                        "Waiting for confirmation...",
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Approve the prompt on your phone.",
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
          ),
          // Deposit lifecycle (PR #202 item 1) — the amount/reference
          // card anchors the deposit in BOTH states: a user who resumes
          // onto a still-pending instruction sees exactly which
          // transaction they are waiting on, same as a confirmed one.
          const SizedBox(height: 12),
          _PanelCard(
            colors: colors,
            fillColor: (_depositConfirmed ? colors.success : colors.accent)
                .withValues(alpha: 0.10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GH₵ $amount',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Prompt sent to $networkName',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                SelectableText(
                  reference.toString(),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            instructions,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (!_depositConfirmed) ...[
            const SizedBox(height: 14),
            // LAST REVIEW — no cancellation contract exists with the
            // provider, so the local action may never present itself as
            // one. The honest label says what the tap actually does
            // (return to Add Cash) and the caption says what it does NOT
            // do (end the instruction): it stays live until the ledger
            // settles it, tracked by exact reference the whole time.
            Text(
              'This deposit is still in progress. Leaving will not '
              'cancel it — we will confirm here and in your '
              'notifications once your provider completes it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 18),
          _PrimaryButton(
            colors: colors,
            // REVIEW FOLLOW-UP P1 — while the continuation record is
            // unconfirmed, the only offered action is saving it; the
            // pending operation must not be reset away.
            label: _continuationPersistFailed
                ? 'Save receipt'
                : _depositConfirmed
                ? 'Start another deposit'
                : 'Back to Add Cash',
            onTap: _continuationPersistFailed
                ? _retryContinuationSave
                : _reset,
          ),
        ],
      ),
    );
  }

  // ── OTP entry ───────────────────────────────────────────────────────────
  // Shown when Moolre returns requiresOtp=true (TP14). The user enters the
  // code sent to their registered phone; _confirmOtp posts it to the OTP
  // endpoint.
  Widget _buildOtpEntry(AzamanColors colors) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeading(
            colors: colors,
            eyebrow: 'Verification',
            title: 'Enter OTP',
            body:
                'Enter the code sent to your registered phone to authorise '
                'this deposit.',
          ),
          const SizedBox(height: 18),
          _PanelCard(
            colors: colors,
            child: TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              autofocus: true,
              maxLength: 6,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••••',
                hintStyle: TextStyle(
                  color: colors.textTertiary,
                  letterSpacing: 4,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _PrimaryButton(
            colors: colors,
            label: _isConfirmingOtp ? 'Verifying…' : 'Confirm deposit',
            onTap: _isConfirmingOtp ? null : _confirmOtp,
            isBusy: _isConfirmingOtp,
          ),
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TextButton(
              // REVIEW FOLLOW-UP — while the continuation record is
              // UNPERSISTED the only offered action is the SAME save's
              // retry: the reference is the only way back to an
              // already-submitted instruction.
              //
              // LAST REVIEW — once the record is durable the action is
              // honestly labelled as a RETURN, never a cancellation: no
              // cancellation contract exists with the provider, so the
              // instruction stays live (tracked by exact reference and
              // durably stored under its owner) and settles whenever
              // the user's provider processes it. The user can get back
              // to it any time from the notification centre's
              // "Deposits in progress" row.
              onPressed: _isConfirmingOtp
                  ? null
                  : _continuationPersistFailed
                  ? _retryContinuationSave
                  : () => setState(() {
                      _requiresOtp = false;
                      _pendingReference = null;
                      _otpController.clear();
                    }),
              child: Text(
                _continuationPersistFailed ? 'Save receipt' : 'Back to Add Cash',
                style: TextStyle(
                  color: _continuationPersistFailed
                      ? colors.accent
                      : colors.textTertiary,
                ),
              ),
            ),
            if (!_continuationPersistFailed && !_isConfirmingOtp)
              Text(
                'The deposit stays active — going back does not cancel '
                'it. You can pick it up again from your notifications.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REVIEW GAP 2 — the fail-closed recovery banner. An unresolved earlier
// deposit keeps its reference on the surface and blocks new deposits
// until the ledger authoritatively answers. It never claims success or
// failure on an unavailable lookup.
// ─────────────────────────────────────────────────────────────────────────────

class _RecoveryUnresolvedBanner extends StatelessWidget {
  const _RecoveryUnresolvedBanner({
    required this.colors,
    required this.reference,
    required this.checking,
    required this.onRetry,
  });

  final AzamanColors colors;
  final String? reference;
  final bool checking;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ref = (reference ?? '').trim();
    final short = ref.length > 14 ? '…${ref.substring(ref.length - 12)}' : ref;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.accentSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accent, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: colors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  checking
                      ? 'Checking your earlier deposit…'
                      : ref.isEmpty
                      ? 'We could not confirm your earlier deposit yet.'
                      : 'We could not confirm your earlier deposit '
                          '($short) yet.',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'A new deposit can only start once it is confirmed. Nothing '
            'was charged again — the same deposit is re-checked.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
          if (!checking) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  backgroundColor: colors.accentSurface,
                  foregroundColor: colors.accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Check again',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUICK AMOUNT PILL
// ─────────────────────────────────────────────────────────────────────────────

class _QuickAmountPill extends StatelessWidget {
  const _QuickAmountPill({
    required this.colors,
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final AzamanColors colors;
  final int amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${AzMoney.ghsSymbol} $amount',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: MotionTokens.control,
          curve: MotionTokens.enter,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? colors.accent.withValues(alpha: 0.14)
                : colors.softSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? colors.accent
                  : colors.border.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          child: Text(
            '${AzMoney.ghsSymbol} $amount',
            style: TextStyle(
              color: selected ? colors.accent : colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT METHOD ROW — the single selected-method surface.
// Primary identity: the verified registered name (accountName) when one
// exists; the nickname is the fallback, never the other way around.
// ─────────────────────────────────────────────────────────────────────────────

class _SelectedMethodRow extends StatelessWidget {
  const _SelectedMethodRow({
    required this.colors,
    required this.account,
    required this.onTap,
  });

  final AzamanColors colors;
  final SavedMomoAccount account;

  /// Null while a validation or submission is in flight — no method
  /// changes during that window (see _validateAndConfirm).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final network = MomoNetwork.of(account.provider);
    // Verified registered name wins; nickname is the fallback.
    final name =
        (account.accountName != null && account.accountName!.trim().isNotEmpty)
        ? account.accountName!
        : account.nickname;
    final phone = MomoNetwork.formatPhone(account.phoneNumber);

    return ScaleTap(
      onTap: onTap,
      child: Semantics(
        button: true,
        label:
            'Payment method: $name, ${network.displayName}, $phone. '
            'Double tap to change.',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          // UI-correction Phase A: card/surface fill, NO border — the row
          // reads as one raised surface, separation comes from the fill
          // against the page, not from a stroked box-in-box.
          decoration: BoxDecoration(
            color: colors.softSurface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              MomoNetworkBadge(provider: account.provider, showLabel: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (account.isPrimary) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.star_rounded,
                            color: colors.warning,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      phone,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.expand_more, color: colors.textTertiary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// No saved accounts at all: an honest call-to-add, never a fabricated
/// payment method.
class _AddMethodRow extends StatelessWidget {
  const _AddMethodRow({required this.colors, required this.onTap});

  final AzamanColors colors;

  /// Null while a validation or submission is in flight — no method
  /// changes during that window (see _validateAndConfirm).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Add mobile money account',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: colors.softSurface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.accent.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline, color: colors.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Add mobile money account',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Accounts exist but none is auto-selectable (multiple, none primary):
/// the user must choose — we never silently pick the first.
class _ChooseMethodRow extends StatelessWidget {
  const _ChooseMethodRow({required this.colors, required this.onTap});

  final AzamanColors colors;

  /// Null while a validation or submission is in flight — no method
  /// changes during that window (see _validateAndConfirm).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Choose a payment method',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          // Same no-border surface grammar as the selected-method row.
          decoration: BoxDecoration(
            color: colors.softSurface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: colors.textTertiary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Choose a payment method',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.expand_more, color: colors.textTertiary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodRowSkeleton extends ConsumerWidget {
  const _MethodRowSkeleton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: colors.softSurface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}

class _MethodErrorRow extends StatelessWidget {
  const _MethodErrorRow({required this.colors, required this.onRetry});

  final AzamanColors colors;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Couldn’t load saved accounts.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Retry',
              style: TextStyle(
                color: colors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT SELECTOR — compact bottom sheet listing saved accounts + the
// add-account action. The user's choice survives opening and closing.
// ─────────────────────────────────────────────────────────────────────────────

/// UI-correction Phase A selection grammar (handoff §4.3):
///   1. selection haptic fires on the tap;
///   2. the accent check changes IMMEDIATELY (sheet-local state, same
///      frame — the parent state was already updated by [onSelect]);
///   3. the sheet closes after a tiny acknowledgement delay so the check
///      is actually seen landing;
/// The close Timer is cancelled on dispose — it never outlives the sheet.
class _PaymentSelectorSheet extends StatefulWidget {
  const _PaymentSelectorSheet({
    required this.colors,
    required this.accounts,
    required this.selectedId,
    required this.maxHeight,
    required this.onSelect,
    required this.onAdd,
  });

  final AzamanColors colors;
  final List<SavedMomoAccount> accounts;
  final String? selectedId;
  final double maxHeight;
  final ValueChanged<SavedMomoAccount> onSelect;
  final VoidCallback onAdd;

  @override
  State<_PaymentSelectorSheet> createState() => _PaymentSelectorSheetState();
}

class _PaymentSelectorSheetState extends State<_PaymentSelectorSheet> {
  static const Duration _acknowledgementDelay = Duration(milliseconds: 160);

  /// The row the user just tapped — drives the check immediately, even
  /// before the parent rebuild flows a new [widget.selectedId] in.
  String? _tappedId;

  Timer? _closeTimer;

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _select(SavedMomoAccount account) {
    if (_closeTimer != null) return; // already acknowledged; closing
    AzamanHaptics.selection();
    setState(() => _tappedId = account.id);
    widget.onSelect(account);
    _closeTimer = Timer(_acknowledgementDelay, () {
      if (!mounted) return;
      Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = _tappedId ?? widget.selectedId;
    final colors = widget.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Payment method',
                      style: AzText.titleL.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close payment methods',
                    excludeSemantics: true,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        color: colors.textTertiary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: widget.accounts.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No saved mobile money accounts yet. Add one to '
                        'deposit with MoMo.',
                        textAlign: TextAlign.center,
                        style: AzText.body.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      children: [
                        for (final account in widget.accounts)
                          _PaymentOptionRow(
                            colors: colors,
                            account: account,
                            selected: account.id == selectedId,
                            onTap: () => _select(account),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: _AddMethodRow(colors: colors, onTap: widget.onAdd),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentOptionRow extends StatelessWidget {
  const _PaymentOptionRow({
    required this.colors,
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final AzamanColors colors;
  final SavedMomoAccount account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final network = MomoNetwork.of(account.provider);
    final name =
        (account.accountName != null && account.accountName!.trim().isNotEmpty)
        ? account.accountName!
        : account.nickname;

    return Semantics(
      button: true,
      selected: selected,
      label:
          '$name, ${network.displayName}, '
          '${MomoNetwork.formatPhone(account.phoneNumber)}',
      excludeSemantics: true,
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: MomoNetworkBadge(provider: account.provider, showLabel: false),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '${network.displayName} · ${MomoNetwork.formatPhone(account.phoneNumber)}',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        trailing: AnimatedContainer(
          duration: MotionTokens.microInteraction,
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: selected ? colors.accent : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? colors.accent
                  : colors.border.withValues(alpha: 0.8),
              width: 1.6,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 15, color: Colors.black)
              : null,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CRYPTO PANEL — deposit USDC on Polygon.
// A deliberately different composition from Fiat: the QR is the main visual,
// the address is copyable/shareable, and the network statement is explicit,
// never buried.
// Fetch is lazy: the TabBarView inflates this panel only when the user
// switches to Crypto, so landing on Fiat never fetches the address.
// ─────────────────────────────────────────────────────────────────────────────

class CryptoReceivePanel extends ConsumerStatefulWidget {
  const CryptoReceivePanel();

  @override
  ConsumerState<CryptoReceivePanel> createState() =>
      CryptoReceivePanelState();
}

class CryptoReceivePanelState extends ConsumerState<CryptoReceivePanel>
    with AutomaticKeepAliveClientMixin {
  String? _address;
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchDepositAddress();
  }

  Future<void> _fetchDepositAddress() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await apiClient.get('/wallet/deposit-address/polygon');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body);
        final data = body['data'] ?? body;
        setState(() {
          _address = data['address'] as String?;
          _isLoading = false;
        });
      } else {
        final body = jsonDecode(response.body);
        setState(() {
          _error = body['message']?.toString() ?? 'Failed to load address';
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Network error. Tap retry.';
        _isLoading = false;
      });
    }
  }

  void _copyAddress(AzamanColors colors) {
    if (_address == null) return;
    Clipboard.setData(ClipboardData(text: _address!));
    AzamanHaptics.confirm();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Address copied'),
        backgroundColor: colors.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _shareAddress() {
    if (_address == null) return;
    AzamanHaptics.navigation();
    Share.share(
      'My Azaman USDC receiving address (Polygon):\n$_address\n\n'
      'IMPORTANT: send only USDC on the Polygon network. '
      'Other tokens or networks will be lost.',
      subject: 'Azaman Receiving Address',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = ref.watch(themeProvider).colors;

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                color: colors.accent,
                strokeWidth: 2.6,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading your receiving address…',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 44, color: colors.danger),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _fetchDepositAddress,
                icon: Icon(Icons.refresh, color: colors.accent),
                label: Text('Retry', style: TextStyle(color: colors.accent)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.accent.withValues(alpha: 0.4)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        final qrSize = (constraints.maxWidth - 110)
            .clamp(compact ? 160.0 : 190.0, 250.0)
            .toDouble();

        return Column(
          children: [
            Expanded(
              flex: 2,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Receive USDC',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: compact ? 20 : 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Network identity — explicit, not decorative.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.softSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF8247E5).withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.hexagon_outlined,
                            color: Color(0xFF8247E5),
                            size: 13,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Polygon',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // The QR is the main visual.
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: AnimatedQrDust(
                  data: _address ?? '',
                  size: qrSize,
                  inkColor: const Color(0xFF141416),
                  backgroundColor: Colors.white,
                  errorCorrectLevel: 0, // QrErrorCorrectLevel.M = 0
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Shortened visually; the FULL address stays available to
            // semantics, copy and share.
            Semantics(
              label: 'Polygon USDC deposit address: ${_address ?? ''}',
              // A standalone node: the full address must never merge with
              // neighbouring announcements.
              container: true,
              excludeSemantics: true,
              child: Text(
                _short(_address ?? ''),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  letterSpacing: 0.1,
                ),
              ),
            ),
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _PrimaryButton(
                      colors: colors,
                      label: 'Copy address',
                      onTap: _address == null
                          ? null
                          : () => _copyAddress(colors),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _IconActionButton(
                    colors: colors,
                    icon: Icons.share_outlined,
                    tooltip: 'Share address',
                    onTap: _address == null ? null : _shareAddress,
                  ),
                ],
              ),
            ),

            Expanded(
              flex: 1,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Send only USDC on the Polygon network. '
                    'Other tokens or networks will be lost.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _short(String addr) {
    if (addr.length < 14) return addr;
    return '${addr.substring(0, 6)}…${addr.substring(addr.length - 4)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED LOW-LEVEL PANEL PIECES (OTP / result views reuse these)
// ─────────────────────────────────────────────────────────────────────────────

class _PanelHeading extends StatelessWidget {
  final AzamanColors colors;
  final String? eyebrow;
  final String title;
  final String? body;

  const _PanelHeading({
    required this.colors,
    this.eyebrow,
    required this.title,
    this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!,
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
        if (body != null) ...[
          const SizedBox(height: 8),
          Text(
            body!,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

class _PanelCard extends StatelessWidget {
  final AzamanColors colors;
  final Widget child;
  final Color? fillColor;

  const _PanelCard({required this.colors, required this.child, this.fillColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: fillColor ?? colors.softSurface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final AzamanColors colors;
  final String label;
  final VoidCallback? onTap;
  final bool isBusy;

  const _PrimaryButton({
    required this.colors,
    required this.label,
    required this.onTap,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: enabled ? colors.accent : colors.accent.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              height: 56,
              alignment: Alignment.center,
              child: isBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _IconActionButton({
    required this.colors,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      enabled: onTap != null,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              child: Icon(icon, color: colors.textPrimary, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingDots extends StatefulWidget {
  final Color color;
  const _PulsingDots({required this.color});
  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 180), () {
        if (mounted) _ctrls[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => AnimatedBuilder(
          animation: _ctrls[i],
          builder: (_, __) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 10,
            height: 10 + (_ctrls[i].value * 10),
            decoration: BoxDecoration(
              color: widget.color.withValues(
                alpha: 0.4 + _ctrls[i].value * 0.6,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
    );
  }
}
