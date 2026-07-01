// lib/widgets/typing_indicator_bubble.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TypingBubble extends ConsumerStatefulWidget {
  final AzamanColors colors;
  const TypingBubble({super.key, required this.colors});
  @override
  ConsumerState<TypingBubble> createState() => _TypingState();
}

class _TypingState extends ConsumerState<TypingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18), topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4), bottomRight: Radius.circular(18))
          ),
        child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final phase = (_ctrl.value + i * 0.15) % 1.0;
              final y = -math.sin(phase * math.pi * 2).clamp(-1.0, 0.0) * 5.0;
              return Transform.translate(
                offset: Offset(0, y),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: c.textTertiary.withOpacity(0.5),
                    shape: BoxShape.circle)),
              );
            });
        })),
      ),
    );
  }
}

