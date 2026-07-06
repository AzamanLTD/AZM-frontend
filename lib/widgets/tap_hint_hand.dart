// =============================================================================
// TAP HINT HAND — Animated first-time hint for the FlippableBalanceCard
//
// A small hand with its index finger pointing at the balance card. Does a
// gentle back-and-forth tapping motion to indicate "tap here." Shows only
// once per user (persisted via SharedPreferences). Fades away after the
// user has tapped the card or after 8 seconds, whichever comes first.
//
// Design:
//   - Hand drawn with CustomPainter (no external assets needed)
//   - Finger does a 3-tap animation with slight scale-down on each tap
//   - Glow pulse around the fingertip on each tap
//   - Fades in on appear, fades out on dismiss
//   - Positioned to overlap the bottom-right of the balance card
// =============================================================================

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/animation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The key used to persist the "has seen tap hint" flag.
const _kHasSeenFlipHintKey = 'has_seen_flippable_card_hint';

/// Shows the [TapHintHand] overlay above its child if the user hasn't
/// seen the hint yet. Dismisses on tap of the child or after a timeout.
///
/// Usage:
/// ```dart
/// TapHintOverlay(
///   hintKey: 'has_seen_flippable_card_hint',
///   child: FlippableBalanceCard(),
/// )
/// ```
class TapHintOverlay extends StatefulWidget {
  final String hintKey;
  final Widget child;
  final Duration timeout;

  const TapHintOverlay({
    super.key,
    required this.hintKey,
    required this.child,
    this.timeout = const Duration(seconds: 8),
  });

  @override
  State<TapHintOverlay> createState() => _TapHintOverlayState();
}

