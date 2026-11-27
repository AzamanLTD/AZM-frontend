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
import 'package:azaman/widgets/money_stage/money_stage.dart';

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
    // On a money stage the keys take the sky's ink and a press bloom; off a
    // stage nothing changes.
    final skin = AzStageSkin.maybeOf(context);

    Widget keyCell(String key) {
      if (skin != null) {
        return Expanded(
          child: _StageKey(
            keyLabel: key,
            enabled: enabled,
            height: rowHeight,
            skin: skin,
            onKey: onKey,
          ),
        );
      }
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

/// One key on a money stage: the digit in the sky's ink, a soft bloom under
/// the finger, a slight press. Same semantics and haptic as the plain key.
class _StageKey extends StatefulWidget {
  const _StageKey({
    required this.keyLabel,
    required this.enabled,
    required this.height,
    required this.skin,
    required this.onKey,
  });

  final String keyLabel;
  final bool enabled;
  final double height;
  final AzStageSkin skin;
  final ValueChanged<String> onKey;

  @override
  State<_StageKey> createState() => _StageKeyState();
}

class _StageKeyState extends State<_StageKey> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final colour = widget.enabled ? skin.ink : skin.inkMuted.withValues(alpha: 0.35);
    final face = widget.keyLabel == 'del'
        ? Icon(Icons.backspace_rounded, size: 24, color: widget.enabled ? skin.inkMuted : colour)
        : Text(widget.keyLabel, style: AzStageType.key(colour));
    final bloom = widget.height * 1.08;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: AmountKeypad.semanticLabel(widget.keyLabel),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => _set(true) : null,
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: widget.enabled
            ? () {
                AzamanHaptics.toggle();
                widget.onKey(widget.keyLabel);
              }
            : null,
        child: SizedBox(
          height: widget.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                duration: Duration(milliseconds: _down ? 60 : 260),
                opacity: _down ? 1 : 0,
                child: AnimatedScale(
                  duration: Duration(milliseconds: _down ? 90 : 320),
                  curve: Curves.easeOutCubic,
                  scale: _down ? 1 : 0.6,
                  child: Container(
                    width: bloom,
                    height: bloom,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: skin.glass,
                    ),
                  ),
                ),
              ),
              AnimatedScale(
                duration: Duration(milliseconds: _down ? 70 : 220),
                curve: Curves.easeOutCubic,
                scale: _down ? 0.9 : 1,
                child: face,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
