// =============================================================================
// ESCROW VAULT RAIL — Flutter V3 Marketplace Sprint (2026-06-21)
//
// The "funds travel" signature moment (premium assessment §4.2C): buyer →
// escrow → vendor. The escrow segment is a translucent vault with a countdown
// ring; when the escrow reaches a terminal state the vault UNSEALS — its goo
// rim dissolves through liquid_engine's blur→threshold filter — and the coins
// fly to the destination party.
//
// Honesty rules enforced here:
//   • No invented deadlines. The countdown ring renders only when BOTH
//     fundedAt and expiresAt exist; the label counts down from expiresAt
//     alone. A missing window renders a calm "Auto-release" line, never a
//     fake countdown.
//   • Names come from the escrow data: 'You' when currentUserId matches a
//     party, otherwise the party's username, falling back to 'Buyer'/'Vendor'.
//   • The decorative coin stack is deterministic — offsets derive from a
//     codeUnits fold seed (F-046: String.hashCode is not stable across runs).
//
// Tickers (F-049): this State drives TWO controllers — the one-shot 1100ms
// unseal controller (pinned at 1.0 when idle, so pumpAndSettle never hangs on
// it) and a 1-second repeater that refreshes the countdown while the escrow
// is active. Two controllers therefore need the plain TickerProviderStateMixin,
// never SingleTickerProviderStateMixin (which asserts on the second one).
// The repeater stops the moment the escrow leaves isActive.
// =============================================================================
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/escrow_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/liquid/liquid_engine.dart';
import 'package:azaman/widgets/premium_glass_container.dart';

/// Where the money ends up when this escrow completes.
enum EscrowSealDestination { buyer, vendor }

/// settled/released pay the vendor; refunded/expired return to the buyer.
EscrowSealDestination escrowSealDestination(SmartEscrow escrow) {
  switch (escrow.status) {
    case EscrowStatus.settled:
    case EscrowStatus.released:
      return EscrowSealDestination.vendor;
    case EscrowStatus.refunded:
    case EscrowStatus.expired:
    default:
      return EscrowSealDestination.buyer;
  }
}

/// Elapsed fraction of the funded→expires window, clamped to 0..1.
/// Returns 0 when either timestamp is missing (honesty rule) or the window is
/// degenerate (expiresAt at/before fundedAt).
double escrowRingFraction(SmartEscrow escrow, DateTime now) {
  final funded = escrow.fundedAt;
  final expires = escrow.expiresAt;
  if (funded == null || expires == null) return 0;
  final total = expires.difference(funded).inMilliseconds;
  if (total <= 0) return 0;
  final elapsed = now.difference(funded).inMilliseconds;
  return (elapsed / total).clamp(0.0, 1.0).toDouble();
}

/// Stable seed for decorative geometry — F-046: never String.hashCode.
int escrowStableSeed(String id) =>
    id.codeUnits.fold<int>(7, (sum, unit) => sum * 31 + unit);

/// Human label under the amount. Never invents a deadline:
/// terminal → the status label; no expiresAt → 'Auto-release';
/// overdue-but-active → 'Release pending'; otherwise d/h, h/m, m or <1m.
String escrowCountdownLabel(SmartEscrow escrow, DateTime now) {
  if (escrow.status.isTerminal) return escrow.status.label;
  final expires = escrow.expiresAt;
  if (expires == null) return 'Auto-release';
  final remaining = expires.difference(now);
  if (remaining.inSeconds <= 0) return 'Release pending';
  final days = remaining.inDays;
  final hours = remaining.inHours % 24;
  final minutes = remaining.inMinutes % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes >= 1) return '${minutes}m';
  return '<1m';
}

// ── Geometry (fixed at design time, all logical px) ─────────────────────────

const double _kRailHeight = 128;
const double _kNodeDot = 22;
const double _kNodeWidth = 68;
const double _kNodeCentreY = 44;
const double _kVaultWidth = 150;
const double _kVaultHeight = 96;
const double _kVaultTop = 6;
const double _kCoinBoxW = 28;
const double _kCoinBoxH = 20;
const double _kCoinRestFromBottom = 14;
const Duration _kSealDuration = Duration(milliseconds: 1100);

/// Buyer → vault → vendor flow rail with the unseal moment.
class EscrowVaultRail extends ConsumerStatefulWidget {
  final SmartEscrow? escrow;
  final int currentUserId;
  final bool isLoading;

