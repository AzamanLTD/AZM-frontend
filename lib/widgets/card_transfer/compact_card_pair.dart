// =============================================================================
// AZAMAN — COMPACT CARD PREVIEWS (Card Transfer, Workstream C — 2026-10-20)
//
// The transfer surface's PURPOSE-DESIGNED compact card pair. This is NOT
// the Home deck's full-height card composition squeezed into half-width
// boxes: [CompactBalancePreview] and [CompactVisaPreview] are renderers
// drawn for this exact footprint (a ~150×96 tile), so the transfer
// surface can give its vertical priority to the amount, keypad, review
// summary and action area instead of two 165px physical cards.
//
// • Both previews share the physical-card material the Home cards wear
//   ([PremiumCardFrame] — carbon body + the shared metallic rim), so the
//   pair reads as the same two cards, in miniature, not a new invention.
// • The pair is STATIC: no gestures, no PIN gate, no sheen of its own
//   beyond the frame material — every Home interaction stays on Home.
// • ONE [DirectionalMoneyFlow] lane runs BETWEEN the two previews,
//   horizontally: `toVisa` travels toward the Visa tile, `fromVisa`
//   reverses. Reduced motion keeps the arrowheads, drops the travel.
// • [CardTransferEntrance] plays the wallet-to-transfer entrance ONCE
//   on route entry and NEVER replays on rebuilds; reduced motion lands
//   on the end state with no motion at all.
//
// FINANCIAL TRUTH: these previews are presentation-only. The Visa rail
// remains USDC-denominated and demo-gated; nothing here settles, debits
// or claims a transfer. The balance tile follows the user's global GHS/
// USDC display preference with the #165 freshness-gated FX snapshot and
// names the equivalent unavailable when no usable rate exists.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/providers/currency_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/widgets/premium_card_surface.dart';

/// The compact pair's fixed tile height — drawn for this footprint.
const double kCompactCardHeight = 96.0;

// ─────────────────────────────────────────────────────────────────────────────
// THE MONEY FLOW — one restrained horizontal lane between the two tiles.
// ─────────────────────────────────────────────────────────────────────────────

/// A restrained horizontal flow of three small value dots travelling
/// between the balance tile and the Visa tile. `toVisa` travels RIGHT
/// (balance → card), `fromVisa` travels LEFT. Reduced motion honours the
/// information, not the motion: the lane renders with directional
/// arrowheads and nothing travels.
class DirectionalMoneyFlow extends StatefulWidget {
  const DirectionalMoneyFlow({
    super.key,
    required this.toVisa,
    required this.colors,
    required this.reduceMotion,
    required this.active,
    this.width = 28,
    this.height = kCompactCardHeight,
  });

  /// Money moving TO the card (right) when true, FROM the card (left)
  /// when false — the chosen tab's direction.
  final bool toVisa;
  final AzamanColors colors;
  final bool reduceMotion;

  /// Whether the travel loop may run. The single screen-level lane passes
  /// true; the loop still stops the moment reduced motion lands.
  final bool active;

  /// The lane's travel length (horizontal extent).
  final double width;

  final double height;

  @override
  State<DirectionalMoneyFlow> createState() => DirectionalMoneyFlowState();
}

