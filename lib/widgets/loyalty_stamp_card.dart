// =============================================================================
// AZAMAN — Loyalty Stamp Card Widget
//
// Visual stamp card shown on business profiles. Displays:
//   • Row of stamp circles (filled/unfilled)
//   • Progress text ("3 more stamps until your free coffee!")
//   • Reward description
//   • Completed state with celebration
//
// Reference: Square Loyalty, Starbucks Rewards, Punchh
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class LoyaltyStampCard extends ConsumerWidget {
  final UserLoyaltyCard card;
  final VoidCallback? onTap;

  const LoyaltyStampCard({
    super.key,
    required this.card,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AzamanHaptics.nav();
        onTap?.call();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.accent.withValues(alpha: 0.10),
              colors.accentSecondary.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: card.isComplete ? colors.accent.withValues(alpha: 0.4) : colors.accent.withValues(alpha: 0.15),
            width: card.isComplete ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    card.type == LoyaltyType.stampCard
                        ? HugeIconsSolid.note01
                        : HugeIconsSolid.gift,
                    size: 20,
                    color: colors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.businessName,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Loyalty Card',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (card.isComplete)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Ready to redeem!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(
                    duration: 1500.ms,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
              ],
            ),

            const SizedBox(height: 20),

            // Stamp circles
            _buildStampRow(colors),

            const SizedBox(height: 16),

            // Progress text
            Row(
              children: [
                Expanded(
                  child: Text(
                    card.isComplete
                        ? 'Your reward is ready: ${card.rewardDescription}'
                        : '${card.stampsRemaining} more stamp${card.stampsRemaining == 1 ? '' : 's'} until ${card.rewardDescription}',
                    style: TextStyle(
                      color: card.isComplete ? colors.accent : colors.textSecondary,
                      fontSize: 13,
                      fontWeight: card.isComplete ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildStampRow(AzamanColors colors) {
    final stamps = card.stampsRequired;
    final filled = card.stampsCollected.clamp(0, stamps);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(stamps, (index) {
        final isFilled = index < filled;
        return Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: isFilled ? colors.accent : colors.softSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFilled ? colors.accent : colors.divider,
              width: isFilled ? 0 : 1,
            ),
            boxShadow: isFilled
                ? [
                    BoxShadow(
                      color: colors.accent.withValues(alpha: 0.3),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            HugeIconsSolid.star,
            size: 18,
            color: isFilled ? Colors.white : colors.textTertiary,
          ),
        ).animate(delay: (index * 50).ms).fadeIn(duration: 200.ms).scale(
          begin: isFilled ? const Offset(0.8, 0.8) : const Offset(1.0, 1.0),
          end: const Offset(1.0, 1.0),
        );
      }),
    );
  }
}
