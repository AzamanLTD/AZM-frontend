// =============================================================================
// CHAT PROFILE SERVICE — Phase UI-5 (2026-05-26)
//
// REST client for the Chat Profile + Vault aggregator endpoints. Wraps:
//   • GET   /api/friends/:friendshipId/profile           — identity tier
//   • PATCH /api/friends/:friendshipId/nickname          — set/clear nickname
//   • GET   /api/friends/:friendshipId/media             — vault tab 1
//   • GET   /api/friends/:friendshipId/docs-links        — vault tab 2
//   • GET   /api/friends/:friendshipId/receipts          — vault tab 4
//   (Tickets — vault tab 3 — already served by `/api/tickets`.)
//
// All requests authenticated via the shared `apiClient` (JWT bearer).
// =============================================================================

import 'dart:convert';

import 'package:azaman/services/api_client.dart';

class ChatProfileFriend {
  final int id;
  final String username;
  final String? profilePictureUrl;
  final String kycStatus;
  final String? role;
  final int tradesCompleted;
  final double completionRate;
  final int positiveReviews;
  final int negativeReviews;
  final String? loyaltyTier;
  final DateTime createdAt;
  // Phase UI-6 + UI-7: pre-computed trust signals from the BE.
  // `completedTransactions` is the global count surfaced in the chat
  // AppBar; the `breakdown` powers the tap-popup and the vault identity
  // tier without any FE re-aggregation.
  final int completedTransactions;
  final TrustBreakdown? completedTransactionsBreakdown;
  final double? rating;
  final bool isVerifiedVendor;

  const ChatProfileFriend({
    required this.id,
    required this.username,
    required this.kycStatus,
    required this.tradesCompleted,
    required this.completionRate,
    required this.positiveReviews,
    required this.negativeReviews,
    required this.createdAt,
    required this.completedTransactions,
    required this.isVerifiedVendor,
    this.profilePictureUrl,
    this.role,
    this.loyaltyTier,
    this.completedTransactionsBreakdown,
    this.rating,
  });

  factory ChatProfileFriend.fromJson(Map<String, dynamic> json) {
    final ratingRaw = json['rating'];
    return ChatProfileFriend(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      username: (json['username'] ?? '').toString(),
      profilePictureUrl: json['profilePictureUrl']?.toString(),
      kycStatus: (json['kycStatus'] ?? 'UNVERIFIED').toString(),
      role: json['role']?.toString(),
      tradesCompleted: json['tradesCompleted'] is int
          ? json['tradesCompleted']
          : int.tryParse('${json['tradesCompleted'] ?? 0}') ?? 0,
      completionRate: json['completionRate'] is num
          ? (json['completionRate'] as num).toDouble()
          : double.tryParse(json['completionRate'].toString()) ?? 0.0,
      positiveReviews: json['positiveReviews'] is int
          ? json['positiveReviews']
          : int.tryParse('${json['positiveReviews'] ?? 0}') ?? 0,
      negativeReviews: json['negativeReviews'] is int
          ? json['negativeReviews']
          : int.tryParse('${json['negativeReviews'] ?? 0}') ?? 0,
      loyaltyTier: json['loyaltyTier']?.toString(),
      createdAt: DateTime.parse(json['createdAt'].toString()),
      // Defensive int parse — older BE deploys may not yet return these.
      completedTransactions: json['completedTransactions'] is int
          ? json['completedTransactions']
          : int.tryParse('${json['completedTransactions'] ?? 0}') ?? 0,
      completedTransactionsBreakdown:
          json['completedTransactionsBreakdown'] is Map<String, dynamic>
              ? TrustBreakdown.fromJson(
                  json['completedTransactionsBreakdown']
                      as Map<String, dynamic>)
              : null,
      rating: ratingRaw == null
          ? null
          : (ratingRaw is num
              ? ratingRaw.toDouble()
              : double.tryParse(ratingRaw.toString())),
      isVerifiedVendor: json['isVerifiedVendor'] == true,
    );
  }
}

class ChatProfileResponse {
  final String friendshipId;
  final DateTime friendSince;
  final String friendshipStatus;
  final ChatProfileFriend friend;
  final String? myNicknameForFriend;
  final int mutualTradesCompleted;

