// =============================================================================
// AZAMAN — TRANSIT BOARDING PASS KEEPSAKE (TASK-014)
//
// §7.3's Level-5 keepsake: a paper boarding pass with a perforated tear
// line. The top stub (barcode + ref) tears off with a downward drag, the
// same gesture as a physical pass.
//
// Honesty rules:
//   * The barcode is DECORATIVE — deterministic bars derived from the
//     booking id, not a scannable code. A real check-in QR belongs to the
//     artifact wallet (TASK-021) and the backend check-in flow.
//   * The status chip comes from TransitBoardingStatus.fromPass — no
//     invented states.
//
// Lifecycle (corrigendum 2.3): this state owns TWO controllers (the live
// 1-second status ticker and the tear controller), so it uses
// TickerProviderStateMixin. The tear duration resolves through
// MotionTokens.accessibleDuration from didChangeDependencies() — the
// reduced-motion lookup reads MediaQuery and never runs in initState.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:azaman/marketplace/experiences/transit/transit_boarding.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';

// Paper palette shared with the restaurant build sheet (TASK-013).
const _paperTop = Color(0xFFF3E9D2);
const _paperMid = Color(0xFFFDF6E3);
const _paperBottom = Color(0xFFFFFBF0);
const _ink = Color(0xFF2D2416);
const _inkMuted = Color(0xFF8B7A5A);
const _seam = Color(0xFFE8DCC4);

/// Stable integer seed for the decorative barcode. [String.hashCode] is NOT
/// stable across runs — never use it for a deterministic visual.
int _stableSeed(String id) =>
    id.codeUnits.fold<int>(7, (sum, unit) => sum * 31 + unit);

class TransitBoardingPassCard extends StatefulWidget {
  final TransitBoardingPass pass;
  final AzamanColors colors;

  const TransitBoardingPassCard({
    super.key,
    required this.pass,
    required this.colors,
  });

  @override
  State<TransitBoardingPassCard> createState() =>
      _TransitBoardingPassCardState();
}

