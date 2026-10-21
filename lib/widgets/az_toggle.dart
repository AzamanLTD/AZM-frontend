// =============================================================================
// AZAMAN — BRANDED TOGGLE (Stage 2)
//
// Replaces the stock Flutter Switch in Settings surfaces. One branded
// control across the app: the current theme's accent does the work (no
// hardcoded success-green), polished in both brightnesses.
//
// Contract:
//   • [value] + [onChanged] — identical to the Flutter Switch callback
//     semantics; the caller keeps persistence/backend sync.
//   • 220 ms slide/roll, snapped under reduced motion
//     (MotionTokens.accessibleDuration).
//   • Touch target ≥ 48 dp (thumb control inside a 48×40 hit field).
//   • Screen-reader truth: Semantics(toggleButton, checked) with a
//     semantic onTap — it is operable without the visual gesture.
//   • No idle animation; the control animates only on state changes.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class AzToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final AzamanColors colors;

  /// Optional semantic label for screen readers (e.g. 'Push Notifications').
  final String? semanticLabel;

  const AzToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.colors,
    this.semanticLabel,
  });

  static const double _trackWidth = 46;
  static const double _trackHeight = 28;
  static const double _thumbSize = 22;

  @override
  Widget build(BuildContext context) {
    final duration = MotionTokens.accessibleDuration(
      context,
      const Duration(milliseconds: 220),
    );

    return Semantics(
      label: semanticLabel,
      button: false,
      toggled: value,
      onTap: () {
        AzamanHaptics.toggle();
        onChanged(!value);
      },
      child: GestureDetector(
        // 48dp-height hit field — the visual control rides centered.
        behavior: HitTestBehavior.opaque,
        // Commit only on a COMPLETED tap. Never on pointer-down: a
        // drag that starts on the toggle and is won by a surrounding
        // scrollable must not change the setting (tap is rejected by
        // the gesture arena, so onTap never fires). Semantic
        // activation goes through the Semantics.onTap above; pointer
        // and semantic paths are disjoint, so a real tap cannot toggle
        // twice.
        onTap: () {
          AzamanHaptics.toggle();
          onChanged(!value);
        },
        child: SizedBox(
          width: _trackWidth + 4,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              width: _trackWidth,
              height: _trackHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_trackHeight / 2),
                color: value
                    ? colors.accent
                    : colors.isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.08),
                border: Border.all(
                  color: value
                      ? colors.accent
                      : colors.divider.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
              child: AnimatedAlign(
                duration: duration,
                curve: Curves.easeOutCubic,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  width: _thumbSize,
                  height: _thumbSize,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value
                        ? (colors.isDark ? const Color(0xFF111111) : Colors.white)
                        : (colors.isDark ? const Color(0xFFEDEDED) : Colors.white),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
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
