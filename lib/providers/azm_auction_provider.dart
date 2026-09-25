// =============================================================================
// AZM AUCTION PROVIDER  (Master Sprint, 2026-05-27)
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';

double _num(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

class AuctionState {
  final String id;
  final DateTime windowStart;
  final DateTime windowEnd;
  final String status; // OPEN | SETTLING | SETTLED | CANCELLED
  final int participantCount;

  AuctionState({
    required this.id,
    required this.windowStart,
    required this.windowEnd,
    required this.status,
    required this.participantCount,
  });

  factory AuctionState.fromJson(Map<String, dynamic> wrap) {
    final auction = wrap['auction'] as Map<String, dynamic>;
    return AuctionState(
      id: auction['id'],
      windowStart: DateTime.parse(auction['windowStart']),
      windowEnd: DateTime.parse(auction['windowEnd']),
      status: auction['status'],
      participantCount: (wrap['participantCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class MyBid {
  final String? id;
  final String? auctionId;
  final int? adId;
  final double? bidAmountAzm;
  final String? status;

  MyBid({this.id, this.auctionId, this.adId, this.bidAmountAzm, this.status});

  factory MyBid.fromJson(Map<String, dynamic>? j) {
    if (j == null) return MyBid();
    return MyBid(
      id: j['id'],
      auctionId: j['auctionId'],
      adId: j['adId'] != null ? (j['adId'] as num).toInt() : null,
      bidAmountAzm: _num(j['bidAmountAzm']),
      status: j['status'],
    );
  }

  bool get hasBid => id != null;
}

class PromotedAd {
  final int id;
  final String paymentMethod;
  final DateTime? boostExpiresAt;

  PromotedAd({required this.id, required this.paymentMethod, this.boostExpiresAt});

  factory PromotedAd.fromJson(Map<String, dynamic> j) => PromotedAd(
        id: (j['id'] as num).toInt(),
        paymentMethod: j['paymentMethod'] ?? '',
        boostExpiresAt: j['boostExpiresAt'] != null
            ? DateTime.tryParse(j['boostExpiresAt'])
            : null,
      );
}

// ── Providers ─────────────────────────────────────────────────────────────

final auctionStateProvider = FutureProvider<AuctionState?>((ref) async {
  final res = await apiClient.get('/azm-auction/current');
  if (res.statusCode != 200) return null;
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return AuctionState.fromJson(body);
});

final myAuctionBidProvider = FutureProvider<MyBid>((ref) async {
  final res = await apiClient.get('/azm-auction/bid');
  if (res.statusCode != 200) return MyBid();
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return MyBid.fromJson(body['bid'] as Map<String, dynamic>?);
});

final promotedAdsProvider = FutureProvider<List<PromotedAd>>((ref) async {
  final res = await apiClient.get('/azm-auction/promoted');
  if (res.statusCode != 200) return const [];
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final list = body['ads'] as List<dynamic>? ?? const [];
  return list.map((e) => PromotedAd.fromJson(e)).toList();
});

class AuctionActions {
  final Ref ref;
  AuctionActions(this.ref);

  Future<void> placeBid({required int adId, required double amountAzm}) async {
    final res = await apiClient.post('/azm-auction/bid', {
      'adId': adId,
      'amountAzm': amountAzm,
    });
    if (res.statusCode != 201) throw Exception(_msg(res.body));
    ref.invalidate(myAuctionBidProvider);
    ref.invalidate(auctionStateProvider);
  }

  Future<void> withdrawBid() async {
    final res = await apiClient.delete('/azm-auction/bid');
    if (res.statusCode != 200) throw Exception(_msg(res.body));
    ref.invalidate(myAuctionBidProvider);
    ref.invalidate(auctionStateProvider);
  }

  String _msg(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return m['message']?.toString() ?? 'Auction request failed';
    } catch (_) {
      return 'Auction request failed';
    }
  }
}

final auctionActionsProvider = Provider<AuctionActions>((ref) => AuctionActions(ref));
