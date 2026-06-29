import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/models/currency_model.dart';

class DualCurrencyText extends ConsumerWidget {
  final double usdc;
  final double? ghsRate;

  const DualCurrencyText({
    super.key,
    required this.usdc,
    this.ghsRate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferred = ref.watch(currencyProvider);
    final rate = ghsRate ?? ref.watch(oracleRateProvider);
    final ghs = usdc * rate;
    final colors = ref.watch(themeProvider).colors;

    if (preferred == DisplayCurrency.ghs) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GH₵ ${ghs.toStringAsFixed(2)}',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '${usdc.toStringAsFixed(2)} USDC',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${usdc.toStringAsFixed(2)} USDC',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'GH₵ ${ghs.toStringAsFixed(2)}',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
