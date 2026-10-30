// AZAMAN — FEEDBACK FOR A LOCKED MONEY ACTION
//
// A blocked action must feel blocked, not broken. Tapping a gated money
// surface while locked produces a short horizontal shake and a medium haptic;
// nothing is revealed and nothing is queued for later. The unlock path stays
// the Azaman button, so a shake explains the refusal instead of opening a
// different flow.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped once per refused attempt. The shake listens to this, not to the lock
/// state, so two refusals in a row each produce their own motion.
final moneyBlockedPulseProvider = StateProvider<int>((ref) => 0);

/// Refuse a money action: haptic plus a visible shake at each gated surface.
void blockedMoneyAccessFeedback(WidgetRef ref) {
  HapticFeedback.mediumImpact();
  ref.read(moneyBlockedPulseProvider.notifier).state++;
}

/// Shakes its child when a money action was refused while locked.
class MoneyLockShake extends ConsumerStatefulWidget {
  const MoneyLockShake({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MoneyLockShake> createState() => _MoneyLockShakeState();
}

class _MoneyLockShakeState extends ConsumerState<MoneyLockShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(moneyBlockedPulseProvider, (previous, next) {
      if (previous == next) return;
      // Reduced motion gets the haptic only: the refusal is still legible
      // without moving the thing the member is looking at.
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
      _controller.forward(from: 0);
    });

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        if (t == 0 || t == 1) return child!;
        // A damped sine: 1.5 oscillations that die away, so it reads as a
        // refusal rather than as the control being grabbed.
        final envelope = (1 - t) * (1 - t);
        final dx = 8 * envelope * math.sin(t * math.pi * 3);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}
