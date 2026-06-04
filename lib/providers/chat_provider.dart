// =============================================================================
// CHAT PROVIDER — Azaman Phase 3.3
//
// Riverpod-based state management for Transaction Chat & Direct Messaging.
// Manages message lists, countdown timers, and chat room state.
//
// Features:
//   • Message list state for active chat rooms
//   • Countdown timer state for transaction chats
//   • Send/receive message handlers
//   • Ripple extension (time request) logic
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Message Model
// ─────────────────────────────────────────────────────────────────────────────
class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final MessageType type;
  final bool isMe;

  // For transaction-specific messages
  final double? amount;
  final String? currency;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.timestamp,
    required this.type,
    required this.isMe,
    this.amount,
    this.currency,
  });

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? text,
    DateTime? timestamp,
    MessageType? type,
    bool? isMe,
    double? amount,
    String? currency,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      isMe: isMe ?? this.isMe,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
    );
  }
}

enum MessageType {
  text,
  system,
  transaction,
  timeRequest,
  timeApproved,
  timeRejected,
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction Chat State (with Countdown)
// ─────────────────────────────────────────────────────────────────────────────
class TransactionChatState {
  final String roomId;
  final List<ChatMessage> messages;
  final DateTime? expiryTime;
  final bool isActive;

  TransactionChatState({
    required this.roomId,
    this.messages = const [],
    this.expiryTime,
    this.isActive = true,
  });

  TransactionChatState copyWith({
    String? roomId,
    List<ChatMessage>? messages,
    DateTime? expiryTime,
    bool? isActive,
  }) {
    return TransactionChatState(
      roomId: roomId ?? this.roomId,
      messages: messages ?? this.messages,
      expiryTime: expiryTime ?? this.expiryTime,
      isActive: isActive ?? this.isActive,
    );
  }

  Duration get remainingTime {
    if (expiryTime == null) return Duration.zero;
    final diff = expiryTime!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  bool get isExpired => remainingTime.inSeconds <= 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction Chat Notifier
// ─────────────────────────────────────────────────────────────────────────────
class TransactionChatNotifier extends StateNotifier<TransactionChatState> {
  TransactionChatNotifier(String roomId, DateTime expiryTime)
      : super(TransactionChatState(
          roomId: roomId,
          expiryTime: expiryTime,
          messages: [],
        ));

  void addMessage(ChatMessage message) {
    state = state.copyWith(
      messages: [...state.messages, message],
    );
  }

  void extendTime(int minutes) {
    if (state.expiryTime == null) return;
    final newExpiry = state.expiryTime!.add(Duration(minutes: minutes));
    state = state.copyWith(expiryTime: newExpiry);

    // Add system message
    addMessage(ChatMessage(
      id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'system',
      text: 'Time extended by $minutes minutes',
      timestamp: DateTime.now(),
      type: MessageType.timeApproved,
      isMe: false,
    ));
  }

  void requestTimeExtension(int minutes) {
    addMessage(ChatMessage(
      id: 'req_${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'me',
      text: 'Requested +$minutes minutes',
      timestamp: DateTime.now(),
      type: MessageType.timeRequest,
      isMe: true,
    ));
  }

  void setExpired() {
    state = state.copyWith(isActive: false);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Direct Message Chat State
// ─────────────────────────────────────────────────────────────────────────────
class DirectChatState {
  final String chatId;
  final String contactId;
  final String contactName;
  final List<ChatMessage> messages;
  final bool isLoading;

  DirectChatState({
    required this.chatId,
    required this.contactId,
    required this.contactName,
    this.messages = const [],
    this.isLoading = false,
  });

  DirectChatState copyWith({
    String? chatId,
    String? contactId,
    String? contactName,
    List<ChatMessage>? messages,
    bool? isLoading,
  }) {
    return DirectChatState(
      chatId: chatId ?? this.chatId,
      contactId: contactId ?? this.contactId,
      contactName: contactName ?? this.contactName,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Direct Chat Notifier
// ─────────────────────────────────────────────────────────────────────────────
class DirectChatNotifier extends StateNotifier<DirectChatState> {
  DirectChatNotifier({
    required String chatId,
    required String contactId,
    required String contactName,
  }) : super(DirectChatState(
          chatId: chatId,
          contactId: contactId,
          contactName: contactName,
        ));

  void addMessage(ChatMessage message) {
    state = state.copyWith(
      messages: [...state.messages, message],
    );
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void updateMessages(List<ChatMessage> messages) {
    state = state.copyWith(messages: messages);
  }

  // Simulate sending a crypto transaction message
  void sendCryptoTransfer(double amount, String currency) {
    addMessage(ChatMessage(
      id: 'crypto_${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'me',
      text: 'Sent $amount $currency',
      timestamp: DateTime.now(),
      type: MessageType.transaction,
      isMe: true,
      amount: amount,
      currency: currency,
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Riverpod Providers
// ─────────────────────────────────────────────────────────────────────────────

// Transaction chat provider (family for multiple rooms)
final transactionChatProvider =
    StateNotifierProvider.family<TransactionChatNotifier, TransactionChatState, String>(
  (ref, roomId) {
    // Default expiry: 15 minutes from now
    final expiryTime = DateTime.now().add(const Duration(minutes: 15));
    return TransactionChatNotifier(roomId, expiryTime);
  },
);

// Direct message chat provider (family for multiple chats)
final directChatProvider =
    StateNotifierProvider.family<DirectChatNotifier, DirectChatState, Map<String, String>>(
  (ref, params) {
    return DirectChatNotifier(
      chatId: params['chatId']!,
      contactId: params['contactId']!,
      contactName: params['contactName']!,
    );
  },
);
