// =============================================================================
// AZAMAN — MIX TAXONOMY BUBBLE RAIL (story-scale subcategory bubbles)
//
// The Mix mode's subcategory filter surface: server-canonical taxonomy
// chips rendered as story-like ICON BUBBLES immediately below the category
// selector. Authority rules (unchanged from the chip rail it replaces in
// the in-place surface):
//   • [MixTaxonomy.canonical] is a byte-exact mirror of the backend's
//     TAXONOMY_ROWS — ids are NEVER inferred, renamed or extended here.
//   • Bubbles render ONLY for the selected category (null applicability =
//     every category). ALL mode renders NO rail at all — an unfiltered
//     feed has no relevant taxonomy.
//   • Tapping a bubble toggles the canonical id through the provider
//     (`taxonomy` repeatable query parameter); the feed resets honestly.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/marketplace_mix_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class MixTaxonomyBubbleRail extends ConsumerWidget {
  const MixTaxonomyBubbleRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(marketplaceMixProvider);
    final colors = ref.watch(themeProvider).colors;

    // ALL mode: no irrelevant taxonomy rail, by contract.
    final chips = MixTaxonomy.forCategory(state.categoryWire);
    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      key: const ValueKey('mix_taxonomy_bubble_rail'),
      height: 88, // story-like scale: 60 bubble + label + breathing room
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: AzSpace.md),
        itemBuilder: (_, i) {
          final chip = chips[i];
          final selected = state.taxonomies.contains(chip.id);
          return GestureDetector(
            key: ValueKey('mix_taxonomy_bubble_${chip.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AzamanHaptics.selection();
              ref
                  .read(marketplaceMixProvider.notifier)
                  .toggleTaxonomy(chip.id);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? colors.accent.withValues(alpha: 0.16)
                        : colors.card,
                    border: Border.all(
                      color: selected
                          ? colors.accent
                          : colors.divider,
                      width: selected ? 1.6 : 0.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    chip.icon,
                    size: 26,
                    color: selected ? colors.accent : colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AzSpace.xs),
                Text(
                  chip.label,
                  style: AzText.caption.copyWith(
                    color: selected ? colors.accent : colors.textSecondary,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