  const ChatProfileResponse({
    required this.friendshipId,
    required this.friendSince,
    required this.friendshipStatus,
    required this.friend,
    required this.mutualTradesCompleted,
    this.myNicknameForFriend,
  });

  factory ChatProfileResponse.fromJson(Map<String, dynamic> json) {
    return ChatProfileResponse(
      friendshipId: (json['friendshipId'] ?? '').toString(),
      friendSince: DateTime.parse(json['friendSince'].toString()),
      friendshipStatus: (json['friendshipStatus'] ?? 'ACCEPTED').toString(),
      friend: ChatProfileFriend.fromJson(
          json['friend'] as Map<String, dynamic>),
      myNicknameForFriend: json['myNicknameForFriend']?.toString(),
      mutualTradesCompleted: json['mutualTradesCompleted'] is int
          ? json['mutualTradesCompleted']
          : int.tryParse(json['mutualTradesCompleted'].toString()) ?? 0,
    );
  }
}

/// Generic vault row used by media + docs/links tabs. Source-agnostic so
/// the UI can render either DirectMessage rows or TicketMessage rows
/// uniformly. The `source` field disambiguates ('DIRECT' or 'TICKET').
class VaultItem {
  final String source; // DIRECT | TICKET
  final String id;
  final String? ticketId;
  final int senderId;
  final String type;     // IMAGE | VIDEO | DOCUMENT | LINK
  final String? content; // for LINK type, this is the URL
  final String? mediaUrl;
  final String? mediaMimeType;
  final int? mediaSize;
  final int? mediaDuration;
  final Map<String, dynamic>? linkPreview;
  final DateTime createdAt;

  const VaultItem({
    required this.source,
    required this.id,
    required this.senderId,
    required this.type,
    required this.createdAt,
    this.ticketId,
    this.content,
    this.mediaUrl,
    this.mediaMimeType,
    this.mediaSize,
    this.mediaDuration,
    this.linkPreview,
  });

  factory VaultItem.fromJson(Map<String, dynamic> json) {
    return VaultItem(
      source: (json['source'] ?? 'DIRECT').toString(),
      id: (json['id'] ?? '').toString(),
      ticketId: json['ticketId']?.toString(),
      senderId: json['senderId'] is int
          ? json['senderId']
          : int.tryParse(json['senderId'].toString()) ?? 0,
      type: (json['type'] ?? 'TEXT').toString().toUpperCase(),
      content: json['content']?.toString(),
      mediaUrl: json['mediaUrl']?.toString(),
      mediaMimeType: json['mediaMimeType']?.toString(),
      mediaSize: json['mediaSize'] is int ? json['mediaSize'] as int : null,
      mediaDuration:
          json['mediaDuration'] is int ? json['mediaDuration'] as int : null,
      linkPreview: json['linkPreview'] is Map<String, dynamic>
          ? json['linkPreview'] as Map<String, dynamic>
          : null,
      createdAt: DateTime.parse(json['createdAt'].toString()),
    );
  }
}

/// Receipt row for the Receipts vault tab. One PeerTransfer per row,
/// with direction flipped relative to the observer.
class ReceiptItem {
  final String id;
  final String friendshipId;
  final double amount;
  final String currency;
  final String? reference;
  final String type; // SEND | REQUEST
  final String status; // PENDING | COMPLETED | DECLINED | FAILED | INSUFFICIENT_FUNDS
  final String direction; // SENT | RECEIVED
  final Map<String, dynamic>? counterparty;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? downloadUrl;

  const ReceiptItem({
    required this.id,
    required this.friendshipId,
    required this.amount,
    required this.currency,
    required this.type,
    required this.status,
    required this.direction,
    required this.createdAt,
    required this.updatedAt,
    this.reference,
    this.counterparty,
    this.downloadUrl,
  });

