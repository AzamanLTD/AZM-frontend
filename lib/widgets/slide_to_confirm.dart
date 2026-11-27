// =============================================================================
// AZAMAN V3 — SLIDE TO CONFIRM WIDGET
//
// A reusable swipe-to-confirm control. User drags a thumb from left to right.
// When it reaches >90% width, onConfirmed fires. Resets with spring animation
// if released before threshold.
//
// Usage:
//   SlideToConfirm(
//     text: 'Slide to send',
//     backgroundColor: colors.card,
//     thumbColor: colors.accent,
//     onConfirmed: () => doSomething(),
//     isLoading: false,
//     enabled: _canSubmit,   // optional — disabled means no-drag, no-fire
//   )
//
// =============================================================================
// PHASE H3 review-pass changes (compared to the original H2 widget):
//
// 1. New `enabled` prop. When false the slider doesn't accept drags. This
//    mirrors `ElevatedButton(onPressed: null)` semantics — important on
//    screens like upload_proof.dart where the action requires a precondition
//    (an image was picked) and we don't want the slider to commit and lock
//    itself when the precondition isn't met.
//
// 2. `didUpdateWidget` re-arms the slider on two transitions:
//    (a) `oldWidget.isLoading && !widget.isLoading && _confirmed` —
//        when the parent's busy flag falls back to false after an action
//        completed (typical: gate authenticated → action ran → finished
//        with success or backend error).
//    (b) `!oldWidget.enabled && widget.enabled && _confirmed` — when the
//        precondition flips back true after a confirmed-then-disabled run.
//
// 3. Public `SlideToConfirmState` (was private). Combined with the
//    `AzamanBiometricGate.run(..., onCancelled: ...)` callback, every gated
//    callsite holds a `GlobalKey<SlideToConfirmState>` and resets the
//    slider directly when the system biometric prompt is cancelled or the
//    auth fails. Without that path, the slider would commit to
//    `_confirmed = true` on swipe completion (necessary so the thumb
//    visibly snaps to the right) and stay locked forever — `_onDragEnd`
//    still does `setState(_confirmed=true); widget.onConfirmed();` in that
//    order, so the lock IS the default; the three reset mechanisms above
//    are what unstick it.
//
// 4. Visual: when `enabled` is false, the whole control is wrapped in
//    `Opacity(0.6)` so the inactive state reads as inactive without
//    needing per-callsite color juggling.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/utils/azaman_haptics.dart';

class SlideToConfirm extends StatefulWidget {
  final String text;
  final Color backgroundColor;
  final Color thumbColor;
  final VoidCallback onConfirmed;
  final bool isLoading;

  /// When false, the slider rejects drags. Mirrors `onPressed: null`.
  /// Defaults to true for backwards compat with H2 callsites.
  final bool enabled;

  const SlideToConfirm({
    super.key,
    required this.text,
    required this.backgroundColor,
    required this.thumbColor,
    required this.onConfirmed,
    this.isLoading = false,
    this.enabled = true,
  });

  @override
  State<SlideToConfirm> createState() => SlideToConfirmState();
}

