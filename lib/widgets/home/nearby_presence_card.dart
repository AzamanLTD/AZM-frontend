// lib/widgets/home/nearby_presence_card.dart
// =============================================================================
// AZAMAN — NEARBY PRESENCE, HOME CARD 0 (Part 6.6 §F)
//
// A DATA-ONLY builder. It emits a HomeReminderCardData and nothing else, so
// the existing deck architecture measures and renders it exactly like every
// other card. No layout, no measurement, no _deckFill or bandCap change.
//
// Visibility is a strict ladder (Part 6.6 §E). Any rung that is not satisfied
// returns null and the card does not exist:
//   1. server feature flag (AppConfig.presenceEnabled)
//   2. app unlocked through MoneyAccessController
//   3. network is not known-down
// A locked app never leaks presence above the lock surface.
// =============================================================================

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/providers/nearby_presence_controller.dart';
import 'package:azaman/providers/presence_preferences_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/widgets/home/home_reminder_deck.dart';

/// Card 0. Returns null whenever Nearby must be invisible.
HomeReminderCardData? nearbyPresenceCard(WidgetRef ref, BuildContext context) {
  // 1. The server flag. Off ⇒ the feature does not exist anywhere.
  if (!AppConfig.presenceEnabled) return null;

  // 2. The lock. Nothing presence-shaped renders above the lock surface.
  final money = ref.watch(moneyAccessProvider);
  if (money.isLocked) return null;

  final prefs = ref.watch(presencePreferencesProvider);

  // 3. Discovery preference OFF: the ONLY thing offered is a way to turn it
  //    on. No scan has run, no permission has been asked.
  if (!prefs.nearbyDiscovery) {
    return HomeReminderCardData(
      id: 'nearby-discover',
      eyebrow: 'NEARBY',
      title: 'Find stores near you',
      subtitle: 'Turn on nearby discovery when you want it',
      icon: HugeIconsSolid.location01,
      onTap: () => GoRouter.of(context).push(AzRoutes.nearbyPreferences),
    );
  }

  final state = ref.watch(nearbyPresenceControllerProvider);

  return switch (state) {
    // Found one: the verified merchant, never an automatic checkout.
    PresenceFoundOne(:final candidate) => HomeReminderCardData(
      id: 'nearby-one-${candidate.branchId}',
      eyebrow: 'NEARBY',
      title: candidate.merchantName,
      subtitle: candidate.proximity.label,
      icon: HugeIconsSolid.store01,
      onTap: () => GoRouter.of(context).push(
        AzRoutes.storefront(candidate.branchId, name: candidate.merchantName),
      ),
    ),

    // Found many: the customer chooses. Never an automatic entry.
    PresenceFoundMany(:final candidates) => HomeReminderCardData(
      id: 'nearby-many',
      eyebrow: 'NEARBY',
      title: '${candidates.length} stores near you',
      subtitle: 'Tap to choose where you are',
      icon: HugeIconsSolid.location01,
      onTap: () => GoRouter.of(context).push(AzRoutes.nearby),
    ),

    // Scanning is a quiet slot state, never a blocking spinner.
    PresenceScanning() => HomeReminderCardData(
      id: 'nearby-scanning',
      eyebrow: 'NEARBY',
      title: 'Looking around you',
      subtitle: 'This takes a few seconds',
      icon: HugeIconsSolid.location01,
      onTap: () => GoRouter.of(context).push(AzRoutes.nearby),
    ),

    // Blocked states: only the ones that are actionable and honest.
    PresenceBlocked(:final reason) => switch (reason) {
      PresenceBlockReason.bluetoothOff => HomeReminderCardData(
        id: 'nearby-bt-off',
        eyebrow: 'NEARBY',
        title: 'Bluetooth is off',
        subtitle: 'Turn it on to find stores near you',
        icon: HugeIconsSolid.location01,
        onTap: () => GoRouter.of(context).push(AzRoutes.nearby),
      ),
      PresenceBlockReason.permissionDenied => HomeReminderCardData(
        id: 'nearby-perm',
        eyebrow: 'NEARBY',
        title: 'Nearby needs permission',
        subtitle: 'Tap to allow when you are ready',
        icon: HugeIconsSolid.location01,
        onTap: () => GoRouter.of(context).push(AzRoutes.nearby),
      ),
      PresenceBlockReason.permissionPermanentlyDenied => HomeReminderCardData(
        id: 'nearby-perm-blocked',
        eyebrow: 'NEARBY',
        title: 'Nearby is blocked in settings',
        subtitle: 'You can still browse the marketplace',
        icon: HugeIconsSolid.location01,
        onTap: () => GoRouter.of(context).push(AzRoutes.nearby),
      ),
      // unsupported / offline / throttled / preference / flag / locked:
      // nothing to say, so nothing is shown.
      _ => null,
    },

    // A quiet retry affordance, never a loud error.
    PresenceError() => HomeReminderCardData(
      id: 'nearby-error',
      eyebrow: 'NEARBY',
      title: 'Could not check nearby stores',
      subtitle: 'Tap to try again',
      icon: HugeIconsSolid.location01,
      onTap: () =>
          ref.read(nearbyPresenceControllerProvider.notifier).requestScan(),
    ),

    // No unsolicited empty-state prompt.
    _ => null,
  };
}
