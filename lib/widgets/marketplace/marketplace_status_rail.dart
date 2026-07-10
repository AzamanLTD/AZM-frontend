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

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/widgets/story_ring.dart';

class MarketplaceStatusRail extends ConsumerStatefulWidget {
  final void Function(String businessProfileId) onOpenBusiness;
  final VoidCallback? onBrowsePressed;

  const MarketplaceStatusRail({
    super.key,
    required this.onOpenBusiness,
    this.onBrowsePressed,
  });

  @override
  ConsumerState<MarketplaceStatusRail> createState() =>
      _MarketplaceStatusRailState();
}

class _MarketplaceStatusRailState extends ConsumerState<MarketplaceStatusRail>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _expandAnim =
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _animCtrl.forward() : _animCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final followingState = ref.watch(followingListProvider);

    return followingState.when(
      loading: () => const SizedBox(height: 40),
      error: (_, __) => const SizedBox.shrink(),
      data: (following) {
        if (following.isEmpty) {
          // Empty state: subtle inline nudge, not a full card
          return GestureDetector(
            onTap: widget.onBrowsePressed,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                        color: colors.accentSurface, shape: BoxShape.circle),
                    child: Icon(Icons.storefront_outlined,
                        size: 14, color: colors.accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Follow businesses to see live updates here',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: colors.textTertiary,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: colors.textTertiary),
                ],
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Collapsed pill: stacked squircles ──────────────────────────
            SizeTransition(
              sizeFactor: ReverseAnimation(_expandAnim),
              axisAlignment: -1,
              child: GestureDetector(
                onTap: _toggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                  child: Row(
                    children: [
                      _StackedSquircles(following: following, colors: colors),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${following.length} business update${following.length == 1 ? '' : 's'}',
                          style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          size: 18, color: colors.textTertiary),
                    ],
                  ),
                ),
              ),
            ),
            // ── Expanded list: full story rings ────────────────────────────
            SizeTransition(
              sizeFactor: _expandAnim,
              axisAlignment: -1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
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
                          onTap: () => widget.onOpenBusiness(id),
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
                                      color: colors.textSecondary),
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
                  ),
                  // Collapse handle
                  GestureDetector(
                    onTap: _toggle,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Icon(Icons.keyboard_arrow_up_rounded,
                          size: 18, color: colors.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// Three stacked squircle avatars (first 3 followed businesses)
class _StackedSquircles extends StatelessWidget {
  final List following;
  final AzamanColors colors;
  const _StackedSquircles({required this.following, required this.colors});

  @override
  Widget build(BuildContext context) {
    final count = following.length.clamp(0, 3);
    const size = 28.0;
    const overlap = 16.0;

    return SizedBox(
      width: size + (count - 1) * overlap,
      height: size,
      child: Stack(
        children: List.generate(count, (i) {
          final biz = following[i];
          final logoUrl = biz['logoUrl']?.toString();
          final name = biz['businessName']?.toString() ?? '';

          return Positioned(
            left: i * overlap,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.background, width: 1.5),
                color: colors.card,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6.5),
                child: logoUrl != null && logoUrl.isNotEmpty
                    ? Image.network(logoUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _initial(name, colors))
                    : _initial(name, colors),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _initial(String name, AzamanColors colors) {
    return Container(
      color: colors.accentSurface,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'B',
        style: TextStyle(
            color: colors.accent, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
