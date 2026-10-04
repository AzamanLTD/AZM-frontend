// Portal/featured merchant card — answers five questions with ≤ 5 elements:
// what is this place · why care · relevant now · what can I do · save.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/experience/motion/az_identity_morph.dart';
import 'package:azaman/marketplace/experience/marketplace_experience_capabilities.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/marketplace_discovery_provider.dart';
import 'package:azaman/providers/saved_businesses_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/utils/business_hours.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/chat_avatar.dart';
import 'package:azaman/widgets/marketplace/discovery/trust_mark.dart';
import 'package:azaman/widgets/scale_tap.dart';

class MerchantCard extends ConsumerWidget {
  final BusinessProfile business;
  final double? distanceKm;
  final VoidCallback onOpen;
  const MerchantCard({
    super.key,
    required this.business,
    this.distanceKm,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final travel = AzMotion.of(context).travel;
    final profile = MarketplaceExperienceCatalog.fromCategory(business.category);
    final open = ref.watch(discoverySnapshotProvider.select((s) => business.openStateAt(s.now)));
    final saved = ref.watch(savedBusinessesProvider.select((s) => s.contains(business.bizId)));

    final relevance = [
      if (open == OpenState.open) 'Open now',
      if (open == OpenState.closed) 'Closed',
      if (distanceKm != null)
        '${distanceKm!.toStringAsFixed(distanceKm! < 10 ? 1 : 0)} km',
    ].join(' · ');

    return RepaintBoundary(
      child: ScaleTap(
        onTap: onOpen,
        child: Container(
          key: ValueKey('merchant_card_${business.bizId}'),
          width: 220,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AzRadius.lg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. what is this place — cover + logo identity (logo is the Hero)
              SizedBox(
                height: 110,
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    if (business.coverImageUrl != null && business.coverImageUrl!.isNotEmpty)
                      AzamanNetworkImage(imageUrl: business.coverImageUrl, fit: BoxFit.cover)
                    else
                      Container(color: colors.accent.withValues(alpha: .18)),
                    Positioned(
                      left: AzSpace.md,
                      bottom: -16,
                      child: AzIdentityMorph(
                        tag: AzIdentityTag.business(business.bizId),
                        travel: travel,
                        child: ChatAvatar(
                          imageUrl: business.logoUrl,
                          name: business.businessName,
                          size: 40,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AzSpace.xl),
              Padding(
                padding: const EdgeInsets.fromLTRB(AzSpace.md, 0, AzSpace.md, AzSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 2. why care — name + trust
                    Row(children: [
                      Expanded(
                        child: Text(business.businessName,
                            style: AzText.title.copyWith(color: colors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      TrustMark(business: business),
                    ]),
                    // 3. relevant now — only real signals
                    if (relevance.isNotEmpty)
                      Text(relevance,
                          key: ValueKey('merchant_card_relevance_${business.bizId}'),
                          style: AzText.bodyS.copyWith(
                              color: open == OpenState.open ? colors.success : colors.textSecondary)),
                    const SizedBox(height: AzSpace.sm),
                    // 4. what can I do — one primary intent from the vertical catalog
                    Row(children: [
                      Expanded(
                        child: Text(profile.primaryActionLabel,
                            style: AzText.label.copyWith(color: colors.accent)),
                      ),
                      // 5. save
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          AzamanHaptics.toggle();
                          ref.read(savedBusinessesProvider.notifier).toggle(business.bizId);
                        },
                        child: Icon(
                          saved ? HugeIconsSolid.bookmark02 : HugeIconsSolid.bookmark01,
                          size: 18,
                          color: saved ? colors.accent : colors.textTertiary,
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}