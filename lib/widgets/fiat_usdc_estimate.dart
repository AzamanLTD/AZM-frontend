import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/rate_refresh_indicator.dart';

/// Shows an approximate USDC value for a local-fiat amount.
///
/// This is intentionally an estimate, not a transaction quote. The backend
/// remains authoritative for the USDC actually credited after settlement.
class FiatUsdcEstimate extends ConsumerWidget {
  const FiatUsdcEstimate({
    super.key,
    required this.amountGhs,
    this.compact = false,
  });

  final double amountGhs;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final rate = ref.watch(oracleRateProvider);
    final metadata = ref.watch(oracleRateMetadataProvider);
    final usdc = rate > 0 ? amountGhs / rate : 0.0;

    if (amountGhs <= 0 || rate <= 0) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.textTertiary.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estimated USDC',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${usdc.toStringAsFixed(2)} USDC',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '1 USDC = GH₵${rate.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const RateRefreshIndicator(),
          if (metadata.stale) ...[
            const SizedBox(width: 6),
            Icon(Icons.warning_amber_rounded, color: colors.warning, size: 16),
          ],
        ],
      ),
    );
  }
}
