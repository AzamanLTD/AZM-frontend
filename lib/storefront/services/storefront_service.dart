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

  Future<List<StorefrontTheme>> listThemes({String? category}) async {
    final query = category != null ? '?category=$category' : '';
    final response = await _apiClient.get('/storefront/themes$query');
    final data = _parseResponse(response);
    return (data as List).map((t) => StorefrontTheme.fromJson(t as Map<String, dynamic>)).toList();
  }

  Future<List<StorefrontWidget>> listWidgets({String? category}) async {
    final query = category != null ? '?category=$category' : '';
    final response = await _apiClient.get('/storefront/widgets$query');
    final data = _parseResponse(response);
    return (data as List).map((w) => StorefrontWidget.fromJson(w as Map<String, dynamic>)).toList();
  }

  Future<List<StorefrontLayoutTemplate>> listTemplates({String? category}) async {
    final query = category != null ? '?category=$category' : '';
    final response = await _apiClient.get('/storefront/templates$query');
    final data = _parseResponse(response);
    return (data as List).map((t) => StorefrontLayoutTemplate.fromJson(t as Map<String, dynamic>)).toList();
  }

  Future<StorefrontRenderResponse?> renderStorefront(String businessProfileId) async {
    final response = await _apiClient.get('/storefront/$businessProfileId/render');
    if (response.statusCode == 404) return null;
    final data = _parseResponse(response);
    return StorefrontRenderResponse.fromJson(data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getPublicTheme(String businessProfileId) async {
    final response = await _apiClient.get('/storefront/$businessProfileId/theme');
    return _parseResponse(response) as Map<String, dynamic>;
  }

  // ── Authenticated endpoints ─────────────────────────────────────────────────

  Future<StorefrontLayout> getDraft() async {
    final response = await _apiClient.get('/storefront/me/draft');
    final data = _parseResponse(response);
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

  Future<StorefrontLayout?> getPublished() async {
    final response = await _apiClient.get('/storefront/me/published');
    final data = _parseResponse(response);
    if (data == null) return null;
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

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

  Future<StorefrontLayout> publish({String? expectedUpdatedAt}) async {
    final response = await _apiClient.post('/storefront/me/publish', {
      if (expectedUpdatedAt != null) 'expectedUpdatedAt': expectedUpdatedAt,
    });
    final data = _parseResponse(response);
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

  Future<List<StorefrontLayoutVersion>> getHistory({int limit = 20}) async {
    final response = await _apiClient.get('/storefront/me/history?limit=$limit');
    final data = _parseResponse(response);
    return (data as List).map((v) => StorefrontLayoutVersion.fromJson(v as Map<String, dynamic>)).toList();
  }

  Future<StorefrontLayout> revertToVersion(String versionId) async {
    final response = await _apiClient.post('/storefront/me/revert', {'versionId': versionId});
    final data = _parseResponse(response);
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

  Future<StorefrontLayout> applyTemplate(String templateId) async {
    final response = await _apiClient.post('/storefront/me/apply-template', {'templateId': templateId});
    final data = _parseResponse(response);
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

  Future<StorefrontEligibility> getEligibility() async {
    final response = await _apiClient.get('/storefront/me/eligibility');
    final data = _parseResponse(response);
    return StorefrontEligibility.fromJson(data as Map<String, dynamic>);
  }

  Future<void> recordEvent(String eventType, Map<String, dynamic> metadata) async {
    await _apiClient.post('/storefront/me/analytics', {'eventType': eventType, 'metadata': metadata});
  }

  // ── AZM Staking ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createStake(double amountAzm) async {
    final response = await _apiClient.post('/azm-stake/create', {'amountAzm': amountAzm});
    return _parseResponse(response) as Map<String, dynamic>;
  }

  Future<AzmStake> requestUnstake(String stakeId) async {
    final response = await _apiClient.post('/azm-stake/unstake', {'stakeId': stakeId});
    final data = _parseResponse(response);
    return AzmStake.fromJson(data as Map<String, dynamic>);
  }

  Future<List<AzmStake>> getStakes() async {
    final response = await _apiClient.get('/azm-stake/stakes');
    final data = _parseResponse(response);
    return (data as List).map((s) => AzmStake.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> getTierInfo() async {
    final response = await _apiClient.get('/azm-stake/tier');
    return _parseResponse(response) as Map<String, dynamic>;
  }

  // ── Discovery ────────────────────────────────────────────────────────────────

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
    if (category != null && category.trim().isNotEmpty) params['category'] = category.trim();

    final queryString = Uri(queryParameters: params).query;
    final response = await _apiClient.get(
      '/storefront/discover?$queryString',
      requireAuth: false,
    );
    final data = _parseResponse(response) as Map<String, dynamic>;
    final results = data['results'];
    if (results is! List) return const [];
    return results.whereType<Map<String, dynamic>>().toList();
  }

  // ── Direct Ordering ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getStorefrontProducts(String businessProfileId) async {
    final response = await _apiClient.get(
      '/storefront/$businessProfileId/products',
      requireAuth: false,
    );
    return _parseResponse(response) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> placeStorefrontOrder({
    required String businessProfileId,
    required String productId,
    int quantity = 1,
    String? customerNotes,
    String? deliveryNotes,
  }) async {
    final response = await _apiClient.post('/storefront/$businessProfileId/order', {
      'productId': productId,
      'quantity': quantity,
      if (customerNotes != null) 'customerNotes': customerNotes,
      if (deliveryNotes != null) 'deliveryNotes': deliveryNotes,
    });
    return _parseResponse(response) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> checkoutCart({
    required String businessProfileId,
    required List<Map<String, dynamic>> items,
    String? customerNotes,
    String? deliveryNotes,
    String? idempotencyKey,
    String paymentMode = 'DIRECT',
  }) async {
    final response = await _apiClient.post('/storefront/$businessProfileId/checkout', {
      'items': items,
      if (customerNotes != null) 'customerNotes': customerNotes,
      if (deliveryNotes != null) 'deliveryNotes': deliveryNotes,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
      'paymentMode': paymentMode,
    });
    return _parseResponse(response) as Map<String, dynamic>;
  }

  // ── Customer Order History ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMyOrders({
    String? status,
    int limit = 20,
    String? cursor,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      if (status != null && status.isNotEmpty) 'status': status,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final queryString = Uri(queryParameters: params).query;
    final response = await _apiClient.get('/storefront/me/orders?$queryString');
    return _parseResponse(response) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getOrderDetail(String orderId) async {
    final response = await _apiClient.get('/storefront/me/orders/$orderId');
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