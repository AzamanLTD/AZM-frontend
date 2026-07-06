// lib/widgets/marketplace/marketplace_status_rail.dart
// =============================================================================
// AZAMAN — MARKETPLACE STATUS RAIL (2026-07-06)
//
// Horizontal rail shown at the top of the marketplace home screen:
//   - If the user follows businesses: one squircle avatar per followed
//     business (StoryRing-style, matching the chat "My Status" pattern for
//     visual consistency), tapping opens that business's profile.
//   - If the user follows none: a compact inline empty state explaining
//     that following businesses surfaces live updates here, with a CTA that
//     jumps straight into the category strip's "All" view to browse.
//
// Backed by followingListProvider (marketplace_extensions_provider.dart),
// which was previously unusable -- the file didn't compile at all. See that
// file's header comment for the fix.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/widgets/story_ring.dart';

class MarketplaceStatusRail extends ConsumerWidget {
  final void Function(String businessProfileId) onOpenBusiness;
  final VoidCallback? onBrowsePressed;

  const MarketplaceStatusRail({
    super.key,
    required this.onOpenBusiness,
    this.onBrowsePressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final followingState = ref.watch(followingListProvider);

    return followingState.when(
      loading: () => const SizedBox(height: 88),
      error: (_, __) => const SizedBox.shrink(),
      data: (following) {
        if (following.isEmpty) {
          return _EmptyFollowRow(colors: colors, onBrowsePressed: onBrowsePressed);
        }
        return SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: following.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final biz = following[index];
              final id = biz['id']?.toString() ?? '';
              final name = biz['businessName']?.toString() ?? '';
              final logoUrl = biz['logoUrl']?.toString();
              final isVerified = biz['isVerified'] == true;

              return GestureDetector(
                onTap: () => onOpenBusiness(id),
                child: SizedBox(
                  width: 68,
                  child: Column(
                    children: [
                      StoryRing(
                        avatarUrl: logoUrl,
                        hasUnseenStory: true,
                        isBoosted: isVerified,
                        size: 60,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _EmptyFollowRow extends StatelessWidget {
  final AzamanColors colors;
  final VoidCallback? onBrowsePressed;
  const _EmptyFollowRow({required this.colors, required this.onBrowsePressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: GestureDetector(
        onTap: onBrowsePressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.accentSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.storefront_outlined, size: 19, color: colors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Follow businesses to get live updates',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'New promos and drops from businesses you follow show up here',
                      style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
