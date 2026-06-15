import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/marketplace_provider.dart';
import 'package:azaman/widgets/vendor_badge_row.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class VendorAdCard extends ConsumerWidget {
  final AdListing ad;

  final VoidCallback? onTap;

  const VendorAdCard({
    super.key,
    required this.ad,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final aiFilterOn = ref.watch(aiFilterProvider);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap!();
            },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IdentityRow(ad: ad, colors: colors),
            const SizedBox(height: 14),
            _RateRow(ad: ad, colors: colors),
            const SizedBox(height: 10),
            _LimitsRow(ad: ad, colors: colors, aiFilterOn: aiFilterOn),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 320.ms, curve: Curves.easeOut)
        .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
  }
}

class _IdentityRow extends StatelessWidget {
  final AdListing ad;
  final AzamanColors colors;
  const _IdentityRow({required this.ad, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _VendorAvatar(username: ad.vendorUsername, colors: colors),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      ad.vendorUsername,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ad.isOnline
                          ? colors.success
                          : colors.textTertiary.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(HugeIconsSolid.star, color: colors.warning, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    '${ad.completedTrades} trades',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '  ·  ',
                    style:
                        TextStyle(color: colors.textTertiary, fontSize: 11.5),
                  ),
                  Text(
                    '${(ad.completionRate * 100).toStringAsFixed(0)}% done',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (ad.vendorId.isNotEmpty)
                VendorBadgeRow(
                  vendorId: int.tryParse(ad.vendorId) ?? 0,
                  colors: colors,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _RiskTag(riskLevel: ad.riskLevel, colors: colors),
      ],
    );
  }
}

class _VendorAvatar extends StatelessWidget {
  final String username;
  final AzamanColors colors;
  const _VendorAvatar({required this.username, required this.colors});

  @override
  Widget build(BuildContext context) {
    final initials = username.length >= 2
        ? username.substring(0, 2).toUpperCase()
        : username.toUpperCase();

    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.card,
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _RiskTag extends StatelessWidget {
  final RiskLevel riskLevel;
  final AzamanColors colors;
  const _RiskTag({required this.riskLevel, required this.colors});

  @override
  Widget build(BuildContext context) {
    final Color tagColor;
    final String label;
    final IconData icon;

    switch (riskLevel) {
      case RiskLevel.low:
        tagColor = colors.success;
        label = 'Low';
        icon = HugeIconsSolid.shield01;
        break;
      case RiskLevel.medium:
        tagColor = colors.warning;
        label = 'Med';
        icon = HugeIconsSolid.alertCircle;
        break;
      case RiskLevel.high:
        tagColor = colors.danger;
        label = 'High';
        icon = HugeIconsSolid.alertCircle;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: tagColor.withValues(alpha: 0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: tagColor, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: tagColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _RateRow extends StatelessWidget {
  final AdListing ad;
  final AzamanColors colors;
  const _RateRow({required this.ad, required this.colors});

  @override
  Widget build(BuildContext context) {
    final isSell = ad.isSellAd;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSell
                ? colors.success.withValues(alpha: 0.12)
                : colors.danger.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            isSell ? 'SELL' : 'BUY',
            style: TextStyle(
              color: isSell ? colors.success : colors.danger,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            ad.paymentMethod,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.0,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Available',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 10,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_fmt(ad.availableUsdc)} USDC',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ],
    );
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
}

class _LimitsRow extends StatelessWidget {
  final AdListing ad;
  final AzamanColors colors;
  final bool aiFilterOn;
  const _LimitsRow({
    required this.ad,
    required this.colors,
    required this.aiFilterOn,
  });

  @override
  Widget build(BuildContext context) {
    final showAi = aiFilterOn && ad.aiScore >= 0.75;
    final showQueue = ad.queueFull && ad.queueDepth > 0;
    return Row(
      children: [
        _InfoChip(
          icon: HugeIconsSolid.exchange01,
          label: '\$${_fmtInt(ad.minLimit)} – \$${_fmtInt(ad.maxLimit)}',
          colors: colors,
        ),
        const Spacer(),
        if (showQueue) ...[
          _MetaChip(
            icon: HugeIconsSolid.hourglass,
            label: '${ad.queueDepth} ahead',
            color: colors.warning,
            colors: colors,
          ),
          if (showAi) const SizedBox(width: 6),
        ],
        if (showAi)
          _MetaChip(
            icon: HugeIconsSolid.sparkles,
            label: 'AI ${(ad.aiScore * 100).toStringAsFixed(0)}%',
            color: colors.accent,
            colors: colors,
          ),
      ],
    );
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

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final AzamanColors colors;
  const _InfoChip(
      {required this.icon, required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: colors.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.textTertiary, size: 12),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final AzamanColors colors;
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: 0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
