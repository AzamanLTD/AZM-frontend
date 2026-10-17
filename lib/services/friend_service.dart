// =============================================================================
// AZAMAN V3 — FRIEND SERVICE
//
// Wraps all /api/friends endpoints using centralized ApiClient.
// Phase: Batch ApiClient sweep — migrated from raw http package.
// =============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

/// r43 — typed failure of GET /users/lookup/:azamanId. Carries the backend
/// errorCode (AZAMAN_ID_INVALID | USER_NOT_FOUND | AZAMAN_ID_SELF | ...)
/// so the Send flow can fail closed with the truthful reason instead of a
/// generic 'User not found' for every failure.
class LookupFailure implements Exception {
  final int statusCode;
  final String errorCode;
  final String message;
  const LookupFailure({
    required this.statusCode,
    required this.errorCode,
    required this.message,
  });
  @override
  String toString() => 'LookupFailure($statusCode $errorCode): $message';
}

class FriendService {
  static final FriendService _instance = FriendService._internal();
  factory FriendService() => _instance;

  // r42 key lifecycle: per-friend transfer keys, held on this singleton so
  // a re-tap after a lost response reuses the SAME key (the server may
  // already have committed the debit). Retired on any answered non-409
  // outcome; a genuinely new transfer then mints a fresh key.
  // r42 durable identities: one per (action, friendship), drawn from the
  // durable registry — the SAME key survives service/app recreation, so a
  // retry of an unfinished transfer converges on the server-side operation
  // instead of executing twice. postFinancial owns the sendFunds lifecycle.
  // r42 OPERATION-INSTANCE MODEL: the action ids name the operation TYPES
  // (per-friendship recovery namespaces). Each genuinely new transfer gets
  // a fresh durable INSTANCE; the per-flow refs are the retry handles — a
  // re-call after a lost response RETRIES THE SAME INSTANCE (same key),
  // and transfers to different friends stay independent.
  String _sendAction(String friendshipId) => 'friend.transfer.send.$friendshipId';
  String _requestAction(String friendshipId) => 'friend.transfer.request.$friendshipId';
  final Map<String, FinancialOperationRef> _flowRefs = {};
  FriendService._internal();

  /// Test seam (same pattern as ApiClient.operationAccountOverride): when
  /// set, every FriendService HTTP call goes through this client instead of
  /// the global [apiClient] singleton. Production code never touches it —
  /// it exists so widget/integration tests can pin the REAL routes this
  /// service calls without monkey-patching the singleton.
  @visibleForTesting
  static ApiClient? testClientOverride;

  ApiClient get _api => testClientOverride ?? apiClient;

  // ===========================================================================
  // USER DISCOVERY
  // ===========================================================================

  /// Search users by username or user ID.
  /// r43: the query is percent-encoded — usernames may contain characters
  /// that would otherwise corrupt the query string.
  Future<List<Map<String, dynamic>>> searchUsers(
      String query, String token) async {
    final response =
        await _api.get('/friends/search?q=${Uri.encodeQueryComponent(query)}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['users'] ?? []);
    }
    throw Exception('Failed to search users: ${response.body}');
  }

  /// r43 — resolve an Azaman ID through the canonical identity rail
  /// (GET /api/users/lookup/:azamanId). Returns the public profile
  /// { azamanId, displayName, avatar, friendship: {friendshipId, status} | null }.
  ///
  /// The friendship field is the CALLER's own row — the Send flow routes to
  /// the canonical friendship-scoped transfer rail (sendFunds) when it is
  /// ACCEPTED, and fails closed with a truthful reason otherwise. Never
  /// invented, never fabricated — an unresolvable ID is an error, not a
  /// 'found' user.
  Future<Map<String, dynamic>> lookupByAzamanId(String azamanId) async {
    final encoded = Uri.encodeComponent(azamanId.trim());
    final response = await _api.get('/users/lookup/$encoded');

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    final body = decoded is Map<String, dynamic> ? decoded : null;

    if (response.statusCode == 200) {
      final user = body?['data']?['user'];
      if (user is Map<String, dynamic>) return user;
      throw const FormatException('Malformed lookup response.');
    }
    final code = body?['errorCode']?.toString() ?? '';
    final message = body?['message']?.toString();
    throw LookupFailure(
      statusCode: response.statusCode,
      errorCode: code.isNotEmpty ? code : 'LOOKUP_HTTP_${response.statusCode}',
      message: message ?? 'Lookup failed.',
    );
  }

