import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart' show AzamanColors;

/// PR #142 VISUAL PASS (2026-10-06) — the small section separator that sits
/// immediately above the Home reminder deck.
///
/// NOT a heading, NOT a card: a centred, small gray "Reminders" label with a
/// very light hairline on each side whose weight fades toward the outer
/// ends — the same restrained grammar as the chat date/section separators.
/// The line is painted (not a Container) so the fade is real alpha falloff,
/// and the widget is reusable for any future Home section.
/// The separator's FIXED height — the deck's pinned geometry (pass B5)
/// is `bandHeight + separatorHeight`, so this must stay a constant, not
/// text-intrinsic.
const double homeDeckSeparatorHeight = 26.0;

class HomeDeckSeparator extends StatelessWidget {
  const HomeDeckSeparator({
    super.key,
    required this.colors,
    this.label = 'Reminders',
  });

  /// The accent-aware palette from the surrounding Home, so the separator
  /// always agrees with the live theme.
  final AzamanColors colors;

  /// The quiet section label.
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = colors;

    return Semantics(
      header: true,
      label: label,
      child: SizedBox(
        height: homeDeckSeparatorHeight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
          key: ValueKey('home-deck-separator-$label'),
          children: [
            Expanded(child: _FadingRule(colors: c, mirror: true)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                    // Deliberately quiet: small gray text, never a heading.
                  color: c.textTertiary,
                  letterSpacing: 0.4,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            Expanded(child: _FadingRule(colors: c)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One hairline whose weight fades toward the OUTER end (transparent) and
/// solidifies toward the label. `mirror: true` puts the solid end on the
/// right, for the line left of the label.
class _FadingRule extends StatelessWidget {
  const _FadingRule({required this.colors, this.mirror = false});

  final AzamanColors colors;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    final line = colors.divider.withValues(alpha: 0.55);
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _FadingRulePainter(
        color: line,
        mirror: mirror,
      ),
    );
  }
}

class _FadingRulePainter extends CustomPainter {
  _FadingRulePainter({required this.color, required this.mirror});

  final Color color;
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final rect = Offset(0, size.height / 2 - 0.5) &
        Size(size.width, 1.0);
    // Weight gently reduces toward the outer end: a horizontal gradient
    // from fully solid at the label to transparent at the edge. The inner
    // (label) side stays the divider hue at partial strength — visible
    // but very light, exactly like a chat section separator.
    final from = mirror ? Alignment.centerRight : Alignment.centerLeft;
    final to = mirror ? Alignment.centerLeft : Alignment.centerRight;
    final shader = LinearGradient(
      begin: from,
      end: to,
      colors: [color, color.withValues(alpha: 0.0)],
      stops: const [0.05, 1.0],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _FadingRulePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mirror != mirror;
}
