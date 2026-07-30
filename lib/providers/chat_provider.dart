// =============================================================================
// CHAT PROVIDER — Azaman Phase 11.0 (Consolidated)
//
// Canonical type exports for the chat system. The actual message state
// management lives in premium_chat_provider.dart (PremiumChatNotifier),
// which handles friend, group, trade, and ticket chat contexts.
//
// This file is kept for:
//   • Re-exporting ChatMessage, MessageKind, MessageStatus from models/
//   • Backward-compat type aliases (MessageType, DmMessageStatus)
//   • totalUnreadChatCountProvider (used by the bottom nav)
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Canonical message types — from models/chat_message.dart
// ─────────────────────────────────────────────────────────────────────────────
import 'package:azaman/models/chat_message.dart';
export 'package:azaman/models/chat_message.dart' show ChatMessage, MessageKind, MessageStatus;

// ─────────────────────────────────────────────────────────────────────────────
// Backward-compat aliases — the canonical ChatMessage lives in models/chat_message.dart.
// ─────────────────────────────────────────────────────────────────────────────
typedef MessageType = MessageKind;
typedef DmMessageStatus = MessageStatus;

// ─────────────────────────────────────────────────────────────────────────────
// Unread chat count — used by the bottom navigation bar badge.
// ─────────────────────────────────────────────────────────────────────────────
final totalUnreadChatCountProvider = FutureProvider<int>((ref) async {
  try {
    final resp = await apiClient.get("/friends");
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final friends = data["friends"] as List? ?? [];
      return friends.fold<int>(0, (sum, c) {
        return sum + ((c["unreadCount"] as num?)?.toInt() ?? 0);
      });
    }
    return 0;
  } catch (_) { return 0; }
});