/// Public state: the loop is part of the reviewed contract — tests pin
/// that it stops at runtime when the reduced-motion preference lands.
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

  /// The loop follows the widget at RUNTIME: it runs only without a
  /// reduced-motion preference, and stops on any change — including a
  /// settings change mid-flight (the inherited AzMotion rebuilds this
  /// widget; didUpdateWidget reacts).
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
    return Semantics(
      label: widget.toVisa
          ? 'Preview flow toward the AZM Visa card'
          : 'Preview flow from the AZM Visa card to the balance',
      excludeSemantics: true,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _flow,
          builder: (context, _) => CustomPaint(
            painter: _FlowPainter(
              progress: _flow.value,
              animate: !widget.reduceMotion && widget.active,
              toVisa: widget.toVisa,
              colors: widget.colors,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  const _FlowPainter({
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
    final cy = size.height / 2;
    final accent = colors.accent;

    // The quiet lane the value travels along.
    final lane = Paint()
      ..color = accent.withValues(alpha: animate ? 0.18 : 0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(4, cy),
      Offset(size.width - 4, cy),
      lane,
    );

    if (!animate) {
      // Reduced motion: static arrowheads carry the direction.
      _arrow(canvas, Offset(size.width * 0.38, cy), toVisa, accent);
      _arrow(canvas, Offset(size.width * 0.62, cy), toVisa, accent);
      return;
    }

    // Three restrained value dots, evenly phased, travelling the lane in
    // the chosen direction.
    for (var i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1.0;
      final t = toVisa ? phase : 1 - phase;
      final x = 4 + (size.width - 8) * t;
      final dotPaint = Paint()
        ..color = accent
            .withValues(alpha: 0.25 + 0.45 * (1 - (t - 0.5).abs() * 2));
      canvas.drawCircle(Offset(x, cy), 3.2, dotPaint);
    }
  }

  void _arrow(Canvas canvas, Offset at, bool right, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dir = right ? 1.0 : -1.0;
    final path = Path()
      ..moveTo(at.dx - 4 * dir, at.dy - 5)
      ..lineTo(at.dx + 4 * dir, at.dy)
      ..lineTo(at.dx - 4 * dir, at.dy + 5);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.progress != progress ||
      old.animate != animate ||
      old.toVisa != toVisa;
}

// ─────────────────────────────────────────────────────────────────────────────
// THE BALANCE TILE — the compact balance-card preview.
// ─────────────────────────────────────────────────────────────────────────────

/// The compact balance preview. Presentation-only: it reads the same
/// `balanceDataProvider` ledger the Home card reads and follows the
/// user's global display preference, GHS-first, with the #165
/// freshness-gated FX snapshot. No usable rate → the cedi equivalent is
/// NAMED unavailable, never fabricated.
class CompactBalancePreview extends ConsumerWidget {
  const CompactBalancePreview({super.key, this.rate});

  /// The validated GHS-per-USDC rate, or null when none is usable. The
  /// caller owns the snapshot gate ([FxRateSnapshot.isUsable]); this
  /// widget never converts on its own.
  final double? rate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final balance = ref.watch(balanceDataProvider);
    final pref = ref.watch(currencyProvider);
    final ghsFirst = pref == DisplayCurrency.ghs;
    final usable = rate != null && rate! > 0 && rate!.isFinite;

    final ghsValue = usable ? balance.availableBalance * rate! : 0.0;
    final primary = ghsFirst && usable
        ? AzMoney.ghs(ghsValue)
        : AzMoney.usdcFirst(balance.availableBalance);
    final secondary = usable
        ? (ghsFirst
            ? AzMoney.usdcFirst(balance.availableBalance)
            : AzMoney.ghs(ghsValue))
        : 'GH₵ unavailable';

    return Semantics(
      label: 'AZM balance card preview',
      excludeSemantics: true,
      child: PremiumCardFrame(
        key: const ValueKey('card-transfer-compact-balance'),
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'AZM',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 13, color: colors.accent.withValues(alpha: 0.9)),
                ],
              ),
              const Spacer(),
              const Text(
                'Balance',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              // The amount must never clip or elide: it scales down to fit
              // whatever the tile's width and the text scale allow.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  primary,
                  key: const ValueKey('card-transfer-compact-balance-amount'),
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  secondary,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
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

// ─────────────────────────────────────────────────────────────────────────────
// THE VISA TILE — the compact sample-card preview.
// ─────────────────────────────────────────────────────────────────────────────

/// The compact Visa preview. Presentation-only: every datum comes from
/// the card-programme seam ([AzmCardProgramme]); the SAMPLE disclosure is
/// permanent, exactly as on the Home card.
class CompactVisaPreview extends ConsumerWidget {
  const CompactVisaPreview({
    super.key,
    required this.maskedCardNumber,
    required this.cardholderLabel,
  });

  final String maskedCardNumber;
  final String cardholderLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      label: 'AZM Visa sample card preview',
      excludeSemantics: true,
      child: PremiumCardFrame(
        key: const ValueKey('card-transfer-compact-visa'),
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The tile's footprint is ~110px wide: the disclosure chip
              // and the network mark sit on TWO stacked lines — never a
              // single overflowing row at 320dp.
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      'SAMPLE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // SAMPLE network mark — Visa-concept visual only.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'VISA',
                      style: TextStyle(
                        color: Color(0xFF1A1F71),
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  maskedCardNumber,
                  key: const ValueKey('card-transfer-compact-visa-number'),
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  cardholderLabel,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 7.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
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

// ─────────────────────────────────────────────────────────────────────────────
// THE PAIR — both tiles side by side with the flow lane between them.
// ─────────────────────────────────────────────────────────────────────────────

/// The compact side-by-side pair: balance tile | flow lane | Visa tile.
/// One composition, fixed grammar — the stage content below owns the
/// rest of the viewport.
class CompactCardPair extends StatelessWidget {
  const CompactCardPair({
    super.key,
    required this.toVisa,
    required this.colors,
    required this.reduceMotion,
    this.rate,
    this.maskedCardNumber = '',
    this.cardholderLabel = 'CARDHOLDER',
  });

  /// The CHOSEN tab's direction — the lane reverses with it.
  final bool toVisa;
  final AzamanColors colors;
  final bool reduceMotion;
  final double? rate;
  final String maskedCardNumber;
  final String cardholderLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('card-transfer-card-pair'),
      height: kCompactCardHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CompactBalancePreview(rate: rate),
          ),
          DirectionalMoneyFlow(
            key: ValueKey(
                'card-transfer-flow-${toVisa ? 'to' : 'from'}-visa'),
            toVisa: toVisa,
            colors: colors,
            reduceMotion: reduceMotion,
            active: true,
          ),
          Expanded(
            child: CompactVisaPreview(
              maskedCardNumber: maskedCardNumber,
              cardholderLabel: cardholderLabel,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THE ENTRANCE — wallet-to-transfer, once, on route entry.
// ─────────────────────────────────────────────────────────────────────────────

/// The wallet-to-transfer entrance: the compact pair rises out of the
/// wallet's pocket and settles — ONCE, on route entry.
///
///   • ONE shot: the controller plays in initState and is never re-run;
///     rebuilds, tab changes and provider updates cannot replay it.
///   • Reduced motion: the pair renders at its end state immediately —
///     no slide, no fade, no scale.
///   • The pair never suggests money has moved: it is the CARDS arriving,
///     not a value in flight.
class CardTransferEntrance extends StatefulWidget {
  const CardTransferEntrance({
    super.key,
    required this.child,
    this.reduceMotion = false,
  });

  final Widget child;
  final bool reduceMotion;

  @override
  State<CardTransferEntrance> createState() => CardTransferEntranceState();
}

/// Public state: the one-shot contract is part of the reviewed surface —
/// tests pin that the entrance plays once and never replays.
class CardTransferEntranceState extends State<CardTransferEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: MotionTokens.emphasized,
  );

  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _entrance, curve: MotionTokens.enter);

  @override
  void initState() {
    super.initState();
    // ONE shot, at mount (route entry). Reduced motion lands directly on
    // the end state. didUpdateWidget deliberately does nothing: no
    // rebuild can replay the entrance.
    if (widget.reduceMotion) {
      _entrance.value = 1;
    } else {
      _entrance.forward();
    }
  }

  /// Whether the entrance is still playing (test contract).
  bool get isPlaying => _entrance.isAnimating;

  /// The entrance's settled-ness (test contract): 1 means fully arrived.
  double get progress => _entrance.value;

  @override
  void dispose() {
    _curve.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduceMotion) {
      // The end state, immediately — no motion at all.
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 28 * (1 - t)),
            child: Transform.scale(
              scale: 0.96 + 0.04 * t,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
