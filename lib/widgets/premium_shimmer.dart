// lib/widgets/premium_shimmer.dart
// =============================================================================
// PREMIUM SHIMMER — Directional gradient skeleton
// Usage: PremiumShimmer(child: Container(...)) or PremiumShimmerBox(...)
// =============================================================================
import 'package:flutter/material.dart';

class PremiumShimmer extends StatefulWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration duration;

  const PremiumShimmer({super.key, required this.child, this.baseColor, this.highlightColor, this.duration = const Duration(milliseconds: 1200)});

  @override State<PremiumShimmer> createState() => _PremiumShimmerState();
}

class _PremiumShimmerState extends State<PremiumShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)..repeat();
  }
  @override void dispose() { _controller.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = widget.baseColor ?? (isDark ? const Color(0xFF1E2329) : const Color(0xFFF0F0F0));
    final highlight = widget.highlightColor ?? (isDark ? const Color(0xFF2A2F36) : Colors.white);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          final dx = _controller.value * bounds.width * 2 - bounds.width;
          return LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [base, highlight, base],
            stops: [(dx / bounds.width).clamp(0.0, 1.0) - 0.3, (dx / bounds.width).clamp(0.0, 1.0), (dx / bounds.width).clamp(0.0, 1.0) + 0.3],
          ).createShader(bounds);
        },
        child: widget.child,
      ),
    );
  }
}

class PremiumShimmerBox extends StatelessWidget {
  final double width; final double height; final double radius; final Color? baseColor;
  const PremiumShimmerBox({super.key, required this.width, required this.height, this.radius = 12, this.baseColor});

  @override Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PremiumShimmer(baseColor: baseColor, child: Container(
      width: width, height: height,
      decoration: BoxDecoration(color: isDark ? const Color(0xFF1E2329) : const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(radius)),
    ));
  }
}
