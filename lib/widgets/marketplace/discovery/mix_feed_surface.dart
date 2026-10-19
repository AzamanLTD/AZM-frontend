// =============================================================================
// AZAMAN — MIX FEED SURFACE (the state-honest discovery feed body)
//
// The ONE implementation of the Mix feed's rendered states, extracted from
// the Mix screen so the IN-PLACE mode (Marketplace Home) and the
// compatibility route wrapper share it verbatim:
//
//   loading skeletons · failed + retry (network/5xx) · empty feed (a
//   LEGITIMATE zero-item success) · disabled (the discovery surface is
//   off — distinct from empty) · invalid request (a filter the server
//   rejected) · ready feed with cursor pagination.
//
// The bottom clearance is the HOST's contract: the in-place mode lives in
// the shell tab (navBandClearance + kNavBandGap), the pushed wrapper sits
// above the band (safe area + AzSpace.xxl). Neither is guessed here.
//
// MONEY/DATA GUARANTEES (PR #153, unchanged): server order, server-verified
// exact 2dp GHS strings, no client ranking, payableIn rails only.
//
// FORMAT: the ready feed renders PRODUCT-GALLERY TILES — two near-square
// MixOfferCards per row (responsive at every phone width: 320dp → ~148dp
// tiles, 390dp → ~179dp tiles). Server ORDER is untouched: reading order is
// left-to-right, top-to-bottom, exactly the payload order.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/marketplace_mix_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/widgets/az_error_surface.dart';
import 'package:azaman/widgets/az_skeleton.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/marketplace/discovery/mix_offer_card.dart';

/// One gallery-format loading tile: a square image block over the panel
/// blocks, mirroring the ready tile's composition at every width.
class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AzSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: AzSkeleton(
                width: double.infinity, height: 16, borderRadius: AzRadius.lg),
          ),
          SizedBox(height: AzSpace.xs),
          AzSkeleton(height: 36, borderRadius: AzRadius.md),
          SizedBox(height: AzSpace.xs),
          AzSkeleton(height: 12, width: 70),
        ],
      ),
    );
  }
}

/// The Mix feed body: phase-switched states + the cursor-paginated offer
/// feed. Both Mix surfaces (in-place mode + compatibility wrapper) render
/// THIS — there is no second feed implementation.
class MixFeedSurface extends ConsumerWidget {
  const MixFeedSurface({
    super.key,
    required this.onOpenStore,
    required this.bottomPadding,
  });

  /// Opens the OFFERING store (each host owns navigation).
  final ValueChanged<MixOffer> onOpenStore;

  /// Bottom feed clearance (the host's chrome contract — see header).
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the provider drives this surface's phase switch — every state
    // body reads its own colours where it paints.
    final state = ref.watch(marketplaceMixProvider);

