import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/marketplace_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class VendorAdCard extends ConsumerWidget {
  final AdListing ad;
  final VoidCallback? onTap;
  final bool showDivider;

  const VendorAdCard({
    super.key,
    required this.ad,
    this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final aiFilterOn = ref.watch(aiFilterProvider);

    return Material(
      color: colors.surface,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap!();
              },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 15, 16, 15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatPaymentMethod(ad.paymentMethod),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _subtitle(ad, colors, aiFilterOn),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            letterSpacing: -0.1,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: colors.success.withOpacity(0.3)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(HugeIconsSolid.shield01, size: 9, color: colors.success),
                              const SizedBox(width: 3),
                              Text("Escrow",
                                style: TextStyle(color: colors.success,
                                  fontSize: 9, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_fmt(ad.availableUsdc)} USDC',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                          height: 1.15,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (_secondaryLine(ad, aiFilterOn) != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _secondaryLine(ad, aiFilterOn)!,
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            letterSpacing: -0.1,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    HugeIconsSolid.arrowRight01,
                    size: 14,
                    color: colors.textTertiary.withValues(alpha: 0.45),
                  ),
                ],
              ),
            ),
            if (showDivider)
              Divider(
                height: 0,
                thickness: 0.5,
                indent: 20,
                color: colors.divider.withValues(alpha: 0.65),
              ),
          ],
        ),
      ),
    );
  }

  String _subtitle(AdListing ad, AzamanColors colors, bool aiFilterOn) {
    final vendor = ad.vendorUsername;
    final limits = '\$${_fmtInt(ad.minLimit)}–\$${_fmtInt(ad.maxLimit)}';
    if (ad.riskLevel == RiskLevel.high) {
      return '$vendor · $limits · High risk';
    }
    if (ad.queueFull && ad.queueDepth > 0) {
      return '$vendor · $limits · ${ad.queueDepth} waiting';
    }
    if (aiFilterOn && ad.aiScore >= 0.75) {
      return '$vendor · $limits · Recommended';
    }
    return '$vendor · $limits';
  }

  String? _secondaryLine(AdListing ad, bool aiFilterOn) {
    if (ad.completedTrades == 0 && ad.completionRate == 0) return null;
    final rate = (ad.completionRate * 100).toStringAsFixed(0);
    if (ad.completedTrades <= 1) {
      return '$rate% completion';
    }
    return '${ad.completedTrades} trades · $rate%';
  }

  String _formatPaymentMethod(String method) {
    final trimmed = method.trim();
    if (trimmed.isEmpty) return method;
    final lower = trimmed.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  String _fmt(double v) {
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      final buffer = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
        buffer.write(s[i]);
      }
      return buffer.toString();
    }
    return v.toStringAsFixed(2);
  }

  String _fmtInt(double v) {
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      final buf = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
        buf.write(s[i]);
      }
      return buf.toString();
    }
    return v.toStringAsFixed(0);
  }
}
