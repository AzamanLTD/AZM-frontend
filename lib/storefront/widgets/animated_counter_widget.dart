import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class AnimatedCounterWidget extends StatefulWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const AnimatedCounterWidget({super.key, required this.props, required this.business});

  @override
  State<AnimatedCounterWidget> createState() => _AnimatedCounterWidgetState();
}

class _AnimatedCounterWidgetState extends State<AnimatedCounterWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    final value = (widget.props['value'] ?? 0).toDouble();
    _controller = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this);
    _animation = Tween<double>(begin: 0, end: value).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Loop every 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) { _controller.reset(); _controller.forward(); }
        });
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.props['label'] as String? ?? '';
    final suffix = widget.props['suffix'] as String? ?? '';
    final prefix = widget.props['prefix'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _animation,
            builder: (ctx, child) => Text(
              '$prefix${_animation.value.toInt()}$suffix',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.primary),
            ),
          ),
          if (label.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)))),
        ],
      ),
    );
  }
}