class SlideToConfirmState extends State<SlideToConfirm>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0.0;

  /// The threshold tick fires once per crossing, never per frame.
  bool _pastThreshold = false;
  double _maxDrag = 0.0;
  bool _confirmed = false;
  late AnimationController _resetController;
  late Animation<double> _resetAnimation;

  static const double _thumbSize = 56.0;
  static const double _threshold = 0.90;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _resetAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _resetController, curve: Curves.elasticOut),
    );
    _resetController.addListener(() {
      setState(() {
        _dragPosition = _resetAnimation.value;
      });
    });
  }

  @override
  void didUpdateWidget(covariant SlideToConfirm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Phase H3 — re-arm on the loading transition. If a parent toggles
    // isLoading true while the action runs and then back to false on a
    // failure (biometric cancel, validation error, network error), reset
    // so the user can retry without leaving the screen.
    if (oldWidget.isLoading && !widget.isLoading && _confirmed) {
      _resetSilently();
    }
    // Re-arm when the slider transitions from disabled to enabled.
    if (!oldWidget.enabled && widget.enabled && _confirmed) {
      _resetSilently();
    }
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enabled || widget.isLoading || _confirmed) return;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || widget.isLoading || _confirmed) return;
    setState(() {
      _dragPosition = (_dragPosition + details.delta.dx).clamp(0.0, _maxDrag);
    });
    final past = _maxDrag > 0 && _dragPosition / _maxDrag >= _threshold;
    if (past != _pastThreshold) {
      _pastThreshold = past;
      if (past) AzamanHaptics.threshold();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled || widget.isLoading || _confirmed) return;

    final progress = _maxDrag > 0 ? _dragPosition / _maxDrag : 0.0;

    if (progress >= _threshold) {
      // Snap to end and confirm
      setState(() {
        _dragPosition = _maxDrag;
        _confirmed = true;
      });
      AzamanHaptics.commit();
      widget.onConfirmed();
    } else {
      // Animate back to start
      _pastThreshold = false;
      _resetAnimation = Tween<double>(begin: _dragPosition, end: 0.0).animate(
        CurvedAnimation(parent: _resetController, curve: Curves.elasticOut),
      );
      _resetController
        ..reset()
        ..forward();
    }
  }

  /// Public reset — call after a transaction completes/fails to re-arm
  /// the slider for another attempt.
  void reset() {
    if (!mounted) return;
    setState(() {
      _dragPosition = 0;
      _confirmed = false;
    });
  }

  /// Internal reset used from didUpdateWidget. Same as reset() but doesn't
  /// require an external GlobalKey/State reference — the widget heals
  /// itself when the parent's isLoading edge tells us the action ended.
  void _resetSilently() {
    setState(() {
      _dragPosition = 0;
      _confirmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxDrag = constraints.maxWidth - _thumbSize;

        final progress = _maxDrag > 0 ? _dragPosition / _maxDrag : 0.0;
        final isInactive = !widget.enabled;
        // The arrow, tick and spinner contrast with the thumb: on a night
        // stage the thumb is the sky's (white) ink, so white-on-white
        // would vanish.
        final onThumb = widget.thumbColor.computeLuminance() > 0.5
            ? const Color(0xFF15121A)
            : Colors.white;

        return Opacity(
          opacity: isInactive ? 0.6 : 1.0,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: widget.thumbColor.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                // Ink trail: fills from the start to the thumb's far edge,
                // deepening as the commit point nears.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: (_dragPosition + _thumbSize).clamp(0.0, constraints.maxWidth),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: ColoredBox(
                      color: widget.thumbColor.withValues(alpha: 0.10 + 0.22 * progress),
                    ),
                  ),
                ),

                // Text label (fades out as you drag)
                Center(
                  child: Opacity(
                    opacity: (1.0 - progress * 2).clamp(0.0, 1.0),
                    child: Text(
                      widget.text,
                      style: TextStyle(
                        color: widget.thumbColor.withValues(alpha: 0.85),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ),

                // Draggable thumb
                Positioned(
                  left: _dragPosition,
                  top: 2,
                  bottom: 2,
                  child: GestureDetector(
                    onHorizontalDragStart: _onDragStart,
                    onHorizontalDragUpdate: _onDragUpdate,
                    onHorizontalDragEnd: _onDragEnd,
                    child: Container(
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.thumbColor,
                        boxShadow: [
                          BoxShadow(
                            color: widget.thumbColor.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: widget.isLoading
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: onThumb,
                              ),
                            )
                          : Icon(
                              _confirmed
                                  ? Icons.check_circle_outline
                                  : Icons.arrow_forward,
                              color: onThumb,
                              size: 24,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
