import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class MilestoneProgress extends ConsumerWidget {
  final double currentVolume;
  final double targetVolume;
  final String tierName;
  final IconData? tierIcon;

  const MilestoneProgress({
    super.key,
    required this.currentVolume,
    required this.targetVolume,
    this.tierName = 'WHALE BADGE',
    this.tierIcon,
  });

  double get _progress => (currentVolume / targetVolume).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.accent.withOpacity(0.12)),
        color: colors.card.withOpacity(0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    tierIcon ?? HugeIconsSolid.medal01,
                    size: 14,
                    color: colors.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tierName.toUpperCase(),
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
              Text(
                '${(currentVolume / 1000).toStringAsFixed(0)}K / ${(targetVolume / 1000).toStringAsFixed(0)}K',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(3)),
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: colors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(colors.glow),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(targetVolume - currentVolume).toStringAsFixed(0)} USDT to unlock',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${(_progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
