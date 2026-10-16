// =============================================================================
// AZAMAN — MARKETPLACE MIX SCREEN (category-first, cross-store browse)
//
// The Mix mode from the Marketplace Mix redesign: pick a CATEGORY, see items
// from MANY businesses in that category in one feed, compare offers, open the
// offering store — never entering a store to browse a category. The feed is
// ONE bounded request per page to the canonical backend endpoint
// `GET /api/discovery/items` (backend PR #349), cursor-paginated, with the
// selected category and taxonomy chips preserved while paging.
//
// REACHABILITY: pushed above the shell (the persistent bottom-nav band does
// not overlap pushed routes), so bottom clearance is the system safe area +
// [AzSpace.xxl].
//
// COMPATIBILITY WRAPPER (in-place Mix PR): the Marketplace's OWN Mix button
// now toggles the in-place mode inside MarketplaceHomeScreen and never
// pushes this route. This screen remains ONLY as the compatibility route
// for external links (/business-market/mix?category=…): its initial
// category travels through the ONE dial↔discovery boundary
// ([MixDialCategoryBoundary.dialToMix] — REAL_ESTATE → HOSPITALITY,
// unknown/absent → null = the unfiltered All feed), and its feed body is
// the SAME shared [MixFeedSurface] the in-place mode renders.
//
// STATES (each rendered honestly — see the provider's failure model):
//   loading skeletons · failed + retry (network/5xx) · empty feed (a
//   LEGITIMATE zero-item success) · disabled (the discovery surface is off —
//   distinct from empty) · invalid request (a filter the server rejected) ·
//   ready feed + taxonomy chip rail. Reduced motion is honoured by the
//   shared widgets (ScaleTap) and the absence of enter/scroll animations on
//   this screen.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/marketplace_mix_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/marketplace/discovery/mix_feed_surface.dart';

class MarketplaceMixScreen extends ConsumerStatefulWidget {
  /// Initial category wire in EITHER vocabulary (a legacy marketplace link
  /// may carry the dial's REAL_ESTATE); translated through the one
  /// boundary, with null/unknown meaning All (the unfiltered feed).
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
    // THE one explicit boundary: dial wire → discovery wire. REAL_ESTATE
    // becomes HOSPITALITY; anything unknown (or absent) becomes null —
    // the unfiltered All feed. An invalid query is impossible and the
    // mismatch NEVER silently defaults to Eat.
    final initial = MixDialCategoryBoundary.dialToMix(widget.category);
    // First frame: kick the load without marking the widget dirty mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(marketplaceMixProvider.notifier).selectCategory(initial);
    });
  }

  void _selectCategory(String? wire) {
    final current = ref.read(marketplaceMixProvider);
    // Same category and already (successfully) loaded: no-op, like the dial.
    if (current.categoryWire == wire &&
        current.taxonomies.isEmpty &&
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
            _taxonomyRail(colors, state),
            Expanded(
              key: const ValueKey('mix_feed_slot'),
              // The SHARED feed surface — the exact body the in-place Mix
              // mode renders. No second feed implementation exists.
              child: MixFeedSurface(
                onOpenStore: _openStore,
                bottomPadding:
                    MediaQuery.paddingOf(context).bottom + AzSpace.xxl,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AzamanColors colors, String? categoryWire) {
    final category = MixCategory.byWire(categoryWire);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AzSpace.lg,
        AzSpace.md,
        AzSpace.lg,
        AzSpace.xs,
      ),
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
                  style: AzText.titleL.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AzSpace.xxs),
                Text(
                  'Browse ${category?.label.toLowerCase() ?? 'items'} across every store',
                  style: AzText.bodyS.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryRail(AzamanColors colors, String? selectedWire) {
    // ALL first (null wire = the unfiltered discovery feed), then the four
    // real categories — the same ladder the in-place mode's dial offers.
    final entries = <(String?, MixCategory?)>[
      (null, null),
      for (final c in MixCategory.values) (c.wire, c),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        key: const ValueKey('mix_category_rail'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: AzSpace.sm),
        itemBuilder: (_, i) {
          final (wire, c) = entries[i];
          final label = c?.label ?? 'All';
          final icon = c?.icon ?? Icons.apps_rounded;
          final selected = wire == selectedWire;
          return GestureDetector(
            key: ValueKey('mix_category_${wire ?? 'ALL'}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _selectCategory(wire),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
                  Icon(
                    icon,
                    size: 14,
                    color: selected ? colors.accent : colors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
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

  /// Canonical taxonomy chips for the selected category. Wire values only
  /// ([MixTaxonomy.canonical] mirrors the backend overlay); a chip is NEVER
  /// inferred from a section name.
  Widget _taxonomyRail(AzamanColors colors, MarketplaceMixState state) {
    // All mode: no chips (the provider returns none for a null wire).
    final chips = MixTaxonomy.forCategory(state.categoryWire);
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AzSpace.xs),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          key: const ValueKey('mix_taxonomy_rail'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: AzSpace.xs),
          itemBuilder: (_, i) {
            final chip = chips[i];
            final selected = state.taxonomies.contains(chip.id);
            return GestureDetector(
              key: ValueKey('mix_taxonomy_${chip.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                AzamanHaptics.selection();
                ref
                    .read(marketplaceMixProvider.notifier)
                    .toggleTaxonomy(chip.id);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? colors.accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? colors.accent : colors.divider,
                    width: selected ? 1.0 : 0.5,
                  ),
                ),
                child: Text(
                  chip.label,
                  style: AzText.caption.copyWith(
                    color: selected ? colors.accent : colors.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 404 — the discovery surface is not enabled/available. Deliberately
  /// distinct from an empty feed: "no items yet" would be a false claim about
  /// the backend state, and "error, retry" would misreport a deliberate flag
  /// as a transient failure.

  /// 422 — the server rejected a request parameter. Surfaced honestly with
  /// the server's own message and a filter-clear affordance; never retried
  /// in a loop.

  /// Feed insets. The BOTTOM inset is the clearance contract: pushed routes
  /// sit above the persistent nav band, so the final item clears the system
  /// gesture area plus a [AzSpace.xxl] gap. Pinned in the widget test.
}