    return switch (state.phase) {
      MixPhase.idle || MixPhase.loading => _loading(),
      MixPhase.failed => _failed(ref, state),
      MixPhase.disabled => _disabled(),
      MixPhase.invalidRequest => _invalidRequest(state),
      MixPhase.ready => _feed(ref, state),
    };
  }

  Widget _loading() {
    // Gallery-grid skeletons: 6 tiles = 3 pair rows, mirroring the ready
    // feed's two-column product format.
    return ListView.builder(
      key: const ValueKey('mix_loading'),
      padding: _insets(),
      itemCount: 3,
      // The row measures the ALREADY-INSETTED content width, so the pair
      // exactly fills the row at every phone width.
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: AzSpace.sm),
        child: Row(
          children: [
            Expanded(child: _TileSkeleton()),
            SizedBox(width: AzSpace.sm),
            Expanded(child: _TileSkeleton()),
          ],
        ),
      ),
    );
  }



  Widget _failed(WidgetRef ref, MarketplaceMixState state) {
    return Center(
      child: SingleChildScrollView(
        child: AzErrorSurface(
          key: const ValueKey('mix_error'),
          message: state.error ?? 'We couldn\'t load this feed right now.',
          hint: 'Check your connection and try again.',
          onRetry: () => ref.read(marketplaceMixProvider.notifier).retry(),
        ),
      ),
    );
  }

  /// 404 — the discovery surface is not enabled/available. Deliberately
  /// distinct from an empty feed: "no items yet" would be a false claim
  /// about the backend state, and "error, retry" would misreport a
  /// deliberate flag as a transient failure.
  Widget _disabled() {
    return const Center(
      child: SingleChildScrollView(
        child: AzamanEmptyState(
          key: ValueKey('mix_disabled'),
          icon: Icons.travel_explore_outlined,
          title: 'Marketplace Mix isn\'t available yet',
          subtitle:
              'Cross-store browsing is still being switched on. Please check back soon.',
        ),
      ),
    );
  }

  /// 422 — the server rejected a request parameter. Surfaced honestly with
  /// the server's own message and a filter-clear affordance; never retried
  /// in a loop.
  Widget _invalidRequest(MarketplaceMixState state) {
    return Consumer(
      builder: (context, ref, _) => Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AzamanEmptyState(
                key: const ValueKey('mix_invalid_request'),
                icon: Icons.filter_alt_off_outlined,
                title: 'That filter isn\'t supported',
                subtitle:
                    state.error ?? 'Please change the filters and try again.',
              ),
              const SizedBox(height: AzSpace.sm),
              TextButton(
                key: const ValueKey('mix_clear_filters'),
                onPressed: () =>
                    ref.read(marketplaceMixProvider.notifier).clearTaxonomies(),
                child: const Text('Clear filters'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feed(WidgetRef ref, MarketplaceMixState state) {
    if (state.offers.isEmpty) {
      final category = MixCategory.byWire(state.categoryWire);
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AzamanEmptyState(
                key: const ValueKey('mix_empty'),
                icon: category?.icon ?? Icons.inventory_2_outlined,
                title: category == null
                    ? 'Nothing here yet'
                    : 'Nothing in ${category.label} yet',
                subtitle: state.taxonomies.isEmpty
                    ? 'New items appear here as stores list them.'
                    : 'No items match these filters. Try clearing a bubble or two.',
              ),
              // Scan-budget boundary (final acceptance pass, 2026-10-19):
              // the notifier auto-follows empty cursor pages on the first
              // load; if its continuation budget itself is exhausted while
              // a cursor remains, the honest empty state carries an
              // explicit continuation affordance instead of a dead end.
              if (state.hasMore) ...[
                const SizedBox(height: AzSpace.sm),
                TextButton(
                  key: const ValueKey('mix_empty_continue'),
                  onPressed: () =>
                      ref.read(marketplaceMixProvider.notifier).loadMore(),
                  child: const Text('Show more'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Near-end trigger for the next cursor page (deterministic, no
        // infinite-loop risk: loadMore is a no-op without a cursor).
        if (n.metrics.extentAfter < 400) {
          ref.read(marketplaceMixProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        key: const ValueKey('mix_feed'),
        padding: _insets(),
        // Pair rows keep server ORDER: offers 2i and 2i+1 render left and
        // right of one row, then the next pair — exactly payload order.
        itemCount: (state.offers.length + 1) ~/ 2 + 1,
        itemBuilder: (context, i) {
          final left = 2 * i;
          if (left < state.offers.length) {
            final right = left + 1;
            final hasRight = right < state.offers.length;
            // The ROW owns the grid's vertical gutter (the tile rect is
            // pure tile — the geometry contract measures it directly).
            return Padding(
              padding: const EdgeInsets.only(bottom: AzSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: MixOfferCard(
                      offer: state.offers[left],
                      onOpenStore: onOpenStore,
                    ),
                  ),
                  const SizedBox(width: AzSpace.sm),
                  Expanded(
                    child: hasRight
                        ? MixOfferCard(
                            offer: state.offers[right],
                            onOpenStore: onOpenStore,
                          )
                        : const SizedBox(),
                  ),
                ],
              ),
            );
          }
          return _feedTail(state);
        },
      ),
    );
  }

  Widget _feedTail(MarketplaceMixState state) {
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AzSpace.lg),
        child: Center(child: AzSkeleton(width: 120, height: 12)),
      );
    }
    return const SizedBox(height: AzSpace.xxs);
  }

  EdgeInsets _insets() =>
      EdgeInsets.fromLTRB(AzSpace.lg, AzSpace.md, AzSpace.lg, bottomPadding);
}
