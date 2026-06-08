import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class Badge {
  final IconData icon;
  final String label;
  final Color color;

  const Badge({
    required this.icon,
    required this.label,
    required this.color,
  });
}

class PublicProfileModal extends ConsumerWidget {
  final String username;
  final String avatarUrl;
  final String joinedDate;
  final List<Badge> badges;

  const PublicProfileModal({
    super.key,
    required this.username,
    this.avatarUrl = '',
    required this.joinedDate,
    this.badges = const [],
  });

  static Future<void> show(
    BuildContext context, {
    required String username,
    String avatarUrl = '',
    required String joinedDate,
    List<Badge> badges = const [],
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => PublicProfileModal(
        username: username,
        avatarUrl: avatarUrl,
        joinedDate: joinedDate,
        badges: badges,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.52,
        minChildSize: 0.36,
        maxChildSize: 0.75,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                _buildHandle(colors),
                _buildHeader(colors),
                _buildBadgeGrid(colors),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHandle(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: colors.textTertiary.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.accent.withOpacity(0.3), width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: colors.accent.withOpacity(0.12),
                  blurRadius: 20,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: CircleAvatar(
              backgroundColor: colors.card,
              backgroundImage: avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl.isEmpty
                  ? Icon(
                      HugeIconsSolid.user,
                      size: 44,
                      color: colors.textTertiary,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            username,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: colors.accentSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  HugeIconsSolid.calendar01,
                  size: 12,
                  color: colors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  'Joined $joinedDate',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeGrid(AzamanColors colors) {
    if (badges.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.divider),
          ),
          child: Column(
            children: [
              Icon(
                HugeIconsSolid.award01,
                size: 32,
                color: colors.textTertiary.withOpacity(0.4),
              ),
              const SizedBox(height: 8),
              Text(
                'No badges earned yet',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final int crossAxisCount = 3;
    final double childAspectRatio = 0.85;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                HugeIconsSolid.award01,
                size: 16,
                color: colors.accent,
              ),
              const SizedBox(width: 6),
              Text(
                'Badges (${badges.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: childAspectRatio,
            ),
            itemCount: badges.length,
            itemBuilder: (context, index) {
              final badge = badges[index];
              return _badgeTile(colors, badge);
            },
          ),
        ],
      ),
    );
  }

  Widget _badgeTile(AzamanColors colors, Badge badge) {
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: badge.color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              badge.icon,
              size: 22,
              color: badge.color,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              badge.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
