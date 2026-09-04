import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/models/currency_model.dart';

String formatGhsEquivalent(double usdc, double rate) {
  if (!rate.isFinite || rate <= 0) return 'GHS unavailable';
  final ghs = usdc * rate;
  if (!ghs.isFinite) return 'GHS unavailable';
  return 'GH₵ ${ghs.toStringAsFixed(2)}';
}

class DualCurrencyText extends ConsumerWidget {
  final double usdc;
  final double? ghsRate;
  final TextStyle? style;
  final TextStyle? secondaryStyle;

  const DualCurrencyText({
    super.key,
    required this.usdc,
    this.ghsRate,
    this.style,
    this.secondaryStyle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferred = ref.watch(currencyProvider);
    final double rate = ghsRate ?? ref.watch(oracleRateProvider);
    final colors = ref.watch(themeProvider).colors;
    final primary = style ?? TextStyle(
      color: colors.textPrimary,
      fontSize: 18,
      fontWeight: FontWeight.bold,
    );
    final secondary = secondaryStyle ?? TextStyle(
      color: colors.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.normal,
    );

    final ghsText = formatGhsEquivalent(usdc, rate);

    if (preferred == DisplayCurrency.ghs) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ghsText, style: primary),
          Text('${usdc.toStringAsFixed(2)} USDC', style: secondary),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${usdc.toStringAsFixed(2)} USDC', style: primary),
        Text(ghsText, style: secondary),
      ],
    );
  }
}
