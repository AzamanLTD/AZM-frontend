// World deck: 4 world cards with real counts and real signals. No fabricated
// imagery — a flat accent fill when the catalog has no cover images.

import 'package:flutter/material.dart';

import 'package:azaman/experience/gateways/marketplace_discovery_gateway.dart';
import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/business_hours.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/scale_tap.dart';

class WorldCardModel {
  final BusinessCategory category;
  final int count;
  final int? openNow; // null when hours unsupported
  final int? withinKm; // null when location unsupported
  final List<String> coverUrls; // ≤ 3, real

  /// From the central blueprint — the portal is never a second owner of
  /// vertical semantics.
  final String promise;

  /// False only when the catalog HAS loaded and this world is genuinely
  /// empty. While nothing is loaded yet (first frame, offline) every world
  /// stays tappable — entering it is how the data gets fetched.
  final bool enabled;

  const WorldCardModel({
    required this.category,
    required this.count,
    required this.promise,
    this.openNow,
    this.withinKm,
    this.coverUrls = const [],
    this.enabled = true,
  });

  /// Signal line rule (brief §3.4): open-now beats distance beats count.
  String get signalLine {
    if (openNow != null && openNow! > 0) return '$openNow open now';
    if (withinKm != null && withinKm! > 0) return '$withinKm within 1 km';
    return count == 1 ? '1 place' : '$count places';
  }
}

bool _inWorld(BusinessProfile b, String wire) {
  final cat = b.category.toUpperCase();
  if (wire == 'HOSPITALITY') return cat == 'HOSPITALITY' || cat == 'REAL_ESTATE';
  return cat == wire;
}

List<WorldCardModel> buildWorldCards(
  DiscoverySnapshot s,
  Set<DiscoverySignal> supported,
) {
  return BusinessCategories.primary.map((cat) {
    final members = s.catalog.where((b) => _inWorld(b, cat.wire)).toList();
    final open = supported.contains(DiscoverySignal.openNow)
        ? members.where((b) => b.openStateAt(s.now) == OpenState.open).length
        : null;
    final near = (supported.contains(DiscoverySignal.nearby) && s.distanceKmByBusinessId != null)
        ? members.where((b) => (s.distanceOf(b) ?? double.infinity) <= 1.0).length
        : null;
    final sorted = List<BusinessProfile>.from(members)
      ..sort((a, b) => b.averageRating.compareTo(a.averageRating));
    return WorldCardModel(
      category: cat,
      count: members.length,
      promise: MarketplaceExperienceBlueprint.fromJson(null, cat.wire).worldPromise,
      openNow: open,
      withinKm: near,
      enabled: members.isNotEmpty || s.catalog.isEmpty,
      coverUrls: sorted
          .map((b) => b.coverImageUrl ?? b.logoUrl)
          .whereType<String>()
          .where((u) => u.isNotEmpty)
          .take(3)
          .toList(),
    );
  }).toList();
}

class WorldDeck extends StatelessWidget {
  final List<WorldCardModel> cards;
  final AzamanColors colors;
  final void Function(String wire) onEnter;
  const WorldDeck({super.key, required this.cards, required this.colors, required this.onEnter});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AzSpace.lg, AzSpace.lg, AzSpace.lg, AzSpace.sm),
          child: Text('Choose your world',
              key: const ValueKey('marketplace_worlds_header'),
              style: AzText.title.copyWith(color: colors.textPrimary)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AzSpace.md,
            crossAxisSpacing: AzSpace.md,
            childAspectRatio: 2.1,
            children: [
              for (final c in cards)
                RepaintBoundary(
                  child: _WorldCard(
                    model: c,
                    colors: colors,
                    onTap: c.enabled ? () => onEnter(c.category.wire) : null,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorldCard extends StatelessWidget {
  final WorldCardModel model;
  final AzamanColors colors;
  final VoidCallback? onTap;
  const _WorldCard({required this.model, required this.colors, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cat = model.category;
    final disabled = onTap == null;
    final card = Container(
      key: ValueKey('marketplace_world_${cat.wire}'),
      decoration: BoxDecoration(
        color: cat.color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AzRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (model.coverUrls.isNotEmpty)
            Row(
              children: [
                for (final url in model.coverUrls)
                  Expanded(
                    child: AzamanNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const SizedBox.shrink(),
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
              ],
            )
          else
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(AzSpace.md),
                child: Icon(cat.icon, color: cat.color, size: 28),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.35, 1.0],
                colors: [Color(0x00000000), Color(0xB3000000)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AzSpace.md),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(cat.icon, color: Colors.white, size: 15),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(cat.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AzText.title.copyWith(color: Colors.white)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(model.promise,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AzText.caption.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                const SizedBox(height: AzSpace.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AzSpace.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AzRadius.pill),
                  ),
                  child: Text(model.signalLine,
                      key: ValueKey('marketplace_world_count_${cat.wire}'),
                      style: AzText.caption.copyWith(color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // Disabled (empty) worlds stay visible so the four-world mental model is
    // stable; they just don't respond.
    if (disabled) return Opacity(opacity: 0.5, child: card);
    return ScaleTap(onTap: onTap, child: card);
  }
}