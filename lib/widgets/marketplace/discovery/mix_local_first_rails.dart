// =============================================================================
// AZAMAN — MIX LOCAL-FIRST RAILS (Workstream H)
//
// The local-first structure above the discovery feed while Mix runs with
// Near You co-activated:
//
//   1. NEARBY FOR YOU — real location-based results from the nearby
//      search provider: embedded business facts + the REAL distance the
//      server measured. No location rows → the rail renders NOTHING
//      (an empty rail would be fake richness).
//   2. FROM YOUR NETWORK — offers in the live discovery feed from
//      businesses the user actually follows (the server-backed follow
//      list — GET /follows/following). No follows or no intersection →
//      the rail renders nothing. The friend-graph social-proof contract
//      (Workstream I2) does not exist yet; this rail never pretends it
//      does — it shows only the verified follow signal that exists.
//
// HONESTY GUARANTEES:
//   • Every nearby row renders the server-measured distanceKm or nothing —
//     a null distance is never guessed and COORDINATES ARE NEVER
//     RENDERED.
//   • Every card carries only embedded facts from the real payload
//     (name/logo/category); absent facts degrade to honest placeholders.
//   • "Popular in this area" is deliberately absent: no server-supported
//     area-popularity signal exists for this surface yet, and a missing
//     signal leaves its enhancement absent (master brief, Workstream H).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/providers/marketplace_mix_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';

import 'package:azaman/widgets/azaman_network_image.dart';

/// Compact one-line proximity indication pinned above the rails while the
/// nearby feed drives part of the Mix surface. Static by design: the
/// co-activation either produced a position (the strip states what the
/// results are ordered by) or never activated the proximity feed at all
/// (the strip is not rendered). No spinner — no fake activity.
class MixProximityStrip extends StatelessWidget {
  const MixProximityStrip({super.key, this.onNearYouPressed});

