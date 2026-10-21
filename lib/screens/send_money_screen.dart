// =============================================================================
// AZAMAN — SEND (UNIFIED PEER SEND COMPOSER, 2026-10-20)
//
// ONE shared money composer, opened from Home (plus launcher, "Send Again"
// activity) or from a personal chat (seeded with that conversation's
// authoritative participant identity).
//
// Interaction grammar is the Add Cash surface's (deposit_screen.dart):
//   • odometer-style amount display, amount-first at the top
//   • the custom AmountKeypad (no system keyboard for the amount)
//   • quick amount pills
//   • ONE dedicated recipient row (no inline contact list)
//   • a deliberate review stage, then a strong bottom action
//
// Financial truth (this is the release-critical part):
//   • The ONLY wire rail is the canonical friendship-based peer transfer,
//     POST /api/friends/transfer/send via FriendService.sendFunds →
//     ApiClient.postFinancial — durable idempotency (the FinancialOperation
//     claim + the persistent registry), never a raw ApiClient.post, never
//     a second idempotency mechanism. The old screen's
//     '/finance/internal-transfer' call targeted a route that does not
//     exist on the backend; it is gone.
//   • A recipient is send-capable ONLY with a live friendshipId from the
//     user's own accepted-friend list. AZM-ID/username/QR lookups resolve
//     identity for display and explicit selection; a resolved non-friend
//     is shown honestly as "not connected" and can never be sent to here.
//   • GHANA-FIRST CURRENCY (2026-10-20): the amount-entry wheel starts
//     in GHS; the typed digits are denominated in the wheel's unit. A GHS
//     composition is CONVERTED, at the validated canonical USDC/GHS
//     retail rate, into an EXACT reviewed USDC amount — that number is
//     the wire payload. A GHS value can never reach the USDC `amount`
//     field, and an unconvertible amount fails closed (never a fake or
//     zero conversion). Review FREEZES the rate snapshot + the wire
//     amount; if the rate changes before the commit, the composition
//     returns to compose for recalculation and a fresh review — the
//     confirmed amount is never silently altered. The wheel is LOCAL to
//     this transaction: it never writes the global display preference.
//   • The wire rail's currency is USDC everywhere (the settlement truth);
//     balance is the authoritative account state, never locally mutated
//     — after a confirmed send the account re-hydrates from the backend.
//   • Fee truth: the backend rail charges no fee and records feeUsdc: 0
//     on both parties' history rows (peerTransferController.sendFunds).
//     The review stage states "No fee" on that authority, nothing
//     invented.
//   • An ambiguous (timeout/offline) outcome is NEVER reported as failed:
//     the transfer may already have committed. Retry re-runs the SAME
//     durable operation identity (FriendService's per-friendship flow
//     ref), never a fresh one.
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/currency_catalog.dart';
import 'package:azaman/models/currency_model.dart'
    show currencyProvider, DisplayCurrency;
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/currency_provider.dart' show fxRateProvider;
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/friend_service.dart';
import 'package:azaman/services/recipient_discovery_service.dart';
import 'package:azaman/utils/amount_input.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/utils/currency_math.dart';
import 'package:azaman/utils/biometric_gate.dart';
import 'package:azaman/utils/durable_operation_registry.dart'
    show PendingFinancialOperationException;
import 'package:azaman/widgets/slide_to_confirm.dart';
import 'package:azaman/widgets/amount_keypad.dart';
import 'package:azaman/widgets/currency_wheel_toggle.dart';
import 'package:azaman/widgets/home/activity_actions.dart'
    show ActivityRecipient;
import 'package:azaman/widgets/odometer_number.dart';
import 'package:azaman/widgets/scale_tap.dart';
import 'package:azaman/widgets/send/recipient_selector_sheet.dart';
import 'package:azaman/widgets/send/send_result_panel.dart';
import 'package:azaman/services/az_sound.dart';

/// Composer stages — a deliberate review gate sits between amount entry
/// and the money action.
enum _SendStage { compose, review, sending, done, failed, unknown }

/// The seed for a chat-opened Send: the conversation's authoritative
/// participant identity (friendshipId is the financial key; username is
/// the canonical handle from the friend row, not a display-name guess).
/// Test seam type for the composer's money action. Production code never
/// sets it: the screen then commits through FriendService.sendFunds.
@visibleForTesting
typedef PeerSendOverride = Future<Map<String, dynamic>> Function(
    String friendshipId, double amount, String? reference, String token);

class SendMoneyScreen extends ConsumerStatefulWidget {
  const SendMoneyScreen(
      {super.key,
      this.initialRecipient,
      this.discovery,
      this.sendOverride,
      this.fxRateOverride})
      : seededFriend = null;

  /// Chat entry: the shared composer pre-seeded with the conversation's
  /// own recipient.
  const SendMoneyScreen.toFriend(
      {super.key,
      required SendRecipient recipient,
      this.discovery,
      this.sendOverride,
      this.fxRateOverride})
      : seededFriend = recipient,
        initialRecipient = null;

  /// "Send Again" seed from an activity record — carries an explicit AZM
  /// ID, which the composer resolves through the live identity contract.
  /// It is NEVER assumed transfer-capable: the backend rail is
  /// friendship-based, and an AZM-ID hit cannot be matched to a
  /// friendship (the identity service projects no User.id), so the
  /// resolved identity is shown honestly with its connection state.
  final ActivityRecipient? initialRecipient;

  /// Test seams. Production callers leave both null: the screen then uses
  /// the live discovery service and the canonical FriendService.sendFunds
  /// durable rail (never a mock).
  final RecipientDiscoveryService? discovery;
  final PeerSendOverride? sendOverride;

  final SendRecipient? seededFriend;

  /// Test/golden seam ONLY: a validated GHS-per-USDC rate for driving the
  /// GHS conversion deterministically. Production callers leave it null —
  /// the screen then reads the canonical FX snapshot (fxRateProvider,
  /// the same single-flight oracle request every other surface shares).
  @visibleForTesting
  final double? fxRateOverride;

