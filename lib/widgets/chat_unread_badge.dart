import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatUnreadBadge extends ConsumerWidget {
  final int count;
  final double fontSize;
  const ChatUnreadBadge({super.key, required this.count, this.fontSize = 11});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    if (count <= 0) return const SizedBox.shrink();
    final text = count > 99 ? '99+' : count.toString();
    return Container(
      constraints: BoxConstraints(minWidth: count > 9 ? 24 : 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: colors.accent.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      child: Center(
        child: Text(text,
          style: TextStyle(color: colors.isDark ? Colors.black : Colors.white, fontSize: fontSize, fontWeight: FontWeight.w800)),
      ),
    ).animate().scale(begin: const Offset(0.5, 0.5), end: const Offset(1.0, 1.0), duration: 300.ms, curve: Curves.elasticOut);
  }
}