class _TapHintOverlayState extends State<TapHintOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _tapCtrl;
  bool _showHint = false;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Tap animation: 3 taps over 2.4s, then pause 0.8s, repeat
    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _checkIfShouldShow();
  }

  Future<void> _checkIfShouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(widget.hintKey) ?? false;
    if (!seen && mounted) {
      setState(() => _showHint = true);
      _fadeCtrl.forward();
      _tapCtrl.repeat();
      // Auto-dismiss after timeout
      Future.delayed(widget.timeout, _dismiss);
    }
  }

  Future<void> _dismiss() async {
    if (_dismissing || !_showHint) return;
    _dismissing = true;
    _tapCtrl.stop();
    await _fadeCtrl.reverse();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(widget.hintKey, true);
    if (mounted) setState(() => _showHint = false);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _tapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showHint) return widget.child;

    return GestureDetector(
      onTap: _dismiss,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          // Hand overlay — positioned at bottom-right of the card
          Positioned(
            right: -8,
            bottom: -4,
            child: AnimatedBuilder(
              animation: _fadeCtrl,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeCtrl.value,
                  child: child,
                );
              },
              child: AnimatedBuilder(
                animation: _tapCtrl,
                builder: (context, _) {
                  return _TapHintHand(progress: _tapCtrl.value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The actual animated hand widget. [progress] is 0.0-1.0 from the
/// repeating AnimationController.
class _TapHintHand extends StatelessWidget {
  final double progress;

  const _TapHintHand({required this.progress});

  @override
  Widget build(BuildContext context) {
    // Calculate tap motion: 3 taps within the 3200ms cycle
    // Tap cycle: 0.0-0.28 = tap 1, 0.28-0.56 = tap 2, 0.56-0.84 = tap 3
    // 0.84-1.0 = pause
    double offsetX = 0;
    double scale = 1.0;
    double glowOpacity = 0;

    final tapProgress = (progress % 0.28) / 0.28;

    if (progress < 0.84) {
      // Each tap: move toward card (offsetX goes negative), scale down slightly
      // Then pull back
      if (tapProgress < 0.5) {
        // Moving toward card
        final t = Curves.easeIn.transform(tapProgress * 2);
        offsetX = -6.0 * t;
        scale = 1.0 - 0.08 * t;
        glowOpacity = t;
      } else {
        // Pulling back
        final t = Curves.easeOut.transform((tapProgress - 0.5) * 2);
        offsetX = -6.0 * (1 - t);
        scale = 0.92 + 0.08 * t;
        glowOpacity = 1.0 - t;
      }
    } else {
      // Pause — slight idle bob
      final t = (progress - 0.84) / 0.16;
      offsetX = math.sin(t * math.pi) * 1.5;
      glowOpacity = 0;
    }

    return Transform.translate(
      offset: Offset(offsetX, 0),
      child: Transform.scale(
        scale: scale,
        child: SizedBox(
          width: 56,
          height: 64,
          child: CustomPaint(
            painter: _HandPainter(
              glowOpacity: glowOpacity,
              accentColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF00D97E)
                  : const Color(0xFF00B364),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter that draws a pointing hand with index finger extended.
class _HandPainter extends CustomPainter {
  final double glowOpacity;
  final Color accentColor;

  _HandPainter({required this.glowOpacity, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Glow circle at fingertip
    if (glowOpacity > 0) {
      final glowPaint = Paint()
        ..color = accentColor.withOpacity(glowOpacity * 0.3)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(w * 0.35, h * 0.18), 10, glowPaint);
    }

    // Hand color
    final handPaint = Paint()
      ..color = const Color(0xFFE8D5C4)
      ..style = PaintingStyle.fill;

    final outlinePaint = Paint()
      ..color = const Color(0xFF8B7355)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Palm (rounded rectangle at bottom)
    final palmRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.15, h * 0.42, w * 0.55, h * 0.45),
      const Radius.circular(8),
    );
    canvas.drawRRect(palmRect, handPaint);
    canvas.drawRRect(palmRect, outlinePaint);

    // Thumb (small, angled left)
    final thumbPath = Path();
    thumbPath.moveTo(w * 0.15, h * 0.55);
    thumbPath.quadraticBezierTo(w * 0.02, h * 0.50, w * 0.05, h * 0.42);
    thumbPath.quadraticBezierTo(w * 0.08, h * 0.38, w * 0.18, h * 0.48);
    canvas.drawPath(thumbPath, handPaint);
    canvas.drawPath(thumbPath, outlinePaint);

    // Index finger (extended upward, pointing at the card)
    final fingerPath = Path();
    fingerPath.moveTo(w * 0.28, h * 0.42);
    fingerPath.quadraticBezierTo(w * 0.30, h * 0.25, w * 0.33, h * 0.08);
    fingerPath.quadraticBezierTo(w * 0.35, h * 0.03, w * 0.38, h * 0.08);
    fingerPath.quadraticBezierTo(w * 0.38, h * 0.25, w * 0.36, h * 0.42);
    canvas.drawPath(fingerPath, handPaint);
    canvas.drawPath(fingerPath, outlinePaint);

    // Fingernail on index finger
    final nailPaint = Paint()
      ..color = const Color(0xFFC4A88B)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromLTWH(w * 0.33, h * 0.06, w * 0.06, h * 0.04),
      nailPaint,
    );

    // Curled fingers (middle, ring, pinky) — shown as a rounded bump
    final curledPath = Path();
    curledPath.moveTo(w * 0.40, h * 0.42);
    curledPath.quadraticBezierTo(w * 0.52, h * 0.35, w * 0.62, h * 0.42);
    curledPath.lineTo(w * 0.62, h * 0.48);
    curledPath.lineTo(w * 0.40, h * 0.48);
    curledPath.close();
    canvas.drawPath(curledPath, handPaint);
    canvas.drawPath(curledPath, outlinePaint);

    // Sleeve/cuff at the bottom (gradient to match app theme)
    final sleevePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF6C5FC7),
          const Color(0xFF4A3F8A),
        ],
      ).createShader(Rect.fromLTWH(0, h * 0.80, w, h * 0.20));
    final sleevePath = Path();
    sleevePath.moveTo(w * 0.12, h * 0.82);
    sleevePath.lineTo(w * 0.73, h * 0.82);
    sleevePath.lineTo(w * 0.78, h * 0.98);
    sleevePath.lineTo(w * 0.07, h * 0.98);
    sleevePath.close();
    canvas.drawPath(sleevePath, sleevePaint);
  }

  @override
  bool shouldRepaint(_HandPainter oldDelegate) =>
      oldDelegate.glowOpacity != glowOpacity;
}
