// =============================================================================
// Storefront Service
//
// API client for storefront endpoints. Handles all HTTP communication with
// the backend storefront SDUI system.
// =============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
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

/// Failure classification for the LIVE durable storefront economic
/// paths (checkoutCart / placeStorefrontOrder via [operationType] + [ref]).
/// Deep-dive step 2 (2026-10-01): callers must not treat every exception
/// as one generic "order failed" — the class tells the UI which action is
/// economically safe:
///
/// - [StorefrontFailureClass.definitivePreEconomic] — the backend PROVED
///   no economic mutation happened (validation / business 4xx). The order
///   did NOT go through; safe to correct the cart and retry. The durable
///   instance was already retired by the disposition (step 1), so a
///   corrected retry begins a new identity — never blind-repeat the same
///   request.
/// - [StorefrontFailureClass.authenticationRequired] — a 401 that survived
///   ApiClient's automatic token refresh. Re-auth, then retry the same
///   logical operation (instance stays armed, same key).
/// - [StorefrontFailureClass.rateLimited] — 429. Wait, then retry the same
///   logical operation (instance stays armed, same key).
/// - [StorefrontFailureClass.domainConflict] — 409: the backend answered
///   that this durable key was already used for DIFFERENT cart contents.
///   Neither a transport failure nor safely retryable: reconcile against
///   the existing order (check orders / refresh) before placing again.
/// - [StorefrontFailureClass.ambiguousOrUnknown] — transport loss,
///   timeout, 408/425 (answered but not proven pre-economic; consistent
///   with StorefrontApiException.isRetryable), 5xx, or a malformed 2xx
///   payload (including a 2xx without the minimum authoritative order
///   shape — non-empty id + orderRef). The order MAY have
///   committed; the durable instance stays armed and a retry of the SAME
///   logical operation reuses the SAME key so the backend converges
///   instead of duplicating. The UI must not claim the order "failed".
///
/// This classification is a read-only projection for callers and the UI.
/// It never decides the durable identity lifecycle — the in-method
/// disposition and DurableOperationRegistry own that (deep-dive step 1).
enum StorefrontFailureClass {
  definitivePreEconomic,
  authenticationRequired,
  rateLimited,
  domainConflict,
  ambiguousOrUnknown,
}

extension StorefrontFailureClassIsUnconfirmed on StorefrontFailureClass {
  /// True when the economic outcome is UNPROVEN — the order may have
  /// committed. UI must warn (check your orders) instead of asserting
  /// the order definitely failed.
  bool get isUnconfirmed => this == StorefrontFailureClass.ambiguousOrUnknown;
}

class StorefrontService {
  /// [apiClient] is injectable so tests can pass a recording client and
  /// assert the exact durable-identity wire behaviour of the production
  /// checkout path. Production callers use the default.
  StorefrontService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

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

  /// r42 disposition, shared by the durable storefront economic paths
  /// (checkoutCart / placeStorefrontOrder): definitive pre-economic 4xx —
  /// everything except 401 / 408 / 409 / 425 / 429 — releases the ref's
  /// instance; every other answered outcome (and every transport loss)
  /// stays armed for a same-key retry.
  ///
  /// The 2026-10-01 recovery audit found the disposition catch previously
  /// listened for StorefrontApiException, which ApiClient._handleResponse
  /// makes UNREACHABLE on the error path: ApiClient.post throws its own
  /// ApiException for every non-2xx BEFORE StorefrontService ever sees the
  /// response. The classification now runs on the type that actually
  /// flows (parity with ApiClient.postFinancial); the StorefrontApiException
  /// clause is kept as defense-in-depth for any direct-response caller.
  ///
  /// 408 (request timeout) and 425 (too early) are EXCLUDED from terminal
  /// disposition: StorefrontApiException.isRetryable treats both as
  /// retryable, and for the durable economic path an answered 408/425 does
  /// not prove the backend never received the request (a proxy/gateway can
  /// answer after the upstream commit). Without a concrete backend proof
  /// that these statuses are always pre-economic, the safe default keeps
  /// the instance ARMED: classify ambiguousOrUnknown, converge via the
  /// fingerprint-checked same-key replay (independent review, 2026-10-01).
  /// Minimum authoritative order shape guaranteed by the live backend on
  /// BOTH success paths and required by the production caller's
  /// confirmation/recovery contract (CartScreen reads the orderRef):
  /// a non-empty string `id` AND a non-empty string `orderRef`.
  /// Traced in AZM-backend routes/storefrontRoutes.js: the fresh 201 is
  /// `data:{order}` = the created BusinessOrder row (id + orderRef
  /// generated at commit); the exact-replay 200 is `data:{order,
  /// idempotent:true}` where order = {id, orderRef, status}. Anything less
  /// is NOT a confirmed checkout: treat as malformed success → the caller
  /// never claims completion, the durable instance stays armed.
  static bool _carriesAuthoritativeOrder(Map<String, dynamic> parsed) {
    final order = parsed['order'];
    if (order is! Map<String, dynamic>) return false;
    final id = order['id'];
    final orderRef = order['orderRef'];
    return id is String &&
        id.isNotEmpty &&
        orderRef is String &&
        orderRef.isNotEmpty;
  }

