// =============================================================================
// Storefront Service
//
// API client for storefront endpoints. Handles all HTTP communication with
// the backend storefront SDUI system.
// =============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:azaman/config.dart';
import 'package:azaman/services/api_client.dart';

import '../models/storefront_models.dart';

class StorefrontService {
  final ApiClient _apiClient = ApiClient();

  static String get _baseUrl => AppConfig.apiUrl;

  // ── Public endpoints ────────────────────────────────────────────────────────

  /// List all active themes (public).
  Future<List<StorefrontTheme>> listThemes({String? category}) async {
    final query = category != null ? '?category=$category' : '';
    final response = await _apiClient.get('/storefront/themes$query');
    final data = _parseResponse(response);
    return (data as List)
        .map((t) => StorefrontTheme.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  /// List all active widgets (public).
  Future<List<StorefrontWidget>> listWidgets({String? category}) async {
    final query = category != null ? '?category=$category' : '';
    final response = await _apiClient.get('/storefront/widgets$query');
    final data = _parseResponse(response);
    return (data as List)
        .map((w) => StorefrontWidget.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  /// List all active layout templates (public).
  Future<List<StorefrontLayoutTemplate>> listTemplates({String? category}) async {
    final query = category != null ? '?category=$category' : '';
    final response = await _apiClient.get('/storefront/templates$query');
    final data = _parseResponse(response);
    return (data as List)
        .map((t) => StorefrontLayoutTemplate.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  /// Render a storefront (public, cached).
  Future<StorefrontRenderResponse?> renderStorefront(String businessProfileId) async {
    final response = await _apiClient.get('/storefront/$businessProfileId/render');
    if (response.statusCode == 404) return null;
    final data = _parseResponse(response);
    return StorefrontRenderResponse.fromJson(data as Map<String, dynamic>);
  }

  /// Get public theme for a business (for web ordering).
  Future<Map<String, dynamic>> getPublicTheme(String businessProfileId) async {
    final response = await _apiClient.get('/storefront/$businessProfileId/theme');
    return _parseResponse(response) as Map<String, dynamic>;
  }

  // ── Authenticated endpoints ─────────────────────────────────────────────────

  /// Get or create the draft layout for the current business.
  Future<StorefrontLayout> getDraft() async {
    final response = await _apiClient.get('/storefront/me/draft');
    final data = _parseResponse(response);
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

  /// Get the published layout for the current business.
  Future<StorefrontLayout?> getPublished() async {
    final response = await _apiClient.get('/storefront/me/published');
    final data = _parseResponse(response);
    if (data == null) return null;
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

  /// Save the draft layout.
  Future<StorefrontLayout> saveDraft({
    required LayoutJson layoutJson,
    required String themeId,
    String? expectedUpdatedAt,
  }) async {
    final response = await _apiClient.put('/storefront/me/draft', {
      'layoutJson': layoutJson.toJson(),
      'themeId': themeId,
      if (expectedUpdatedAt != null) 'expectedUpdatedAt': expectedUpdatedAt,
    });
    final data = _parseResponse(response);
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

  /// Publish the draft layout.
  Future<StorefrontLayout> publish() async {
    final response = await _apiClient.post('/storefront/me/publish', {});
    final data = _parseResponse(response);
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

  /// Get version history.
  Future<List<StorefrontLayoutVersion>> getHistory({int limit = 20}) async {
    final response = await _apiClient.get('/storefront/me/history?limit=$limit');
    final data = _parseResponse(response);
    return (data as List)
        .map((v) => StorefrontLayoutVersion.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  /// Revert to a specific version.
  Future<StorefrontLayout> revertToVersion(String versionId) async {
    final response = await _apiClient.post('/storefront/me/revert', {
      'versionId': versionId,
    });
    final data = _parseResponse(response);
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

  /// Apply a template to the draft.
  Future<StorefrontLayout> applyTemplate(String templateId) async {
    final response = await _apiClient.post('/storefront/me/apply-template', {
      'templateId': templateId,
    });
    final data = _parseResponse(response);
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

  /// Check eligibility (staked AZM, tier, disabled status).
  Future<StorefrontEligibility> getEligibility() async {
    final response = await _apiClient.get('/storefront/me/eligibility');
    final data = _parseResponse(response);
    return StorefrontEligibility.fromJson(data as Map<String, dynamic>);
  }

  /// Record an analytics event.
  Future<void> recordEvent(String eventType, Map<String, dynamic> metadata) async {
    await _apiClient.post('/storefront/me/analytics', {
      'eventType': eventType,
      'metadata': metadata,
    });
  }

  // ── AZM Staking ──────────────────────────────────────────────────────────────

  /// Create a new stake.
  Future<Map<String, dynamic>> createStake(double amountAzm) async {
    final response = await _apiClient.post('/azm-stake/create', {
      'amountAzm': amountAzm,
    });
    return _parseResponse(response) as Map<String, dynamic>;
  }

  /// Request unstaking.
  Future<AzmStake> requestUnstake(String stakeId) async {
    final response = await _apiClient.post('/azm-stake/unstake', {
      'stakeId': stakeId,
    });
    final data = _parseResponse(response);
    return AzmStake.fromJson(data as Map<String, dynamic>);
  }

  /// List all user stakes.
  Future<List<AzmStake>> getStakes() async {
    final response = await _apiClient.get('/azm-stake/stakes');
    final data = _parseResponse(response);
    return (data as List)
        .map((s) => AzmStake.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// Get current tier and staked balance.
  Future<Map<String, dynamic>> getTierInfo() async {
    final response = await _apiClient.get('/azm-stake/tier');
    return _parseResponse(response) as Map<String, dynamic>;
  }


  // ── Discovery (Phase 2) ─────────────────────────────────────────────────────

  /// Discover businesses with published storefronts.
  /// Returns a list of storefront summaries with business info.
  Future<List<Map<String, dynamic>>> discoverStorefronts({
    String? query,
    String? category,
    int limit = 20,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    if (category != null) params['category'] = category;

    final queryString = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    final response = await _apiClient.get('/storefront/discover?\$queryString', requireAuth: false);
    final data = _parseResponse(response) as Map<String, dynamic>;
    return (data['results'] as List).cast<Map<String, dynamic>>();
  }

  // ── Direct Ordering (Phase 4) ────────────────────────────────────────────────

  /// Get public product listing for a business's storefront.
  Future<Map<String, dynamic>> getStorefrontProducts(String businessProfileId) async {
    final response = await _apiClient.get(
      '/storefront/\$businessProfileId/products',
      requireAuth: false,
    );
    return _parseResponse(response) as Map<String, dynamic>;
  }


  /// Place an order from the storefront (Phase 4 — direct ordering).
  /// Requires authentication. Creates a BusinessOrder with AWAITING_PAYMENT.
  Future<Map<String, dynamic>> placeStorefrontOrder({
    required String businessProfileId,
    required String productId,
    int quantity = 1,
    String? customerNotes,
    String? deliveryNotes,
  }) async {
    final response = await _apiClient.post(
      '/storefront/$businessProfileId/order',
      body: jsonEncode({
        'productId': productId,
        'quantity': quantity,
        if (customerNotes != null) 'customerNotes': customerNotes,
        if (deliveryNotes != null) 'deliveryNotes': deliveryNotes,
      }),
    );
    return _parseResponse(response) as Map<String, dynamic>;
  }


  // ── Customer Order History ──────────────────────────────────────────────────

  /// Get the authenticated customer's storefront order history (paginated).
  Future<Map<String, dynamic>> getMyOrders({
    String? status,
    int limit = 20,
    String? cursor,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      if (status != null) 'status': status,
      if (cursor != null) 'cursor': cursor,
    };
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final response = await _apiClient.get(
      '/storefront/me/orders?\$query',
    );
    return _parseResponse(response) as Map<String, dynamic>;
  }

  /// Get details for a single order.
  Future<Map<String, dynamic>> getOrderDetail(String orderId) async {
    final response = await _apiClient.get(
      '/storefront/me/orders/\$orderId',
    );
    return _parseResponse(response) as Map<String, dynamic>;
  }

  // ── Helper ──────────────────────────────────────────────────────────────────

  dynamic _parseResponse(http.Response response) {
    if (response.statusCode >= 400) {
      final body = jsonDecode(response.body);
      throw Exception(body['message'] ?? 'Request failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body['success'] == true) return body['data'];
    if (body['data'] != null) return body['data'];
    return body;
  }
}
