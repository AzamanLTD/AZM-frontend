// lib/screens/presence/nearby_presence_screen.dart
// =============================================================================
// AZAMAN — NEARBY PRESENCE (Part 6.6 §G) — DIAGNOSTIC / MANUAL FLOW
//
// This screen is NOT the customer multi-store selector (that is the modal
// bottom sheet in `nearby_selector_sheet.dart`, shown over Home). It remains
// as the deliberate manual "check nearby stores" surface, and it is where the
// honest blocked/unavailable states are explained in full.
//
// Everything rendered here comes from the controller's typed state. Nothing
// computes a distance, a floor or a verification badge the server did not
// send.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/nearby_presence_controller.dart';
import 'package:azaman/providers/presence_preferences_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/screens/presence/nearby_selector_sheet.dart';
import 'package:azaman/services/presence/presence_gateway.dart';

class NearbyPresenceScreen extends ConsumerStatefulWidget {
  const NearbyPresenceScreen({super.key});

  @override
  ConsumerState<NearbyPresenceScreen> createState() =>
      _NearbyPresenceScreenState();
}

class _NearbyPresenceScreenState extends ConsumerState<NearbyPresenceScreen> {
  @override
  void initState() {
    super.initState();
    // Manual surface: the customer explicitly asked to check. Still deferred
    // past the first frame and still subject to every gate + throttle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(nearbyPresenceControllerProvider.notifier)
          .requestScan(explicit: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nearbyPresenceControllerProvider);
    final prefs = ref.watch(presencePreferencesProvider);
    final controller = ref.read(nearbyPresenceControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Nearby')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!prefs.nearbyDiscovery)
            _body(
              context,
              icon: HugeIconsSolid.location01,
              title: 'Find stores near you',
              message:
                  'Turn on store discovery to check which participating '
                  'business you are standing in.',
              actionLabel: 'Turn on discovery',
              onAction: () async {
                await ref
                    .read(presencePreferencesProvider.notifier)
                    .setNearbyDiscovery(true);
                if (!context.mounted) return;
                await controller.requestScan(explicit: true);
              },
            )
          else
            ..._stateBody(context, state, controller),
          const SizedBox(height: 28),
          _privacyNote(context),
        ],
      ),
    );
  }

  List<Widget> _stateBody(
    BuildContext context,
    NearbyPresenceState state,
    NearbyPresenceController controller,
  ) {
    switch (state) {
      case PresenceIdle():
        return [
          _body(
            context,
            icon: HugeIconsSolid.location01,
            title: 'Check nearby stores',
            message:
                'We check for participating stores only when you ask, and '
                'only in the foreground.',
            actionLabel: 'Check now',
            onAction: () => controller.requestScan(explicit: true),
          ),
        ];
      case PresenceCheckingPrereqs():
      case PresenceScanning():
        return [_status(context, 'Looking for stores around you…')];
      case PresenceResolving():
        return [_status(context, 'Checking which store this is…')];
      case PresenceFoundOne(:final candidate):
        return [_foundCard(context, candidate, controller)];
      case PresenceFoundMany(:final candidates):
        return [
          _body(
            context,
            icon: HugeIconsSolid.store01,
            title: '${candidates.length} stores nearby',
            message:
                'Choose the store you are visiting. Nothing opens until '
                'you pick one.',
            actionLabel: 'Choose a store',
            onAction: () async {
              final chosen = await showNearbySelectorSheet(
                context,
                candidates: candidates,
              );
              if (chosen == null) {
                for (final c in candidates) {
                  controller.rememberChoice(c.locationId, chosen: false);
                }
              } else {
                controller.rememberChoice(chosen.locationId, chosen: true);
              }
            },
          ),
        ];
      case PresenceNone(:final explicit):
        if (!explicit) return const [];
        return [
          _body(
            context,
            icon: HugeIconsSolid.location01,
            title: 'No participating store detected',
            message:
                'We could not match a participating store to the signals '
                'around you. You can browse the marketplace as usual.',
            actionLabel: 'Check again',
            onAction: () => controller.requestScan(explicit: true),
          ),
        ];
      case PresenceBlocked(:final reason):
        return [_blocked(context, reason)];
      case PresenceError(:final message):
        return [
          _body(
            context,
            icon: HugeIconsSolid.refresh,
            title: 'Could not check right now',
            message: message,
            actionLabel: 'Try again',
            onAction: () => controller.requestScan(explicit: true),
          ),
        ];
    }
  }

  Widget _foundCard(
    BuildContext context,
    PresenceCandidate candidate,
    NearbyPresenceController controller,
  ) {
    final theme = Theme.of(context);
    final detail = <String>[
      if (candidate.branchName.isNotEmpty) candidate.branchName,
      if (candidate.floor != null && candidate.floor!.isNotEmpty)
        'Floor ${candidate.floor}',
      if (candidate.zone != null && candidate.zone!.isNotEmpty) candidate.zone!,
    ].join(' · ');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  backgroundImage:
                      (candidate.logoUrl != null &&
                          candidate.logoUrl!.isNotEmpty)
                      ? NetworkImage(candidate.logoUrl!)
                      : null,
                  child:
                      (candidate.logoUrl == null || candidate.logoUrl!.isEmpty)
                      ? const Icon(HugeIconsSolid.store01, size: 20)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.businessName.isEmpty
                            ? candidate.branchName
                            : candidate.businessName,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (candidate.proximityHint != null)
                  Text(
                    candidate.proximityHint!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _StorefrontAction(candidate: candidate, controller: controller),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => controller.rememberChoice(
                  candidate.locationId,
                  chosen: false,
                ),
                child: const Text('Not here'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blocked(BuildContext context, PresenceBlockReason reason) {
    switch (reason) {
      case PresenceBlockReason.featureFlagOff:
        return _body(
          context,
          icon: HugeIconsSolid.location01,
          title: 'Not available yet',
          message:
              'Store discovery is not available in this build. You can still '
              'find businesses in the marketplace.',
        );
      case PresenceBlockReason.preferenceOff:
        return _body(
          context,
          icon: HugeIconsSolid.location01,
          title: 'Discovery is off',
          message:
              'Turn on discovery in Nearby preferences to check for '
              'participating stores.',
        );
      case PresenceBlockReason.appLocked:
        return _body(
          context,
          icon: HugeIconsSolid.lock,
          title: 'Unlock to check',
          message:
              'Nearby only runs while the app is unlocked. Unlock Azaman and '
              'try again.',
        );
      case PresenceBlockReason.bluetoothOff:
        return _body(
          context,
          icon: HugeIconsSolid.bluetooth,
          title: 'Bluetooth is off',
          message:
              'Turn on Bluetooth to check which participating store you are '
              'in. The marketplace works either way.',
        );
      case PresenceBlockReason.permissionDenied:
        return _body(
          context,
          icon: HugeIconsSolid.bluetooth,
          title: 'Bluetooth permission needed',
          message:
              'Nearby needs Bluetooth permission to check for stores. Nothing '
              'is scanned until you allow it.',
        );
      case PresenceBlockReason.permissionPermanentlyDenied:
        return _settingsBlocked(context);
      case PresenceBlockReason.unsupported:
        return _body(
          context,
          icon: HugeIconsSolid.location01,
          title: 'Nearby is not supported on this device',
          message:
              'This build cannot check for stores automatically. You can still '
              'browse the marketplace to find businesses.',
        );
      case PresenceBlockReason.offline:
        return _body(
          context,
          icon: HugeIconsSolid.location01,
          title: 'You are offline',
          message:
              'Checking for stores needs a connection. We will not guess at a '
              'store while offline.',
        );
      case PresenceBlockReason.throttled:
        return _body(
          context,
          icon: HugeIconsSolid.location01,
          title: 'Just a moment',
          message: 'We checked a few seconds ago. Try again shortly.',
        );
    }
  }

  /// Permanently denied: never a dead button. If a settings deep-link has been
  /// wired at bootstrap we use it; otherwise we state the dependency honestly.
  Widget _settingsBlocked(BuildContext context) {
    final openSettings = ref.read(presenceOpenSettingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _body(
          context,
          icon: HugeIconsSolid.bluetooth,
          title: 'Bluetooth is blocked',
          message:
              'Bluetooth permission was turned off for Azaman. You can '
              're-enable it in your device settings. Everything else keeps '
              'working.',
        ),
        if (openSettings != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton(
              onPressed: () => openSettings(),
              child: const Text('Open settings'),
            ),
          ),
      ],
    );
  }

  Widget _status(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );

  Widget _body(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: theme.colorScheme.primary),
          const SizedBox(height: 10),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
          ],
        ],
      ),
    );
  }

  Widget _privacyNote(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Nearby only checks while you have the app open and unlocked, and only '
      'when you ask. Signal strength tells us "very close", "nearby" or "in '
      'the area" — never an exact position.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Opens the storefront for a candidate, honouring the three documented modes
/// and validating the server's route hint before using it.
class _StorefrontAction extends StatelessWidget {
  const _StorefrontAction({required this.candidate, required this.controller});

  final PresenceCandidate candidate;
  final NearbyPresenceController controller;

  @override
  Widget build(BuildContext context) {
    switch (candidate.storefrontMode) {
      case StorefrontMode.listingOnly:
      case StorefrontMode.catalogueAndPayment:
        return FilledButton(
          onPressed: () {
            final route =
                safeStorefrontRoute(candidate.storefrontRoute) ??
                AzRoutes.businessProfile(candidate.businessId);
            controller.rememberChoice(candidate.locationId, chosen: true);
            context.push(route);
          },
          child: Text(
            candidate.storefrontMode == StorefrontMode.listingOnly
                ? 'View listing'
                : 'Open store',
          ),
        );
      case StorefrontMode.paymentOnly:
        // No branch-payment intent exists yet. Say so; do not invent a
        // payment screen with a made-up amount.
        return FilledButton.tonal(
          onPressed: null,
          child: const Text('In-store payment coming soon'),
        );
    }
  }
}
