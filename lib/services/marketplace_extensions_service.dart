// lib/services/marketplace_extensions_service.dart
// =============================================================================
// AZAMAN — MARKETPLACE EXTENSIONS SERVICE (v2, 2026-07-03)
// Handles API calls for follow, ads, dine-in, showcase, and trust scores.
//
// FIX (2026-07-06): this entire file was unused anywhere in the app and had
// never actually been exercised:
//   1. Every endpoint pointed at a made-up `/marketplace/...` base that no
//      backend route uses (real mounts are top-level: /follows, /ad-posts,
//      /dine-in, /transit; only /showcases/... and /trust-score/... — the
//      latter genuinely nested under /marketplace — were already correct).
//   2. Every call read `res.data[...]`, a Dio-ism. This app's ApiClient
//      wraps `package:http` and returns `http.Response`, which has no
//      `.data` getter at all -- this would have thrown `undefined_getter`
//      compile errors the moment this file was actually used anywhere.
// Rewritten to use the same `jsonDecode(res.body)` pattern as every other
// working service in this codebase (see azm_reward_service.dart).
// =============================================================================

import 'dart:convert';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/models/marketplace_extensions_models.dart';

class MarketplaceExtensionsService {
  final ApiClient _api;
  MarketplaceExtensionsService(this._api);

  // ── Follow ──
  Future<bool> checkFollow(String businessProfileId) async {
    final res = await _api.get('/follows/check/$businessProfileId');
    final body = jsonDecode(res.body);
    return body['isFollowing'] ?? false;
  }

  Future<void> follow(String businessProfileId) async {
    await _api.post('/follows', {'businessProfileId': businessProfileId});
  }

  Future<void> unfollow(String businessProfileId) async {
    await _api.delete('/follows/$businessProfileId');
  }

  /// Businesses the current user follows -- drives the marketplace "status"
  /// rail (backlog item: show a live-updates rail for followed businesses,
  /// or an empty-state prompting the user to follow some). Returns raw maps
  /// (id, businessName, logoUrl, category, isVerified, averageRating,
  /// followedAt) rather than forcing into the heavier BusinessProfile model,
  /// which requires several fields this endpoint doesn't return.
  Future<List<Map<String, dynamic>>> getFollowing({int limit = 50, int offset = 0}) async {
    final res = await _api.get('/follows/following?limit=$limit&offset=$offset');
    final body = jsonDecode(res.body);
    final list = body['following'] as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  // ── Ads ──
  Future<List<BusinessAdPost>> getAdFeed({int limit = 20, int offset = 0}) async {
    final res = await _api.get('/ad-posts/feed?limit=$limit&offset=$offset');
    final body = jsonDecode(res.body);
    final ads = (body['ads'] as List?)?.map((e) => BusinessAdPost.fromJson(e)).toList() ?? [];
    return ads;
  }

  Future<List<BusinessAdPost>> getActiveAds(String businessProfileId) async {
    final res = await _api.get('/ad-posts/active/$businessProfileId');
    final body = jsonDecode(res.body);
    final ads = (body['ads'] as List?)?.map((e) => BusinessAdPost.fromJson(e)).toList() ?? [];
    return ads;
  }

  // ── Dine-In ──
  Future<DineInTab> getTab(String tabId) async {
    final res = await _api.get('/dine-in/tabs/$tabId');
    final body = jsonDecode(res.body);
    return DineInTab.fromJson(body['tab']);
  }

  Future<void> payTab(String tabId, {double? tip}) async {
    await _api.post('/dine-in/tabs/$tabId/pay', {
      if (tip != null) 'tipUsdc': tip,
    });
  }

  // ── Showcase ──
  Future<List<BusinessShowcase>> getShowcase(String businessProfileId) async {
    final res = await _api.get('/showcases/$businessProfileId');
    final body = jsonDecode(res.body);
    final items = (body['items'] as List?)?.map((e) => BusinessShowcase.fromJson(e)).toList() ?? [];
    return items;
  }

  // ── Trust Score ──
  Future<TrustScore> getTrustScore(String azamanId) async {
    final res = await _api.get('/marketplace/trust-score/$azamanId');
    final body = jsonDecode(res.body);
    return TrustScore.fromJson(body);
  }

  // ── Transit QR ──
  Future<Map<String, dynamic>> generateTransitQR(String bookingId) async {
    final res = await _api.get('/transit/bookings/$bookingId/checkin-qr');
    return jsonDecode(res.body);
  }
}
