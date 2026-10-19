// =============================================================================
// AZAMAN — CARD TRANSFER (Balance ↔ Visa)  — full-height transfer surface
//
// Opened from the Home deck's seam control. A Receive-like full-height
// surface: pull-down dismissible, bottom tabs "To Visa" / "From Visa" that
// answer BOTH taps and horizontal swipes (one TabController), both physical
// cards rendered by the SAME card renderers Home uses ([FlippableBalanceCard]
// and [AzmVisaCard] — no duplicate card illustrations anywhere in this
// file), and ONE restrained directional money-flow animation between the two
// faces that REVERSES with the chosen tab ([DirectionalMoneyFlow]).
//
// STAGES: amount (AmountKeypad reuse + clear amount/currency + source and
// destination) → review (the full transfer statement).
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

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/amount_input.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/amount_keypad.dart';
import 'package:azaman/widgets/flippable_balance_card.dart';
import 'package:azaman/widgets/home/azm_visa_card.dart';
import 'package:azaman/widgets/pull_down_dismissible_surface.dart';

enum CardTransferDirection { toVisa, fromVisa }

enum _Stage { amount, review }

/// The transfer direction's human labels — the single source for every
/// surface (tabs, review statement, semantics).
extension CardTransferDirectionCopy on CardTransferDirection {
  String get tabLabel => this == CardTransferDirection.toVisa
      ? 'To Visa'
      : 'From Visa';

  String get sourceLabel => this == CardTransferDirection.toVisa
      ? 'Azaman Balance'
      : 'AZM Visa card';

  String get destinationLabel => this == CardTransferDirection.toVisa
      ? 'AZM Visa card'
      : 'Azaman Balance';
}

class CardTransferScreen extends ConsumerStatefulWidget {
  const CardTransferScreen({super.key});

  @override
  ConsumerState<CardTransferScreen> createState() => _CardTransferScreenState();
}

