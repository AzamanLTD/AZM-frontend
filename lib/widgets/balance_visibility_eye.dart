// =============================================================================
// BALANCE VISIBILITY EYE — the single balance-visibility toggle control
//
// RELOCATED, NOT REDESIGNED (Home header refresh, 2026-10-12): this is the
// exact control that used to sit in Home's greeting header — same
// balanceVisibleProvider toggle, same PremiumGlassContainer surface, same
// ScaleTap press, same AnimatedSwitcher view/view-off glyph transition, same
// AzamanHaptics.toggle() sensation. It now lives on the physical balance
// card itself, aligned with the AVAILABLE label.
//
// NESTED-GESTURE CONTRACT: the enclosing FlippableBalanceCard detects taps
// with a raw top-level Listener (it deliberately does NOT enter the gesture
// arena, so the holographic light Listener can coexist — see TASK-009c /
// F-024 notes in flippable_balance_card.dart). A raw Listener therefore also
// sees every tap that lands on this control. To keep "tap the eye" from also
// flipping the card, the flip card passes a [flipGuard]: this control's own
// Listener marks the guard on pointer-down, and the flip card skips its tap
// for that gesture. The guard is owned by the flip card and consumed there.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:azaman/widgets/scale_tap.dart';

class BalanceVisibilityEye extends ConsumerWidget {
  /// Visual diameter. 40 is the standalone/default control size; the
  /// balance-card header passes 32 so the card's 165px interior keeps its
  /// hero figure untouched (same surface, glyph, press, haptic — only the
  /// diameter adapts to the host).
  final double size;

  /// Set on pointer-down inside this control so the enclosing flip card's raw
  /// Listener does not also flip the card for the same gesture. Null when
  /// the eye is hosted outside a flip surface.
  final ValueNotifier<bool>? flipGuard;

  const BalanceVisibilityEye({super.key, this.flipGuard, this.size = 40});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final isVisible = ref.watch(balanceVisibleProvider);
    final reduceMotion = !AzMotion.of(context).travel;

    return Listener(
      // Raw Listener (no arena): fires BEFORE the enclosing flip card's
      // Listener decides whether this gesture is a card tap. Both Listeners
      // receive the event because neither claims it — this one just marks
      // the guard so the flip card can cede the gesture.
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => flipGuard?.value = true,
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: isVisible ? 'Hide balance' : 'Show balance',
        child: ScaleTap(
          onTap: () {
            AzamanHaptics.toggle();
            ref.read(balanceVisibleProvider.notifier).state = !isVisible;
          },
          child: PremiumGlassContainer(
            blur: 8,
            opacity: 0.06,
            borderRadius: 20,
            padding: EdgeInsets.zero,
            enableShadow: false,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : 250.ms,
                  transitionBuilder: (child, anim) => RotationTransition(
                    turns: child.key == const ValueKey(true)
                        ? Tween(begin: 0.5, end: 1.0).animate(anim)
                        : Tween(begin: 1.0, end: 0.5).animate(anim),
                    child: ScaleTransition(scale: anim, child: child),
                  ),
                  child: Icon(
                    isVisible ? HugeIconsStroke.viewOff : HugeIconsStroke.view,
                    key: ValueKey(isVisible),
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
