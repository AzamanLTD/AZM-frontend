// =============================================================================
// AZAMAN — CARD TRANSFER (Balance ↔ Visa)  — compact transfer surface
//
// Opened from the Home deck's seam control. A Receive-like full-height
// surface: pull-down dismissible, bottom tabs "To Visa" / "From Visa" that
// answer BOTH taps and horizontal swipes (one TabController), and the two
// cards rendered as PURPOSE-DESIGNED COMPACT side-by-side previews
// ([CompactCardPair] — Workstream C, 2026-10-20): the full-height Home
// card renderers are NOT squeezed into half-width boxes; the pair is
// drawn for a ~150×96 tile footprint so the vertical priority belongs to
// the amount, keypad, review summary and action area.
//
// ENTRANCE: the pair arrives once, on route entry, via the wallet-to-
// transfer entrance ([CardTransferEntrance]) — the cards rise out of the
// pocket and settle. It plays ONCE, never replays on rebuilds or tab
// changes, and reduced motion lands on the end state with no motion.
//
// STAGES: amount (AmountKeypad reuse + the #165 currency wheel, clear
// amount/currency, honestly-labelled rail equivalent, source and
// destination) → review (the full transfer statement).
//
// CURRENCY TRUTH (PR #165 services, no duplication): the amount may be
// entered in GHS or USDC through the shared [CurrencyWheelToggle] and
// [CurrencyMath] at the freshness-gated [FxRateSnapshot] rate. The AZM
// Visa rail remains USDC-denominated: a GHS entry is DISPLAYED with an
// honestly-labelled USDC rail equivalent ("preview"), and nothing here
// claims GHS settlement or sends any amount anywhere — the wheel is a
// preview denomination, never an executable settlement currency.
//
// ── HARD FINANCIAL CAPABILITY GATE ──────────────────────────────────────────
// The current card programme is the demo-only [DemoCardProgramme]; the card
// on Home is a SAMPLE surface. This screen therefore NEVER calls a card
// funding endpoint, NEVER mutates balances locally, and NEVER displays a
// successful transfer. Submission in THIS BUILD is structurally disabled —
// there is no transfer execution path at all, so no capability flag alone
// can imply that a transfer can be made: the gate copy is identical in
// every state, and the submit control never enables. When a REAL card
// programme, the backend transfer ledger / settlement / idempotency
// contract, and the funding rail are proven together, THAT change wires
// [AzmCardProgramme.supportsTransfers] to a real submit — not this one.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/currency_catalog.dart';
import 'package:azaman/providers/currency_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/nav_band_clearance.dart';
import 'package:azaman/utils/amount_input.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/utils/currency_math.dart';
import 'package:azaman/widgets/amount_keypad.dart';
import 'package:azaman/widgets/card_transfer/compact_card_pair.dart';
import 'package:azaman/widgets/home/azm_visa_card.dart'
    show azmCardProgrammeProvider;
import 'package:azaman/widgets/currency_wheel_toggle.dart';
import 'package:azaman/widgets/pull_down_dismissible_surface.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:go_router/go_router.dart' show GoRouterHelper;

export 'package:azaman/widgets/card_transfer/compact_card_pair.dart'
    show DirectionalMoneyFlow, DirectionalMoneyFlowState;

enum CardTransferDirection { toVisa, fromVisa }

enum _Stage { amount, review }

/// The transfer direction's human labels — the single source for every
/// surface (tabs, review statement, semantics).
extension CardTransferDirectionCopy on CardTransferDirection {
  String get tabLabel =>
      this == CardTransferDirection.toVisa ? 'To Visa' : 'From Visa';

  String get sourceLabel =>
      this == CardTransferDirection.toVisa ? 'Azaman Balance' : 'AZM Visa card';

  String get destinationLabel =>
      this == CardTransferDirection.toVisa ? 'AZM Visa card' : 'Azaman Balance';
}

class CardTransferScreen extends ConsumerStatefulWidget {
  const CardTransferScreen({super.key, this.fxRateOverride});