  @override
  ConsumerState<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends ConsumerState<SendMoneyScreen> {
  final TextEditingController _referenceController = TextEditingController();

  _SendStage _stage = _SendStage.compose;

  // PR #165 review finding 1: the money action is confirmed through the
  // same audited safeguards as the legacy TransferModal — an intentional
  // SlideToConfirm gesture (a reflex tap can't fire it), then the opt-in
  // AzamanBiometricGate before the wire. The key re-arms the slider when
  // authentication is cancelled: a cancelled gate NEVER executes the
  // transfer.
  final GlobalKey<SlideToConfirmState> _slideKey =
      GlobalKey<SlideToConfirmState>();

  // The amount state machine: AmountInput.applyKey owns every invariant
  // (one decimal point, two fraction digits, no leading-zero buildup, no
  // negative — no sign key exists). An invalid amount can never exist.
  String _amountRaw = '';

  // GHANA-FIRST: the entry wheel always starts in GHS (the Send surface's
  // initial input denomination). The wheel is LOCAL to this composition —
  // it never writes the user's global display preference.
  int _entryIndex = 0;

  // The review FREEZE: the exact USDC wire amount the user reviewed, the
  // rate snapshot it was derived at, and the entered amount. Frozen at
  // review entry; the commit path uses ONLY the frozen wire amount, and
  // revalidates the rate snapshot before the wire.
  double? _frozenRate;
  double? _frozenUsdc;
  double? _frozenEntry;

  SendRecipient? _recipient;

  bool _seedLookupDone = false;
  bool _seedLookingUp = false;
  String? _error;

  // Quick amounts per entry unit — a '10' pill is NEVER ambiguous: the
  // label carries the unit, and GHS pills are cedi-scale, not USDC digits.
  List<double> get _quickAmounts =>
      _entryIndex == 0 ? const [20.0, 50.0, 100.0, 200.0] : const [5.0, 10.0, 20.0, 50.0];

  @override
  void initState() {
    super.initState();
    final seed = widget.seededFriend;
    if (seed != null) {
      _recipient = seed;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The friend list is the authoritative friendship source for the
      // recipient selector.
      ref.read(friendProvider).refreshAll();
      unawaited(refreshCanonicalBalance(ref));
      _resolveSeedIfAny();
    });
  }

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  /// "Send Again" seed → live AZM-ID lookup. The resolved identity is
  /// displayed with its honest connection state; the AZM-ID contract
  /// cannot recover a friendshipId, so a non-friend seed is never
  /// send-capable.
  Future<void> _resolveSeedIfAny() async {
    final seed = widget.initialRecipient;
    if (seed == null || _seedLookupDone) return;
    _seedLookupDone = true;
    final myAzamanId = ref.read(authProvider).user?.azamanId;
    final discovery =
        widget.discovery ?? RecipientDiscoveryService();
    setState(() => _seedLookingUp = true);
    final outcome =
        await discovery.lookupByAzamanId(seed.azamanId, myAzamanId: myAzamanId);
    if (!mounted) return;
    setState(() => _seedLookingUp = false);
    switch (outcome.status) {
      case AzmLookupStatus.found:
        setState(() => _recipient = outcome.recipient);
        break;
      case AzmLookupStatus.self:
        // The activity record was for a transfer to... this account.
        // Honest state, no recipient.
        setState(() => _error = "That AZM ID is yours — you can't send to yourself.");
        break;
      case AzmLookupStatus.notFound:
        setState(() => _error =
            'That AZM ID no longer resolves to an active account.');
        break;
      case AzmLookupStatus.malformed:
        setState(() => _error = 'That AZM ID is not valid.');
        break;
      case AzmLookupStatus.network:
        setState(() => _error =
            'Could not confirm that AZM ID. Check your connection.');
        break;
    }
  }

  double? get _amountValue => AmountInput.value(_amountRaw);
  String get _amountDisplay => AmountInput.display(_amountRaw);

  AzCurrency get _entryUnit => CurrencyCatalog.sendEntryUnits[_entryIndex];

  /// The validated canonical GHS-per-USDC rate for THIS screen. The test
  /// seam wins when present (deterministic suites/goldens); production
  /// reads the typed FX snapshot and never a legacy or fabricated rate.
  double? _liveRate() {
    final override = widget.fxRateOverride;
    if (override != null) {
      return CurrencyMath.isUsableRate(override) ? override : null;
    }
    final fx = ref.read(fxRateProvider).value;
    return (fx != null && fx.isUsable) ? fx.ghsPerUsdc : null;
  }

  /// The COMMIT-GATE rate reader. Unlike the sync [_liveRate], this
  /// awaits the oracle's CURRENT snapshot: after an invalidation a sync
  /// `AsyncValue.value` still returns the PREVIOUS retained figure, so a
  /// stale retained rate could silently satisfy revalidation. The money
  /// action must never be authorized by a retained value — it waits for
  /// the authoritative snapshot and fails closed on any error.
  Future<double?> _commitRate() async {
    final override = widget.fxRateOverride;
    if (override != null) {
      return CurrencyMath.isUsableRate(override) ? override : null;
    }
    try {
      // §2: the commit gate must not accept the provider's RETAINED
      // value — after a stale window the cached snapshot could still
      // hold an old, no-longer-fresh observation. Invalidate first so
      // the oracle is genuinely re-fetched and freshness is re-derived
      // from lastExternalSync at commit time, then await the NEW
      // snapshot. On any failure: null — never a silent pass.
      ref.invalidate(fxRateProvider);
      final fx = await ref.read(fxRateProvider.future);
      return (fx != null && fx.isUsable) ? fx.ghsPerUsdc : null;
    } catch (_) {
      return null; // the oracle itself failed: never a silent pass
    }
  }