  static bool _isDefinitivePreEconomic(int statusCode) =>
      statusCode >= 400 &&
      statusCode < 500 &&
      statusCode != 401 &&
      statusCode != 408 &&
      statusCode != 409 &&
      statusCode != 425 &&
      statusCode != 429;

  /// Maps a thrown failure of the live durable storefront economic paths
  /// to its economic class. Pure projection: reuses the SAME definitive
  /// predicate as the disposition ([_isDefinitivePreEconomic]), so the
  /// classification can never contradict the identity lifecycle.
  ///
  /// Traced wire semantics (backend routes/storefrontRoutes.js, 2026-10-01):
  /// - 401 'TOKEN_EXPIRED' is already auto-refreshed inside
  ///   ApiClient._executeWithRefresh; a 401 surfacing HERE means the
  ///   refresh failed or the account is genuinely unauthorized.
  /// - 409 on these routes is a FINGERPRINT-MISMATCH answer: the durable
  ///   key was already used for different cart contents. (An exact replay
  ///   answers 200 with `idempotent: true` — the success path, not 409.)
  /// - 400/403/404 are the backend's explicit pre-economic validations
  ///   (empty items, >50 items, paused business, unavailable product,
  ///   escrow not offered). Residual gap, recorded in the deep-dive: the
  ///   backend `wrap` catch-all also surfaces uncaught internal errors as
  ///   400 with no machine-readable code — in current source every such
  ///   throw precedes the order commit, so 400 stays de-facto
  ///   pre-economic, but that contract is implicit; the backend should
  ///   make it explicit (dedicated status/code) rather than Flutter
  ///   guessing.
  /// - 408 / 425: answered, but the answer does not prove the backend
  ///   never received the request (gateway may answer after the upstream
  ///   commit). Same fail-safe as 5xx: ambiguousOrUnknown, instance ARMED
  ///   (consistency with StorefrontApiException.isRetryable).
  /// - 5xx / transport loss / malformed 2xx payload: outcome UNPROVEN —
  ///   always [StorefrontFailureClass.ambiguousOrUnknown], fail-safe.
  static StorefrontFailureClass classifyStorefrontFailure(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 401) {
        return StorefrontFailureClass.authenticationRequired;
      }
      if (error.statusCode == 429) return StorefrontFailureClass.rateLimited;
      if (error.statusCode == 409) return StorefrontFailureClass.domainConflict;
      if (_isDefinitivePreEconomic(error.statusCode)) {
        return StorefrontFailureClass.definitivePreEconomic;
      }
      return StorefrontFailureClass.ambiguousOrUnknown; // 5xx / other
    }
    if (error is StorefrontApiException) {
      // Direct-response paths (defense-in-depth; ApiClient.post maps every
      // non-2xx to ApiException before the service parses anything).
      if (error.statusCode == 409) return StorefrontFailureClass.domainConflict;
      if (_isDefinitivePreEconomic(error.statusCode)) {
        return StorefrontFailureClass.definitivePreEconomic;
      }
      return StorefrontFailureClass.ambiguousOrUnknown;
    }
    if (error is StorefrontConflictException) {
      return StorefrontFailureClass.domainConflict;
    }
    // FormatException (malformed 2xx payload), TimeoutException, http
    // ClientException / SocketException, and anything unrecognized: the
    // economic outcome is UNPROVEN. Fail safe as unknown — never "safe to
    // retry blindly", never "definitive".
    return StorefrontFailureClass.ambiguousOrUnknown;
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

  final ApiClient _apiClient;

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
    if (operationType == null) {
      final response = await _apiClient.post('/storefront/$businessProfileId/order', body);
      return _parseResponse(response) as Map<String, dynamic>;
    }
    // 2026-10-01 recovery audit: the POST must be INSIDE the disposition
    // scope (as in ApiClient.postFinancial). Previously it sat outside the
    // try, so no answered error could ever reach the disposition — a
    // definitive 4xx silently left the instance armed.
    try {
      final response = await _apiClient.post('/storefront/$businessProfileId/order', body);
      final parsed = _parseResponse(response) as Map<String, dynamic>;
      // Malformed-success guard (deep-dive step 2, tightened by
      // independent review): a 2xx must carry an AUTHORITATIVE order —
      // not merely an `order` key. {order: {}} would previously pass, be
      // surfaced as success, retire the instance and let the caller treat
      // an unconfirmed order as placed. Anything short of the minimum
      // authoritative shape (non-empty id + orderRef) is an unknown
      // economic state: never success, never definitive; the durable
      // instance stays armed for a same-key retry.
      if (!_carriesAuthoritativeOrder(parsed)) {
        throw const FormatException(
            'Order response was successful but carried no authoritative '
            'order result (id/orderRef).');
      }
      // Answered success — this order instance is complete.
      await _releaseOperation(ref);
      return parsed;
    } on ApiException catch (e) {
      // Disposition mirrors checkoutCart / postFinancial: definitive
      // pre-economic 4xx (everything except 401/408/409/425/429) →
      // terminal;
      // retained otherwise so a same-key retry converges on the committed
      // order. ApiClient.post throws ApiException for every non-2xx — this
      // is the type that actually reaches the seam.
      if (_isDefinitivePreEconomic(e.statusCode)) {
        await _releaseOperation(ref);
      }
      rethrow;
    } on StorefrontApiException catch (e) {
      // Defense-in-depth (unreachable via ApiClient.post today): same
      // disposition if a direct-response path ever throws here.
      if (_isDefinitivePreEconomic(e.statusCode)) {
        await _releaseOperation(ref);
      }
      rethrow;
    }
  }

  /// CANONICAL IDENTITY BOUNDARY (retail checkout recovery, 2026-10-01
  /// audit): one logical cart checkout owns ONE durable identity, and the
  /// ONLY authoritative path to it is [operationType] + [ref] →
  /// [_resolveOperation] → [DurableOperationRegistry] (account-fenced
  /// journal, request fingerprint, retry-same-instance, new-instance on a
  /// materially different cart, disposition on answered outcomes). The
  /// LIFETIME owner is the UI/application operation — CartScreen's
  /// [FinancialOperationRef] — never this service or a gateway.
  ///
  /// The [idempotencyKey] parameter is the LEGACY PRE-ARMED transport kept
  /// for the non-production retail gateway chain
  /// (RetailCheckoutController → RetailCheckoutOperation →
  /// StorefrontRetailCheckoutGateway — unreachable from production UI
  /// since TASK-012). It journals nothing, recovers nothing and disposes
  /// nothing: a key armed this way has no retry/recovery semantics. It
  /// must never become a second identity path for production callers.
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
    if (idempotencyKey == null && operationType != null) {
      // 2026-10-01 recovery audit: the POST must be INSIDE the disposition
      // scope (as in ApiClient.postFinancial). Previously it sat outside the
      // try, so no answered error could ever reach the disposition — a
      // definitive 4xx silently left the instance armed.
      try {
        final response = await _apiClient.post('/storefront/$businessProfileId/checkout', body);
        final parsed = _parseResponse(response) as Map<String, dynamic>;
        // Malformed-success guard (deep-dive step 2, tightened by
        // independent review): an answered 2xx whose payload does not carry
        // an AUTHORITATIVE order — a non-empty id + orderRef, the minimum
        // shape both backend success paths guarantee and the caller's
        // confirmation contract requires — is an UNKNOWN economic state:
        // the order may or may not have committed. Never surface it as
        // success (the caller would clear the cart and claim completion on
        // an unconfirmed order) and never as a definitive failure. The
        // FormatException stays outside every disposition clause → the
        // durable instance stays armed for a same-key retry;
        // classifyStorefrontFailure maps it to ambiguousOrUnknown.
        if (!_carriesAuthoritativeOrder(parsed)) {
          throw const FormatException(
              'Checkout response was successful but carried no authoritative '
              'order result (id/orderRef).');
        }
        // Answered success — this checkout instance is complete.
        await _releaseOperation(ref);
        return parsed;
      } on ApiException catch (e) {
        // Disposition mirrors postFinancial: definitive pre-economic 4xx
        // (everything except 401/408/409/425/429) → the instance is
        // terminal; the backend released the claim. 401/408/409/425/429
        // (and every 5xx and
        // transport loss) → retained (the mutation may be committed/
        // in-flight; a same-key retry converges).
        // 2026-10-01 recovery audit: ApiClient.post throws ApiException
        // for every non-2xx BEFORE StorefrontService parses anything, so
        // the classification must run on THIS type — the previous
        // StorefrontApiException catch never fired, silently keeping
        // definitive-failure instances armed.
        if (_isDefinitivePreEconomic(e.statusCode)) {
          await _releaseOperation(ref);
        }
        rethrow;
      } on StorefrontApiException catch (e) {
        // Defense-in-depth (unreachable via ApiClient.post today): same
        // disposition if a direct-response path ever throws here.
        if (_isDefinitivePreEconomic(e.statusCode)) {
          await _releaseOperation(ref);
        }
        rethrow;
      }
    }
    // Legacy paths (pre-armed key or no identity at all): no durable
    // lifecycle — plain transport.
    final response = await _apiClient.post('/storefront/$businessProfileId/checkout', body);
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