  /// Test seam: a deterministic rate for the currency preview (the
  /// production path is the freshness-gated [FxRateSnapshot]). Reuses the
  /// same seam contract as the Send composer.
  final double? fxRateOverride;

  @override
  ConsumerState<CardTransferScreen> createState() => _CardTransferScreenState();
}

class _CardTransferScreenState extends ConsumerState<CardTransferScreen>
    with TickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_onTabChanged);

  _Stage _stage = _Stage.amount;
  String _amountRaw = '';

  /// The ENTRY denomination (a preview unit, never a settlement claim).
  /// GHS-first default — the same catalog order the Send composer uses.
  int _entryIndex = 0;

  /// The fail-closed wheel message (mirrors the Send composer contract).
  String? _entryError;

  /// The equivalent FROZEN at review-open: review must never silently
  /// re-derive under a rate refresh while the user reads the statement.
  ({double? value, bool fromGhs})? _frozenEquivalent;

  double? get _amountValue => AmountInput.value(_amountRaw);
  String get _amountDisplay => AmountInput.display(_amountRaw);
  AzCurrency get _entryUnit => CurrencyCatalog.sendEntryUnits[_entryIndex];

  /// The validated GHS-per-USDC rate for THIS surface. The test seam
  /// wins when present; production reads the typed FX snapshot and never
  /// a legacy or fabricated rate. NO conversion ever runs on a rate this
  /// gate rejects.
  double? _liveRate() {
    final override = widget.fxRateOverride;
    if (override != null) {
      return CurrencyMath.isUsableRate(override) ? override : null;
    }
    final fx = ref.read(fxRateProvider).value;
    return (fx != null && fx.isUsable) ? fx.ghsPerUsdc : null;
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    // A direction change invalidates the review statement (and its frozen
    // equivalent). Both are screen state, so one setState.
    if (mounted) {
      setState(() {
        _stage = _Stage.amount;
        _frozenEquivalent = null;
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _closeSurface() {
    AzamanHaptics.navigation();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AzRoutes.shell);
    }
  }

  void _onKey(String key) {
    setState(() => _amountRaw = AmountInput.applyKey(_amountRaw, key));
  }

  /// Converts an existing entry to [next] (wheel switch). Returns null
  /// when the conversion cannot be established — the caller then refuses
  /// the switch instead of silently relabelling the digits (the Send
  /// composer's fail-closed contract, verbatim).
  double? _convertEntry(AzCurrency next, double? rate) {
    final amount = _amountValue;
    if (amount == null) return null;
    if (rate == null) return null;
    return CurrencyMath.convert(
      amount: amount,
      from: _entryUnit,
      to: next,
      ghsPerUsdc: rate,
    );
  }

  void _onEntryUnitChanged(int newIndex) {
    if (newIndex == _entryIndex) return;
    final next = CurrencyCatalog.sendEntryUnits[newIndex];
    final rate = _liveRate();

    // No amount typed yet — a pure denomination change, nothing to convert.
    if (_amountRaw.isEmpty) {
      setState(() {
        _entryIndex = newIndex;
        _entryError = null;
      });
      return;
    }

    final converted = _convertEntry(next, rate);
    if (converted == null) {
      // Fail closed: the switch is REFUSED — digits are never relabelled,
      // never silently zeroed, never converted at a fabricated rate.
      setState(
        () => _entryError = rate == null
            ? 'Exchange rate unavailable — the amount stays in '
                  '${_entryUnit.symbol}. Enter it in ${next.symbol} if needed.'
            : 'That amount converts to less than the smallest ${next.symbol} '
                  'unit — enter a larger amount.',
      );
      return;
    }
    AzamanHaptics.toggle();
    setState(() {
      _entryIndex = newIndex;
      _amountRaw = _formatQuick(converted);
      _entryError = null;
    });
  }

  /// Re-enters a converted amount as the raw string the keypad grammar
  /// expects: plain digits, no grouping, trailing zeros trimmed (the
  /// same re-entry the Send composer performs).
  String _formatQuick(double value) {
    var s = value.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+\$'), '').replaceFirst(RegExp(r'\.\$'), '');
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final programme = ref.watch(azmCardProgrammeProvider);
    final reduceMotion = !AzMotion.of(context).travel;

    // The live, freshness-gated rate for the PREVIEW displays. WATCHED,
    // so the pair and the equivalent caption track the snapshot as it
    // loads or refreshes; the test seam wins when present.
    final fxOverride = widget.fxRateOverride;
    final fxAsync = ref.watch(fxRateProvider);
    final fx = fxAsync.value;
    final rate = fxOverride != null
        ? (CurrencyMath.isUsableRate(fxOverride) ? fxOverride : null)
        : ((fx != null && fx.isUsable) ? fx.ghsPerUsdc : null);

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: PullDownDismissibleSurface(
          onDismiss: _closeSurface,
          canDismiss: () {
            if (_stage == _Stage.review) {
              // The review stage consumes the committed pull: it returns
              // to the amount stage instead of closing the surface.
              setState(() {
                _stage = _Stage.amount;
                _frozenEquivalent = null;
              });
              return false;
            }
            return true;
          },
          onDismissRejected: () {
            AzamanHaptics.selection();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TransferHeader(colors: colors, onClose: _closeSurface),
              // The bottom tabs: taps AND horizontal swipes move the same
              // TabController, so the tab bar, the swipe pages and the
              // flow direction can never disagree.
              _DirectionTabBar(controller: _tabs, colors: colors),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, AzSpace.md, 20, 0),
                child: CardTransferEntrance(
                  reduceMotion: reduceMotion,
                  child: CompactCardPair(
                    toVisa: _tabs.index == 0,
                    colors: colors,
                    reduceMotion: reduceMotion,
                    rate: rate,
                    maskedCardNumber: programme.maskedNumber,
                    cardholderLabel: programme.cardholderLabel,
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _DirectionPane(
                      key: const ValueKey('card-transfer-pane-to-visa'),
                      direction: CardTransferDirection.toVisa,
                      maskedCardNumber: programme.maskedNumber,
                      stage: _stage,
                      amountDisplay: _amountDisplay,
                      amountValue: _amountValue,
                      entryIndex: _entryIndex,
                      entryUnit: _entryUnit,
                      entryError: _entryError,
                      rate: rate,
                      frozenEquivalent: _frozenEquivalent,
                      colors: colors,
                      onKey: _onKey,
                      onEntryUnitChanged: _onEntryUnitChanged,
                      onReview: _openReview,
                      onBackToAmount: _backToAmount,
                    ),
                    _DirectionPane(
                      key: const ValueKey('card-transfer-pane-from-visa'),
                      direction: CardTransferDirection.fromVisa,
                      maskedCardNumber: programme.maskedNumber,
                      stage: _stage,
                      amountDisplay: _amountDisplay,
                      amountValue: _amountValue,
                      entryIndex: _entryIndex,
                      entryUnit: _entryUnit,
                      entryError: _entryError,
                      rate: rate,
                      frozenEquivalent: _frozenEquivalent,
                      colors: colors,
                      onKey: _onKey,
                      onEntryUnitChanged: _onEntryUnitChanged,
                      onReview: _openReview,
                      onBackToAmount: _backToAmount,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openReview() {
    if ((_amountValue ?? 0) <= 0) return;
    AzamanHaptics.selection();
    // FREEZE the equivalent the statement shows: computed once, at the
    // moment the review opens, from the same validated rate. A rate drift
    // mid-review can never silently rewrite the statement the user is
    // reading; leaving and returning recomputes it.
    final amount = _amountValue!;
    final rate = _liveRate();
    final fromGhs = _entryUnit.code == 'GHS';
    final value = rate == null
        ? null
        : CurrencyMath.convert(
            amount: amount,
            from: _entryUnit,
            to: fromGhs ? CurrencyCatalog.usdc : CurrencyCatalog.ghs,
            ghsPerUsdc: rate,
          );
    setState(() {
      _frozenEquivalent = (value: value, fromGhs: fromGhs);
      _stage = _Stage.review;
    });
  }

  void _backToAmount() {
    AzamanHaptics.navigation();
    setState(() {
      _stage = _Stage.amount;
      _frozenEquivalent = null;
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER — the Deposit/Receive grammar.
// ─────────────────────────────────────────────────────────────────────────────

class _TransferHeader extends StatelessWidget {
  const _TransferHeader({required this.colors, required this.onClose});

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
            label: 'Close Card Transfer',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: Container(
                key: const ValueKey('card-transfer-close'),
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
          Expanded(
            child: Text(
              'Card Transfer',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIRECTION TABS
// ─────────────────────────────────────────────────────────────────────────────

class _DirectionTabBar extends StatelessWidget {
  const _DirectionTabBar({required this.controller, required this.colors});

  final TabController controller;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, AzSpace.md, 20, 0),
      child: Container(
        key: const ValueKey('card-transfer-tabs'),
        height: 44,
        decoration: BoxDecoration(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: TabBar(
          controller: controller,
          // Taps AND swipes both land here: the TabBar writes the controller,
          // the TabBarView writes the same controller — one source of truth.
          onTap: (_) => AzamanHaptics.selection(),
          splashBorderRadius: BorderRadius.circular(22),
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.accent.withValues(alpha: 0.4)),
          ),
          labelColor: colors.textPrimary,
          unselectedLabelColor: colors.textTertiary,
          labelStyle: AzText.body.copyWith(fontWeight: FontWeight.w700),
          tabs: [
            Tab(
              key: const ValueKey('card-transfer-tab-to-visa'),
              child: Text(
                CardTransferDirection.toVisa.tabLabel,
                textAlign: TextAlign.center,
              ),
            ),
            Tab(
              key: const ValueKey('card-transfer-tab-from-visa'),
              child: Text(
                CardTransferDirection.fromVisa.tabLabel,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIRECTION PANE — the stage content (amount/review) for one direction.
// The compact pair lives ABOVE the TabBarView at screen level.
// ─────────────────────────────────────────────────────────────────────────────

class _DirectionPane extends StatelessWidget {
  const _DirectionPane({
    super.key,
    required this.direction,
    required this.maskedCardNumber,
    required this.stage,
    required this.amountDisplay,
    required this.amountValue,
    required this.entryIndex,
    required this.entryUnit,
    required this.entryError,
    required this.rate,
    required this.frozenEquivalent,
    required this.colors,
    required this.onKey,
    required this.onEntryUnitChanged,
    required this.onReview,
    required this.onBackToAmount,
  });

  final CardTransferDirection direction;
  final String maskedCardNumber;
  final _Stage stage;
  final String amountDisplay;

  /// The parsed entry amount (null when empty/zero) — the pane computes
  /// the preview from the VALUE, never by reparsing the display string.
  final double? amountValue;
  final int entryIndex;
  final AzCurrency entryUnit;
  final String? entryError;
  final double? rate;
  final ({double? value, bool fromGhs})? frozenEquivalent;
  final AzamanColors colors;
  final ValueChanged<String> onKey;
  final ValueChanged<int> onEntryUnitChanged;
  final VoidCallback onReview;
  final VoidCallback onBackToAmount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        // The keypad gives ground first: 54 at full height, 46 medium, 40
        // when the stage region is tight (short viewports scroll last).
        final keypadRow = h >= 560 ? 54.0 : (h >= 480 ? 46.0 : 40.0);

        // The nav-band clearance utility: on shell-hosted surfaces this
        // is the live floating-nav height; on a pushed route it degrades
        // to the system safe area. Either way the keypad and the CTA
        // remain fully usable above what lies beneath. It sits OUTSIDE the
        // scroll view — an inside-scroll padding would fabricate a scroll
        // extent on every viewport (the stage could then always eat the
        // pull-down dismiss).
        final clearance = navBandClearance(context) + kNavBandGap;

        return Padding(
          padding: EdgeInsets.only(bottom: clearance),
          child: _StageScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: h - clearance),
              child: IntrinsicHeight(
                child: stage == _Stage.amount
                    ? _AmountStage(
                        direction: direction,
                        maskedCardNumber: maskedCardNumber,
                        amountDisplay: amountDisplay,
                        amountValue: amountValue,
                        entryIndex: entryIndex,
                        entryUnit: entryUnit,
                        entryError: entryError,
                        rate: rate,
                        colors: colors,
                        onKey: onKey,
                        onEntryUnitChanged: onEntryUnitChanged,
                        onReview: onReview,
                        keypadRow: keypadRow,
                      )
                    : _ReviewStage(
                        direction: direction,
                        maskedCardNumber: maskedCardNumber,
                        amountDisplay: amountDisplay,
                        entryUnit: entryUnit,
                        frozenEquivalent: frozenEquivalent,
                        colors: colors,
                        onBackToAmount: onBackToAmount,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AMOUNT STAGE — the #165 wheel, clear amount, the honest equivalent,
// source/destination, keypad, review.
// ─────────────────────────────────────────────────────────────────────────────

class _AmountStage extends StatelessWidget {
  const _AmountStage({
    required this.direction,
    required this.maskedCardNumber,
    required this.amountDisplay,
    required this.amountValue,
    required this.entryIndex,
    required this.entryUnit,
    required this.entryError,
    required this.rate,
    required this.colors,
    required this.onKey,
    required this.onEntryUnitChanged,
    required this.onReview,
    required this.keypadRow,
  });

  final CardTransferDirection direction;
  final String maskedCardNumber;
  final String amountDisplay;
  final double? amountValue;
  final int entryIndex;
  final AzCurrency entryUnit;
  final String? entryError;
  final double? rate;
  final AzamanColors colors;
  final ValueChanged<String> onKey;
  final ValueChanged<int> onEntryUnitChanged;
  final VoidCallback onReview;
  final double keypadRow;

  @override
  Widget build(BuildContext context) {
    final usable = rate != null && CurrencyMath.isUsableRate(rate!);
    final amount = amountValue;

    // The honestly-labelled equivalent — the SAME #165 conversion path
    // (CurrencyMath at the validated rate), never a fabricated figure.
    String? equivalent;
    if (amount != null && amount > 0 && usable) {
      final converted = CurrencyMath.convert(
        amount: amount,
        from: entryUnit,
        to: entryUnit.code == 'GHS'
            ? CurrencyCatalog.usdc
            : CurrencyCatalog.ghs,
        ghsPerUsdc: rate!,
      );
      if (converted != null) {
        equivalent = entryUnit.code == 'GHS'
            ? '≈ ${AzMoney.usdc(converted)} · rail denomination — preview'
            : '≈ ${AzMoney.ghs(converted)} · current estimate';
      }
    }
    final equivalentUnavailable =
        amount != null && amount > 0 && equivalent == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              CurrencyWheelToggle(
                key: const ValueKey('card-transfer-currency-wheel'),
                options: CurrencyCatalog.sendEntryUnits,
                selectedIndex: entryIndex,
                onChanged: onEntryUnitChanged,
                semanticLabelPrefix: 'Input currency',
              ),
              const SizedBox(height: AzSpace.md),
              // The amount must never clip or elide — it scales to fit.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$amountDisplay ${entryUnit.symbol}',
                  key: const ValueKey('card-transfer-amount'),
                  style: AzText.titleXl.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: AzSpace.xs),
              Text(
                equivalent ??
                    (equivalentUnavailable
                        ? (entryUnit.code == 'GHS'
                              ? 'USDC rail equivalent unavailable'
                              : 'GH₵ equivalent unavailable')
                        : ''),
                key: const ValueKey('card-transfer-equivalent'),
                textAlign: TextAlign.center,
                style: AzText.caption.copyWith(
                  color: equivalent != null
                      ? colors.textSecondary
                      : colors.warning,
                  fontWeight: equivalent != null ? FontWeight.w600 : null,
                ),
              ),
              if (entryError != null) ...[
                const SizedBox(height: AzSpace.xs),
                Text(
                  entryError!,
                  key: const ValueKey('card-transfer-entry-error'),
                  textAlign: TextAlign.center,
                  style: AzText.caption.copyWith(color: colors.danger),
                ),
              ],
              const SizedBox(height: AzSpace.sm),
              _RouteRow(
                direction: direction,
                maskedCardNumber: maskedCardNumber,
                colors: colors,
              ),
            ],
          ),
          AmountKeypad(onKey: onKey, rowHeight: keypadRow),
          _ReviewCta(
            enabled: (amountValue ?? 0) > 0,
            colors: colors,
            onReview: onReview,
          ),
        ],
      ),
    );
  }
}

/// Source → destination for the chosen direction, with the programme's real
/// masked number — clear about where the money would move.
class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.direction,
    required this.maskedCardNumber,
    required this.colors,
  });

  final CardTransferDirection direction;
  final String maskedCardNumber;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    final cardLabel = 'AZM Visa $maskedCardNumber';
    return Row(
      key: ValueKey(
        'card-transfer-route-${direction == CardTransferDirection.toVisa ? 'to' : 'from'}-visa',
      ),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            direction.sourceLabel,
            style: AzText.caption.copyWith(color: colors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AzSpace.sm),
          child: Icon(Icons.arrow_forward, size: 14, color: colors.accent),
        ),
        Flexible(
          child: Text(
            direction == CardTransferDirection.toVisa
                ? cardLabel
                : direction.destinationLabel,
            style: AzText.caption.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ReviewCta extends StatelessWidget {
  const _ReviewCta({
    required this.enabled,
    required this.colors,
    required this.onReview,
  });

  final bool enabled;
  final AzamanColors colors;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Review transfer',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onReview : null,
        child: Container(
          key: const ValueKey('card-transfer-review-cta'),
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? colors.accent : colors.softSurface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'Review transfer',
            style: AzText.body.copyWith(
              color: enabled ? colors.onAccent : colors.textTertiary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REVIEW STAGE — the transfer statement, then the HONEST capability gate.
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewStage extends StatelessWidget {
  const _ReviewStage({
    required this.direction,
    required this.maskedCardNumber,
    required this.amountDisplay,
    required this.entryUnit,
    required this.frozenEquivalent,
    required this.colors,
    required this.onBackToAmount,
  });

  final CardTransferDirection direction;
  final String maskedCardNumber;
  final String amountDisplay;
  final AzCurrency entryUnit;
  final ({double? value, bool fromGhs})? frozenEquivalent;
  final AzamanColors colors;
  final VoidCallback onBackToAmount;

  @override
  Widget build(BuildContext context) {
    final eq = frozenEquivalent;
    final equivalentText = eq == null || eq.value == null
        ? 'Unavailable'
        : (eq.fromGhs
              ? '≈ ${AzMoney.usdc(eq.value!)} — preview'
              : '≈ ${AzMoney.ghs(eq.value!)} — current estimate');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, AzSpace.lg, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            direction.tabLabel,
            key: const ValueKey('card-transfer-review-title'),
            style: AzText.titleL.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AzSpace.md),
          Container(
            padding: const EdgeInsets.all(AzSpace.lg),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                _StatementRow(
                  label: 'Amount',
                  value: '$amountDisplay ${entryUnit.symbol}',
                  emphasize: true,
                  colors: colors,
                ),
                const SizedBox(height: AzSpace.sm),
                // The rail pairing, honestly labelled. A GHS entry names
                // the USDC rail amount a PREVIEW; a USDC entry names the
                // cedi figure a CURRENT ESTIMATE. Neither claims the
                // entry unit is a settlement currency, and neither is
                // ever presented as payable value.
                _StatementRow(
                  label: eq != null && eq.fromGhs
                      ? 'Rail amount (preview)'
                      : 'GH₵ equivalent',
                  value: equivalentText,
                  colors: colors,
                ),
                const SizedBox(height: AzSpace.sm),
                _StatementRow(
                  label: 'From',
                  value: direction == CardTransferDirection.toVisa
                      ? direction.sourceLabel
                      : 'AZM Visa $maskedCardNumber',
                  colors: colors,
                ),
                const SizedBox(height: AzSpace.sm),
                _StatementRow(
                  label: 'To',
                  value: direction == CardTransferDirection.toVisa
                      ? 'AZM Visa $maskedCardNumber'
                      : direction.destinationLabel,
                  colors: colors,
                ),
              ],
            ),
          ),
          const SizedBox(height: AzSpace.md),
          // ── THE CAPABILITY GATE ────────────────────────────────────────
          // Truthful, always: submission is disabled while the demo card
          // programme cannot settle a real transfer. No invented endpoint
          // is called, no balance is mutated, no success is ever shown.
          Container(
            key: const ValueKey('card-transfer-gate'),
            padding: const EdgeInsets.all(AzSpace.lg),
            decoration: BoxDecoration(
              color: colors.softSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: colors.warning),
                    const SizedBox(width: AzSpace.sm),
                    Expanded(
                      child: Text(
                        'Card transfers aren\'t available yet',
                        style: AzText.body.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AzSpace.sm),
                // The SAME honest copy in every state: this build has no
                // transfer execution path at all, so no capability flag
                // can ever imply that a transfer can be made here. When
                // the real programme + backend settlement contract land,
                // THAT change replaces this gate with a real submit.
                Text(
                  'Your AZM card is a sample preview. Moving money '
                  'between your balance and a real card needs the '
                  'Flutterwave card programme and our transfer '
                  'settlement contract — both are coming. Nothing '
                  'has been sent.',
                  style: AzText.caption.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AzSpace.lg),
          GestureDetector(
            onTap: onBackToAmount,
            child: Container(
              key: const ValueKey('card-transfer-back-to-amount'),
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.softSurface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Back to amount',
                style: AzText.body.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: AzSpace.md),
          // The submit control: present for the statement's grammar, but
          // DISABLED until the real card programme + backend contract
          // exist. It can never display a successful transfer today.
          Semantics(
            button: true,
            enabled: false,
            label:
                'Transfer — unavailable while the card programme is a sample',
            excludeSemantics: true,
            child: Container(
              key: const ValueKey('card-transfer-submit'),
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.softSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(width: AzSpace.sm),
                  Text(
                    'Transfer unavailable',
                    style: AzText.body.copyWith(
                      color: colors.textTertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatementRow extends StatelessWidget {
  const _StatementRow({
    required this.label,
    required this.value,
    required this.colors,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final AzamanColors colors;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AzText.caption.copyWith(color: colors.textSecondary),
        ),
        Flexible(
          child: Text(
            value,
            style: AzText.body.copyWith(
              color: emphasize ? colors.accent : colors.textPrimary,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THE STAGE SCROLL VIEW — scroll only when the content actually overflows.
// ─────────────────────────────────────────────────────────────────────────────

/// The stage scrolls only when its content genuinely overflows the pane.
///
/// While it FITS, the scroll view uses [NeverScrollableScrollPhysics]: the
/// stage never enters the vertical-gesture arena, so the surface's
/// committed pull-down dismiss stays reachable from the whole stage, not
/// just the compact-pair strip. The moment real overflow is measured
/// (short viewports, large text, an open IME inset), the physics switch to
/// clamping and the stage scrolls — dismissal remains available from the
/// non-scrolling pair strip, exactly like the full-height card region it
/// replaced.
class _StageScrollView extends StatefulWidget {
  const _StageScrollView({required this.child});

  final Widget child;

  @override
  State<_StageScrollView> createState() => _StageScrollViewState();
}

class _StageScrollViewState extends State<_StageScrollView> {
  bool _needsScroll = false;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        final needs = notification.metrics.maxScrollExtent > 0;
        if (needs != _needsScroll) {
          setState(() => _needsScroll = needs);
        }
        return false;
      },
      child: SingleChildScrollView(
        physics: _needsScroll
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        child: widget.child,
      ),
    );
  }
}
