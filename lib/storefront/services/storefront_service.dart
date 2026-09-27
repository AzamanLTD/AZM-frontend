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
import 'storefront_conflict_exception.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

class StorefrontApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;

  const StorefrontApiException({required this.statusCode, required this.message, this.code});

  bool get isRetryable => statusCode == 408 || statusCode == 425 || statusCode == 429 || statusCode >= 500;

  @override
  String toString() => 'StorefrontApiException($statusCode${code == null ? '' : ', $code'}): $message';
}

class StorefrontService {
  // r42 DURABLE key lifecycle: per-escrow funding identities drawn from the
  // durable registry — the SAME key survives service/app recreation, so a
  // lost-response retry after process death converges on the server-side
  // operation instead of funding twice.
  String _fundAction(String escrowId) => 'storefront.escrow.fund.$escrowId';
  final Map<String, FinancialOperationRef> _fundRefs = {};

  /// Resolves the durable operation instance for a service-owned financial
  /// flow (the SAME policy as [ApiClient.postFinancial]): retry the ref's
  /// instance when it is still pending and the body matches its recorded
  /// fingerprint; otherwise begin a GENUINELY NEW instance (the old record
  /// stays untouched and recoverable — never silently replaced).
  Future<DurableOperation> _resolveOperation({
    required String type,
    required String endpoint,
    required Map<String, dynamic> request,
    FinancialOperationRef? ref,
  }) async {
    final account = await _apiClient.operationAccount(failClosed: true);
    final retryId = ref?.operationId;
    if (retryId != null) {
      try {
        return await DurableOperationRegistry.retry(retryId,
            account: account, request: request);
      } on DurableOperationException {
        // Not retryable as that instance (terminal, or a materially
        // different request): a genuinely new action.
      }
    }
    final op = await DurableOperationRegistry.begin(
        account: account, type: type, endpoint: endpoint, request: request);
    if (ref != null) ref.operationId = op.operationId;
    return op;
  }

  /// Terminal completion / definitive pre-economic release of the ref's
  /// instance: retires THAT instance only and clears the ref.
  Future<void> _releaseOperation(FinancialOperationRef? ref) async {
    final id = ref?.operationId;
    if (id == null) return;
    await DurableOperationRegistry.retire(id,
        account: await _apiClient.operationAccount(failClosed: true));
    if (ref != null) ref.operationId = null;
  }

  final ApiClient _apiClient = ApiClient();

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

