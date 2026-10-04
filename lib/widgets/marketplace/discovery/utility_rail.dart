// Utility filters. Only chips whose signal is supported render.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/experience/gateways/marketplace_discovery_gateway.dart';
import 'package:azaman/providers/saved_businesses_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/scale_tap.dart';

enum UtilityFilter { nearMe, openNow, topRated, saved }

extension UtilityFilterX on UtilityFilter {
  String get label => switch (this) {
        UtilityFilter.nearMe => 'Near me',
        UtilityFilter.openNow => 'Open now',
        UtilityFilter.topRated => 'Top rated',
        UtilityFilter.saved => 'Saved',
      };

  DiscoverySignal? get signal => switch (this) {
        UtilityFilter.nearMe => DiscoverySignal.nearby,
        UtilityFilter.openNow => DiscoverySignal.openNow,
        UtilityFilter.topRated => DiscoverySignal.topRated,
        UtilityFilter.saved => null,
      };
}

/// Pure visibility rule — tested without widgets.
List<UtilityFilter> visibleUtilityFilters({
  required Set<DiscoverySignal> supported,
  required bool hasSaves,
}) =>
    UtilityFilter.values.where((f) {
      if (f == UtilityFilter.saved) return hasSaves;
      return supported.contains(f.signal);
    }).toList();

class UtilityRail extends ConsumerWidget {
  final UtilityFilter? active;
  final ValueChanged<UtilityFilter?> onChanged;
  const UtilityRail({super.key, required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final supported = ref.watch(marketplaceDiscoveryGatewayProvider).supportedSignals;
    final hasSaves = ref.watch(savedBusinessesProvider.select((s) => s.isNotEmpty));
    final filters = visibleUtilityFilters(supported: supported, hasSaves: hasSaves);
    if (filters.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView.separated(
        key: const ValueKey('marketplace_utility_rail'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: AzSpace.sm),
        itemBuilder: (_, i) {
          final f = filters[i];
          final selected = f == active;
          return ScaleTap(
            onTap: () {
              AzamanHaptics.toggle();
              onChanged(selected ? null : f);
            },
            child: Container(
              key: ValueKey('marketplace_utility_${f.name}'),
              padding: const EdgeInsets.symmetric(horizontal: AzSpace.md),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? colors.accent : colors.softSurface,
                borderRadius: BorderRadius.circular(AzRadius.pill),
              ),
              child: Text(f.label,
                  style: AzText.label.copyWith(
                      color: selected ? colors.background : colors.textPrimary)),
            ),
          );
        },
      ),
    );
  }
}