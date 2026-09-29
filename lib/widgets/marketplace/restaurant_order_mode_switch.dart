import 'package:flutter/material.dart';

import 'package:azaman/marketplace/experiences/restaurant/restaurant_order_mode.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// Sliding-glass segmented control for the restaurant order mode.
///
/// Three segments ride on one glass capsule; a tinted thumb slides between
/// them with [MotionTokens.symmetric] easing. The thumb is the ONLY moving
/// element — labels never re-layout, so the switch never "jumps".
class RestaurantOrderModeSwitch extends StatelessWidget {
  final RestaurantOrderMode selected;
  final ValueChanged<RestaurantOrderMode> onChanged;
  final AzamanColors colors;

  /// When false, the Dine-in segment renders dimmed and ignores taps — a
  /// dine-in tab can only be started from a dine-in QR code.
  final bool dineInEnabled;

  const RestaurantOrderModeSwitch({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.colors,
    this.dineInEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final duration = MotionTokens.accessibleDuration(context, MotionTokens.control);
    final modes = RestaurantOrderMode.values;
    return LayoutBuilder(
      builder: (context, constraints) {
        final segmentWidth = constraints.maxWidth / modes.length;
        return Container(
          height: 44,
          decoration: BoxDecoration(
            color: colors.isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05),
            borderRadius: AzRadius.brLg,
            border: Border.all(
              color: colors.isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                alignment: Alignment(-1 + 2 * (selected.index / (modes.length - 1)), 0),
                duration: duration,
                curve: MotionTokens.symmetric,
                child: Container(
                  width: segmentWidth,
                  height: 40,
                  margin: const EdgeInsets.all(AzSpace.xxs),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: AzRadius.brMd,
                    boxShadow: [
                      BoxShadow(
                        color: colors.accent.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Row(
                  children: [for (final mode in modes) Expanded(child: _segment(mode))],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _segment(RestaurantOrderMode mode) {
    final isSelected = selected == mode;
    final enabled = mode != RestaurantOrderMode.dineIn || dineInEnabled;
    final Color ink = isSelected
        ? (colors.isDark ? Colors.black : Colors.white)
        : (enabled
            ? colors.textSecondary
            : colors.textTertiary.withValues(alpha: 0.5));
    return Semantics(
      button: true,
      selected: isSelected,
      enabled: enabled,
      label: mode.label,
      child: InkWell(
        borderRadius: AzRadius.brMd,
        onTap: enabled && !isSelected
            ? () {
                AzamanHaptics.toggle();
                onChanged(mode);
              }
            : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(mode.icon, size: 14, color: ink),
            const SizedBox(width: AzSpace.xs),
            Text(mode.label, style: AzText.label.copyWith(color: ink)),
          ],
        ),
      ),
    );
  }
}
