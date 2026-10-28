// lib/widgets/marketplace/marketplace_status_rail.dart
// =============================================================================
// AZAMAN — MARKETPLACE STATUS RAIL (2026-07-10, Telegram-style v2)
//
// Two display states controlled by the parent's scroll position:
//
//   COLLAPSED (default):
//     Three small stacked squircle avatars (like the top of a Telegram story
//     row) sit between the header and the category strip. Tap to expand.
//
//   EXPANDED:
//     Full-width horizontal scrollable list of followed-business story rings,
//     identical to the chat-screen status bar — same StoryRing widget, same
//     label pattern. A second pull/scroll triggers the page refresh.
//
// The parent (marketplace_home_screen.dart) passes `isExpanded` (derived from
// its scroll position) and an `onToggle` callback.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/widgets/story_ring.dart';
import 'package:flutter_animate/flutter_animate.dart';
// EXPERIENCE PASS §16 — the marketplace rail speaks the SAME story
// grammar as chat: metrics come from the shared StoryRailMetrics, and
// the collapse math lives in StoryRailCollapse.
import 'package:azaman/widgets/stories/story_rail_compact.dart'
    show CompactStoryItem, CompactStoryRail;
import 'package:azaman/widgets/stories/story_rail_strip.dart'
    show StoryRailMetrics;
import 'package:azaman/theme/az_space.dart';

class MarketplaceCollapsedAvatars extends ConsumerWidget {
  final VoidCallback onTap;

  const MarketplaceCollapsedAvatars({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followingState = ref.watch(followingListProvider);

    // Workstream A (2026-10-21): the collapsed marketplace stories affordance
    // is the SAME design language as chat's StoryRailCompact — overlapping
    // circular StoryRings, caption label, chevron — via the shared
    // CompactStoryRail. The old stacked-squircle treatment is gone: it read
    // as a detached stack of business logos, not the story grammar.
    //
    // Loading/error/empty keep the affordance present with the shared
    // label-only presentation — honest (no invented avatars) and no layout
    // jump when real data arrives.
    final following = followingState.valueOrNull ?? const [];
    final unseen = following.where(businessHasUnseenStory).length;

    return Semantics(
      button: true,
      label: unseen > 0
          ? '$unseen businesses with new stories. Tap to expand stories'
          : 'Stories. Tap to expand',
      child: CompactStoryRail(
        stripKey: const ValueKey('marketplace_story_rail_compact'),
        labelKey: const ValueKey('marketplace_story_rail_compact_label'),
        items: [
          for (final biz in following.take(3))
            CompactStoryItem(
              avatarUrl: biz['logoUrl']?.toString(),
              // Count-less source (§9): the business feed carries only
              // lastStoryAt/lastViewedAt — the dash renders, the numeric
              // badge does NOT (never a manufactured count).
              counts: StoryRingCounts.fromUnseenFlag(
                businessHasUnseenStory(biz),
              ),
              // Business VERIFICATION is not a story boost. The followed
              // business feed carries no boost field, so the boost ring
              // treatment stays OFF — verified status never masquerades
              // as a boosted story (review A4, real data only §9).
            ),
        ],
        label: unseen > 0 ? '$unseen new' : 'Stories',
        onTap: onTap,
        // Review A1/A3 — chat parity with NO marketplace-only styling
        // variants: the SAME defaults as the chat collapsed strip
        // (chevron at the affordance's trailing edge, the rail's own
        // AzSpace.xl horizontal padding). The parent header row
        // contributes no extra leading padding so the EFFECTIVE ring
        // position matches the chat strip exactly; see the header
        // padding note in marketplace_home_screen.dart.
      ),
    );
  }
}

/// Real-data unseen test for a followed-business map: a story exists and
/// has not been viewed. Shared by the expanded rail and the collapsed
/// affordance so the two presentations can never disagree.
bool businessHasUnseenStory(Map<String, dynamic> biz) {
  final lastStoryAt = biz['lastStoryAt'];
  final lastViewedAt = biz['lastViewedAt'];
  if (lastStoryAt == null) return false;
  try {
    final story = DateTime.parse(lastStoryAt.toString());
    final viewed = lastViewedAt == null
        ? null
        : DateTime.parse(lastViewedAt.toString());
    return viewed == null || story.isAfter(viewed);
  } on FormatException {
    return false;
  }
}

class MarketplaceExpandedStories extends ConsumerWidget {
  final void Function(String businessProfileId) onOpenBusiness;
  final VoidCallback? onBrowsePressed;