class _CardTransferScreenState extends ConsumerState<CardTransferScreen>
    with TickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
  )..addListener(_onTabChanged);

  _Stage _stage = _Stage.amount;
  String _amountRaw = '';

  double? get _amountValue => AmountInput.value(_amountRaw);
  String get _amountDisplay => AmountInput.display(_amountRaw);

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    // A direction change invalidates the review statement AND hands the
    // money-flow animation to the newly selected pane (the off-screen
    // pane's loop stops). Both are screen state, so one setState.
    if (mounted) {
      setState(() => _stage = _Stage.amount);
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
      context.go('/');
    }
  }

  void _onKey(String key) {
    setState(() => _amountRaw = AmountInput.applyKey(_amountRaw, key));
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final programme = ref.watch(azmCardProgrammeProvider);

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
              setState(() => _stage = _Stage.amount);
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
              // money-flow direction can never disagree.
              _DirectionTabBar(controller: _tabs, colors: colors),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _DirectionPane(
                      key: const ValueKey('card-transfer-pane-to-visa'),
                      direction: CardTransferDirection.toVisa,
                      maskedCardNumber: programme.maskedNumber,
                      active: _tabs.index == 0,
                      stage: _stage,
                      amountDisplay: _amountDisplay,
                      hasAmount: (_amountValue ?? 0) > 0,
                      colors: colors,
                      onKey: _onKey,
                      onReview: _openReview,
                      onBackToAmount: _backToAmount,
                    ),
                    _DirectionPane(
                      key: const ValueKey('card-transfer-pane-from-visa'),
                      direction: CardTransferDirection.fromVisa,
                      maskedCardNumber: programme.maskedNumber,
                      active: _tabs.index == 1,
                      stage: _stage,
                      amountDisplay: _amountDisplay,
                      hasAmount: (_amountValue ?? 0) > 0,
                      colors: colors,
                      onKey: _onKey,
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
    setState(() => _stage = _Stage.review);
  }

  void _backToAmount() {
    AzamanHaptics.navigation();
    setState(() => _stage = _Stage.amount);
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
// DIRECTION PANE — both cards (the Home renderers), the money flow between
// them, then the amount/review stage content.
// ─────────────────────────────────────────────────────────────────────────────

class _DirectionPane extends StatelessWidget {
  const _DirectionPane({
    super.key,
    required this.direction,
    required this.maskedCardNumber,
    required this.active,
    required this.stage,
    required this.amountDisplay,
    required this.hasAmount,
    required this.colors,
    required this.onKey,
    required this.onReview,
    required this.onBackToAmount,
  });

  final CardTransferDirection direction;
  final String maskedCardNumber;

  /// The SELECTED direction — only the active pane's flow animates; the
  /// off-screen pane's controller is stopped (not merely painted away).
  final bool active;
  final _Stage stage;
  final String amountDisplay;
  final bool hasAmount;
  final AzamanColors colors;
  final ValueChanged<String> onKey;
  final VoidCallback onReview;
  final VoidCallback onBackToAmount;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = !AzMotion.of(context).travel;

    // Responsive compression: the two card faces + the flow between them
    // are the composition's fixed grammar; the keypad gives way first.
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        // CARD HEIGHT IS PINNED AT THE DECK'S OWN 165: both card renderers
        // are audited for exactly this footprint (their interior content
        // overflows below ~162), and the deck on Home renders them at this
        // same height — one composition, one size. Short viewports give
        // ground to the STAGE (which scrolls), never to the card faces.
        const cardH = 165.0;
        // The keypad gives ground first: 54 at full height, 46 medium, 40
        // when the stage region is tight.
        final keypadRow = h >= 640 ? 54.0 : (h >= 560 ? 46.0 : 40.0);

        Widget pane = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(
              height: cardH,
              // The SAME balance-card renderer Home mounts — never a copy.
              child: FlippableBalanceCard(),
            ),
            DirectionalMoneyFlow(
              key: ValueKey(
                  'card-transfer-flow-${direction == CardTransferDirection.toVisa ? 'to' : 'from'}-visa'),
              toVisa: direction == CardTransferDirection.toVisa,
              colors: colors,
              reduceMotion: reduceMotion,
              active: active,
              height: 44.0,
            ),
            const SizedBox(
              height: cardH,
              // The SAME Visa sample-card renderer Home mounts — never a copy.
              child: AzmVisaCard(),
            ),
            // The stage content scrolls only when it must (short
            // viewports); the minHeight keeps the spaceAround spreading
            // when it fits, so no layout exception at any viewport.
            Expanded(
              child: LayoutBuilder(
                builder: (context, stageConstraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: stageConstraints.maxHeight,
                    ),
                    // IntrinsicHeight hands the minHeight down as a BOUNDED
                    // height, so the stage's spaceAround still spreads when
                    // the content fits — and scrolls when it does not.
                    child: IntrinsicHeight(
                      child: stage == _Stage.amount
                        ? _AmountStage(
                            direction: direction,
                            maskedCardNumber: maskedCardNumber,
                            amountDisplay: amountDisplay,
                            hasAmount: hasAmount,
                            colors: colors,
                            onKey: onKey,
                            onReview: onReview,
                            keypadRow: keypadRow,
                          )
                        : _ReviewStage(
                            direction: direction,
                            maskedCardNumber: maskedCardNumber,
                            amountDisplay: amountDisplay,
                            colors: colors,
                            onBackToAmount: onBackToAmount,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

        return pane;
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THE MONEY FLOW — one restrained directional animation between the cards.
// ─────────────────────────────────────────────────────────────────────────────

/// A restrained vertical flow of three small value dots travelling between
/// the balance card and the Visa card. The DIRECTION is the chosen tab:
/// `toVisa` travels DOWN (balance → card), `fromVisa` travels UP. Reduced
/// motion honours the information, not the motion: the flow path renders
/// with directional arrowheads and nothing travels.
class DirectionalMoneyFlow extends StatefulWidget {
  const DirectionalMoneyFlow({
    super.key,
    required this.toVisa,
    required this.colors,
    required this.reduceMotion,
    required this.active,
    this.height = 44,
  });

  /// Money moving TO the card (down) when true, FROM the card (up) when
  /// false — the tab's direction.
  final bool toVisa;
  final AzamanColors colors;
  final bool reduceMotion;

  /// The SELECTED direction pane — only the active pane's loop runs; the
  /// off-screen pane's controller is STOPPED (its state remains legible
  /// as a static painting).
  final bool active;
  final double height;

  @override
  State<DirectionalMoneyFlow> createState() => DirectionalMoneyFlowState();
}

/// Public state: the loop is part of the reviewed contract — tests pin
/// that it runs ONLY for the active direction and stops at runtime when
/// the reduced-motion preference lands.
class DirectionalMoneyFlowState extends State<DirectionalMoneyFlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    // One slow, restrained loop — value dots amble, they do not race.
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    _syncLoop();
  }

  /// Whether the travel loop is currently running (test contract).
  bool get isLooping => _flow.isAnimating;

  /// The loop follows the widget at RUNTIME: it starts only for the
  /// ACTIVE pane without a reduced-motion preference, and stops on any
  /// change of either — including a settings change mid-flight (the
  /// inherited AzMotion rebuilds this widget; didUpdateWidget reacts).
  void _syncLoop() {
    final shouldRun = widget.active && !widget.reduceMotion;
    if (shouldRun && !_flow.isAnimating) {
      _flow.repeat();
    } else if (!shouldRun && _flow.isAnimating) {
      _flow.stop();
    }
  }

  @override
  void didUpdateWidget(DirectionalMoneyFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.reduceMotion != widget.reduceMotion) {
      _syncLoop();
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduceMotion || !widget.active) {
      // Reduced motion OR the off-screen pane: the direction stays
      // legible without any travel — a static painting, no loop.
      return SizedBox(
        height: widget.height,
        child: CustomPaint(
          painter: _FlowPainter(
            progress: 0,
            animate: false,
            toVisa: widget.toVisa,
            colors: widget.colors,
          ),
          size: Size.infinite,
        ),
      );
    }
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _flow,
        builder: (context, _) => CustomPaint(
          painter: _FlowPainter(
            progress: _flow.value,
            animate: true,
            toVisa: widget.toVisa,
            colors: widget.colors,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.progress,
    required this.animate,
    required this.toVisa,
    required this.colors,
  });

  final double progress;
  final bool animate;
  final bool toVisa;
  final AzamanColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final accent = colors.accent;

    // The quiet lane the value travels along.
    final lane = Paint()
      ..color = accent.withValues(alpha: animate ? 0.18 : 0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx, 6),
      Offset(cx, size.height - 6),
      lane,
    );

    if (!animate) {
      // Reduced motion: static arrowheads carry the direction.
      _arrow(canvas, Offset(cx, size.height * 0.38), toVisa, accent);
      _arrow(canvas, Offset(cx, size.height * 0.62), toVisa, accent);
      return;
    }

    // Three restrained value dots, evenly phased, travelling the lane in
    // the tab's direction.
    for (var i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1.0;
      final t = toVisa ? phase : 1 - phase;
      final y = 6 + (size.height - 12) * t;
      final dotPaint = Paint()
        ..color = accent.withValues(alpha: 0.25 + 0.45 * (1 - (t - 0.5).abs() * 2));
      canvas.drawCircle(Offset(cx, y), 3.2, dotPaint);
    }
  }

  void _arrow(Canvas canvas, Offset at, bool down, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dir = down ? 1.0 : -1.0;
    final path = Path()
      ..moveTo(at.dx - 5, at.dy - 4 * dir)
      ..lineTo(at.dx, at.dy + 4 * dir)
      ..lineTo(at.dx + 5, at.dy - 4 * dir);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.progress != progress ||
      old.animate != animate ||
      old.toVisa != toVisa;
}

// ─────────────────────────────────────────────────────────────────────────────
// AMOUNT STAGE — clear amount/currency, source/destination, keypad, review.
// ─────────────────────────────────────────────────────────────────────────────

class _AmountStage extends StatelessWidget {
  const _AmountStage({
    required this.direction,
    required this.maskedCardNumber,
    required this.amountDisplay,
    required this.hasAmount,
    required this.colors,
    required this.onKey,
    required this.onReview,
    required this.keypadRow,
  });

  final CardTransferDirection direction;
  final String maskedCardNumber;
  final String amountDisplay;
  final bool hasAmount;
  final AzamanColors colors;
  final ValueChanged<String> onKey;
  final VoidCallback onReview;
  final double keypadRow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Clear amount + currency.
          Column(
            children: [
              Text(
                '$amountDisplay ${AzMoney.usdcSymbol}',
                key: const ValueKey('card-transfer-amount'),
                style: AzText.titleXl.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AzSpace.sm),
              _RouteRow(
                direction: direction,
                maskedCardNumber: maskedCardNumber,
                colors: colors,
              ),
            ],
          ),
          AmountKeypad(
            onKey: onKey,
            rowHeight: keypadRow,
          ),
          _ReviewCta(
            enabled: hasAmount,
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
          'card-transfer-route-${direction == CardTransferDirection.toVisa ? 'to' : 'from'}-visa'),
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
    required this.colors,
    required this.onBackToAmount,
  });

  final CardTransferDirection direction;
  final String maskedCardNumber;
  final String amountDisplay;
  final AzamanColors colors;
  final VoidCallback onBackToAmount;

  @override
  Widget build(BuildContext context) {
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
                  value: '$amountDisplay ${AzMoney.usdcSymbol}',
                  emphasize: true,
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
              border: Border.all(
                color: colors.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: colors.warning),
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
            label: 'Transfer — unavailable while the card programme is a sample',
            excludeSemantics: true,
            child: Container(
              key: const ValueKey('card-transfer-submit'),
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.softSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.border.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline,
                      size: 16, color: colors.textTertiary),
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
