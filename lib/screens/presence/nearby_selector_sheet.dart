// lib/screens/presence/nearby_selector_sheet.dart
// =============================================================================
// AZAMAN — MULTI-STORE SELECTOR (Part 6.6 §G: "Selection bottom sheet")
//
// When more than one eligible branch is detected, the customer chooses the
// store they are actually standing in. This is a MODAL BOTTOM SHEET over
// Home, not a full-screen route, because the customer must never lose their
// place for what is a small disambiguation.
//
// Contract:
//   • Only what the SERVER supplied is rendered (business, branch, logo,
//     proximityHint, floor, zone). No distance, no floor estimate, no
//     verification badge the backend did not send.
//   • The customer must explicitly choose. Nothing here auto-navigates.
//   • Dismissal and choice are both remembered for the session.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/services/presence/presence_gateway.dart';

/// Opens the selector. Returns the chosen candidate, or null when the
/// customer dismissed the sheet.
Future<PresenceCandidate?> showNearbySelectorSheet(
  BuildContext context, {
  required List<PresenceCandidate> candidates,
}) {
  if (candidates.isEmpty) return Future<PresenceCandidate?>.value();
  return showModalBottomSheet<PresenceCandidate>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => _NearbySelectorBody(candidates: candidates),
  );
}

class _NearbySelectorBody extends StatelessWidget {
  const _NearbySelectorBody({required this.candidates});

  final List<PresenceCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Which store are you in?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${candidates.length} stores nearby. Pick the one you are '
                  'visiting — nothing opens until you choose.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: candidates.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) => _CandidateTile(
                candidate: candidates[i],
                onTap: () => Navigator.of(context).pop(candidates[i]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Not here'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate, required this.onTap});

  final PresenceCandidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = <String>[
      if (candidate.branchName.isNotEmpty) candidate.branchName,
      if (candidate.floor != null && candidate.floor!.isNotEmpty)
        'Floor ${candidate.floor}',
      if (candidate.zone != null && candidate.zone!.isNotEmpty) candidate.zone!,
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        backgroundImage:
            (candidate.logoUrl != null && candidate.logoUrl!.isNotEmpty)
            ? NetworkImage(candidate.logoUrl!)
            : null,
        child: (candidate.logoUrl == null || candidate.logoUrl!.isEmpty)
            ? Text(
                _initials(candidate.businessName),
                style: theme.textTheme.labelMedium,
              )
            : null,
      ),
      title: Text(
        candidate.businessName.isEmpty
            ? candidate.branchName
            : candidate.businessName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: detail.isEmpty
          ? null
          : Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
      // Only a server-supplied hint. Never a computed distance or floor.
      trailing: candidate.proximityHint == null
          ? null
          : Text(
              candidate.proximityHint!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}