  const MarketplaceExpandedStories({
    super.key,
    required this.onOpenBusiness,
    this.onBrowsePressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final followingState = ref.watch(followingListProvider);

    return followingState.when(
      loading: () => const SizedBox(height: 40),
      error: (err, st) => _buildEmptyState(context, colors),
      data: (following) {
        if (following.isEmpty) {
          return _buildEmptyState(context, colors);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              // §16 — one scale language: the rail content height is the
              // shared rail metrics (ring + label gap + label), the same
              // constants the chat rail renders at.
              height:
                  StoryRailMetrics.ring +
                  StoryRailMetrics.labelGap +
                  StoryRailMetrics.label,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: following.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AzSpace.lg - 2),
                itemBuilder: (context, index) {
                  final biz = following[index];
                  final id = biz['id']?.toString() ?? '';
                  final name = biz['businessName']?.toString() ?? '';
                  final logoUrl = biz['logoUrl']?.toString();
                  // Review A4 — verification is not a story boost; the
                  // feed carries no boost field, so the expanded ring
                  // keeps the boost treatment OFF too (honest §9 data).
                  final hasUnseen = businessHasUnseenStory(biz);

                  return GestureDetector(
                    onTap: () => onOpenBusiness(id),
                    child: SizedBox(
                      width: 68,
                      child: Column(
                        children: [
                          Hero(
                                tag: 'marketplace-story-ring-$id',
                                child: StoryRing(
                                  avatarUrl: logoUrl,
                                  // Count-less source (§9): the business feed
                                  // carries only lastStoryAt/lastViewedAt — the
                                  // dash renders, the numeric badge does NOT
                                  // (never a manufactured count).
                                  counts: StoryRingCounts.fromUnseenFlag(
                                    hasUnseen,
                                  ),
                                  size: StoryRailMetrics.ring,
                                ),
                              )
                              .animate()
                              .scale(
                                delay: Duration(milliseconds: index * 60),
                                duration: 380.ms,
                                curve: Curves.easeOutCubic,
                                begin: Offset(0.3, 0.3),
                                end: Offset(1, 1),
                              )
                              .fadeIn(
                                delay: Duration(milliseconds: index * 60),
                                duration: 280.ms,
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
                          ).animate().fadeIn(
                            delay: Duration(milliseconds: index * 60 + 100),
                            duration: 280.ms,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, AzamanColors colors) {
    // §16 fix — the empty state renders at the SAME 94px rail geometry as
    // the populated rail: rail box (86) + breathing (4) fits the extent
    // with room to spare. The old 'Suggested businesses' heading cost 18px
    // more than the rail extent allows (RenderFlex overflow, clipped at
    // the bottom) and claimed suggestion data that does not exist (§9) —
    // the heading's explanatory value now lives in the Semantics label
    // below, exposed to screen readers without stealing rail geometry.
    return Semantics(
      container: true,
      label:
          'No followed businesses yet. Tap Browse to discover '
          'businesses, or follow one to see its stories here.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height:
                StoryRailMetrics.ring +
                StoryRailMetrics.labelGap +
                StoryRailMetrics.label,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AzSpace.lg - 2),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return GestureDetector(
                    onTap: onBrowsePressed,
                    child: SizedBox(
                      width: 68,
                      child: Column(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: colors.accentSurface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: colors.accent.withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.explore_rounded,
                              color: colors.accent,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Browse',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } else {
                  // Suggested business skeletons (shimmer placeholders)
                  return SizedBox(
                    width: 68,
                    child: Column(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: colors.softSurface,
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ).animate().shimmer(
                          delay: (index * 200).ms,
                          duration: 1200.ms,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 40,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors.softSurface,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ).animate().shimmer(
                          delay: (index * 200 + 100).ms,
                          duration: 1200.ms,
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
