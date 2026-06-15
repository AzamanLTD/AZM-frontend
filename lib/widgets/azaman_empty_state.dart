import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';

// =============================================================================
// AZAMAN EMPTY STATE — Reusable empty/no-data display widget
//
// Provides a consistent, premium empty-state experience across all screens.
// Replaces the 6+ inconsistent private _buildEmptyState() methods scattered
// throughout the app (admin_war_room, vendor_dashboard, friend_chat,
// marketplace, leaderboard, azm_rewards, etc.).
//
// Usage:
//   AzamanEmptyState(
//     icon: HugeIconsSolid.inbox,
//     title: 'No notifications yet',
//     subtitle: 'You\'ll see updates here when something happens.',
//     actionLabel: 'Refresh',
//     onAction: () => ref.read(provider).refresh(),
//   )
// =============================================================================

class AzamanEmptyState extends ConsumerWidget {
  /// Primary icon displayed at the top (large, muted).
  final IconData icon;

  /// Bold headline text below the icon.
  final String title;

  /// Optional descriptive text below the title.
  final String? subtitle;

  /// Optional action button label (e.g., "Retry", "Refresh", "Create").
  final String? actionLabel;

  /// Callback for the action button. Required if [actionLabel] is set.
  final VoidCallback? onAction;

  /// Optional custom icon size. Defaults to 56.
  final double iconSize;

  /// Whether to use compact layout (less padding, smaller icon).
  /// Useful inside cards or constrained containers.
  final bool compact;

  const AzamanEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.iconSize = 56,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final double verticalPadding = compact ? 24 : 48;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32, vertical: verticalPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Decorative circle behind icon
          Container(
            padding: EdgeInsets.all(compact ? 16 : 20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.accent.withOpacity(0.06),
            ),
            child: Icon(
              icon,
              size: compact ? 40 : iconSize,
              color: colors.textTertiary,
            ),
          ),
          SizedBox(height: compact ? 16 : 20),

          // Title
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: compact ? 14 : 16,
              fontWeight: FontWeight.w600,
            ),
          ),

          // Subtitle
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: compact ? 12 : 13,
                height: 1.4,
              ),
            ),
          ],

          // Action button
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: compact ? 16 : 24),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: colors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: colors.accent.withOpacity(0.3)),
                ),
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
