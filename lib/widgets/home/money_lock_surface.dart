// AZAMAN — LOCKED MONEY SURFACE
//
// What a member sees in place of money while the local gate is locked. The
// sensitive content is NOT built and NOT painted: this is a replacement, not
// a blur over a live number, so no amount can leak through semantics, screen
// readers, screenshots of the widget tree or the accessibility tree.
//
// Tapping it explains the affordance instead of performing it: a short
// selection haptic, one small shake, and a hint pointing at the Home lock.
// Nothing navigates, no quote is created, no request is sent.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/widgets/home/money_lock_blocked_feedback.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class LockedMoneySurface extends ConsumerStatefulWidget {
  const LockedMoneySurface({
    super.key,
    this.message = 'Your money is locked',
    this.hint = 'Tap the Azaman button below to unlock.',
    this.compact = false,
  });

  final String message;
  final String hint;

  /// Compact drops the body hint, for tight rows inside existing furniture.
  final bool compact;

  @override
  ConsumerState<LockedMoneySurface> createState() => _LockedMoneySurfaceState();
}

class _LockedMoneySurfaceState extends ConsumerState<LockedMoneySurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  late final Animation<double> _offset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -4.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -4.0, end: 4.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 4.0, end: -2.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -2.0, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _shake, curve: Curves.easeOut));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      TickerMode.valuesOf(context).enabled == false ||
      MediaQuery.maybeDisableAnimationsOf(context) == true;

  void _onTap() {
    AzamanHaptics.selection();
    if (_reduceMotion) return;
    _shake.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Semantics(
      button: true,
      label: widget.message,
      hint: widget.hint,
      child: GestureDetector(
        key: const ValueKey('locked-money-surface'),
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: AnimatedBuilder(
          animation: _offset,
          builder: (context, child) => Transform.translate(
            offset: Offset(_offset.value, 0),
            child: child,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 22, color: colors.mutedAccent),
                const SizedBox(height: 8),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: AzText.title.copyWith(color: colors.textPrimary),
                ),
                if (!widget.compact) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.hint,
                    textAlign: TextAlign.center,
                    style: AzText.caption.copyWith(color: colors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders [child] only when the money gate is unlocked.
class MoneyLockGate extends ConsumerWidget {
  const MoneyLockGate({
    super.key,
    required this.child,
    this.compact = false,
    this.message,
    this.hint,
    this.height,
  });

  final Widget child;
  final bool compact;
  final String? message;
  final String? hint;

  /// Optional fixed height for the locked replacement. Surfaces that have a
  /// size contract of their own (the 180dp balance deck) pass it so the gate
  /// never collapses layout while locked.
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(moneyAccessProvider);
    if (access.canViewMoney) return child;
    // A tap on the gate is a refused attempt: it shakes and haptics instead of
    // silently doing nothing, and it never reveals or defers the action.
    final locked = MoneyLockShake(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => blockedMoneyAccessFeedback(ref),
        child: LockedMoneySurface(
          compact: compact,
          message: message ?? 'Your money is locked',
          hint: hint ?? 'Tap the Azaman button below to unlock.',
        ),
      ),
    );
    if (height == null) return locked;
    return SizedBox(height: height, child: locked);
  }
}
