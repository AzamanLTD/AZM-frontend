// =============================================================================
// AZAMAN — STORY VIEWER: BUSINESS TRAY
//
// Story → store continuity (Overhaul 05 §7). Renders ONLY when the linked
// business resolves; tapping opens the business profile imperatively — the
// viewer itself is an imperative route on the root navigator, so go_router's
// push would land the profile BELOW it (see onTap). The page pushed is the
// same one the /business/:bizId route builds (AzRoutes.businessProfile,
// route_registry.dart:211 → app_router.dart:528). The vertical's
// primary action label comes from the EXISTING marketplace catalog — nothing
// invented. No money moves from a story: no pay CTA exists until the backend
// exposes a story payment-intent object (seam documented below).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';

import 'package:azaman/marketplace/experience/marketplace_experience_capabilities.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/chat_avatar.dart';

/// Resolves a story's linked business. Cache-first: a business already in the
/// search results is used as-is; otherwise the public GET /business/:bizId
/// (BusinessService.getBusinessByBizId) loads it. Unresolvable → null → the
/// tray stays hidden (no placeholder chip pretending a store exists).
final linkedBusinessProvider =
    FutureProvider.autoDispose.family<BusinessProfile?, String>(
  (ref, bizId) async {
    final cached = ref
        .read(businessSearchProvider)
        .results
        .where((b) => b.bizId == bizId || b.id == bizId)
        .firstOrNull;
    if (cached != null) return cached;
    return BusinessService().getBusinessByBizId(bizId);
  },
);

class StoryBusinessTray extends ConsumerWidget {
  const StoryBusinessTray({
    super.key,
    required this.bizId,
    required this.onPause,
    required this.onResume,
  });

  final String bizId;

  /// The viewer pauses playback while the profile route is above it.
  final VoidCallback onPause;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final biz = ref.watch(linkedBusinessProvider(bizId)).valueOrNull;
    if (biz == null) return const SizedBox.shrink();

    final profile = MarketplaceExperienceCatalog.fromCategory(biz.category);
    // TODO(story-pay-intent): a "Send money" CTA may only appear here once the
    // backend exposes a story payment-intent object. Never auto-execute a
    // financial action from a story; the seam is this tray, not a hidden call.

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Semantics(
          button: true,
          label: '${profile.primaryActionLabel} at ${biz.businessName}',
          child: Material(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AzRadius.pill),
            child: InkWell(
              borderRadius: BorderRadius.circular(AzRadius.pill),
              onTap: () {
                AzamanHaptics.selection();
                onPause();
                // The viewer is an IMPERATIVE route pushed on the root
                // navigator (StoryViewerScreen.open); go_router's
                // context.push would add the profile to the router's stack
                // BELOW the opaque viewer — invisible, and playback would
                // stay paused forever. Push imperatively with the same page
                // the /business/:bizId route builds (app_router.dart:528).
                Navigator.of(context)
                    .push(MaterialPageRoute(
                      builder: (_) => BusinessProfileScreen(bizId: biz.bizId),
                    ))
                    .whenComplete(onResume);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AzSpace.md, vertical: AzSpace.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChatAvatar(
                        imageUrl: biz.logoUrl,
                        name: biz.businessName,
                        size: 28),
                    const SizedBox(width: AzSpace.sm),
                    Flexible(
                      child: Text(
                        biz.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AzText.label.copyWith(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: AzSpace.sm),
                    Text(
                      profile.primaryActionLabel,
                      style:
                          AzText.label.copyWith(color: Colors.amberAccent),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