  /// The EXACT USDC wire amount for [amount] in the current entry unit at
  /// [rate] — or null when the conversion cannot be established safely
  /// (unusable rate, non-finite input, or a result that would round to a
  /// zero transfer). This is the ONLY amount derivation path.
  double? _wireAmount({required double amount, required double? rate}) {
    // §1: a DIRECT USDC entry is already the wire amount and needs no
    // FX rate — CurrencyMath's same-unit path deliberately converts with
    // an unusable/absent rate. Only a GHS composition requires the rate
    // to derive the exact USDC amount (and fails closed without it).
    return CurrencyMath.convert(
      amount: amount,
      from: _entryUnit,
      to: CurrencyCatalog.usdc,
      ghsPerUsdc: rate ?? 0,
    );
  }

  /// Converts an existing entry to [next] (wheel switch). Returns null
  /// when the conversion cannot be established — the caller then refuses
  /// the switch instead of silently relabelling the digits.
  double? _convertEntry(AzCurrency next, double? rate) {
    final amount = _amountValue;
    if (amount == null) return null;
    if (rate == null) return null;
    return CurrencyMath.convert(
        amount: amount, from: _entryUnit, to: next, ghsPerUsdc: rate);
  }

  void _onEntryUnitChanged(int newIndex) {
    if (newIndex == _entryIndex) return;
    final next = CurrencyCatalog.sendEntryUnits[newIndex];
    final rate = _liveRate();

    // No amount typed yet — a pure denomination change, nothing to convert.
    if (_amountRaw.isEmpty) {
      setState(() => _entryIndex = newIndex);
      return;
    }

    final converted = _convertEntry(next, rate);
    if (converted == null) {
      // Fail closed: the switch is REFUSED — digits are never relabelled,
      // never silently zeroed, never converted at a fabricated rate.
      setState(() => _error = rate == null
          ? 'Exchange rate unavailable — the amount stays in '
              '${_entryUnit.symbol}. Enter it in ${next.symbol} if needed.'
          : 'That amount converts to less than the smallest ${next.symbol} '
              'unit — enter a larger amount.');
      return;
    }
    AzamanHaptics.toggle();
    setState(() {
      _entryIndex = newIndex;
      _amountRaw = _formatQuick(converted);
      _error = null;
    });
  }

  bool get _canProgress =>
      _amountValue != null && _recipient != null && _recipient!.canReceive;

  void _onKeypadKey(String key) {
    setState(() => _amountRaw = AmountInput.applyKey(_amountRaw, key));
  }

  Future<void> _chooseRecipient() async {
    if (_stage == _SendStage.sending) return;
    AzamanHaptics.nav();
    final picked = await showRecipientSelectorSheet(
      context,
      currentRecipient: _recipient,
      discovery: widget.discovery,
    );
    if (picked != null && mounted) {
      setState(() {
        _recipient = picked;
        _error = null;
      });
    }
  }

  void _clearRecipient() {
    if (_stage == _SendStage.sending) return;
    AzamanHaptics.nav();
    setState(() {
      _recipient = null;
      _error = null;
    });
  }

  void _openReview() {
    if (!_canProgress) return;
    final amount = _amountValue!;
    final rate = _liveRate();

    // Fail closed: a GHS composition whose USDC wire amount cannot be
    // derived at a VALID rate never reaches review — no fake amount, no
    // zero conversion, no silent use of a display-only rate.
    final wire = _wireAmount(amount: amount, rate: rate);
    if (wire == null) {
      setState(() => _error = _entryUnit == CurrencyCatalog.ghs
          ? 'Exchange rate unavailable — enter the amount in USDC instead, '
              'or try again in a moment.'
          : 'Enter an amount greater than zero to continue.');
      return;
    }

    AzamanHaptics.confirm();
    setState(() {
      // THE FREEZE: the exact wire amount + the rate snapshot it was
      // derived at. Review and commit use only these frozen numbers.
      _frozenRate = rate;
      _frozenUsdc = wire;
      _frozenEntry = amount;
      _stage = _SendStage.review;
      _error = null;
    });
  }

  void _backToCompose() {
    // PR #165 review finding 2: while the outcome of a committed attempt
    // is UNKNOWN, the amount/recipient/reference are FROZEN — editing the
    // composition before the durable operation is resolved could silently
    // start a materially different financial operation while the prior
    // one is unresolved (and fails closed at the service layer if forced).
    if (_stage == _SendStage.sending || _stage == _SendStage.unknown) return;
    // Edit path: the entered amount AND the recipient are preserved —
    // going back never discards the user's composition.
    setState(() => _stage = _SendStage.compose);
  }

  // ── The money action ────────────────────────────────────────────────────

  /// The ONLY path into the money action. Reached exclusively from the
  /// SlideToConfirm gesture on the review stage, never from a bare tap.
  /// The biometric gate runs FIRST when the user has enabled biometric
  /// lock; cancellation re-arms the slider and NEVER executes the
  /// transfer (the send money screen's financial action inherits the
  /// audited TransferModal contract, PR #165 review finding 1).
  void _confirmSlide() {
    AzamanBiometricGate.runSync(
      context,
      _commit,
      reason: 'Authenticate to send funds',
      onCancelled: () => _slideKey.currentState?.reset(),
    );
  }

