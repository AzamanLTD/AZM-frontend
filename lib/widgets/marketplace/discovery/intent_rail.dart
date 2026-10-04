// Intent rail: Eat · Shop · Ride · Stay · Nearby · My saves · Recent.
// Items are hidden — never disabled — when their signal/data is unsupported.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/experience/az_intent.dart';
import 'package:azaman/experience/gateways/marketplace_discovery_gateway.dart';
import 'package:azaman/providers/marketplace_discovery_provider.dart';
import 'package:azaman/providers/marketplace_world_memory_provider.dart';
import 'package:azaman/providers/saved_businesses_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/scale_tap.dart';

class DiscoveryIntentItem {
  final AzIntent intent;
  final String label;
  final IconData icon;
  final String? worldWire;
  final DiscoverySignal? signal;
  final bool savesOnly;
  final bool recentOnly;

  const DiscoveryIntentItem({
    required this.intent,
    required this.label,
    required this.icon,
    this.worldWire,
    this.signal,
    this.savesOnly = false,
    this.recentOnly = false,
  });
}

const List<DiscoveryIntentItem> kDiscoveryIntents = [
  DiscoveryIntentItem(intent: AzIntent.order, label: 'Eat', icon: HugeIconsSolid.restaurant01, worldWire: 'FOOD_BEVERAGE'),
  DiscoveryIntentItem(intent: AzIntent.open, label: 'Shop', icon: HugeIconsSolid.shoppingBag01, worldWire: 'RETAIL'),
  DiscoveryIntentItem(intent: AzIntent.book, label: 'Ride', icon: HugeIconsSolid.bus01, worldWire: 'LOGISTICS'),
  DiscoveryIntentItem(intent: AzIntent.book, label: 'Stay', icon: HugeIconsSolid.hotel01, worldWire: 'HOSPITALITY'),
  DiscoveryIntentItem(intent: AzIntent.discover, label: 'Nearby', icon: HugeIconsSolid.location01, signal: DiscoverySignal.nearby),
  DiscoveryIntentItem(intent: AzIntent.save, label: 'My saves', icon: HugeIconsSolid.bookmark01, savesOnly: true),
  DiscoveryIntentItem(intent: AzIntent.discover, label: 'Recent', icon: HugeIconsSolid.clock01, recentOnly: true),
];

/// Pure visibility rule — tested without widgets.
List<DiscoveryIntentItem> visibleIntents({
  required Set<DiscoverySignal> supported,
  required bool hasSaves,
  required bool hasRecent,
}) =>
    kDiscoveryIntents.where((i) {
      if (i.signal != null && !supported.contains(i.signal)) return false;
      if (i.savesOnly && !hasSaves) return false;
      if (i.recentOnly && !hasRecent) return false;
      return true;
    }).toList();

class IntentRail extends ConsumerWidget {
  final void Function(DiscoveryIntentItem item) onSelect;
  const IntentRail({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final supported = ref.watch(marketplaceDiscoveryGatewayProvider).supportedSignals;
    final hasSaves = ref.watch(savedBusinessesProvider.select((s) => s.isNotEmpty));
    final now = ref.watch(discoveryClockProvider)();
    final hasRecent = ref.watch(
        worldMemoryProvider.select((m) => m.values.any((w) => w.isFresh(now))));
    final items = visibleIntents(supported: supported, hasSaves: hasSaves, hasRecent: hasRecent);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        key: const ValueKey('marketplace_intent_rail'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: AzSpace.sm),
        itemBuilder: (_, i) => _IntentChip(
          item: items[i],
          colors: colors,
          onTap: () {
            AzamanHaptics.selection();
            onSelect(items[i]);
          },
        ),
      ),
    );
  }
}

class _IntentChip extends StatelessWidget {
  final DiscoveryIntentItem item;
  final AzamanColors colors;
  final VoidCallback onTap;
  const _IntentChip({required this.item, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: onTap,
      child: Container(
        key: ValueKey('marketplace_intent_${item.label}'),
        padding: const EdgeInsets.symmetric(horizontal: AzSpace.md),
        decoration: BoxDecoration(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(AzRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 16, color: colors.textPrimary),
            const SizedBox(width: 6),
            Text(item.label, style: AzText.label.copyWith(color: colors.textPrimary)),
          ],
        ),
      ),
    );
  }
}