// lib/screens/presence/nearby_presence_screen.dart
// =============================================================================
// AZAMAN — NEARBY PRESENCE (Part 6.6 §G)
//
// One screen, driven by the controller's state. Every branch is an honest
// rendering of what the device actually knows — there is no skeleton that
// implies a result, no spinner over the whole surface, and no branch that
// claims a distance or floor from RSSI.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/nearby_presence_controller.dart';
import 'package:azaman/router/route_registry.dart';
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
    // An explicit arrival IS the user action that permits a scan.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(nearbyPresenceControllerProvider.notifier).requestScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nearbyPresenceControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby')),
      body: SafeArea(child: _body(context, state)),
    );
  }

  Widget _body(BuildContext context, NearbyPresenceState state) {
    return switch (state) {
      PresenceIdle() || PresenceCheckingPrereqs() => const _Quiet(),
      PresenceScanning() => const _Quiet(label: 'Looking around you…'),
      PresenceResolving() => const _Quiet(label: 'Checking nearby stores…'),

      PresenceFoundOne(:final candidate) => _FoundOne(candidate: candidate),

      PresenceFoundMany(:final candidates) => _FoundMany(
        candidates: candidates,
      ),

      // No unsolicited empty prompt: this screen was opened deliberately, so
      // the message is legitimate here.
      PresenceNone() => _Message(
        title: 'No stores found nearby',
        body: 'Move closer to a participating store and try again.',
        action: FilledButton.tonal(
          onPressed: () =>
              ref.read(nearbyPresenceControllerProvider.notifier).requestScan(),
          child: const Text('Check again'),
        ),
      ),

      PresenceBlocked(:final reason) => _Blocked(reason: reason),

      PresenceError() => _Message(
        title: 'Could not check nearby stores',
        body: 'Nothing changed on your account. Try again in a moment.',
        action: FilledButton.tonal(
          onPressed: () =>
              ref.read(nearbyPresenceControllerProvider.notifier).requestScan(),
          child: const Text('Try again'),
        ),
      ),
    };
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet({this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    // Deliberately NOT a blocking spinner over the surface.
    return Center(
      child: Text(
        label ?? '',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body, this.action});
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class _Blocked extends ConsumerWidget {
  const _Blocked({required this.reason});
  final PresenceBlockReason reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (reason) {
      case PresenceBlockReason.permissionPermanentlyDenied:
        // Non-blocking, with a settings affordance.
        return _Message(
          title: 'Nearby is blocked in settings',
          body:
              'You can turn it back on in your device settings. '
              'The marketplace works exactly as before.',
          action: Consumer(
            builder: (context, ref, _) {
              final open = ref.watch(presenceOpenSettingsProvider);
              if (open == null) return const SizedBox.shrink();
              return TextButton(
                onPressed: open,
                child: const Text('Open settings'),
              );
            },
          ),
        );

      case PresenceBlockReason.permissionDenied:
        return _Message(
          title: 'Nearby needs Bluetooth permission',
          body:
              'Azaman only uses Bluetooth to notice a participating store '
              'when you choose to check. Nothing runs in the background.',
          action: FilledButton.tonal(
            onPressed: () => ref
                .read(nearbyPresenceControllerProvider.notifier)
                .requestScan(),
            child: const Text('Allow and check'),
          ),
        );

      case PresenceBlockReason.bluetoothOff:
        return const _Message(
          title: 'Bluetooth is off',
          body:
              'Turn Bluetooth on to find stores near you. '
              'You can still browse the marketplace.',
        );

      case PresenceBlockReason.unsupported:
        return _Message(
          title: 'Nearby is not available on this device',
          body: 'Manual browsing in the marketplace is unaffected.',
          action: TextButton(
            onPressed: () => context.push(AzRoutes.marketplace),
            child: const Text('Browse the marketplace'),
          ),
        );

      case PresenceBlockReason.offline:
        return const _Message(
          title: 'You are offline',
          body: 'Nearby needs a connection to confirm which store you are at.',
        );

      case PresenceBlockReason.preferenceOff:
      case PresenceBlockReason.featureFlagOff:
      case PresenceBlockReason.appLocked:
      case PresenceBlockReason.throttled:
        return const _Quiet();
    }
  }
}

class _FoundOne extends ConsumerWidget {
  const _FoundOne({required this.candidate});
  final PresenceCandidate candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BranchTile(candidate: candidate, dense: true),
            const SizedBox(height: 12),
            Text(
              'You are at ${candidate.merchantName}.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.push(
                AzRoutes.storefront(
                  candidate.branchId,
                  name: candidate.merchantName,
                ),
              ),
              child: const Text('Open store'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                ref
                    .read(nearbyPresenceControllerProvider.notifier)
                    .rememberChoice(candidate.branchId, chosen: false);
                context.pop();
              },
              child: const Text('Not here?'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoundMany extends ConsumerWidget {
  const _FoundMany({required this.candidates});
  final List<PresenceCandidate> candidates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Choose the store you are visiting',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'More than one participating store is close by.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final c in candidates)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => context.push(
                AzRoutes.storefront(c.branchId, name: c.merchantName),
              ),
              child: _BranchTile(candidate: c),
            ),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            for (final c in candidates) {
              ref
                  .read(nearbyPresenceControllerProvider.notifier)
                  .rememberChoice(c.branchId, chosen: false);
            }
            context.pop();
          },
          child: const Text('Not here?'),
        ),
      ],
    );
  }
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({required this.candidate, this.dense = false});
  final PresenceCandidate candidate;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Missing logos are a real case: fall back to an initial, never a
          // broken image.
          CircleAvatar(
            radius: dense ? 20 : 22,
            child: Text(_initial(candidate.merchantName)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.merchantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (candidate.branchName.isNotEmpty)
                  Text(
                    candidate.branchName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Text(
                  candidate.proximity.label, // strong / near / far ONLY
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (candidate.verified)
            Icon(Icons.verified, size: 18, color: scheme.primary),
        ],
      ),
    );
  }

  static String _initial(String name) {
    final t = name.trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }
}
