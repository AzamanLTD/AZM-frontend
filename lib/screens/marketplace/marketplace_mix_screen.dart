// =============================================================================
// AZAMAN — MARKETPLACE MIX SCREEN (category-first, cross-store browse)
//
// The Mix mode from the Marketplace Mix redesign: pick a CATEGORY, see items
// from MANY businesses in that category in one feed, compare offers, open the
// offering store — never entering a store to browse a category.
//
// REACHABILITY: pushed above the shell (the persistent bottom-nav band does
// not overlap pushed routes), so bottom clearance is the system safe area +
// [AzSpace.xxl]. If Mix later becomes an in-tab home mode, the clearance must
// adopt PR #151's `navBandClearance` helper instead — deliberately NOT
// duplicated here (that helper only exists on #151's branch).
//
// STATES: loading skeletons · failed + retry · empty category (no stores) ·
// ready with no listings · partial store failures (slim notice). Reduced
// motion is honoured by the shared widgets (ScaleTap) and the absence of
// enter/scroll animations on this screen.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/marketplace_mix_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/az_error_surface.dart';
import 'package:azaman/widgets/az_skeleton.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/marketplace/discovery/mix_offer_card.dart';

class MarketplaceMixScreen extends ConsumerStatefulWidget {
  /// Initial category wire. Defaults to Eat (FOOD_BEVERAGE).
  final String? category;

  const MarketplaceMixScreen({super.key, this.category});

  @override
  ConsumerState<MarketplaceMixScreen> createState() =>
      _MarketplaceMixScreenState();
}

