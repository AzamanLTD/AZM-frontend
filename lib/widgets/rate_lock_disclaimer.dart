import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class RateLockDisclaimer extends ConsumerWidget {
  final bool compact;

  const RateLockDisclaimer({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return Container(
      width: double.infinity,
      margin: compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.accent.withOpacity(0.08),
        border: Border(
          bottom: BorderSide(color: colors.accent.withOpacity(0.2)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(HugeIconsSolid.lock, color: colors.accent, size: compact ? 14 : 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Final fiat payouts are locked at the time the trade is initiated. '
              'Sudden Yellow Card rate fluctuations will not affect active escrows.',
              style: TextStyle(
                color: colors.accent,
                fontSize: compact ? 10 : 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