  /// Optional explicit path to the Near You control's request/retry flow
  /// (the honest recovery route when proximity data is missing).
  final VoidCallback? onNearYouPressed;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final colors = ref.watch(themeProvider).colors;
        return Semantics(
          label:
              'Nearby results on. Businesses ordered by their real distance '
              'from your current location.',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.softSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.near_me_rounded, size: 14, color: colors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nearby for you — results ordered by real distance '
                      'from where you are',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AzText.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The local-first rails: real nearby businesses first, then offers from
/// the user's followed businesses. Real-data-only — either rail hides
/// itself when its real signal is empty.
class MixLocalFirstRails extends ConsumerWidget {
  const MixLocalFirstRails({
    super.key,
    required this.onOpenStore,
    this.maxNearby = 6,
    this.maxNetwork = 6,
  });

  /// Opens the offering store through the SAME route the Mix feed uses —
  /// the rails create no second navigation authority.
  final void Function(MixOffer offer) onOpenStore;

  final int maxNearby;
  final int maxNetwork;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ── Rail 1: nearby, from the real proximity provider ──────────────
    final nearby = ref.watch(nearbySearchProvider);
    final nearbyRows = <_NearbyRowData>[];
    if (!nearby.isLoading) {
      for (final loc in nearby.locations) {
        final name = loc.businessName;
        if (name == null || name.trim().isEmpty) continue;
        // Only rows the server actually measured carry distanceKm; a row
        // without a distance still shows (the position search returned
        // it) but never shows a GUESSED distance.
        nearbyRows.add(
          _NearbyRowData(
            name: name,
            logoUrl: loc.businessLogoUrl,
            distanceKm: loc.distanceKm,
          ),
        );
        if (nearbyRows.length >= maxNearby) break;
      }
    }

    // ── Rail 2: the user's REAL followed businesses intersected with the
    // live discovery feed. Absent on any error/empty — never fabricated.
    final mix = ref.watch(marketplaceMixProvider);
    final following = ref.watch(followingListProvider).valueOrNull ?? [];
    final followedIds = <String>{};
    for (final f in following) {
      final id = f['businessProfileId']?.toString();
      if (id != null && id.isNotEmpty) followedIds.add(id);
    }
    final networkOffers = <MixOffer>[];
    if (followedIds.isNotEmpty) {
      for (final offer in mix.offers) {
        // IDENTITY FIX: the follow list carries canonical
        // BusinessProfile.id values; the offer's STORE identity is
        // offer.businessId. Comparing against the display bizId code
        // matched nothing — the rail only ever rendered by luck of
        // identical strings, which the two identities never share.
        if (followedIds.contains(offer.businessId)) {
          networkOffers.add(offer);
          if (networkOffers.length >= maxNetwork) break;
        }
      }
    }

    if (nearbyRows.isEmpty && networkOffers.isEmpty) {
      // Nothing real to say → no rails at all. The full discovery feed
      // below is the honest surface.
      return const SizedBox.shrink(
        key: ValueKey('mix_local_first_rails_empty'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (nearbyRows.isNotEmpty)
          _Rail(
            title: 'Nearby for you',
            children: [
              for (final row in nearbyRows)
                _NearbyRailCard(
                  key: ValueKey('mix_nearby_rail_${row.name}'),
                  data: row,
                ),
            ],
          ),
        if (networkOffers.isNotEmpty)
          _Rail(
            // WORDING FIX (review 5): these businesses come from the
            // user's OWN follow list — "From your network" overstated a
            // social-graph signal that this rail does not measure.
            title: 'Your follows',
            children: [
              for (final offer in networkOffers)
                _NetworkRailCard(
                  key: ValueKey('mix_network_rail_${offer.productId}'),
                  offer: offer,
                  onTap: () => onOpenStore(offer),
                ),
            ],
          ),
        const SizedBox(height: AzSpace.xs),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rail scaffolding
// ─────────────────────────────────────────────────────────────────────────────

class _Rail extends StatelessWidget {
  const _Rail({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final colors = ref.watch(themeProvider).colors;
        return Padding(
          padding: const EdgeInsets.only(top: AzSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  title,
                  style: AzText.eyebrow.copyWith(color: colors.textTertiary),
                ),
              ),
              const SizedBox(height: AzSpace.xs),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  // The rails scroll horizontally; the parent feed keeps
                  // every vertical gesture.
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  clipBehavior: Clip.none,
                  itemCount: children.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AzSpace.sm),
                  itemBuilder: (_, i) => children[i],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NearbyRowData {
  const _NearbyRowData({
    required this.name,
    required this.logoUrl,
    required this.distanceKm,
  });

  final String name;
  final String? logoUrl;

  /// The REAL server-measured distance, or null when the payload did not
  /// supply one — rendered as nothing, never guessed.
  final double? distanceKm;
}

class _NearbyRailCard extends StatelessWidget {
  const _NearbyRailCard({super.key, required this.data});

  final _NearbyRowData data;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final colors = ref.watch(themeProvider).colors;
        final distanceLabel = data.distanceKm == null
            ? null
            : '${data.distanceKm!.toStringAsFixed(data.distanceKm! < 10 ? 1 : 0)} km';
        return Semantics(
          button: true,
          label: distanceLabel == null
              ? '${data.name}, nearby'
              : '${data.name}, $distanceLabel away',
          excludeSemantics: true,
          child: Container(
            width: 148,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: colors.softSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      (data.logoUrl != null && data.logoUrl!.startsWith('http'))
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AzamanNetworkImage(
                            imageUrl: data.logoUrl!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Icon(
                          Icons.storefront_rounded,
                          color: colors.textTertiary,
                          size: 20,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AzText.bodyS.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (distanceLabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          distanceLabel,
                          style: AzText.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NetworkRailCard extends StatelessWidget {
  const _NetworkRailCard({super.key, required this.offer, required this.onTap});

  final MixOffer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final colors = ref.watch(themeProvider).colors;
        final thumb = offer.imageUrls.isNotEmpty ? offer.imageUrls.first : null;
        return Semantics(
          button: true,
          label:
              '${offer.name} from ${offer.businessName}, a business you '
              'follow',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 132,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.softSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: (thumb != null && thumb.startsWith('http'))
                          ? AzamanNetworkImage(
                              imageUrl: thumb,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          : Container(
                              color: colors.card,
                              child: Center(
                                child: Icon(
                                  Icons.shopping_bag_outlined,
                                  color: colors.textTertiary,
                                  size: 20,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    offer.businessName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AzText.caption.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    offer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AzText.bodyS.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
