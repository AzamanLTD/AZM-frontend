// =============================================================================
// AZAMAN — NEARBY SEARCH OUTCOME (Workstream E).
//
// The map's nearby search has THREE honest outcomes and each must render as
// itself, never as another:
//   • FAILURE  → "Couldn't load nearby businesses" + Retry
//   • EMPTY    → "No businesses nearby" (a legitimate zero-result success)
// A failed request was previously rendered as the EMPTY state — the user was
// told there were no businesses when the request had actually died. That
// conflation is retired here: the outcome is decided in ONE place, by the
// presence of [error], and the two texts can never swap.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/widgets/azaman_empty_state.dart';

class NearbyOutcome extends StatelessWidget {
  /// Non-null means the last nearby request FAILED. Null means the request
  /// succeeded (and the caller renders this widget only when the result list
  /// is empty).
  final String? error;

  /// Retry callback — only rendered (and only meaningful) on failure.
  final VoidCallback? onRetry;

  const NearbyOutcome({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return ListView(
        children: [
          const SizedBox(height: 60),
          AzamanEmptyState(
            key: const Key('nearby-outcome-failure'),
            icon: Icons.wifi_off_outlined,
            title: 'Couldn\'t load nearby businesses',
            subtitle: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: onRetry,
          ),
        ],
      );
    }
    return ListView(
      children: const [
        SizedBox(height: 60),
        AzamanEmptyState(
          key: Key('nearby-outcome-empty'),
          icon: Icons.location_off_outlined,
          title: 'No businesses nearby',
          subtitle: 'Try expanding your search area.',
        ),
      ],
    );
  }
}
