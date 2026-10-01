// =============================================================================
// AZAMAN — AMOUNT KEYPAD
//
// The Add Cash surface's custom numeric keypad (deposit redesign, 2026-10).
// Grammar borrowed from the reference: a visually minimal 3-column grid,
// generous touch targets, no key backgrounds — the keys ARE the type, not
// chips. Only the delete affordance carries an icon.
//
//   1  2  3
//   4  5  6
//   7  8  9
//   .  0  ⌫
//
// The keypad EMITS key events (`'0'..'9'`, `'.'`, `'del'`); it owns NO amount
// state. The amount state machine (leading zeros, single decimal point, two
// fractional digits) lives beside the odometer it feeds, so the validation
// rules are testable without pumping this widget. The keypad is deliberately
// dumb: it cannot produce an invalid state because it cannot produce a state
// at all.
//
// Haptics: every keypress fires `AzamanHaptics.toggle()` — the picker-
// selection vocabulary — exactly once, from the single `GestureDetector` that
// also carries the tap. No duplicate haptic paths.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// Keys are identified by plain strings: `'0'`..`'9'`, `'.'`, `'del'`.
class AmountKeypad extends ConsumerWidget {
  const AmountKeypad({
    super.key,
    required this.onKey,
    this.enabled = true,
    this.rowHeight = 54.0,
  });

  /// Fires with `'0'`..`'9'`, `'.'` (decimal point) or `'del'` (backspace).
  final ValueChanged<String> onKey;

  /// Disabled while a financial mutation is in flight — keys grey out and
  /// become inert so a mid-submit amount edit cannot race the initiation.
  final bool enabled;

  /// Per-row key height. The deposit surface compresses this on short
  /// viewports (measured layout, not a scroll escape hatch).
  final double rowHeight;

  static const List<String> _keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '.',
    '0',
    'del',
  ];

  static String semanticLabel(String key) => switch (key) {
    'del' => 'Delete',
    '.' => 'Decimal point',
    _ => key,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final disabledColor = colors.textTertiary.withValues(alpha: 0.4);

    Widget keyCell(String key) {
      final active = enabled;
      final labelColor = active
          ? (key == 'del' ? colors.textSecondary : colors.textPrimary)
          : disabledColor;

      final Widget face;
      if (key == 'del') {
        face = Icon(Icons.backspace_outlined, size: 26, color: labelColor);
      } else {
        face = Text(
          key,
          style: TextStyle(
            color: labelColor,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.0,
          ),
        );
      }

      return Expanded(
        child: Semantics(
          button: true,
          enabled: active,
          label: semanticLabel(key),
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: active
                ? () {
                    AzamanHaptics.toggle();
                    onKey(key);
                  }
                : null,
            child: SizedBox(
              height: rowHeight,
              child: Center(child: face),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < 4; row++)
          Row(
            children: [
              for (var col = 0; col < 3; col++) keyCell(_keys[row * 3 + col]),
            ],
          ),
      ],
    );
  }
}
