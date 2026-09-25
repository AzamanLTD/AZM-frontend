// =============================================================================
// AZAMAN — Reply Preview Bar
//
// Shown above the chat composer when a reply-to is selected.
// Reference: WhatsApp reply preview bar (appears above input when replying).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/chat_message.dart';

// ── Reply Provider ───────────────────────────────────────────────────────────

/// The message currently being replied to (null = no reply in progress).
final replyTargetProvider = StateProvider<ChatMessage?>((ref) => null);

// ── Reply Preview Bar Widget ─────────────────────────────────────────────────

class ReplyPreviewBar extends ConsumerWidget {
  const ReplyPreviewBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replyTarget = ref.watch(replyTargetProvider);
    if (replyTarget == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isMe = replyTarget.isMe;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isMe ? 'You' : (replyTarget.senderUsername ?? 'Unknown'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    replyTarget.text.isNotEmpty
                        ? replyTarget.text
                        : '[Media]',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => ref.read(replyTargetProvider.notifier).state = null,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
