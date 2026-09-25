// =============================================================================
// MESSAGE STATUS TICKS — Phase 11.1
//
// Animated read receipt transitions: clock → single tick → double grey → blue.
// Uses AnimatedSwitcher for 150ms cross-fade between states.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:azaman/models/chat_message.dart';

class MessageStatusTicks extends StatelessWidget {
  final MessageStatus status;
  final bool isOutgoing;
  final Color? accentColor;

  const MessageStatusTicks({
    super.key,
    required this.status,
    this.isOutgoing = true,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      MessageStatus.sending => (Icons.access_time_rounded, Colors.white38),
      MessageStatus.sent => (Icons.done_rounded, Colors.white54),
      MessageStatus.delivered => (Icons.done_all_rounded, Colors.white54),
      MessageStatus.read => (Icons.done_all_rounded, accentColor ?? const Color(0xFF4FC3F7)),
      _ => (Icons.done_rounded, Colors.white38),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: Icon(icon, key: ValueKey('$status'), size: 15, color: color),
    );
  }
}
