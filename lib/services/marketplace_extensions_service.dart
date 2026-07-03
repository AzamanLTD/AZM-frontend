// lib/services/marketplace_extensions_service.dart
// =============================================================================
// AZAMAN — MARKETPLACE EXTENSIONS SERVICE (v2, 2026-07-03)
// Handles API calls for follow, ads, dine-in, showcase, and trust scores.
// =============================================================================

import 'dart:convert';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/models/marketplace_extensions_models.dart';

class MarketplaceExtensionsService {
  final ApiClient _api;
  MarketplaceExtensionsService(this._api);

  // ── Follow ──
  Future<bool> checkFollow(String businessProfileId) async {
    final res = await _api.get('/marketplace/follow/check/$businessProfileId');
    return jsonDecode(res.body)['isFollowing'] ?? false;
  }

  Future<void> follow(String businessProfileId) async {
    await _api.post('/marketplace/follow', {'businessProfileId': businessProfileId});
  }

  Future<void> unfollow(String businessProfileId) async {
    await _api.delete('/marketplace/follow/$businessProfileId');
  }

  // ── Ads ──
  Future<List<BusinessAdPost>> getAdFeed({int limit = 20, int offset = 0}) async {
    final res = await _api.get('/marketplace/ads/feed?limit=$limit&offset=$offset');
    final ads = (jsonDecode(res.body)['ads'] as List?)?.map((e) => BusinessAdPost.fromJson(e)).toList() ?? [];
    return ads;
  }

  Future<List<BusinessAdPost>> getActiveAds(String businessProfileId) async {
    final res = await _api.get('/marketplace/ads/active/$businessProfileId');
    final ads = (jsonDecode(res.body)['ads'] as List?)?.map((e) => BusinessAdPost.fromJson(e)).toList() ?? [];
    return ads;
  }

  // ── Dine-In ──
  Future<DineInTab> getTab(String tabId) async {
    final res = await _api.get('/marketplace/dine-in/tabs/$tabId');
    return DineInTab.fromJson(jsonDecode(res.body)['tab']);
  }

  Future<void> payTab(String tabId, {double? tip}) async {
    await _api.post('/marketplace/dine-in/tabs/$tabId/pay', {
      if (tip != null) 'tipUsdc': tip,
    });
  }

  // ── Showcase ──
  Future<List<BusinessShowcase>> getShowcase(String businessProfileId) async {
    final res = await _api.get('/marketplace/showcase/$businessProfileId');
    final items = (jsonDecode(res.body)['items'] as List?)?.map((e) => BusinessShowcase.fromJson(e)).toList() ?? [];
    return items;
  }

  // ── Trust Score ──
  Future<TrustScore> getTrustScore(String azamanId) async {
    final res = await _api.get('/marketplace/trust-score/$azamanId');
    return TrustScore.fromJson(jsonDecode(res.body));
  }

  // ── Transit QR ──
  Future<Map<String, dynamic>> generateTransitQR(String bookingId) async {
    final res = await _api.get('/marketplace/transit/bookings/$bookingId/checkin-qr');
    return jsonDecode(res.body);
  }
}
