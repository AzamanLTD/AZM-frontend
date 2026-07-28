import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class GradientHeroWidget extends StatefulWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const GradientHeroWidget({super.key, required this.props, required this.business});

  @override
  State<GradientHeroWidget> createState() => _GradientHeroWidgetState();
}

class _GradientHeroWidgetState extends State<GradientHeroWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final speed = widget.props['animationSpeed'] as String? ?? 'medium';
    final duration = switch (speed) {
      'slow' => const Duration(seconds: 8),
      'fast' => const Duration(seconds: 2),
      _ => const Duration(seconds: 4),
    };
    _controller = AnimationController(duration: duration, vsync: this)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.props['title'] as String? ?? '';
    final subtitle = widget.props['subtitle'] as String? ?? '';
    final from = _parseColor(widget.props['gradientFrom'] as String?, const Color(0xFF6C4FD1));
    final to = _parseColor(widget.props['gradientTo'] as String?, const Color(0xFFE07B30));

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (ctx, child) {
          final t = _controller.value;
          return Container(
            height: 280,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(t * 2 - 1, 0),
                end: Alignment((t * 2 - 1) + 1, 1),
                colors: [from, to],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.3)])))),
                Positioned(left: 24, right: 24, bottom: 28, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title.isNotEmpty) Text(title, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                    if (subtitle.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 16))),
                  ],
                )),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _parseColor(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    try { return Color(int.parse(h, radix: 16)); } catch (_) { return fallback; }
  }
}
