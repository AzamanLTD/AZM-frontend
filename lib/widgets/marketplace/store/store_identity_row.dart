/// Store identity row (Overhaul 03 §1.1) — the first content block inside the
/// storefront sheet, identical for every vertical: logo (identity morph) ·
/// name · trust mark · category line.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/experience/motion/az_identity_morph.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/chat_avatar.dart';
import 'package:azaman/widgets/marketplace/discovery/trust_mark.dart';

class StoreIdentityRow extends ConsumerWidget {
  final BusinessProfile business;

  const StoreIdentityRow({super.key, required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final travel = AzMotion.of(context).travel;
    final cat = BusinessCategories.fromWire(business.category);
    final sub = business.subcategory;
    final contextLine = <String>[
      if (cat.wire.isNotEmpty) cat.label,
      if (sub != null && sub.trim().isNotEmpty) sub.trim(),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(AzSpace.xl, AzSpace.md, AzSpace.xl, AzSpace.sm),
      child: Row(
        children: [
          // Same `logoUrl` as the top pill — one identity, three sizes.
          AzIdentityMorph(
            tag: AzIdentityTag.business(business.bizId),
            travel: travel,
            child: ChatAvatar(imageUrl: business.logoUrl, name: business.businessName, size: 56),
          ),
          const SizedBox(width: AzSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        business.businessName,
                        style: AzText.titleL.copyWith(color: colors.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AzSpace.xs),
                    TrustMark(business: business, compact: true),
                  ],
                ),
                if (contextLine.isNotEmpty)
                  Text(
                    contextLine,
                    key: const ValueKey('store_identity_context'),
                    style: AzText.bodyS.copyWith(color: colors.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}