class _MarketplaceMixScreenState extends ConsumerState<MarketplaceMixScreen> {
  @override
  void initState() {
    super.initState();
    final initial = MixCategory.byWire(widget.category) != null
        ? widget.category!
        : 'FOOD_BEVERAGE';
    // First frame: kick the load without marking the widget dirty mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(marketplaceMixProvider.notifier).selectCategory(initial);
    });
  }

  void _selectCategory(String wire) {
    final current = ref.read(marketplaceMixProvider);
    // Same category and already (successfully) loaded: no-op, like the dial.
    if (current.categoryWire == wire &&
        current.phase != MixPhase.failed &&
        current.phase != MixPhase.idle) {
      return;
    }
    AzamanHaptics.selection();
    ref.read(marketplaceMixProvider.notifier).selectCategory(wire);
  }

  /// Opens the OFFERING store, preserving the selected item's store identity.
  void _openStore(MixOffer offer) {
    // Interactions are recorded against the item+store pair through the real
    // backend events contract (see the provider: product_tap + productId).
    ref.read(marketplaceMixProvider.notifier).trackOfferTap(offer);
    context.push('/business/${offer.bizId}');
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(marketplaceMixProvider);

    return Scaffold(
      key: const ValueKey('marketplace_mix_screen'),
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(colors, state.categoryWire),
            _categoryRail(colors, state.categoryWire),
            Expanded(
              key: const ValueKey('mix_feed_slot'),
              child: switch (state.phase) {
                MixPhase.idle || MixPhase.loading => _loading(colors),
                MixPhase.failed => _failed(colors),
                MixPhase.ready => _feed(colors, state),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AzamanColors colors, String categoryWire) {
    final category = MixCategory.byWire(categoryWire);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AzSpace.lg, AzSpace.md, AzSpace.lg, AzSpace.xs),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('mix_back'),
            icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
            onPressed: () => context.pop(),
            tooltip: 'Back',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Marketplace Mix',
                  style:
                      AzText.titleL.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AzSpace.xxs),
                Text(
                  'Browse ${category?.label.toLowerCase() ?? 'items'} across every store',
                  style:
                      AzText.bodyS.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryRail(AzamanColors colors, String selectedWire) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        key: const ValueKey('mix_category_rail'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
        itemCount: MixCategory.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AzSpace.sm),
        itemBuilder: (_, i) {
          final c = MixCategory.values[i];
          final selected = c.wire == selectedWire;
          return GestureDetector(
            key: ValueKey('mix_category_${c.wire}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _selectCategory(c.wire),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? colors.accent.withValues(alpha: 0.12)
                    : colors.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? colors.accent : colors.divider,
                  width: selected ? 1.2 : 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(c.icon,
                      size: 14,
                      color: selected
                          ? colors.accent
                          : colors.textTertiary),
                  const SizedBox(width: 6),
                  Text(
                    c.label,
                    style: AzText.label.copyWith(
                      color: selected ? colors.accent : colors.textSecondary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _loading(AzamanColors colors) {
    return ListView.builder(
      key: const ValueKey('mix_loading'),
      padding: _feedInsets(),
      itemCount: 6,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: AzSpace.sm),
        child: Row(
          children: [
            AzSkeleton(width: 96, height: 96, borderRadius: AzRadius.lg),
            SizedBox(width: AzSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AzSkeleton(height: 14, width: 180),
                  SizedBox(height: AzSpace.sm),
                  AzSkeleton(height: 12, width: 120),
                  SizedBox(height: AzSpace.sm),
                  AzSkeleton(height: 12, width: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _failed(AzamanColors colors) {
    final state = ref.watch(marketplaceMixProvider);
    return Center(
      child: SingleChildScrollView(
        child: AzErrorSurface(
          key: const ValueKey('mix_error'),
          message: state.error ?? 'We couldn\'t load this category right now.',
          hint: 'Check your connection and try again.',
          onRetry: () => ref.read(marketplaceMixProvider.notifier).retry(),
        ),
      ),
    );
  }

  Widget _feed(colors, MarketplaceMixState state) {
    if (state.offers.isEmpty) {
      final category = MixCategory.byWire(state.categoryWire);
      return Center(
        child: SingleChildScrollView(
          child: AzamanEmptyState(
            key: const ValueKey('mix_empty'),
            icon: category?.icon ?? Icons.inventory_2_outlined,
            title: state.stores.isEmpty
                ? 'No stores in ${category?.label ?? 'this category'} yet'
                : 'No listings yet in ${category?.label ?? 'this category'}',
            subtitle: state.stores.isEmpty
                ? 'New stores appear here as they join Azaman.'
                : 'Stores in this category haven\'t listed any items yet.',
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Near-end trigger for the next store page (deterministic, no
        // infinite-loop risk: loadMoreStores is a no-op without a cursor).
        if (n.metrics.extentAfter < 400) {
          ref.read(marketplaceMixProvider.notifier).loadMoreStores();
        }
        return false;
      },
      child: ListView.builder(
        key: const ValueKey('mix_feed'),
        padding: _feedInsets(),
        // +1 for the partial-failure notice / load-more tail row.
        itemCount: state.offers.length + 1,
        itemBuilder: (context, i) {
          if (i < state.offers.length) {
            final offer = state.offers[i];
            return MixOfferCard(
              offer: offer,
              onOpenStore: _openStore,
            );
          }
          return _feedTail(colors, state);
        },
      ),
    );
  }

  Widget _feedTail(AzamanColors colors, MarketplaceMixState state) {
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AzSpace.lg),
        child: Center(child: AzSkeleton(width: 120, height: 12)),
      );
    }
    if (state.failedStores > 0) {
      return Padding(
        key: const ValueKey('mix_partial_failure'),
        padding: const EdgeInsets.symmetric(vertical: AzSpace.sm),
        child: Center(
          child: Text(
            '${state.failedStores} store${state.failedStores == 1 ? '' : 's'} couldn\'t be loaded',
            style: AzText.caption.copyWith(color: colors.textTertiary),
          ),
        ),
      );
    }
    return const SizedBox(height: AzSpace.xxs);
  }

  /// Feed insets. The BOTTOM inset is the clearance contract: pushed routes
  /// sit above the persistent nav band, so the final item clears the system
  /// gesture area plus a [AzSpace.xxl] gap. Pinned in the widget test.
  EdgeInsets _feedInsets() {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return EdgeInsets.fromLTRB(
      AzSpace.lg,
      AzSpace.md,
      AzSpace.lg,
      bottomInset + AzSpace.xxl,
    );
  }
}