  const EscrowVaultRail({
    super.key,
    required this.escrow,
    required this.currentUserId,
    required this.isLoading,
  });

  @override
  ConsumerState<EscrowVaultRail> createState() => _EscrowVaultRailState();
}

class _EscrowVaultRailState extends ConsumerState<EscrowVaultRail>
    with TickerProviderStateMixin {
  /// One-shot unseal controller. Pinned at 1.0 when idle so pumpAndSettle
  /// never hangs on it. F-049: this State drives TWO controllers — plain
  /// TickerProviderStateMixin, never SingleTickerProviderStateMixin.
  late final AnimationController _seal = AnimationController(
    vsync: this,
    duration: _kSealDuration,
    value: 1.0,
  );

  /// One-second repeater refreshing the countdown while the escrow is active.
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  SmartEscrow? _lastEscrow;
  bool _playedUnseal = false;

  @override
  void initState() {
    super.initState();
    _lastEscrow = widget.escrow;
    _seal.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_playedUnseal) {
        _playedUnseal = true;
        AzamanHaptics.moneyLanded();
      }
    });
    _syncTicker(widget.escrow);
  }

  @override
  void didUpdateWidget(EscrowVaultRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prev = _lastEscrow;
    final next = widget.escrow;
    _lastEscrow = next;
    if (next == null) {
      _ticker.stop();
      return;
    }

    final prevActive = prev != null && prev.status.isActive;
    if (prevActive && next.status.isTerminal) {
      // The live moment: the provider pushed a terminal escrow while the user
      // is looking at an active one. Stop the repeater, play the unseal.
      _syncTicker(next);
      if (liquidReducedMotion(context)) {
        _seal.value = 1.0;
        if (!_playedUnseal) {
          _playedUnseal = true;
          AzamanHaptics.moneyLanded();
        }
      } else if (_seal.value >= 1.0) {
        _seal.forward(from: 0);
      }
    } else {
      _syncTicker(next);
    }
  }

  void _syncTicker(SmartEscrow? escrow) {
    if (escrow != null && escrow.status.isActive) {
      if (!_ticker.isAnimating) _ticker.repeat();
    } else {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _seal.dispose();
    _ticker.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final escrow = widget.escrow;

    if (escrow == null) {
      return Container(
        height: 56,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(AzRadius.md),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.isLoading ? 'Vault status loading…' : 'No escrow on this ticket',
          style: AzText.caption.copyWith(color: colors.textTertiary),
        ),
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_ticker, _seal]),
      builder: (context, _) {
        final now = DateTime.now();
        final terminal = escrow.status.isTerminal;
        final t = _seal.value;
        final postState = terminal && t >= 1.0;
        final dest = escrowSealDestination(escrow);
        final buyerLabel = widget.currentUserId == escrow.payerId
            ? 'You'
            : (escrow.payer?.username ?? 'Buyer');
        final vendorLabel = widget.currentUserId == escrow.payeeId
            ? 'You'
            : (escrow.payee?.username ?? 'Vendor');
        final hasWindow = escrow.fundedAt != null && escrow.expiresAt != null;

        return SizedBox(
          height: _kRailHeight,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              if (w <= 0) return const SizedBox.shrink();
              final vaultLeft = w / 2 - _kVaultWidth / 2;
              final destX = dest == EscrowSealDestination.vendor ? w - 36 : 36.0;
              final slideT = Curves.easeInOut
                  .transform(((t - 0.30) / 0.45).clamp(0.0, 1.0).toDouble());
              final vaultCx = w / 2;
              const coinRestY = _kVaultTop + _kVaultHeight - _kCoinRestFromBottom;
              final coinCx = vaultCx + (destX - vaultCx) * slideT;
              final coinCy = coinRestY + (_kNodeCentreY - coinRestY) * slideT;
              final vaultOpacity =
                  (1.0 - (t / 0.45).clamp(0.0, 1.0).toDouble());
              final coinOpacity =
                  t <= 0.30 ? 1.0 : (1.0 - (t - 0.30) / 0.70).clamp(0.0, 1.0);

              return Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _FlowPainter(
                          t: t,
                          terminal: terminal,
                          width: w,
                          vaultLeft: vaultLeft,
                          vaultRight: vaultLeft + _kVaultWidth,
                          destX: destX,
                          destY: _kNodeCentreY,
                          divider: colors.divider,
                          accent: colors.accent,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 2,
                    top: _kNodeCentreY - _kNodeDot / 2,
                    width: _kNodeWidth,
                    child: _PartyNode(
                      label: buyerLabel,
                      isYou: widget.currentUserId == escrow.payerId,
                      colors: colors,
                    ),
                  ),
                  Positioned(
                    right: 2,
                    top: _kNodeCentreY - _kNodeDot / 2,
                    width: _kNodeWidth,
                    child: _PartyNode(
                      label: vendorLabel,
                      isYou: widget.currentUserId == escrow.payeeId,
                      colors: colors,
                    ),
                  ),
                  if (!postState)
                    Positioned(
                      left: vaultLeft,
                      top: _kVaultTop,
                      width: _kVaultWidth,
                      height: _kVaultHeight,
                      child: Opacity(
                        opacity: vaultOpacity,
                        child: PremiumGlassContainer(
                          blur: 14,
                          opacity: 0.08,
                          borderRadius: AzRadius.md,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AzSpace.sm,
                            vertical: AzSpace.sm,
                          ),
                          child: Stack(
                            children: [
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'ESCROW',
                                      style: AzText.eyebrow.copyWith(
                                          color: colors.textTertiary),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${escrow.amountUsdc.toStringAsFixed(2)} USDC',
                                      style: AzText.money(
                                          colors.textPrimary, size: 19),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      escrowCountdownLabel(escrow, now),
                                      style: AzText.caption.copyWith(
                                          color: colors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              if (hasWindow)
                                Positioned(
                                  right: AzSpace.sm,
                                  top: AzSpace.sm,
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      key: const ValueKey(
                                          'escrow-countdown-ring'),
                                      size: const Size(22, 22),
                                      painter: _CountdownRingPainter(
                                        fraction:
                                            escrowRingFraction(escrow, now),
                                        ring: colors.accent,
                                        track: colors.divider,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (postState)
                    Positioned(
                      left: vaultLeft,
                      top: _kVaultTop,
                      width: _kVaultWidth,
                      height: _kVaultHeight,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.success.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(AzRadius.md),
                          border: Border.all(
                              color: colors.success.withValues(alpha: 0.35)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              escrow.status.label.toUpperCase(),
                              style: AzText.eyebrow
                                  .copyWith(color: colors.success),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${escrow.amountUsdc.toStringAsFixed(2)} USDC',
                              style: AzText.money(colors.textPrimary, size: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!postState)
                    Positioned(
                      left: coinCx - _kCoinBoxW / 2,
                      top: coinCy - _kCoinBoxH / 2,
                      width: _kCoinBoxW,
                      height: _kCoinBoxH,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: coinOpacity,
                          child: _CoinStack(
                            key: const ValueKey('escrow-coin-slide'),
                            seed: escrowStableSeed(escrow.id),
                            coin: colors.warning,
                          ),
                        ),
                      ),
                    ),
                  if (!postState)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: const ValueKey('escrow-seal-rim'),
                          painter: _SealPainter(
                            t: t,
                            rect: Rect.fromLTWH(vaultLeft, _kVaultTop,
                                _kVaultWidth, _kVaultHeight),
                            rim: colors.accent,
                            terminal: terminal,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painters and nodes.
// ─────────────────────────────────────────────────────────────────────────────

/// Dashed connectors + destination glow bloom. Everything is computed from
/// [t] so a single painter drives the whole flow layer.
class _FlowPainter extends CustomPainter {
  final double t;
  final bool terminal;
  final double width;
  final double vaultLeft;
  final double vaultRight;
  final double destX;
  final double destY;
  final Color divider;
  final Color accent;

  const _FlowPainter({
    required this.t,
    required this.terminal,
    required this.width,
    required this.vaultLeft,
    required this.vaultRight,
    required this.destX,
    required this.destY,
    required this.divider,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final slideT = Curves.easeInOut
        .transform(((t - 0.30) / 0.45).clamp(0.0, 1.0).toDouble());
    final flow = Color.lerp(divider, accent, terminal ? slideT * 0.8 : 0.0)!;
    final paint = Paint()
      ..color = flow
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    _dash(canvas, const Offset(36 + _kNodeDot / 2 + 4, _kNodeCentreY),
        Offset(vaultLeft, _kNodeCentreY), paint);
    _dash(canvas, Offset(vaultRight, _kNodeCentreY),
        Offset(width - 36 - _kNodeDot / 2 - 4, _kNodeCentreY), paint);

    if (terminal) {
      final landingT =
          ((t - 0.70) / 0.30).clamp(0.0, 1.0).toDouble();
      if (landingT > 0) {
        final landingE = Curves.easeOutBack.transform(landingT);
        canvas.drawCircle(
          Offset(destX, destY),
          12 + 8 * landingE,
          Paint()
            ..color = accent
                .withValues(alpha: (0.30 * (1 - landingT)).clamp(0.0, 1.0))
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  static void _dash(Canvas canvas, Offset a, Offset b, Paint paint) {
    final delta = b - a;
    final total = delta.distance;
    if (total <= 0) return;
    final dir = delta / total;
    const dash = 4.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < total) {
      final end = math.min(x + dash, total);
      canvas.drawLine(a + dir * x, a + dir * end, paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.t != t ||
      old.terminal != terminal ||
      old.width != width ||
      old.vaultLeft != vaultLeft ||
      old.vaultRight != vaultRight ||
      old.destX != destX ||
      old.destY != destY ||
      old.divider != divider ||
      old.accent != accent;
}

/// The goo rim. Held (t = 0): crisp 1px contour via paintGoo at sigma 1.
/// Dissolve (t → 0.45): sigma runs 1 → 7 (the blur→threshold pair moves
/// together inside paintGoo — gooRimFor interpolates both) and the rim alpha
/// runs to 0. At t ≥ 0.45 this widget is not rendered at all (postState).
class _SealPainter extends CustomPainter {
  final double t;
  final Rect rect;
  final Color rim;
  final bool terminal;

  const _SealPainter({
    required this.t,
    required this.rect,
    required this.rim,
    required this.terminal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dissolveT = (t / 0.45).clamp(0.0, 1.0).toDouble();
    final sigma = 1.0 + 6.0 * dissolveT;
    final alpha = terminal
        ? (0.9 * (1.0 - dissolveT)).clamp(0.0, 1.0).toDouble()
        : 0.9;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          rect.deflate(1.5), const Radius.circular(AzRadius.md)));
    paintGoo(
      canvas,
      bounds: rect.inflate(24),
      sigma: sigma,
      body: Colors.transparent,
      rim: rim.withValues(alpha: alpha),
      shapes: (c, p) => c.drawPath(path, p),
    );
  }

  @override
  bool shouldRepaint(_SealPainter old) =>
      old.t != t || old.rect != rect || old.rim != rim || old.terminal != terminal;
}

/// 22px countdown badge: divider track + accent arc sweeping the window.
class _CountdownRingPainter extends CustomPainter {
  final double fraction;
  final Color ring;
  final Color track;

  const _CountdownRingPainter({
    required this.fraction,
    required this.ring,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 2;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = track,
    );
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0.0, 1.0).toDouble(),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_CountdownRingPainter old) =>
      old.fraction != fraction || old.ring != ring || old.track != track;
}

/// Buyer / vendor node: dot + one-line label. 'You' renders accent and bold.
class _PartyNode extends StatelessWidget {
  final String label;
  final bool isYou;
  final AzamanColors colors;

  const _PartyNode({
    required this.label,
    required this.isYou,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final dot = isYou ? colors.accent : colors.textTertiary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _kNodeDot,
          height: _kNodeDot,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dot.withValues(alpha: isYou ? 0.18 : 0.12),
            border: Border.all(color: dot.withValues(alpha: 0.8), width: 1.5),
          ),
          child: Icon(Icons.person_outline, size: 13, color: dot),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: _kNodeWidth,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AzText.caption.copyWith(
              color: isYou ? colors.accent : colors.textTertiary,
              fontWeight: isYou ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Three decorative coins, offsets derived from [seed] (F-046).
class _CoinStack extends StatelessWidget {
  final int seed;
  final Color coin;

  const _CoinStack({super.key, required this.seed, required this.coin});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < 3; i++)
          Positioned(
            left: _kCoinBoxW / 2 -
                (14 - i * 1.5) / 2 +
                (((seed >> (i * 4)) % 7) - 3).toDouble(),
            top: i * 3.0,
            child: Container(
              width: 14 - i * 1.5,
              height: 14 - i * 1.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: coin.withValues(alpha: 1.0 - i * 0.22),
                border: Border.all(color: coin.withValues(alpha: 0.35)),
              ),
            ),
          ),
      ],
    );
  }
}
