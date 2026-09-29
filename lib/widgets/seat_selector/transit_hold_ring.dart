// =============================================================================
// AZAMAN — TRANSIT HOLD RING (TASK-014)
//
// A draining ring that visualises the seat-hold countdown in the booking
// dock. Per §7.3: accent → warning → danger as the window drains, tabular
// seconds, a single threshold haptic at 25%, and one "expired" callback.
//
// TEST-SAFETY (critical): this widget must never hold a pending Timer.
// `pumpAndSettle` is already unusable around BusSeatSelector (repeating
// pulse animation), and a pending Timer would fail widget tests outright.
// The ring therefore ticks on a 1-second repeating AnimationController and
// computes the remaining time from DateTime.now() (or the injectable
// [clock] seam) on every tick. Repeating tickers are safe; timers are not.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// Fraction of the hold window remaining: 1.0 (just granted) → 0.0 (gone).
/// Pure and deterministic — pass [now] to evaluate any point in time.
double transitHoldFraction(
  DateTime? expiresAt,
  Duration window, {
  DateTime? now,
}) {
  if (expiresAt == null) return 0;
  final t = now ?? DateTime.now();
  if (!expiresAt.isAfter(t)) return 0;
  final total = window.inSeconds;
  if (total <= 0) return 0;
  final remaining = expiresAt.difference(t).inSeconds;
  return (remaining / total).clamp(0.0, 1.0).toDouble();
}

/// `m:ss` countdown label. Null expiry → `--:--`; expired → `0:00`.
String transitHoldCountdownLabel(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return '--:--';
  final t = now ?? DateTime.now();
  if (!expiresAt.isAfter(t)) return '0:00';
  final remaining = expiresAt.difference(t);
  final minutes = remaining.inMinutes;
  final seconds = remaining.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// The draining hold ring. Renders `SizedBox.shrink()` when [expiresAt] is
/// null, so callers can leave it mounted unconditionally.
class TransitHoldRing extends StatefulWidget {
  final DateTime? expiresAt;
  final Duration window;
  final Color accentColor;
  final Color warningColor;
  final Color dangerColor;
  final Color trackColor;

  /// Fired exactly once, on the frame the hold crosses into expiry.
  final VoidCallback? onExpired;

  /// Injectable clock for tests. Defaults to [DateTime.now].
  final DateTime Function()? clock;

  const TransitHoldRing({
    super.key,
    required this.expiresAt,
    this.window = const Duration(minutes: 5),
    required this.accentColor,
    required this.warningColor,
    required this.dangerColor,
    required this.trackColor,
    this.onExpired,
    this.clock,
  });

  @override
  State<TransitHoldRing> createState() => _TransitHoldRingState();
}

class _TransitHoldRingState extends State<TransitHoldRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  bool _thresholdFired = false;
  bool _expiredFired = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // A repeating ticker, never a Timer: listeners fire before the
    // AnimatedBuilder rebuild each second.
    _ticker =
        AnimationController(duration: const Duration(seconds: 1), vsync: this)
          ..addListener(_onTick)
          ..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick() {
    if (widget.expiresAt == null) return;
    final fraction = transitHoldFraction(
      widget.expiresAt,
      widget.window,
      now: _now,
    );

    // One urgency beat as the window enters its last quarter.
    if (fraction <= 0.25 && !_thresholdFired) {
      _thresholdFired = true;
      AzamanHaptics.threshold();
    }
    // Exactly one expiry callback, delivered post-frame.
    if (fraction <= 0 && !_expiredFired) {
      _expiredFired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExpired?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.expiresAt == null) return const SizedBox.shrink();

    return SizedBox(
      width: 36,
      height: 36,
      child: AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) {
          final fraction = transitHoldFraction(
            widget.expiresAt,
            widget.window,
            now: _now,
          );
          final label = transitHoldCountdownLabel(widget.expiresAt, now: _now);
          final color = fraction > 0.5
              ? widget.accentColor
              : fraction > 0.25
              ? widget.warningColor
              : widget.dangerColor;
          // Semantics lives INSIDE the ticker so TalkBack reads a live label.
          return Semantics(
            label: 'Seat hold expires in $label',
            child: CustomPaint(
              painter: _HoldRingPainter(
                fraction: fraction,
                color: color,
                trackColor: widget.trackColor,
                label: label,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HoldRingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color trackColor;
  final String label;

  const _HoldRingPainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 2.5;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, trackPaint);

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      progressPaint,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          fontFeatures: AzText.tabular,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
    tp.dispose();
  }

  @override
  bool shouldRepaint(_HoldRingPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.label != label;
  }
}