  /// r43 — page through the caller's accepted friendships until the row for
  /// [userId] is found, then return that friendship row (the shape
  /// getFriends returns: { friendshipId, friend: {...}, ... }). Null when the
  /// bound is exhausted — callers must FAIL CLOSED on null, never guess.
  Future<Map<String, dynamic>?> findFriendshipByUserId(
      int userId, String token) async {
    // Provider-cache-first is the caller's job; this is the authoritative
    // fallback when the cache page missed. Bounded: 10 pages x 100 rows.
    String? cursor;
    for (var page = 0; page < 10; page += 1) {
      final endpoint = cursor == null
          ? '/friends?limit=100'
          : '/friends?limit=100&cursor=${Uri.encodeQueryComponent(cursor)}';
      final response = await _api.get(endpoint);
      if (response.statusCode != 200) {
        // Read error => cannot prove friendship => fail closed (null).
        return null;
      }
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        return null;
      }
      final body = decoded is Map<String, dynamic> ? decoded : null;
      final rows = body?['friends'];
      final friends = rows is List
          ? rows.whereType<Map<String, dynamic>>().toList()
          : const <Map<String, dynamic>>[];
      for (final row in friends) {
        final friend = row['friend'];
        final id = friend is Map<String, dynamic> ? friend['id'] : null;
        if (id is int && id == userId) return row;
        final parsed = int.tryParse('$id');
        if (parsed == userId) return row;
      }
      final hasMore = body?['hasMore'] == true;
      final next = body?['nextCursor']?.toString();
      if (!hasMore || next == null || next.isEmpty) return null;
      cursor = next;
    }
    return null;
  }

  // ===========================================================================
  // FRIEND REQUESTS
  // ===========================================================================

  /// Send a friend request to another user
  Future<Map<String, dynamic>> sendFriendRequest(
      int addresseeId, String message, String token) async {
    final response = await _api.post('/friends/request', {
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
    final response = await _api.get('/friends/requests');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['requests'] ?? []);
    }
    throw Exception('Failed to get pending requests: ${response.body}');
  }

  /// Accept a friend request
  Future<Map<String, dynamic>> acceptFriendRequest(
      String id, String token) async {
    final response = await _api.put('/friends/request/$id/accept', {});

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to accept friend request: ${response.body}');
  }

  /// Reject a friend request
  Future<Map<String, dynamic>> rejectFriendRequest(
      String id, String token) async {
    final response = await _api.put('/friends/request/$id/reject', {});

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
    final response = await _api.get('/friends');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['friends'] ?? []);
    }
    throw Exception('Failed to get friends: ${response.body}');
  }

  /// Remove a friend
  Future<bool> removeFriend(String id, String token) async {
    final response = await _api.delete('/friends/$id');
    return response.statusCode == 200;
  }

  // ===========================================================================
  // DIRECT MESSAGING
  // ===========================================================================

  /// Get messages for a friendship conversation
  Future<Map<String, dynamic>> getMessages(
      String friendshipId, String token,
      {int page = 1}) async {
    final response = await _api.get(
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
    final response = await _api.post(
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
    await _api.put('/friends/chat/$friendshipId/read', {});
  }

  /// Get total unread message count across all conversations
  Future<int> getUnreadCount(String token) async {
    final response = await _api.get('/friends/chat/unread-count');

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
    // r42: one logical transfer, one DURABLE identity — postFinancial arms
    // the registry key (surviving app restart) and overwrites the legacy
    // Phase H12 clientRequestId with it, so the header and the body carry
    // the same identity and the backend's legacy txHash derivation stays
    // consistent. Lifecycle (retire on answered outcomes, retain on 409 /
    // network loss) is owned by the helper.
    final response = await _api.postFinancial('/friends/transfer/send', {
      'friendshipId': friendshipId,
      'amount': amount,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
      'clientRequestId': '', // auto-filled from the durable registry
    }, operationType: _sendAction(friendshipId),
        ref: _flowRefs.putIfAbsent(
            'send.$friendshipId', () => FinancialOperationRef()));

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
    // Not an r42-mounted route (plain POST), but the same duplicate-protection
    // rationale: one durable identity per logical ask, so a retry of an
    // unfinished ask is the same ask. Retired on any ANSWERED outcome.
    // Same instance-resolution policy as postFinancial (the flow ref's
    // unfinished instance is retried with the SAME key when the ask is
    // unchanged; a materially different ask begins a genuinely new
    // instance and the old record stays recoverable).
    final requestRef = _flowRefs.putIfAbsent(
        'request.$friendshipId', () => FinancialOperationRef());
    final account = await _api.operationAccount(failClosed: true);
    DurableOperation op;
    final retryId = requestRef.operationId;
    if (retryId != null) {
      try {
        op = await DurableOperationRegistry.retry(retryId, account: account,
            request: {
              'friendshipId': friendshipId,
              'amount': amount,
              if (reference != null && reference.isNotEmpty) 'reference': reference,
              // close-out review 2, finding 3: the wire request carries
              // clientRequestId (= the durable key). The stored snapshot
              // carries the SAME FIELD as a placeholder so a recovered
              // replay is byte-identical to the original wire request;
              // the exact-only path rewrites it to the instance's key.
              'clientRequestId': '',
            });
      } on DurableOperationException {
        op = await DurableOperationRegistry.begin(
            account: account,
            type: _requestAction(friendshipId),
            endpoint: '/friends/transfer/request',
            request: {
              'friendshipId': friendshipId,
              'amount': amount,
              if (reference != null && reference.isNotEmpty) 'reference': reference,
              // close-out review 2, finding 3: the wire request carries
              // clientRequestId (= the durable key). The stored snapshot
              // carries the SAME FIELD as a placeholder so a recovered
              // replay is byte-identical to the original wire request;
              // the exact-only path rewrites it to the instance's key.
              'clientRequestId': '',
            });
      }
    } else {
      // The snapshot must be byte-identical to the wire request the way the
      // retry branch stores it: the wire body carries clientRequestId (= the
      // durable key), so the snapshot carries the SAME FIELD as a
      // placeholder. The exact-only recovery path rewrites it to the
      // instance's key — a recovered replay without the field would be a
      // materially different request.
      op = await DurableOperationRegistry.begin(
          account: account,
          type: _requestAction(friendshipId),
          endpoint: '/friends/transfer/request',
          request: {
            'friendshipId': friendshipId,
            'amount': amount,
            if (reference != null && reference.isNotEmpty) 'reference': reference,
            'clientRequestId': '',
          });
    }
    requestRef.operationId = op.operationId;
    final requestId = op.key;
    final response = await _api.post('/friends/transfer/request', {
      'friendshipId': friendshipId,
      'amount': amount,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
      'clientRequestId': requestId,
    });
    // Answered — committed or definitively failed: this instance is
    // terminal. Retire THAT instance only and clear the flow ref.
    await DurableOperationRegistry.retire(op.operationId, account: account);
    requestRef.operationId = null;
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    
    throw Exception('Failed to request funds: ${response.body}');
  }

  /// Fulfill a pending transfer request (pay it)
  Future<Map<String, dynamic>> fulfillTransfer(
      String transferId, String token) async {
    final response = await _api.put('/friends/transfer/$transferId/fulfill', {});

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to fulfill transfer: ${response.body}');
  }

  /// Decline a pending transfer request
  Future<Map<String, dynamic>> declineTransfer(
      String transferId, String token) async {
    final response = await _api.put('/friends/transfer/$transferId/decline', {});

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to decline transfer: ${response.body}');
  }

  /// Get details of a specific transfer
  Future<Map<String, dynamic>> getTransferDetails(
      String transferId, String token) async {
    final response = await _api.get('/friends/transfer/$transferId');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to get transfer details: ${response.body}');
  }

  /// Get all pending transfer requests (incoming)
  Future<Map<String, dynamic>> getPendingTransferRequests(String token) async {
    final response = await _api.get('/friends/transfer/pending');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to get pending transfers: ${response.body}');
  }
}