  factory ReceiptItem.fromJson(Map<String, dynamic> json) {
    final amountRaw = json['amount'];
    return ReceiptItem(
      id: (json['id'] ?? '').toString(),
      friendshipId: (json['friendshipId'] ?? '').toString(),
      amount: amountRaw is num
          ? amountRaw.toDouble()
          : double.tryParse(amountRaw.toString()) ?? 0.0,
      currency: (json['currency'] ?? 'USDC').toString(),
      reference: json['reference']?.toString(),
      type: (json['type'] ?? 'SEND').toString(),
      status: (json['status'] ?? 'COMPLETED').toString(),
      direction: (json['direction'] ?? 'SENT').toString(),
      counterparty: json['counterparty'] is Map<String, dynamic>
          ? json['counterparty'] as Map<String, dynamic>
          : null,
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
      downloadUrl: json['downloadUrl']?.toString(),
    );
  }

  bool get isCompleted => status == 'COMPLETED';
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase UI-7 (2026-05-27): per-category trust breakdown. Always returned
// alongside `completedTransactions` so the AppBar tap-popup and the vault
// identity tier card share one source of truth and never re-aggregate.
//
//   tradesCompleted    — formal P2P escrow trades (User.tradesCompleted)
//   completedTransfers — fulfilled PeerTransfer rows (off-ticket money)
//   closedTickets      — Ticket workspaces with status=CLOSED
//
// `total` is the sum, returned for convenience so callers don't have to
// add the three columns themselves.
// ─────────────────────────────────────────────────────────────────────────────
class TrustBreakdown {
  final int tradesCompleted;
  final int completedTransfers;
  final int closedTickets;

  const TrustBreakdown({
    required this.tradesCompleted,
    required this.completedTransfers,
    required this.closedTickets,
  });

  int get total => tradesCompleted + completedTransfers + closedTickets;

  factory TrustBreakdown.fromJson(Map<String, dynamic> json) {
    int parse(dynamic v) =>
        v is int ? v : int.tryParse('${v ?? 0}') ?? 0;
    return TrustBreakdown(
      tradesCompleted: parse(json['tradesCompleted']),
      completedTransfers: parse(json['completedTransfers']),
      closedTickets: parse(json['closedTickets']),
    );
  }

