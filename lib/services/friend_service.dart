// =============================================================================
// AZAMAN V3 — FRIEND SERVICE
//
// Wraps all /api/friends endpoints using centralized ApiClient.
// Phase: Batch ApiClient sweep — migrated from raw http package.
// =============================================================================

import 'dart:convert';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/idempotency_key.dart';

class FriendService {
  static final FriendService _instance = FriendService._internal();
  factory FriendService() => _instance;
  FriendService._internal();

  // ===========================================================================
  // USER DISCOVERY
  // ===========================================================================

  /// Search users by username or user ID
  Future<List<Map<String, dynamic>>> searchUsers(
      String query, String token) async {
    final response = await apiClient.get('/friends/search?q=$query');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['users'] ?? []);
    }
    throw Exception('Failed to search users: ${response.body}');
  }

  // ===========================================================================
  // FRIEND REQUESTS
  // ===========================================================================

  /// Send a friend request to another user
  Future<Map<String, dynamic>> sendFriendRequest(
      int addresseeId, String message, String token) async {
    final response = await apiClient.post('/friends/request', {
      'addresseeId': addresseeId,
      'message': message,
    });

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to send friend request: ${response.body}');
  }

  /// Get pending incoming friend requests
  Future<List<Map<String, dynamic>>> getPendingRequests(String token) async {
    final response = await apiClient.get('/friends/requests');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['requests'] ?? []);
    }
    throw Exception('Failed to get pending requests: ${response.body}');
  }

  /// Accept a friend request
  Future<Map<String, dynamic>> acceptFriendRequest(
      String id, String token) async {
    final response = await apiClient.put('/friends/request/$id/accept', {});

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to accept friend request: ${response.body}');
  }

  /// Reject a friend request
  Future<Map<String, dynamic>> rejectFriendRequest(
      String id, String token) async {
    final response = await apiClient.put('/friends/request/$id/reject', {});

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to reject friend request: ${response.body}');
  }

  // ===========================================================================
  // FRIENDS LIST
  // ===========================================================================

  /// Get all friends with chat preview info
  Future<List<Map<String, dynamic>>> getFriends(String token) async {
    final response = await apiClient.get('/friends');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['friends'] ?? []);
    }
    throw Exception('Failed to get friends: ${response.body}');
  }

  /// Remove a friend
  Future<bool> removeFriend(String id, String token) async {
    final response = await apiClient.delete('/friends/$id');
    return response.statusCode == 200;
  }

  // ===========================================================================
  // DIRECT MESSAGING
  // ===========================================================================

  /// Get messages for a friendship conversation
  Future<Map<String, dynamic>> getMessages(
      String friendshipId, String token,
      {int page = 1}) async {
    final response = await apiClient.get(
        '/friends/chat/$friendshipId/messages?page=$page');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to get messages: ${response.body}');
  }

  /// Send a message in a friendship conversation. Phase UI-3 added the
  /// optional media kwargs (`messageType`, `mediaUrl`, etc.) so callers
  /// can post IMAGE / VIDEO / AUDIO / DOCUMENT / LINK rows; the BE
  /// validates them in `directMessageController.sendMessage`.
  Future<Map<String, dynamic>> sendMessage(
    String friendshipId,
    String content,
    String token, {
    String? messageType,
    Map<String, dynamic>? metadata,
    String? mediaUrl,
    String? mediaType,
    String? mediaMimeType,
    int? mediaSize,
    int? mediaDuration,
    List<int>? mediaWaveformPeaks,
    Map<String, dynamic>? linkPreview,
  }) async {
    final body = <String, dynamic>{
      'content': content,
      if (messageType != null) 'messageType': messageType,
      if (metadata != null) 'metadata': metadata,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaType != null) 'mediaType': mediaType,
      if (mediaMimeType != null) 'mediaMimeType': mediaMimeType,
      if (mediaSize != null) 'mediaSize': mediaSize,
      if (mediaDuration != null) 'mediaDuration': mediaDuration,
      if (mediaWaveformPeaks != null)
        'mediaWaveformPeaks': mediaWaveformPeaks,
      if (linkPreview != null) 'linkPreview': linkPreview,
    };
    final response = await apiClient.post(
      '/friends/chat/$friendshipId/messages',
      body,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to send message: ${response.body}');
  }

  /// Mark all messages as read in a conversation
  Future<void> markAsRead(String friendshipId, String token) async {
    await apiClient.put('/friends/chat/$friendshipId/read', {});
  }

  /// Get total unread message count across all conversations
  Future<int> getUnreadCount(String token) async {
    final response = await apiClient.get('/friends/chat/unread-count');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['unreadCount'] ?? 0;
    }
    return 0;
  }

  // ===========================================================================
  // PEER TRANSFERS
  // ===========================================================================

  /// Send funds to a friend.
  ///
  /// Phase H6 BUGFIX (2026-05-27): the BE `peerTransferController.sendFunds`
  /// supports an optional `clientRequestId` (or `X-Idempotency-Key`
  /// header) for retry safety — it's used to derive the unique
  /// `TransactionHistory.txHash` so a flaky-network retry hits the BE's
  /// `@unique` constraint and returns the original outcome instead of
  /// double-charging the sender. The FE was never sending one, so any
  /// retry on a transient error WAS a fresh debit. We now generate a
  /// random v4-style id per call and ship it in the body.
  ///
  /// Phase H12: helper extracted into `lib/utils/idempotency_key.dart`
  /// so other money-moving endpoints (savings deposit, etc.) can share
  /// the same generator.
  Future<Map<String, dynamic>> sendFunds(
      String friendshipId, double amount, String? reference, String token) async {
    final response = await apiClient.post('/friends/transfer/send', {
      'friendshipId': friendshipId,
      'amount': amount,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
      'clientRequestId': IdempotencyKey.generate(),
    });

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to send funds: ${response.body}');
  }

  /// Request funds from a friend. Same idempotency rationale as
  /// [sendFunds] — a request retry should be a no-op rather than a
  /// duplicate ask.
  Future<Map<String, dynamic>> requestFunds(
      String friendshipId, double amount, String? reference, String token) async {
    final response = await apiClient.post('/friends/transfer/request', {
      'friendshipId': friendshipId,
      'amount': amount,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
      'clientRequestId': IdempotencyKey.generate(),
    });

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to request funds: ${response.body}');
  }

  /// Fulfill a pending transfer request (pay it)
  Future<Map<String, dynamic>> fulfillTransfer(
      String transferId, String token) async {
    final response = await apiClient.put('/friends/transfer/$transferId/fulfill', {});

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to fulfill transfer: ${response.body}');
  }

  /// Decline a pending transfer request
  Future<Map<String, dynamic>> declineTransfer(
      String transferId, String token) async {
    final response = await apiClient.put('/friends/transfer/$transferId/decline', {});

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to decline transfer: ${response.body}');
  }

  /// Get details of a specific transfer
  Future<Map<String, dynamic>> getTransferDetails(
      String transferId, String token) async {
    final response = await apiClient.get('/friends/transfer/$transferId');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to get transfer details: ${response.body}');
  }

  /// Get all pending transfer requests (incoming)
  Future<Map<String, dynamic>> getPendingTransferRequests(String token) async {
    final response = await apiClient.get('/friends/transfer/pending');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to get pending transfers: ${response.body}');
  }
}