class _TransitBoardingPassCardState extends State<TransitBoardingPassCard>
    with TickerProviderStateMixin {
  late final AnimationController _ticker;
  late final AnimationController _tearController;
  double _tearDrag = 0;
  bool _torn = false;

  @override
  void initState() {
    super.initState();
    // 1-second ticker for the live departure status (ticker, not a Timer).
    _ticker = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
    // Duration starts at the normal value; the accessibility-aware duration
    // is resolved in didChangeDependencies (never MediaQuery in initState).
    _tearController = AnimationController(
      duration: MotionTokens.standard,
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = MotionTokens.accessibleDuration(
      context,
      MotionTokens.standard,
    );
    if (_tearController.duration != duration) {
      // Reduced-motion setting may have changed; update without replaying.
      _tearController.duration = duration;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tearController.dispose();
    super.dispose();
  }

  void _onTearUpdate(DragUpdateDetails details) {
    if (_torn) return;
    setState(() {
      _tearDrag = (_tearDrag + details.delta.dy).clamp(0.0, 90.0).toDouble();
    });
  }

  void _onTearEnd(DragEndDetails details) {
    if (_torn) return;
    if (_tearDrag >= 45) {
      // Committed: the stub separates and falls away.
      AzamanHaptics.moneyLanded();
      setState(() => _torn = true);
      _tearController.forward(from: 0);
    } else {
      // Didn't commit: the pass snaps shut — instant, like real paper.
      setState(() => _tearDrag = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pass = widget.pass;
    const stubHeight = 96.0;

    return AnimatedBuilder(
      animation: _tearController,
      builder: (context, _) {
        final t = _tearController.value;
        final tornGone = _torn && t >= 1.0;
        return Container(
          decoration: BoxDecoration(
            borderRadius: AzRadius.brLg,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_paperTop, _paperMid, _paperBottom],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              AnimatedPadding(
                duration: MotionTokens.control,
                curve: MotionTokens.enter,
                padding: EdgeInsets.only(top: tornGone ? 18.0 : stubHeight),
                child: _buildMain(pass),
              ),
              if (!tornGone)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildStub(pass, t),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStub(TransitBoardingPass pass, double t) {
    final y = _torn
        ? _tearDrag + 130.0 * Curves.easeIn.transform(t)
        : _tearDrag;
    final angle = (_tearDrag / 90.0) * 0.05 + (_torn ? 0.45 * t : 0);
    final opacity = _torn ? 1.0 - t : 1.0;

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, y),
        child: Transform.rotate(
          angle: angle,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onVerticalDragUpdate: _onTearUpdate,
            onVerticalDragEnd: _onTearEnd,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            'AZAMAN TRANSIT',
                            style: AzText.caption.copyWith(
                              color: _ink,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'KEEP THIS STUB',
                            style: AzText.caption.copyWith(
                              color: _inkMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AzSpace.sm),
                      SizedBox(
                        width: double.infinity,
                        height: 34,
                        child: CustomPaint(
                          painter: _BarcodePainter(
                            seed: _stableSeed(pass.bookingId),
                          ),
                        ),
                      ),
                      const SizedBox(height: AzSpace.sm),
                      Text(
                        pass.bookingId.toUpperCase(),
                        style: AzText.caption.copyWith(
                          color: _inkMuted,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'PULL DOWN TO TEAR',
                        style: AzText.caption.copyWith(
                          color: _inkMuted,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: double.infinity,
                  height: 14,
                  child: CustomPaint(painter: _PerforationPainter()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMain(TransitBoardingPass pass) {
    final trip = pass.trip;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _ticker,
            builder: (context, _) => _statusChip(pass),
          ),
          const SizedBox(height: AzSpace.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _station(trip.origin, _formatTime(trip.departure)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AzSpace.sm),
                child: Column(
                  children: [
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: _inkMuted,
                    ),
                    Text(
                      '${trip.departure.day}/${trip.departure.month}',
                      style: AzText.caption.copyWith(color: _inkMuted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _station(
                  trip.destination,
                  _formatTime(trip.arrival),
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AzSpace.md),
          const _PaperRule(),
          const SizedBox(height: AzSpace.sm),
          _kv('Operator', trip.operatorName ?? '—'),
          _kv('Vehicle', trip.vehicleType ?? '—'),
          _kv('Seats', pass.seatIds.join(', ')),
          const SizedBox(height: AzSpace.sm),
          const _PaperRule(),
          const SizedBox(height: AzSpace.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Present this pass at boarding',
                  style: AzText.bodyS.copyWith(color: _inkMuted),
                ),
              ),
              Text(
                '${trip.currency ?? 'USDC'} ${trip.fare?.toStringAsFixed(2) ?? '—'}',
                style: AzText.money(_ink, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(TransitBoardingPass pass) {
    final status = TransitBoardingStatus.fromPass(pass);
    final color = status.actionable
        ? widget.colors.success
        : widget.colors.textTertiary;
    return Container(
      padding: AzSpace.tag,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AzRadius.brSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: AzText.label.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _station(String name, String time, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          time,
          style: AzText.titleL.copyWith(
            color: _ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AzSpace.xs),
        Text(
          name,
          style: AzText.bodyS.copyWith(color: _inkMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: AzText.caption.copyWith(color: _inkMuted),
          ),
          const Spacer(),
          Text(
            value,
            style: AzText.label.copyWith(
              color: _ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _PaperRule extends StatelessWidget {
  const _PaperRule();

  @override
  Widget build(BuildContext context) => Container(height: 1, color: _seam);
}

/// Deterministic decorative barcode — derived from a stable integer seed
/// (never [String.hashCode], which is not stable across runs).
class _BarcodePainter extends CustomPainter {
  final int seed;
  const _BarcodePainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    final barPaint = Paint()..color = _ink;
    double x = 0;
    while (x < size.width) {
      final width = 1.0 + random.nextInt(3).toDouble();
      final gap = 1.5 + random.nextInt(3).toDouble();
      if (x + width > size.width) break;
      canvas.drawRect(Rect.fromLTWH(x, 0, width, size.height), barPaint);
      x += width + gap;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter oldDelegate) => oldDelegate.seed != seed;
}

/// Perforation: a dashed seam with bite notches at both ends.
class _PerforationPainter extends CustomPainter {
  const _PerforationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final dashPaint = Paint()
      ..color = _seam
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const dash = 7.0;
    const gap = 5.0;
    double x = 18;
    while (x < size.width - 18) {
      canvas.drawLine(Offset(x, midY), Offset(x + dash, midY), dashPaint);
      x += dash + gap;
    }

    final bitePaint = Paint()
      ..color = _seam
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final edgeX in [0.0, size.width]) {
      final center = Offset(edgeX == 0 ? 8 : size.width - 8, midY);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 6),
        edgeX == 0 ? -math.pi / 2 : math.pi / 2,
        math.pi,
        false,
        bitePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter oldDelegate) => false;
}
