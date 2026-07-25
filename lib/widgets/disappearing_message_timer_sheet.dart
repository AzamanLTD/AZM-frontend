// lib/widgets/disappearing_message_timer_sheet.dart
// AZAMAN PREMIUM — Disappearing Message Timer Bottom Sheet
//
// Presented from the chat app bar's timer icon.
// Lets the user pick a TTL for messages in the current conversation.
// The selection is stored in PremiumChatState.disappearAfterSeconds and
// every new outgoing message includes it in the socket payload.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/premium_chat_provider.dart';

/// Pre-defined timer options (seconds, label, icon)
const List<({int seconds, String label, IconData icon})> _kDisappearOptions = [
  (seconds: 0,       label: 'Off',           icon: Icons.timer_off_outlined),
  (seconds: 30,      label: '30 seconds',    icon: Icons.timer_outlined),
  (seconds: 60,      label: '1 minute',      icon: Icons.timer_outlined),
  (seconds: 300,     label: '5 minutes',    icon: Icons.timer_outlined),
  (seconds: 3600,    label: '1 hour',        icon: Icons.hourglass_top_outlined),
  (seconds: 86400,   label: '24 hours',      icon: Icons.today_outlined),
  (seconds: 604800,  label: '7 days',        icon: Icons.date_range_outlined),
];

/// Show the disappearing message timer sheet.
/// Pass the active [ChatContextParams] so the sheet reads/writes the right
/// provider instance.
void showDisappearTimerSheet(BuildContext context, ChatContextParams params) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => Consumer(
      builder: (ctx, ref, _) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final currentTimer = ref.watch(premiumChatProvider(params)).disappearAfterSeconds;

        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(top: 12, bottom: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.outline.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title row
              Padding(
                padding: const EdgeInsets.only(left: 24, right: 24, bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 22, color: cs.primary),
                    const SizedBox(width: 8),
                    Text('Disappearing Messages',
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              // Description
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: Text(
                  'New messages sent in this chat will disappear after the '
                  'selected time. The timer starts when the message is sent.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant),
                ),
              ),
              const Divider(height: 24),
              // Options
              ..._kDisappearOptions.map((opt) {
                final isSelected = (currentTimer ?? 0) == opt.seconds;
                return ListTile(
                  leading: Icon(opt.icon,
                      size: 22,
                      color: isSelected ? cs.primary : cs.onSurfaceVariant),
                  title: Text(opt.label),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, size: 22, color: cs.primary)
                      : null,
                  onTap: () {
                    ref.read(premiumChatProvider(params).notifier)
                        .setDisappearTimer(opt.seconds == 0 ? null : opt.seconds);
                    Navigator.of(ctx).pop();
                  },
                );
              }),
            ],
          ),
        );
      },
    ),
  );
}
