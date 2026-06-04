import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';

class TradeDisclaimer extends ConsumerWidget {
  final bool compact;

  const TradeDisclaimer({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return Container(
      width: double.infinity,
      margin: compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.warning.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(color: colors.warning.withOpacity(0.25)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: colors.warning, size: compact ? 14 : 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Note: Escrow only locks the exact crypto amount requested. Underpayments can be retrieved, but overpayments are not guaranteed. Vendors failing to refund verified overpayments will be severely sanctioned.',
              style: TextStyle(
                color: colors.warning,
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