  /// Retrieve the published category-native experience contract separately
  /// from the legacy render model while that model remains intentionally
  /// focused on SDUI layout concerns.
  Future<Map<String, dynamic>?> getPublicExperience(String businessProfileId) async {
    final response = await _apiClient.get('/storefront/$businessProfileId/experience');
    if (response.statusCode == 404) return null;
    final data = _parseResponse(response);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Storefront experience response must be a JSON object.');
    }
    return data;
  }

  Future<Map<String, dynamic>> getPublicTheme(String businessProfileId) async {
    final response = await _apiClient.get('/storefront/$businessProfileId/theme');
    return _parseResponse(response) as Map<String, dynamic>;
  }

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

  Future<StorefrontLayout> saveDraft({required LayoutJson layoutJson, required String themeId, String? expectedUpdatedAt}) async {
    // LayoutJson intentionally models only the stable SDUI layout fields. The
    // backend now also stores the versioned Experience Blueprint in the same
    // draft snapshot, so preserve that opaque field when an editor save occurs.
    final currentResponse = await _apiClient.get('/storefront/me/draft');
    final currentData = _parseResponse(currentResponse);
    final currentLayout = currentData is Map<String, dynamic> ? currentData['layoutJson'] : null;
    final currentExperience = currentLayout is Map<String, dynamic> ? currentLayout['experience'] : null;

    final payload = layoutJson.toJson();
    if (currentExperience is Map<String, dynamic>) {
      payload['experience'] = currentExperience;
    }

    final response = await _apiClient.put('/storefront/me/draft', {
      'layoutJson': payload,
      'themeId': themeId,
      if (expectedUpdatedAt != null) 'expectedUpdatedAt': expectedUpdatedAt,
    });
    final data = _parseResponse(response);
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

  Future<StorefrontLayout> publish({String? expectedUpdatedAt}) async {
    final response = await _apiClient.post('/storefront/me/publish', {if (expectedUpdatedAt != null) 'expectedUpdatedAt': expectedUpdatedAt});
    final data = _parseResponse(response);
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

  Future<List<StorefrontLayoutVersion>> getHistory({int limit = 20}) async {
    final response = await _apiClient.get('/storefront/me/history?limit=$limit');
    final data = _parseResponse(response);
    return (data as List).map((v) => StorefrontLayoutVersion.fromJson(v as Map<String, dynamic>)).toList();
  }

  Future<StorefrontLayout> revertToVersion(String versionId, {String? expectedUpdatedAt}) async {
    final response = await _apiClient.post('/storefront/me/revert', {'versionId': versionId, if (expectedUpdatedAt != null) 'expectedUpdatedAt': expectedUpdatedAt});
    final data = _parseResponse(response);
    return StorefrontLayout.fromJson(data as Map<String, dynamic>);
  }

  Future<StorefrontLayout> applyTemplate(String templateId, {String? expectedUpdatedAt}) async {
    final response = await _apiClient.post('/storefront/me/apply-template', {'templateId': templateId, if (expectedUpdatedAt != null) 'expectedUpdatedAt': expectedUpdatedAt});
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

  Future<List<Map<String, dynamic>>> discoverStorefronts({String? query, String? category, int limit = 20, int offset = 0}) async {
    final params = <String, String>{'limit': limit.toString(), 'offset': offset.toString()};
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    if (category != null && category.trim().isNotEmpty) params['category'] = category.trim();
    final queryString = Uri(queryParameters: params).query;
    final response = await _apiClient.get('/storefront/discover?$queryString', requireAuth: false);
    final data = _parseResponse(response) as Map<String, dynamic>;
    final results = data['results'];
    if (results is! List) return const [];
    return results.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> getStorefrontProducts(String businessProfileId) async {
    final response = await _apiClient.get('/storefront/$businessProfileId/products', requireAuth: false);
    return _parseResponse(response) as Map<String, dynamic>;
  }

  /// r42 alignment: single-item storefront orders carry the SAME durable
  /// key lifecycle as [checkoutCart] (the backend /order route now honors the
  /// body `idempotencyKey` with a @unique-backed dedup). With [operationType]
  /// + [ref], a lost-response retry reuses the ref's unfinished instance (same
  /// key → the SAME logical order); a materially different product/quantity/
  /// notes body begins a genuinely new instance.
  Future<Map<String, dynamic>> placeStorefrontOrder({required String businessProfileId, required String productId, int quantity = 1, String? customerNotes, String? deliveryNotes, String? operationType, FinancialOperationRef? ref}) async {
    final body = {'productId': productId, 'quantity': quantity, if (customerNotes != null) 'customerNotes': customerNotes, if (deliveryNotes != null) 'deliveryNotes': deliveryNotes};
    if (operationType != null) {
      body['idempotencyKey'] = ''; // placeholder → rewritten to op.key
      final op = await _resolveOperation(
          type: operationType,
          endpoint: '/storefront/$businessProfileId/order',
          request: body,
          ref: ref);
      body['idempotencyKey'] = op.key;
    }
    final response = await _apiClient.post('/storefront/$businessProfileId/order', body);
    if (operationType == null) {
      return _parseResponse(response) as Map<String, dynamic>;
    }
    try {
      final parsed = _parseResponse(response) as Map<String, dynamic>;
      // Answered success — this order instance is complete.
      await _releaseOperation(ref);
      return parsed;
    } on StorefrontApiException catch (e) {
      // Disposition mirrors checkoutCart: definitive pre-economic 4xx
      // (everything except 401/409/429) → terminal; retained otherwise so a
      // same-key retry converges on the committed order.
      final definitive = e.statusCode >= 400 &&
          e.statusCode < 500 &&
          e.statusCode != 401 &&
          e.statusCode != 409 &&
          e.statusCode != 429;
      if (definitive) await _releaseOperation(ref);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> checkoutCart({required String businessProfileId, required List<Map<String, dynamic>> items, String? customerNotes, String? deliveryNotes, String? operationType, FinancialOperationRef? ref, String? idempotencyKey, String paymentMode = 'DIRECT'}) async {
    final body = {'items': items, if (customerNotes != null) 'customerNotes': customerNotes, if (deliveryNotes != null) 'deliveryNotes': deliveryNotes, 'paymentMode': paymentMode};
    // r42 OPERATION-INSTANCE MODEL: the body's legacy `idempotencyKey`
    // field carries the durable instance key. EITHER the caller passes a
    // PRE-ARMED key (idempotencyKey — the retail gateway path, lifecycle
    // owned by the caller) OR the service resolves a durable INSTANCE by
    // [operationType] + [ref] (the cart screen path, lifecycle owned by
    // this method): the ref's unfinished instance is retried with the
    // SAME key when the cart matches its fingerprint, and a materially
    // different cart begins a GENUINELY NEW instance — the old record is
    // never replaced or lost, it stays recoverable in the journal.
    if (idempotencyKey != null) {
      body['idempotencyKey'] = idempotencyKey;
    } else if (operationType != null) {
      // close-out review 2, finding 3: the wire request carries the
      // instance key as the legacy `idempotencyKey` BODY field. The stored
      // snapshot carries the SAME FIELD as a placeholder so a recovered
      // replay is byte-identical to the original wire request (the
      // exact-only recovery path rewrites it to the instance's key).
      body['idempotencyKey'] = ''; // placeholder → rewritten to op.key
      final op = await _resolveOperation(
          type: operationType,
          endpoint: '/storefront/$businessProfileId/checkout',
          request: body,
          ref: ref);
      body['idempotencyKey'] = op.key;
    }
    final response = await _apiClient.post('/storefront/$businessProfileId/checkout', body);
    if (idempotencyKey == null && operationType != null) {
      try {
        final parsed = _parseResponse(response) as Map<String, dynamic>;
        // Answered success — this checkout instance is complete.
        await _releaseOperation(ref);
        return parsed;
      } on StorefrontApiException catch (e) {
        // Disposition mirrors postFinancial: definitive pre-economic 4xx
        // (everything except 401/409/429) → the instance is terminal; the
        // backend released the claim. 401/409/429 → retained (the mutation
        // may be committed/in-flight; a same-key retry converges).
        final definitive = e.statusCode >= 400 &&
            e.statusCode < 500 &&
            e.statusCode != 401 &&
            e.statusCode != 409 &&
            e.statusCode != 429;
        if (definitive) await _releaseOperation(ref);
        rethrow;
      }
    }
    return _parseResponse(response) as Map<String, dynamic>;
  }

  /// Fund the escrow created by an escrow-protected storefront checkout.
  ///
  /// The backend's /escrow/fund endpoint performs step-up authentication and
  /// atomically moves the customer's USDC. We deliberately keep this separate
  /// from checkout creation so an order can safely exist in AWAITING_PAYMENT
  /// until the authenticated funding transaction commits.
  Future<void> fundEscrow({required String escrowId, String? totpToken, String? password}) async {
    // r42: escrow funding moves USDC — one Idempotency-Key per LOGICAL
    // funding action. Armed once and REUSED across retries of the same
    // funding (a lost response may mean the USDC already moved); retired
    // on any answered definitive outcome so a corrected retry is a new
    // action. An idempotency 409 keeps the key armed — the retry must
    // converge on the same server-side operation.
    final request = {
      'escrowId': escrowId,
      if (totpToken != null && totpToken.trim().isNotEmpty) 'totpToken': totpToken.trim(),
      if (password != null && password.isNotEmpty) 'password': password,
    };
    // r42 OPERATION-INSTANCE MODEL: funding is a GENUINELY NEW instance
    // per user action (per-escrow retry ref). The durable record is
    // persisted BEFORE the first request; retries through the same ref
    // reuse the SAME key.
    final ref = _fundRefs.putIfAbsent(
        escrowId, () => FinancialOperationRef());
    final op = await _resolveOperation(
        type: _fundAction(escrowId),
        endpoint: '/escrow/fund',
        request: request,
        ref: ref);
    try {
      final response = await _apiClient.post('/escrow/fund', request,
          idempotencyKey: op.key);
      await _releaseOperation(ref); // answered success
      _parseResponse(response);
    } on StorefrontApiException catch (e) {
      // Disposition mirrors postFinancial (see checkoutCart).
      final definitive = e.statusCode >= 400 &&
          e.statusCode < 500 &&
          e.statusCode != 401 &&
          e.statusCode != 409 &&
          e.statusCode != 429;
      if (definitive) await _releaseOperation(ref);
      rethrow;
    } on StorefrontConflictException catch (e) {
      // 409: an idempotency replay conflict keeps the durable instance; a
      // storefront draft conflict is unrelated to this action — release.
      if (!e.code.startsWith('IDEMPOTENCY')) {
        await _releaseOperation(ref);
      }
      rethrow;
    }
    // Network error / timeout: no server answer — the durable instance
    // stays pending, so the retry through the same ref reuses the SAME
    // key.
  }

  Future<Map<String, dynamic>> getMyOrders({String? status, int limit = 20, String? cursor}) async {
    final params = <String, String>{'limit': limit.toString(), if (status != null && status.isNotEmpty) 'status': status, if (cursor != null && cursor.isNotEmpty) 'cursor': cursor};
    final queryString = Uri(queryParameters: params).query;
    final response = await _apiClient.get('/storefront/me/orders?$queryString');
    return _parseResponse(response) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getOrderDetail(String orderId) async {
    final response = await _apiClient.get('/storefront/me/orders/$orderId');
    return _parseResponse(response) as Map<String, dynamic>;
  }

  dynamic _parseResponse(http.Response response) {
    if (response.statusCode >= 400) {
      Map<String, dynamic> body = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {}
      final code = body['code'];
      if (response.statusCode == 409 || code == 'STOREFRONT_DRAFT_CONFLICT') {
        throw StorefrontConflictException(message: body['message'] ?? 'This storefront draft changed elsewhere. Refresh before continuing.', code: code ?? 'STOREFRONT_DRAFT_CONFLICT');
      }
      throw StorefrontApiException(statusCode: response.statusCode, code: code?.toString(), message: body['message']?.toString() ?? 'Request failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) throw const FormatException('Storefront response must be a JSON object.');
    if (body['success'] == true) return body['data'];
    if (body['data'] != null) return body['data'];
    return body;
  }
}