  /// Commits the transfer through the canonical durable rail. Duplicate
  /// submission is blocked here AND by the disabled slide AND by the
  /// backend's idempotency claim — widget-level protection is never the
  /// only layer.
  Future<void> _commit() async {
    final recipient = _recipient;
    final amount = _frozenUsdc; // the EXACT reviewed wire amount — never recomputed
    if (_stage == _SendStage.sending) return;
    if (recipient == null || !recipient.canReceive || amount == null) return;

    // Quote revalidation (fail closed): a GHS-derived wire amount is only
    // valid at the rate the user reviewed. If the live rate has moved or
    // become unusable, the composition returns to compose for
    // recalculation and a FRESH review — the confirmed amount is never
    // silently altered after confirmation.
    if (_entryUnit == CurrencyCatalog.ghs) {
      final live = await _commitRate();
      if (!mounted) return;
      if (live == null || _frozenRate == null || live != _frozenRate) {
        if (!mounted) return;
        setState(() {
          _stage = _SendStage.compose;
          _frozenRate = null;
          _frozenUsdc = null;
          _frozenEntry = null;
          _error = 'The exchange rate changed since you reviewed the '
              'amount. Review the new amount before sending.';
        });
        _rearmRetrySlider();
        AzamanHaptics.warn();
        return;
      }
    }

    final myUsername = ref.read(authProvider).user?.username;
    if (myUsername != null && myUsername == recipient.username) {
      setState(() => _error = "That's you — you can't send to yourself.");
      _rearmRetrySlider();
      return;
    }

    final token = ref.read(authProvider).user?.token;
    if (token == null || token.isEmpty) {
      setState(() =>
          _error = 'Your session needs to be refreshed. Re-open Send to continue.');
      _rearmRetrySlider();
      return;
    }

    final reference = _referenceController.text.trim();

    setState(() {
      _stage = _SendStage.sending;
      _error = null;
    });
    AzamanHaptics.confirm();

    try {
      final commit = widget.sendOverride;
      if (commit != null) {
        await commit(recipient.friendshipId!, amount,
            reference.isEmpty ? null : reference, token);
      } else {
        // The canonical durable rail — protected by require2FA and the
        // idempotency middleware, with the FinancialOperation lifecycle
        // owned by postFinancial. Never bypassed in production.
        await FriendService().sendFunds(
          recipient.friendshipId!,
          amount,
          reference.isEmpty ? null : reference,
          token,
        );
      }
      // 2xx from the canonical service is the only success signal.
      AzamanHaptics.commit();
      AzSound.success();
      if (!mounted) return;
      setState(() => _stage = _SendStage.done);
      // Authoritative account state: re-hydrate from the backend. The
      // balance shown is never locally mutated.
      unawaited(ref.read(authProvider).fetchUserDetails());
      unawaited(ref.read(friendProvider).fetchFriends());
    } on PendingFinancialOperationException {
      // Fail-closed fingerprint change: the flow still holds an UNRESOLVED
      // send and the request changed. Zero wire traffic occurred. The
      // honest path: retry the SAME transfer (the slider is armed for
      // exactly that) so the durable registry resolves the pending
      // instance; a materially different send stays refused until then.
      if (!mounted) return;
      setState(() {
        _stage = _SendStage.unknown;
        _error =
            'A previous transfer of this kind is still resolving. Retry '
            'the same transfer to resolve it first — no new transfer was '
            'started.';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      _classifyApiException(e);
    } on SocketException {
      _onAmbiguousOutcome();
    } on TimeoutException {
      _onAmbiguousOutcome();
    } on HttpException {
      _onAmbiguousOutcome();
    } catch (e) {
      if (!mounted) return;
      // FriendService throws Exception('Failed to send funds: <body>') on
      // non-2xx — the body's own `message` is the honest user-facing text
      // when present; anything else stays generic (no internals leaked).
      final raw = e.toString();
      if (raw.contains('ClientException') || raw.contains('Connection')) {
        _onAmbiguousOutcome();
        return;
      }
      final msgMatch =
          RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(raw)?.group(1);
      if (msgMatch != null) {
        setState(() {
          _stage = _SendStage.failed;
          _error = msgMatch;
        });
      } else {
        setState(() {
          _stage = _SendStage.failed;
          _error = 'The transfer could not be completed. Please try again.';
        });
      }
    }
    // Recoverability: every terminal outcome except success leaves the
    // slide armed for the identical retry. The success path builds the
    // done stage (no slider), so it is excluded by design.
    if (_stage == _SendStage.failed || _stage == _SendStage.unknown) {
      _rearmRetrySlider();
    }
  }

  void _classifyApiException(ApiException e) {
    final statusCode = e.statusCode;
    final body = e.message;
    // PR #165 review finding 2: 409 (idempotent replay collision), 429
    // (rate limited — the request may have been processed before the
    // limiter answered) and every 5xx are UNKNOWN outcomes unless the
    // financial contract proves otherwise. The durable layer RETAINS the
    // operation identity for exactly these statuses
    // (postFinancial: retire on 2xx and definitive pre-economic 4xx,
    // retain on 401/409/429, 5xx and network loss) — the screen must not
    // contradict it by calling the transfer "failed" and offering edits.
    if (statusCode == 409 || statusCode == 429 || statusCode >= 500) {
      if (!mounted) return;
      setState(() => _stage = _SendStage.unknown);
      return;
    }
    // 2FA / step-up denial: the rail is require2FA()-protected.
    if (statusCode == 401 ||
        body.contains('2FA') ||
        body.toLowerCase().contains('two-factor')) {
      setState(() {
        _stage = _SendStage.failed;
        _error =
            'Two-factor confirmation is required for transfers. Verify and try again.';
      });
      return;
    }
    if (body.contains('INSUFFICIENT_FUNDS') ||
        body.toLowerCase().contains('insufficient')) {
      setState(() {
        _stage = _SendStage.failed;
        _error = 'Insufficient balance for this transfer.';
      });
      return;
    }
    if (statusCode == 403) {
      setState(() {
        _stage = _SendStage.failed;
        _error =
            'The transfer was blocked. Check that you are connected, or contact support.';
      });
      return;
    }
    if (statusCode == 404) {
      setState(() {
        _stage = _SendStage.failed;
        _error =
            'That connection no longer exists. Refresh your friends and try again.';
      });
      return;
    }
    setState(() {
      _stage = _SendStage.failed;
      _error = 'The transfer could not be completed. Please try again.';
    });
  }

  /// The outcome is UNKNOWN — the request may have committed before the
  /// connection dropped. NEVER claim failure. Retry re-runs the SAME
  /// durable operation identity (FriendService's per-friendship flow
  /// ref), so a committed transfer replays its original result instead
  /// of executing twice.
  void _onAmbiguousOutcome() {
    if (!mounted) return;
    setState(() => _stage = _SendStage.unknown);
  }

  // PR #165 review finding 2 (recoverability): every retryable outcome
  // must leave the slide re-armed. didUpdateWidget re-arms on the
  // isLoading true->false edge, but when the failure lands before a
  // sending frame renders (an immediate throw, or a synchronous
  // client-side refusal), the edge never fires and the slider would stay
  // locked at _confirmed=true with no way to retry. Reset explicitly.
  void _rearmRetrySlider() {
    final st = _slideKey.currentState;
    if (st != null && st.mounted) st.reset();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final balance = ref.watch(authProvider).user?.availableBalance ?? 0.0;
    final myAzamanId = ref.watch(authProvider).user?.azamanId ?? '';

    // PR #165 review finding 2: while the outcome of the committed
    // attempt is UNKNOWN, ordinary navigation (system back, edge swipe)
    // must never silently abandon the unresolved operation. The pop is
    // intercepted with an explicit decision: retry the exact operation
    // (same durable identity) or acknowledge leaving it pending.
    return PopScope(
      canPop: _stage != _SendStage.unknown,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _stage != _SendStage.unknown || !mounted) return;
        _showUnknownPendingDialog();
      },
      child: Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        key: const ValueKey('send-app-bar'),
        backgroundColor: colors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: _stage == _SendStage.review ||
                _stage == _SendStage.sending ||
                _stage == _SendStage.unknown
            ? IconButton(
                key: const ValueKey('send-edit-back'),
                icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
                // Disabled mid-flight AND while the outcome is UNKNOWN —
                // the composition is frozen until the durable operation
                // resolves (PR #165 review finding 2).
                onPressed: (_stage == _SendStage.sending ||
                        _stage == _SendStage.unknown)
                    ? null
                    : _backToCompose,
                tooltip: 'Back to edit',
              )
            : IconButton(
                icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Text(
          _stage == _SendStage.review ||
                  _stage == _SendStage.sending ||
                  _stage == _SendStage.unknown
              ? 'Review transfer'
              : 'Send',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: switch (_stage) {
          _SendStage.done => _buildDone(colors),
          _SendStage.compose => LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 620;
                return _buildCompose(colors, compact, balance, myAzamanId);
              },
            ),
          _ => _buildReview(colors),
        },
      ),
      ),
    );
  }

  /// The unknown-outcome pop decision: retry the exact operation (same
  /// durable identity) or explicitly acknowledge leaving it pending on
  /// the account. Leaving is never silent (PR #165 review finding 2).
  Future<void> _showUnknownPendingDialog() async {
    final colors = ref.read(themeProvider).colors;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('send-unknown-leave-dialog'),
        backgroundColor: colors.card,
        title: Text('This transfer is still pending',
            key: const ValueKey('send-unknown-dialog-title'),
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800)),
        content: Text(
          'We could not confirm the result yet. Retrying re-runs the exact '
          'same transfer and never double-sends it. Leaving now keeps it '
          'pending on your account.',
          key: const ValueKey('send-unknown-dialog-body'),
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            key: const ValueKey('send-unknown-dialog-retry'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Retry transfer',
                style: TextStyle(
                    color: colors.accent, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            key: const ValueKey('send-unknown-dialog-leave'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Leave pending',
                style: TextStyle(
                    color: colors.textTertiary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (leave != true) {
      // Retry resolves the SAME durable operation — fields are frozen so
      // the body is byte-identical.
      if (mounted && _stage == _SendStage.unknown) _commit();
    } else if (mounted && _stage == _SendStage.unknown) {
      // Acknowledged abandonment: leave the pending operation on the
      // account and pop the composer.
      _stage = _SendStage.compose; // release the PopScope guard
      Navigator.of(context).pop(true);
    }
  }

  // ── Compose stage: the Add Cash grammar ─────────────────────────────────

  Widget _buildCompose(
      AzamanColors colors, bool compact, double balance, String myAzamanId) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final recipient = _recipient;
    // The chip is a DISPLAY surface: it follows the user's global display
    // preference (never the local entry wheel) and shows the ledger truth
    // (USDC) alongside its equivalent when the rate is valid.
    final pref = ref.watch(currencyProvider);
    final chipRate = _liveRate();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: _BalanceChip(
              colors: colors,
              balance: balance,
              myAzamanId: myAzamanId,
              ghsFirst: pref == DisplayCurrency.ghs,
              rate: chipRate),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Amount-first composition, the Add Cash anchor.
                Padding(
                  padding: EdgeInsets.fromLTRB(4, compact ? 4 : 10, 4, 0),
                  child: SizedBox(
                    width: double.infinity,
                    // GHANA-FIRST: the inline currency wheel rides
                    // immediately before the amount. It chooses the
                    // denomination the digits represent (LOCAL to
                    // this transaction — never the global display
                    // preference) and a switch CONVERTS the amount.
                    //
                    // VERTICAL roller: the selected chip sits fully
                    // visible with the neighbour units peeking above/
                    // below, never cropped by the row. The wheel rides
                    // OUTSIDE the amount's scale-down box so its 44dp
                    // touch target and published 74×72 geometry hold at
                    // every width — only the FIGURE ever shrinks to fit.
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: CurrencyWheelToggle(
                            key: const ValueKey('send-amount-currency'),
                            axis: CurrencyWheelAxis.vertical,
                            options: CurrencyCatalog.sendEntryUnits,
                            selectedIndex: _entryIndex,
                            onChanged: _onEntryUnitChanged,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: OdometerNumber(
                              value: _amountDisplay,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: compact ? 48 : 60,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.0,
                                height: 1.0,
                              ),
                              semanticsLabel:
                                  '$_amountDisplay ${_entryUnit.symbol}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Live paired equivalent — updates while typing, at the
                // current valid rate. Compose-only: Review freezes.
                Builder(builder: (_) {
                  final amount = _amountValue;
                  if (amount == null) return const SizedBox.shrink();
                  final rate = _liveRate();
                  final other = _entryUnit == CurrencyCatalog.ghs
                      ? CurrencyCatalog.usdc
                      : CurrencyCatalog.ghs;
                  final converted = CurrencyMath.convert(
                      amount: amount,
                      from: _entryUnit,
                      to: other,
                      ghsPerUsdc: rate ?? 0);
                  if (converted == null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        '${other.code} equivalent unavailable — rate not loaded yet',
                        key: const ValueKey('send-amount-equivalent'),
                        style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4),
                    child: Text(
                      '≈ ${other == CurrencyCatalog.ghs ? AzMoney.ghs(converted) : AzMoney.usdc(converted)}'
                      '${other == CurrencyCatalog.ghs ? '' : ' — the reviewed transfer is in USDC'}',
                      key: const ValueKey('send-amount-equivalent'),
                      style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                  );
                }),
                const SizedBox(height: 12),

                // Quick amounts — denominated in the wheel's selected unit.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final amt in _quickAmounts)
                        _QuickAmountPill(
                          colors: colors,
                          amount: amt,
                          unit: _entryUnit,
                          selected: _amountRaw == _formatQuick(amt),
                          onTap: () {
                            AzamanHaptics.toggle();
                            setState(() => _amountRaw = _formatQuick(amt));
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ONE dedicated recipient row — never an inline list.
                _RecipientField(
                  colors: colors,
                  recipient: recipient,
                  lookingUp: _seedLookingUp,
                  onChoose: _chooseRecipient,
                  onClear: _clearRecipient,
                ),

                if (_error != null) ...[
                  const SizedBox(height: 10),
                  _ErrorText(colors: colors, message: _error!),
                ],
              ],
            ),
          ),
        ),

        // Keypad + CTA anchored to the bottom; never scrolls, never hides
        // behind the bottom navigation (safe-area inset included).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: AmountKeypad(
            onKey: _onKeypadKey,
            enabled: _stage != _SendStage.sending,
            rowHeight: compact ? 46 : 54,
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottomInset),
          child: _PrimaryAction(
            colors: colors,
            label: 'Review',
            enabled: _canProgress,
            onTap: _openReview,
            semanticsLabel: _canProgress
                ? 'Review transfer of $_amountDisplay USDC'
                : 'Enter an amount and choose a recipient to continue',
          ),
        ),
      ],
    );
  }

  static String _formatQuick(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  // ── Review stage ────────────────────────────────────────────────────────

  Widget _buildReview(AzamanColors colors) {
    final recipient = _recipient!;
    // THE FREEZE: review reads only the frozen snapshot — a live rate move
    // can never silently rewrite what the user is looking at. The commit
    // path revalidates the snapshot before the wire.
    final amount = _frozenUsdc ?? _amountValue!;
    final entryAmount = _frozenEntry ?? _amountValue!;
    final entryUnit = _entryUnit;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final reference = _referenceController.text.trim();
    final sending = _stage == _SendStage.sending;
    final failed = _stage == _SendStage.failed;
    final unknown = _stage == _SendStage.unknown;

    final ctaLabel = sending
        ? 'Sending…'
        : failed
            ? 'Retry transfer'
            : unknown
                ? 'Retry transfer'
                : 'Send ${amount.toStringAsFixed(2)} USDC';

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Summary card.
                Container(
                  key: const ValueKey('send-review-card'),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TO',
                          style: TextStyle(
                              color: colors.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _Avatar(
                              colors: colors,
                              url: recipient.avatarUrl,
                              name: recipient.name),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(recipient.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                if (recipient.hasUsername)
                                  Text(
                                    '@${recipient.username!}',
                                    key: const ValueKey('send-review-handle'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 13),
                                  ),
                                if (recipient.azamanId != null) ...[
                                  const SizedBox(height: 2),
                                  Text(recipient.azamanId!,
                                      style: TextStyle(
                                          color: colors.textTertiary,
                                          fontSize: 12)),
                                ],
                              ],
                            ),
                          ),
                          _FriendChip(colors: colors),
                        ],
                      ),
                      const Divider(height: 28),
                      // GHANA-FIRST REVIEW: the entered amount leads in
                      // the denomination the user chose; the EXACT USDC
                      // amount the backend will transfer is identified
                      // explicitly right under it, plus the frozen rate
                      // it was derived at.
                      // §4 — the pair is always shown under BOTH entry
                      // units: the entry denomination leads; the exact
                      // USDC wire amount (the only thing the backend
                      // transfers) is identified explicitly second.
                      if (entryUnit == CurrencyCatalog.ghs) ...[
                        _ReviewRow(
                            colors: colors,
                            label: 'Amount',
                            value: AzMoney.ghs(entryAmount),
                            valueKey:
                                const ValueKey('send-review-entry-amount'),
                            emphasized: true),
                        const SizedBox(height: 12),
                        _ReviewRow(
                            colors: colors,
                            label: 'You send (USDC)',
                            value: '${amount.toStringAsFixed(2)} USDC',
                            valueKey:
                                const ValueKey('send-review-amount'),
                            emphasized: true),
                        const SizedBox(height: 12),
                        _ReviewRow(
                            colors: colors,
                            // §2: honest labelling — this is the rate the
                            // USDC amount was DERIVED at, not a guaranteed
                            // provider execution quote.
                            label: 'Rate used to derive the USDC amount',
                            value:
                                '1 USDC = ${AzMoney.ghs(_frozenRate ?? 0)}',
                            valueKey:
                                const ValueKey('send-review-rate')),
                        const SizedBox(height: 12),
                      ] else ...[
                        _ReviewRow(
                            colors: colors,
                            label: 'Amount',
                            value: '${amount.toStringAsFixed(2)} USDC',
                            valueKey:
                                const ValueKey('send-review-amount'),
                            emphasized: true),
                        const SizedBox(height: 12),
                        _ReviewRow(
                            colors: colors,
                            // Direct USDC entry: the GHS equivalent is a
                            // DISPLAY value — it is never presented as a
                            // separate GHS settlement. Unavailable rate →
                            // the equivalent is named unavailable, never a
                            // false GH₵ 0.00.
                            label: 'GHS equivalent',
                            value: (_frozenRate != null &&
                                    CurrencyMath.isUsableRate(_frozenRate!))
                                ? AzMoney.ghs(CurrencyMath.convert(
                                    amount: amount,
                                    from: CurrencyCatalog.usdc,
                                    to: CurrencyCatalog.ghs,
                                    ghsPerUsdc: _frozenRate!) ?? 0)
                                : 'Unavailable — rate not loaded',
                            valueKey: const ValueKey(
                                'send-review-ghs-equivalent')),
                        const SizedBox(height: 12),
                        if (_frozenRate != null &&
                            CurrencyMath.isUsableRate(_frozenRate!))
                          _ReviewRow(
                              colors: colors,
                              label: 'Rate used for the equivalent',
                              value:
                                  '1 USDC = ${AzMoney.ghs(_frozenRate!)}',
                              valueKey:
                                  const ValueKey('send-review-rate')),
                      ],
                      const SizedBox(height: 12),
                      // Fee truth: the backend rail records feeUsdc: 0 for
                      // both parties (peerTransferController.sendFunds) —
                      // nothing is invented here.
                      _ReviewRow(colors: colors, label: 'Fee', value: 'No fee'),
                      if (reference.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _ReviewRow(
                            colors: colors, label: 'Reference', value: reference),
                      ],
                    ],
                  ),
                ),

                // Optional reference — travels as the wire's `reference`.
                if (!sending && !failed && !unknown) ...[
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('send-reference-field'),
                    controller: _referenceController,
                    maxLength: 80,
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Add a reference (optional)',
                      counterText: '',
                      hintStyle: TextStyle(color: colors.textTertiary),
                      filled: true,
                      fillColor: colors.card,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],

                if (sending) ...[
                  const SizedBox(height: 14),
                  _SendingBanner(colors: colors),
                ],
                if (unknown) ...[
                  const SizedBox(height: 14),
                  _UnknownBanner(colors: colors),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  _ErrorText(colors: colors, message: _error!),
                ],

                const SizedBox(height: 18),

                // Edit preserves everything — review is deliberate, not a
                // trap. Never visible mid-flight AND never while the
                // outcome is UNKNOWN (the composition is frozen until the
                // unresolved operation resolves — PR #165 review finding 2).
                if (!sending && !unknown)
                  ScaleTap(
                    onTap: _backToCompose,
                    child: Text('Edit amount or recipient',
                        key: const ValueKey('send-review-edit'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: colors.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + bottomInset),
          child: SlideToConfirm(
            key: _slideKey,
            // PR #165 review finding 1: the money action requires the
            // same audited safeguards as the legacy TransferModal —
            // SlideToConfirm (a reflex tap cannot fire it; the thumb
            // snaps back under threshold) with the opt-in
            // AzamanBiometricGate in _confirmSlide. In flight the
            // slider shows progress and rejects drags, so a duplicate
            // gesture can never re-enter _commit. The unknown state
            // re-arms the SAME durable operation identity on retry.
            text: ctaLabel,
            backgroundColor: colors.card,
            thumbColor: colors.accent,
            onConfirmed: _confirmSlide,
            isLoading: sending,
            enabled: !sending,
          ),
        ),
      ],
    );
  }

  // ── Result stages ───────────────────────────────────────────────────────

  Widget _buildDone(AzamanColors colors) {
    final recipient = _recipient;
    final amount = _frozenUsdc ?? _amountValue;
    final entryAmount = _frozenEntry ?? _amountValue;
    final wasGhs = _entryUnit == CurrencyCatalog.ghs;
    return SendResultPanel(
      colors: colors,
      // GHANA-FIRST SUCCESS: the amount the user entered leads; the USDC
      // actually transferred on the wire is identified separately and
      // labelled as the transfer — an equivalent is never presented as
      // proof that funds settled in that currency.
      amountText: wasGhs
          ? AzMoney.ghs(entryAmount ?? 0)
          : '${(amount ?? 0).toStringAsFixed(2)} USDC',
      // §4: under USDC entry the cedi equivalent rides second when the
      // frozen rate is valid; an unavailable rate is named honestly — a
      // false GH₵ 0.00 equivalent is never shown. The label keeps the
      // truth clear: the WIRE amount is the USDC one.
      secondaryAmountText: wasGhs
          ? '${(amount ?? 0).toStringAsFixed(2)} USDC'
          : (_frozenRate != null && CurrencyMath.isUsableRate(_frozenRate!)
              ? AzMoney.ghs(CurrencyMath.convert(
                  amount: amount ?? 0,
                  from: CurrencyCatalog.usdc,
                  to: CurrencyCatalog.ghs,
                  ghsPerUsdc: _frozenRate!) ?? 0)
              : 'GHS equivalent unavailable — rate not loaded'),
      secondaryAmountLabel:
          wasGhs ? 'Transferred on the wire as' : 'Equivalent in cedis (display only — the transfer settled in USDC)',
      recipientName: recipient?.name ?? '',
      // RAW canonical username (unprefixed) — the panel's AtHandle
      // formatter adds the glyph at most once, or nothing when there is
      // no real handle. '@@ama' can never render again.
      recipientUsername: recipient?.username ?? '',
      onDone: () {
        // Correct navigation semantics: pop the composer with a positive
        // result so the originating screen (Home or chat) refreshes.
        Navigator.of(context).pop(true);
      },
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────

class _BalanceChip extends StatelessWidget {
  const _BalanceChip({required this.colors, required this.balance, required this.myAzamanId, required this.ghsFirst, required this.rate});
  final AzamanColors colors;
  final double balance;
  final String myAzamanId;

  /// Global display preference ordering. The USDC ledger value stays the
  /// financial authority either way — only the presentation order moves.
  final bool ghsFirst;

  /// Validated GHS-per-USDC rate, or null when no honest equivalent can
  /// be shown (then the chip shows the ledger value alone).
  final double? rate;

  @override
  Widget build(BuildContext context) {
    // Ghana-first: with the GHS preference the cedi equivalent leads and
    // the actual USDC ledger balance follows. Reversed when the user has
    // deliberately selected USDC. No rate → ledger value only, no fake.
    final hasRate = rate != null && CurrencyMath.isUsableRate(rate!);
    final ghsText = hasRate ? AzMoney.ghs(balance * rate!) : null;
    final ledgerText = '${balance.toStringAsFixed(2)} USDC';
    final available = ghsFirst
        ? (ghsText == null
            ? 'Available: $ledgerText'
            : 'Available: $ghsText · $ledgerText')
        : (ghsText == null
            ? 'Available: $ledgerText'
            : 'Available: $ledgerText · $ghsText');
    return Container(
      key: const ValueKey('send-balance-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.accentSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(Icons.wallet_outlined, size: 16, color: colors.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            available,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: colors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700),
          ),
        ),
        if (myAzamanId.isNotEmpty)
          Flexible(
            child: Text('Your ID: $myAzamanId',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}

class _QuickAmountPill extends StatelessWidget {
  const _QuickAmountPill(
      {required this.colors, required this.amount, required this.unit, required this.selected, required this.onTap});
  final AzamanColors colors;
  final double amount;
  final AzCurrency unit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The label ALWAYS names the unit: 'GH₵ 100' is never misread as
    // '100 USDC' when the wheel has moved.
    final label = amount == amount.truncateToDouble()
        ? '${unit.symbol}\u00A0${amount.toStringAsFixed(0)}'
        : '${unit.symbol}\u00A0${amount.toStringAsFixed(2)}';
    final face = selected ? colors.accent : colors.card;
    final textColor = selected ? colors.onAccent : colors.textSecondary;
    return ScaleTap(
      key: ValueKey('send-quick-$label'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: face,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? colors.accent : colors.divider),
        ),
        child: Text(label,
            style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _RecipientField extends StatelessWidget {
  const _RecipientField({
    required this.colors,
    required this.recipient,
    required this.lookingUp,
    required this.onChoose,
    required this.onClear,
  });

  final AzamanColors colors;
  final SendRecipient? recipient;
  final bool lookingUp;
  final VoidCallback onChoose;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final r = recipient;
    if (r == null) {
      final body = lookingUp
          ? Row(children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text('Resolving AZM ID…',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            ])
          : Row(children: [
              Icon(Icons.person_add_outlined,
                  size: 20, color: colors.textTertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Choose recipient',
                    style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.chevron_right, size: 20, color: colors.textTertiary),
            ]);
      return ScaleTap(
        key: const ValueKey('send-recipient-field'),
        onTap: onChoose,
        child: Semantics(
          button: true,
          label: 'Choose recipient',
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.divider),
            ),
            child: body,
          ),
        ),
      );
    }

    // Confirmed recipient: resolved identity + obvious Change and Clear.
    return Container(
      key: const ValueKey('send-recipient-confirmed'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: r.canReceive ? colors.accent : colors.danger),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(colors: colors, url: r.avatarUrl, name: r.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      // PR #165 review finding 4: honest identity line. A
                      // username-less AZM lookup shows displayName + the
                      // real AZM ID — the display name is NEVER
                      // manufactured into an `@handle`.
                      r.identityLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: colors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              r.canReceive
                  ? _FriendChip(colors: colors)
                  : _NotConnectedChip(colors: colors),
            ],
          ),
          if (!r.canReceive) ...[
            const SizedBox(height: 8),
            Text(
              'You are not connected yet. Peer sends require an accepted friendship — this recipient cannot receive this transfer.',
              style: TextStyle(color: colors.textTertiary, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ScaleTap(
                key: const ValueKey('send-recipient-change'),
                onTap: onChoose,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  child: Text('Change',
                      style: TextStyle(
                          color: colors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 4),
              ScaleTap(
                key: const ValueKey('send-recipient-clear'),
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  child: Text('Clear',
                      style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FriendChip extends StatelessWidget {
  const _FriendChip({required this.colors});
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('send-friend-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.accentSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('Friend',
          style: TextStyle(
              color: colors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _NotConnectedChip extends StatelessWidget {
  const _NotConnectedChip({required this.colors});
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('send-not-connected-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('Not connected',
          style: TextStyle(
              color: colors.danger, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.colors, this.url, required this.name});
  final AzamanColors colors;
  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final circle = CircleAvatar(
      radius: 20,
      backgroundColor: colors.accentSurface,
      backgroundImage: url != null ? NetworkImage(url!) : null,
      child: url == null
          ? Text(initial,
              style: TextStyle(
                  color: colors.accent,
                  fontSize: 16,
                  fontWeight: FontWeight.w700))
          : null,
    );
    // The avatar INITIAL is presentation-only — it is never a recipient
    // identity (see SendRecipient's placeholder guard).
    return Semantics(label: name, image: url != null, child: circle);
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.colors, required this.label, required this.value, this.valueKey, this.emphasized = false});
  final AzamanColors colors;
  final String label;
  final String value;
  final Key? valueKey;

  /// The primary figures (entered amount, wire amount) render heavier so
  /// the hierarchy is unmistakable — per the GHS-first review contract.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(label,
            style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const Spacer(),
        Flexible(
          child: Text(value,
              key: valueKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: emphasized ? 16.5 : 15,
                  fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700)),
        ),
      ],
    );
  }
}

/// Ambiguous-outcome banner: the transfer may ALREADY have committed.
/// Never claims failure; retrying is safe (same durable identity) but the
/// user is told to check their history first.
class _UnknownBanner extends StatelessWidget {
  const _UnknownBanner({required this.colors});
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('send-unknown-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(Icons.help_outline, size: 18, color: colors.danger),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'We couldn\'t confirm the transfer — it may have gone through. '
            'Check your balance and history before retrying; a retry never '
            'double-sends the same transfer.',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ),
      ]),
    );
  }
}

class _SendingBanner extends StatelessWidget {
  const _SendingBanner({required this.colors});
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('send-sending-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Sending… keep this screen open.',
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.colors, required this.message});
  final AzamanColors colors;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      key: const ValueKey('send-error-text'),
      style: TextStyle(color: colors.danger, fontSize: 12),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.colors,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.semanticsLabel,
  });

  final AzamanColors colors;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel ?? label,
      child: ScaleTap(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? colors.accent : colors.divider,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            key: ValueKey('send-cta-$label'),
            style: TextStyle(
              color: enabled ? colors.onAccent : colors.textTertiary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
