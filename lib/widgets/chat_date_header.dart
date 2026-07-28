import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:azaman/providers/theme_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatDateHeader extends ConsumerWidget {
  final DateTime date;
  const ChatDateHeader({super.key, required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: colors.softSurface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _formatDate(date),
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return intl.DateFormat('EEEE').format(dt);
    return intl.DateFormat('dd/MM/yyyy').format(dt);
  }
}