  static const empty = TrustBreakdown(
    tradesCompleted: 0,
    completedTransfers: 0,
    closedTickets: 0,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase UI-6 (2026-05-27): Chat-header trust metrics. Lightweight payload
// fetched by the chat AppBar to render the persistent subtitle line:
//
//   ⭐ {rating} · {completedTransactions} Completed Transactions   (+ ✓ for verified vendors)
//
// `rating` is null when the friend has no reviews yet — UI suppresses the
// star icon entirely in that case.
// ─────────────────────────────────────────────────────────────────────────────
class ChatTrustMetrics {
  final int completedTransactions;
  // Phase UI-7: breakdown — always returned by current BE; defaults to
  // an empty breakdown when an older BE deploy is in front of a new FE.
  final TrustBreakdown breakdown;
  final double? rating; // 5-star scale, null when no reviews
  final int positiveReviews;
  final int negativeReviews;
  final bool isVerifiedVendor;
  final String kycStatus;

  const ChatTrustMetrics({
    required this.completedTransactions,
    required this.breakdown,
    required this.positiveReviews,
    required this.negativeReviews,
    required this.isVerifiedVendor,
    required this.kycStatus,
    this.rating,
  });

  factory ChatTrustMetrics.fromJson(Map<String, dynamic> json) {
    final ratingRaw = json['rating'];
    final breakdownRaw = json['breakdown'];
    return ChatTrustMetrics(
      completedTransactions: json['completedTransactions'] is int
          ? json['completedTransactions']
          : int.tryParse(json['completedTransactions'].toString()) ?? 0,
      breakdown: breakdownRaw is Map<String, dynamic>
          ? TrustBreakdown.fromJson(breakdownRaw)
          : TrustBreakdown.empty,
      rating: ratingRaw == null
          ? null
          : (ratingRaw is num
              ? ratingRaw.toDouble()
              : double.tryParse(ratingRaw.toString())),
      positiveReviews: json['positiveReviews'] is int
          ? json['positiveReviews']
          : int.tryParse('${json['positiveReviews'] ?? 0}') ?? 0,
      negativeReviews: json['negativeReviews'] is int
          ? json['negativeReviews']
          : int.tryParse('${json['negativeReviews'] ?? 0}') ?? 0,
      isVerifiedVendor: json['isVerifiedVendor'] == true,
      kycStatus: (json['kycStatus'] ?? 'UNVERIFIED').toString(),
    );
  }
}

class VaultListResponse<T> {
  final List<T> items;
  final int count;
  final bool hasMore;
  final String? nextCursor;
  const VaultListResponse({
    required this.items,
    required this.count,
    this.hasMore = false,
    this.nextCursor,
  });
}

class ChatProfileService {
  ChatProfileService._();
  static final ChatProfileService instance = ChatProfileService._();

  Future<ChatProfileResponse> getProfile(String friendshipId) async {
    final res = await apiClient.get('/friends/$friendshipId/profile');
    final body = jsonDecode(res.body);
    if (res.statusCode != 200 || body['profile'] == null) {
      throw _exception(res.statusCode, body, 'Profile fetch failed');
    }
    return ChatProfileResponse.fromJson(
        body['profile'] as Map<String, dynamic>);
  }

  /// Set the caller's local nickname for this friend. Pass null or an empty
  /// string to clear it.
  Future<String?> setNickname(String friendshipId, String? nickname) async {
    final res = await apiClient.patch(
      '/friends/$friendshipId/nickname',
      body: {'nickname': nickname},
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw _exception(res.statusCode, body, 'Nickname update failed');
    }
    return body['nickname']?.toString();
  }

  Future<VaultListResponse<VaultItem>> getMedia(
    String friendshipId, {
    String? type, // IMAGE | VIDEO | null for both
    int limit = 50,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      if (type != null) 'type': type.toUpperCase(),
    };
    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final res = await apiClient.get('/friends/$friendshipId/media?$query');
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw _exception(res.statusCode, body, 'Media fetch failed');
    }
    final items = (body['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(VaultItem.fromJson)
        .toList();
    return VaultListResponse<VaultItem>(
      items: items,
      count: body['count'] is int ? body['count'] : items.length,
    );
  }

  Future<VaultListResponse<VaultItem>> getDocsAndLinks(
    String friendshipId, {
    int limit = 50,
  }) async {
    final res =
        await apiClient.get('/friends/$friendshipId/docs-links?limit=$limit');
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw _exception(res.statusCode, body, 'Docs/links fetch failed');
    }
    final items = (body['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(VaultItem.fromJson)
        .toList();
    return VaultListResponse<VaultItem>(
      items: items,
      count: body['count'] is int ? body['count'] : items.length,
    );
  }

  Future<VaultListResponse<ReceiptItem>> getReceipts(
    String friendshipId, {
    String? status,
    String? cursor,
    int limit = 50,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      if (status != null) 'status': status.toUpperCase(),
      if (cursor != null) 'cursor': cursor,
    };
    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final res = await apiClient.get('/friends/$friendshipId/receipts?$query');
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw _exception(res.statusCode, body, 'Receipts fetch failed');
    }
    final items = (body['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReceiptItem.fromJson)
        .toList();
    return VaultListResponse<ReceiptItem>(
      items: items,
      count: body['count'] is int ? body['count'] : items.length,
      hasMore: body['hasMore'] == true,
      nextCursor: body['nextCursor']?.toString(),
    );
  }

  ChatProfileServiceException _exception(
      int code, Map<String, dynamic> body, String fallback) {
    return ChatProfileServiceException(
      statusCode: code,
      message: body['message']?.toString() ?? fallback,
    );
  }

  /// Phase UI-6: lightweight trust-metrics fetch for the chat AppBar.
  /// Cheaper than [getProfile] — skips mutual-trade aggregation and
  /// nickname resolution. Used by the persistent header subtitle.
  Future<ChatTrustMetrics> getTrustMetrics(String friendshipId) async {
    final res =
        await apiClient.get('/friends/$friendshipId/trust-metrics');
    final body = jsonDecode(res.body);
    if (res.statusCode != 200 || body['metrics'] == null) {
      throw _exception(res.statusCode, body, 'Trust metrics fetch failed');
    }
    return ChatTrustMetrics.fromJson(body['metrics'] as Map<String, dynamic>);
  }
}

class ChatProfileServiceException implements Exception {
  final int statusCode;
  final String message;
  const ChatProfileServiceException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() => 'ChatProfileServiceException($statusCode): $message';
}
