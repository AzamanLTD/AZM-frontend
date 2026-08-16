import 'package:flutter/material.dart';

/// Cheap "liquid" tab indicator: a single rounded shape that stretches
/// toward its destination while animating, then settles back to a circle —
/// reads as gooey/liquid without any BackdropFilter/blur cost.
///
/// Integration: place as a Stack sibling inside PremiumBottomNav's
/// existing Container, positioned behind the icon row.
class LiquidTabBackdrop extends StatefulWidget {
  final int selectedIndex;
  final int tabCount;
  final double totalWidth;
  final double barHeight;
  final Color color;

  const LiquidTabBackdrop({
    super.key,
    required this.selectedIndex,
    required this.tabCount,
    required this.totalWidth,
    required this.barHeight,
    required this.color,
  });

  @override
  State<LiquidTabBackdrop> createState() => _LiquidTabBackdropState();
}

class _LiquidTabBackdropState extends State<LiquidTabBackdrop> {
  int? _previousIndex;

  @override
  void didUpdateWidget(covariant LiquidTabBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _previousIndex = oldWidget.selectedIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabWidth = widget.totalWidth / widget.tabCount;
    final targetCenterX = tabWidth * (widget.selectedIndex + 0.5);

    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.selectedIndex),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        // Squash-and-stretch: at t=0.5 (mid-transition) the blob is ~35% wider
        // and slightly shorter — this reads as "liquid" rather than rigid slide.
        final stretch = 1.0 + (0.35 * (1 - (2 * t - 1).abs()));
        final squash = 1.0 - (0.12 * (1 - (2 * t - 1).abs()));
        final startCenterX = _previousIndex != null
            ? tabWidth * (_previousIndex! + 0.5)
            : targetCenterX;
        final currentCenterX =
            Curves.easeOutCubic.transform(t) * (targetCenterX - startCenterX) +
                startCenterX;

        return Positioned(
          left: currentCenterX - (40 * stretch) / 2,
          top: (widget.barHeight - 40 * squash) / 2,
          child: Container(
            width: 40 * stretch,
            height: 40 * squash,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20 * squash),
            ),
          ),
        );
      },
    );
  }
}
