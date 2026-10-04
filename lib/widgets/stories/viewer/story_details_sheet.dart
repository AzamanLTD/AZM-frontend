// =============================================================================
// AZAMAN — STORY VIEWER: DETAILS SHEET
//
// The swipe-up sheet (Overhaul 05 §6.3). Everything in it is capability-
// gated: a viewers roster requires `viewers` (no endpoint today) and the
// reaction grid requires `react` (no endpoint today), so with the REAL
// gateway the shell never even opens the sheet (see _ViewerShell
// _openDetails) — it stays a dormant, tested seam rather than a row of dead
// buttons. When the backend ships the endpoints, adding the capability to
// the gateway makes this sheet come alive with zero further changes.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/experience/gateways/az_gateway_result.dart';
import 'package:azaman/experience/gateways/story_gateway.dart';
import 'package:azaman/models/story_model.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';

class StoryDetailsSheet extends ConsumerWidget {
  const StoryDetailsSheet({
    super.key,
    required this.story,
    required this.authorId,
    required this.currentUserId,
  });

  final StoryItem story;
  final int authorId;
  final int currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(storyGatewayProvider).capabilities;
    final canViewers = capabilities.contains(StoryCapability.viewers);
    final canReact = capabilities.contains(StoryCapability.react);
    final isOwnStory = authorId == currentUserId;

    // Nothing offerable → the shell never opens the sheet; if it got here
    // anyway, the honest empty state beats fabricated rows.
    if (!canViewers && !canReact) {
      return Padding(
        padding: const EdgeInsets.all(AzSpace.xl),
        child: Text(
          'Story details aren\'t available yet.',
          style: AzText.body.copyWith(color: Colors.white70),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AzSpace.lg),
      children: [
        if (isOwnStory && canViewers) ...[
          const Text('Viewers'),
          const SizedBox(height: AzSpace.sm),
          const _CapabilityBoundary(
              reason: 'A viewers roster needs a per-story viewer-list endpoint, '
                  'which the backend does not expose yet'),
        ] else if (!isOwnStory && canReact) ...[
          const Text('Send a reaction'),
          const SizedBox(height: AzSpace.sm),
          Wrap(
            spacing: AzSpace.md,
            runSpacing: AzSpace.md,
            children: [
              for (final emoji in ['❤️', '🔥', '😂', '👏', '😮', '😢'])
                _ReactionChip(storyId: story.id, emoji: emoji),
            ],
          ),
        ],
      ],
    );
  }
}

class _ReactionChip extends ConsumerWidget {
  const _ReactionChip({required this.storyId, required this.emoji});
  final String storyId;
  final String emoji;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        final result = await ref.read(storyGatewayProvider).react(storyId, emoji);
        if (!context.mounted) return;
        // Only a server-confirmed result pops the sheet. Unsupported/failed
        // results surface the reason — never a fabricated success.
        if (result case AzOk<void>()) {
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.errorMessage ?? 'Reaction not sent'),
            duration: const Duration(seconds: 1),
          ));
        }
      },
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 28)),
      ),
    );
  }
}

class _CapabilityBoundary extends StatelessWidget {
  const _CapabilityBoundary({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AzSpace.md),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                size: 16, color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(width: AzSpace.sm),
            Expanded(
              child: Text(
                reason,
                style: AzText.bodyS
                    .copyWith(color: Colors.white.withValues(alpha: 0.5)),
              ),
            ),
          ],
        ),
      );
}
