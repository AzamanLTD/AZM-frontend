/// One inbox row (Overhaul 04 §3.6).
///
/// Unread hierarchy = weight + colour only. Transaction context = one 14dp
/// glyph. No ticks, no "You:" prefix — money direction carries that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/experience/motion/az_identity_morph.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/chat_avatar.dart';
import 'package:azaman/widgets/chat_unread_badge.dart';
import 'package:azaman/widgets/inbox/group_identity_avatar.dart';
import 'package:azaman/widgets/inbox/inbox_entry.dart';

class InboxRow extends ConsumerWidget {
  final InboxEntry entry;
  final VoidCallback onTap;

  /// Row actions (07 §5). Null = no long-press affordance yet.
  final VoidCallback? onLongPress;

  /// Injected clock for deterministic relative times in tests.
  final DateTime? now;

  const InboxRow({super.key, required this.entry, required this.onTap, this.onLongPress, this.now});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final strong = entry.hasUnread;
    final time = InboxEntry.relativeTime(entry.lastAt, now: now);
    final travel = AzMotion.of(context).travel;

    final Widget avatar = switch (entry.kind) {
      InboxKind.group => AzIdentityMorph(
          tag: AzIdentityTag.group(entry.id),
          travel: travel,
          child: GroupIdentityAvatar(group: entry.group!, colors: colors, size: 48),
        ),
      InboxKind.friend => ChatAvatar(
          imageUrl: entry.avatarUrl,
          name: entry.title,
          size: 48,
          showOnlineDot: true,
          isOnline: entry.isOnline,
          // FriendChatScreen already uses this tag for its header avatar.
          heroTag: entry.friendId != null ? 'avatar-${entry.friendId}' : null,
        ),
    };

    return Semantics(
      label: '${entry.title}. ${strong ? '${entry.unread} unread. ' : ''}${entry.preview}',
      child: InkWell(
        key: ValueKey('inbox_row_${entry.kind.name}_${entry.id}'),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg, vertical: AzSpace.md),
          child: Row(
            children: [
              avatar,
              const SizedBox(width: AzSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (entry.pinned)
                          Padding(
                            padding: const EdgeInsets.only(right: AzSpace.xs),
                            child: Icon(Icons.push_pin_rounded, size: 12, color: colors.textTertiary),
                          ),
                        Expanded(
                          child: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (strong ? AzText.title : AzText.body).copyWith(color: colors.textPrimary),
                          ),
                        ),
                        if (entry.isVerifiedVendor)
                          Padding(
                            padding: const EdgeInsets.only(left: AzSpace.xs),
                            child: Icon(HugeIconsSolid.checkmarkBadge01, size: 14, color: colors.accent),
                          ),
                        const SizedBox(width: AzSpace.sm),
                        Text(
                          time,
                          style: AzText.caption.copyWith(color: strong ? colors.accent : colors.textTertiary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _SignalGlyph(signal: entry.signal, colors: colors),
                        if (entry.mentioned)
                          Padding(
                            padding: const EdgeInsets.only(right: AzSpace.xs),
                            child: Text(
                              '@',
                              key: const ValueKey('inbox_row_mention'),
                              style: AzText.caption.copyWith(color: colors.accent, fontWeight: FontWeight.w800),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            entry.preview.isEmpty ? 'Start chatting...' : entry.preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AzText.bodyS.copyWith(
                              color: strong ? colors.textPrimary : colors.textSecondary,
                            ),
                          ),
                        ),
                        if (entry.muted)
                          Padding(
                            padding: const EdgeInsets.only(left: AzSpace.xs),
                            child: Icon(Icons.notifications_off_outlined, size: 14, color: colors.textTertiary),
                          ),
                        if (strong) ...[
                          const SizedBox(width: AzSpace.sm),
                          ChatUnreadBadge(count: entry.unread, fontSize: 10),
                        ],
                      ],
                    ),
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

class _SignalGlyph extends StatelessWidget {
  final InboxSignal signal;
  final AzamanColors colors;

  const _SignalGlyph({required this.signal, required this.colors});

  @override
  Widget build(BuildContext context) {
    final (IconData? icon, Color? color) = switch (signal) {
      InboxSignal.moneyIn => (Icons.south_west_rounded, colors.success),
      InboxSignal.moneyOut => (Icons.north_east_rounded, colors.textSecondary),
      InboxSignal.request => (Icons.request_quote_outlined, colors.accent),
      InboxSignal.susuActive => (HugeIconsSolid.coins01, colors.accent),
      InboxSignal.susuConfiguring => (HugeIconsSolid.coins01, colors.textTertiary),
      InboxSignal.none => (null, null),
    };
    if (icon == null) return const SizedBox.shrink();
    return Padding(
      key: ValueKey('inbox_signal_${signal.name}'),
      padding: const EdgeInsets.only(right: AzSpace.xs),
      child: Icon(icon, size: 14, color: color),
    );
  }
}