// Portal identity header: "Discover" + inline search hint (opens the search).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/marketplace_discovery_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/scale_tap.dart';

class DiscoveryHeader extends ConsumerWidget {
  final VoidCallback onSearchTap;
  const DiscoveryHeader({super.key, required this.onSearchTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final nearby = ref.watch(
        discoverySnapshotProvider.select((s) => s.distanceKmByBusinessId != null));
    return Padding(
      padding: const EdgeInsets.fromLTRB(AzSpace.lg, AzSpace.sm, AzSpace.lg, AzSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Discover',
              key: const ValueKey('marketplace_portal_title'),
              style: AzText.titleXl.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AzSpace.xs),
          Text(nearby ? 'Around you, on Azaman.' : 'Everything local, on Azaman.',
              key: const ValueKey('marketplace_portal_tagline'),
              style: AzText.body.copyWith(color: colors.textSecondary),
              maxLines: 2),
          const SizedBox(height: AzSpace.lg),
          Semantics(
            button: true,
            label: 'Search the marketplace',
            child: ScaleTap(
              onTap: onSearchTap,
              child: Container(
                key: const ValueKey('marketplace_portal_search_hint'),
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
                decoration: BoxDecoration(
                  color: colors.softSurface,
                  borderRadius: BorderRadius.circular(AzRadius.pill),
                ),
                child: Row(children: [
                  Icon(HugeIconsSolid.search01, size: 18, color: colors.textTertiary),
                  const SizedBox(width: AzSpace.md),
                  Expanded(
                    child: Text('What are you looking for?',
                        style: AzText.body.copyWith(color: colors.textTertiary)),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}