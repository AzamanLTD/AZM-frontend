// lib/screens/presence/nearby_preferences_screen.dart
// =============================================================================
// AZAMAN — NEARBY PREFERENCES (Part 6.6 §E)
//
// Three switches, each independent, each defaulting OFF. Turning one on never
// turns another on. No permission is requested here: the copy explains what
// each does and the scan action stays explicit.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/presence_preferences_provider.dart';

class NearbyPreferencesScreen extends ConsumerWidget {
  const NearbyPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(presencePreferencesProvider);
    final notifier = ref.read(presencePreferencesProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby')),
      body: ListView(
        children: [
          SwitchListTile(
            value: prefs.nearbyDiscovery,
            onChanged: notifier.setNearbyDiscovery,
            title: const Text('Discover stores near me'),
            subtitle: const Text(
              'Notices a participating store when you choose to check. '
              'Off by default.',
            ),
          ),
          SwitchListTile(
            value: prefs.presenceNotifications,
            onChanged: notifier.setPresenceNotifications,
            title: const Text('Nearby notifications'),
            subtitle: const Text('Separate from discovery. Off by default.'),
          ),
          SwitchListTile(
            value: prefs.personalisation,
            onChanged: notifier.setPersonalisation,
            title: const Text('Personalise from visits'),
            subtitle: const Text(
              'Separate from the two above. Off by default.',
            ),
          ),
        ],
      ),
    );
  }
}
