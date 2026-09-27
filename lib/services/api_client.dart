import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:azaman/config.dart';
import 'package:azaman/data/demo_interceptor.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

/// A centralized API client for handling HTTP requests to the Azaman backend.
/// Provides consistent error handling, authentication headers, timeouts,
/// and base URL management.
class ApiClient {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final http.Client _client;

  /// [client] is injectable so tests can pass a MockClient and assert the
  /// exact wire headers financial mutations produce.
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  bool _isRefreshing = false;
  Future<bool>? _refreshFuture;

  static String get baseUrl => AppConfig.apiUrl;

  Future<http.Response> _executeWithRefresh(
    Future<http.Response> Function() makeRequest,
  ) async {
    try {
      return await makeRequest();
    } on ApiException catch (e) {
      if (e.statusCode == 401 && e.code == 'TOKEN_EXPIRED') {
        final refreshed = await _tryRefreshToken();
        if (refreshed) return await makeRequest();
      }
      rethrow;
    }
  }

  Future<http.Response> get(String endpoint, {Map<String, String>? headers, bool requireAuth = true}) async {
    if (AppConfig.demoMode) { final m = DemoInterceptor.tryGet(endpoint); if (m != null) return m; }
    final requestHeaders = <String, String>{'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true', ...?headers};
    return _executeWithRefresh(() async {
      if (requireAuth) {
        final token = await _storage.read(key: 'auth_token');
        if (token != null) requestHeaders['Authorization'] = 'Bearer $token';
      }
      final response = await _client.get(Uri.parse('$baseUrl$endpoint'), headers: Map.of(requestHeaders)).timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    });
  }

  /// POST with the HTTP `Idempotency-Key` header — the single wire contract
  /// for every backend route protected by the r42 shared financial
  /// idempotency authority. Prefer [postFinancial] for money-moving calls.
  ///
  /// The key identifies the OPERATION INSTANCE, not one HTTP attempt:
  /// token-refresh retries inside [_executeWithRefresh] reuse the same
  /// captured header. Financial callers should use [postFinancial], which
  /// draws the key from the durable operation registry and owns the
  /// instance lifecycle; raw keys are for pre-armed gateway paths only.
  Future<http.Response> post(String endpoint, Map<String, dynamic> body,
      {Map<String, String>? headers, bool requireAuth = true, String? idempotencyKey}) async {
    if (AppConfig.demoMode) { final m = DemoInterceptor.tryPost(endpoint, body); if (m != null) return m; }
    final requestHeaders = <String, String>{'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true', ...?headers};
    if (idempotencyKey != null) {
      if (idempotencyKey.trim().isEmpty) {
        throw ArgumentError('idempotencyKey must be a non-empty string when provided');
      }
      requestHeaders['Idempotency-Key'] = idempotencyKey.trim();
    }
    return _executeWithRefresh(() async {
      if (requireAuth) {
        final token = await _storage.read(key: 'auth_token');
        if (token != null) requestHeaders['Authorization'] = 'Bearer $token';
      }
      final response = await _client.post(Uri.parse('$baseUrl$endpoint'), headers: Map.of(requestHeaders), body: jsonEncode(body)).timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    });
  }

  /// The account namespace for durable operations: the signed-in user's
  /// id from secure storage, or 'anon' when unavailable (demo mode, tests,
  /// pre-auth). Records are namespaced per account so one user's pending
  /// operation can never become another's.
  Future<String> operationAccount() async {
    try {
      final userId = await _storage.read(key: 'user_id');
      if (userId != null && userId.trim().isNotEmpty) return userId;
    } catch (_) {
      // Secure storage unavailable (tests / not-yet-bound engine): the
      // anonymous namespace is a safe fallback — it is still a STABLE,
      // isolated namespace for the device.
    }
    return 'anon';
  }

  /// Financial mutation POST: the backend r42 authority REQUIRES an
  /// Idempotency-Key on these routes and rejects keyless requests before
  /// the handler runs. This helper makes the requirement impossible to
  /// forget — it refuses to send a money-moving request without the key.
  ///
  /// r42 OPERATION-INSTANCE MODEL (independent review, 2026-09-27):
  /// [operationType] names the operation TYPE / recovery namespace
  /// ("withdrawal.fiat", "trade.accept.<id>", ...) — it NEVER identifies an
  /// instance on its own. The instance identity is a durable
  /// [DurableOperation] record created by [DurableOperationRegistry.begin]
  /// and PERSISTED BEFORE the first request leaves the device.
  ///
  /// [ref] is the caller's per-flow retry handle:
  ///   - ref == null            → begin a NEW instance (fresh key).
  ///   - ref.operationId == null → begin a NEW instance (fresh key) and
  ///     write the instance id into ref before sending.
  ///   - ref.operationId != null → RETRY that instance: the SAME key is
  ///     reused when the body matches the recorded fingerprint. If the
  ///     body has materially changed (or the instance already reached a
  ///     terminal state), this call is treated as a GENUINELY NEW action:
  ///     a fresh instance is begun and the old record is left untouched
  ///     and recoverable — never silently replaced.
  ///
  /// Starting operation B must never disturb outstanding operation A, even
  /// for the same type: every instance is an independent durable record.
  ///
  /// Disposition (the helper owns the lifecycle, mirroring the backend):
  ///       2xx                  → retire (authoritative response received;
  ///                              ref cleared)
  ///       definitive 4xx*      → retire (pre-economic; the backend
  ///                              authority released the claim; ref
  ///                              cleared) *every 4xx except 401/409/429
  ///       401/409/429, 5xx     → retain (may be committed/in-flight — a
  ///                              same-key retry is exactly the protection;
  ///                              ref kept armed)
  ///       network error/timeout → retain (instance stays pending; ref
  ///                              kept armed)
  ///
  /// Where the body carries a legacy in-body identity (clientRequestId),
  /// the helper OVERWRITES it with the instance key: one logical operation,
  /// one identity — in the durable record, in the header, and in the body.
  Future<http.Response> postFinancial(String endpoint, Map<String, dynamic> body,
      {required String operationType,
      FinancialOperationRef? ref,
      bool requireAuth = true,
      Map<String, String>? headers}) async {
    if (operationType.trim().isEmpty) {
      throw ArgumentError('Financial mutations require a non-empty operationType');
    }
    // Demo mode short-circuits before economics: no durable entry needed.
    if (AppConfig.demoMode) {
      final m = DemoInterceptor.tryPost(endpoint, body);
      if (m != null) return m;
    }
    final account = await operationAccount();
    final body_ = Map<String, dynamic>.from(body);

    // Resolve the instance: retry the ref's instance when it is still
    // pending and the body matches; otherwise begin a genuinely new one.
    DurableOperation op;
    final retryId = ref?.operationId;
    if (retryId != null) {
      try {
        op = await DurableOperationRegistry.retry(retryId,
            account: account, request: body_);
      } on DurableOperationNotFoundException {
        // Already terminal (or never existed / another namespace): there
        // is no outstanding claim — this is a genuinely new action.
        op = await DurableOperationRegistry.begin(
            account: account,
            type: operationType,
            endpoint: endpoint,
            request: body_);
      } on DurableOperationFingerprintMismatchException {
        // Materially different request: a genuinely NEW instance. The
        // old one stays pending, untouched and recoverable.
        op = await DurableOperationRegistry.begin(
            account: account,
            type: operationType,
            endpoint: endpoint,
            request: body_);
      }
    } else {
      op = await DurableOperationRegistry.begin(
          account: account,
          type: operationType,
          endpoint: endpoint,
          request: body_);
    }

    // The durable record exists now — arm the caller's handle BEFORE the
    // request leaves the device, so a failure here is a RETRY of this
    // instance on the caller's next attempt.
    if (ref != null) ref.operationId = op.operationId;

    final key = op.key;
    if (body_.containsKey('clientRequestId')) {
      body_['clientRequestId'] = key; // one identity, everywhere
    }
    try {
      final response = await post(endpoint, body_,
          headers: headers, requireAuth: requireAuth, idempotencyKey: key);
      // 2xx: the authoritative outcome is in hand — terminal.
      await DurableOperationRegistry.retire(op.operationId, account: account);
      if (ref != null) ref.operationId = null;
      return response;
    } on ApiException catch (e) {
      // post() throws ApiException for every answered non-2xx status; the
      // durable disposition rides the SAME contract as the wire statuses:
      //   definitive pre-economic 4xx (everything except 401/409/429) →
      //     the backend authority released the claim; a corrected retry
      //     is a genuinely new action → retire.
      //   401 / 409 / 429 → retained (auth incomplete / same action in
      //     flight / throttled retry of the same action).
      final code = e.statusCode;
      final definitivePreEconomic4xx =
          code >= 400 && code < 500 && code != 401 && code != 409 && code != 429;
      final unknownServerState = code >= 500;
      if (definitivePreEconomic4xx && !unknownServerState) {
        await DurableOperationRegistry.retire(op.operationId, account: account);
        if (ref != null) ref.operationId = null;
      }
      // 401 / 409 / 429 AND every 5xx: the instance stays pending — the
      // mutation may have committed; the retry MUST reuse the same key.
      rethrow;
    } catch (_) {
      // Timeout / connection loss: the operation may have committed
      // server-side. The durable instance survives — the retry (through
      // the same ref) reuses the same key.
      rethrow;
    }
  }

  Future<http.Response> put(String endpoint, Map<String, dynamic> body, {Map<String, String>? headers, bool requireAuth = true}) async {
    if (AppConfig.demoMode) { final m = DemoInterceptor.tryPut(endpoint, body); if (m != null) return m; }
    final requestHeaders = <String, String>{'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true', ...?headers};
    return _executeWithRefresh(() async {
      if (requireAuth) {
        final token = await _storage.read(key: 'auth_token');
        if (token != null) requestHeaders['Authorization'] = 'Bearer $token';
      }
      final response = await _client.put(Uri.parse('$baseUrl$endpoint'), headers: Map.of(requestHeaders), body: jsonEncode(body)).timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    });
  }

  Future<http.Response> patch(String endpoint, {Map<String, dynamic>? body, Map<String, String>? headers, bool requireAuth = true}) async {
    if (AppConfig.demoMode) { final m = DemoInterceptor.tryPatch(endpoint); if (m != null) return m; }
    final requestHeaders = <String, String>{'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true', ...?headers};
    return _executeWithRefresh(() async {
      if (requireAuth) {
        final token = await _storage.read(key: 'auth_token');
        if (token != null) requestHeaders['Authorization'] = 'Bearer $token';
      }
      final response = await _client.patch(Uri.parse('$baseUrl$endpoint'), headers: Map.of(requestHeaders), body: body != null ? jsonEncode(body) : null).timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    });
  }

  Future<http.Response> delete(String endpoint, {Map<String, String>? headers, bool requireAuth = true}) async {
    if (AppConfig.demoMode) { final m = DemoInterceptor.tryDelete(endpoint); if (m != null) return m; }
    final requestHeaders = <String, String>{'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true', ...?headers};
    return _executeWithRefresh(() async {
      if (requireAuth) {
        final token = await _storage.read(key: 'auth_token');
        if (token != null) requestHeaders['Authorization'] = 'Bearer $token';
      }
      final response = await _client.delete(Uri.parse('$baseUrl$endpoint'), headers: Map.of(requestHeaders)).timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    });
  }

  Future<http.Response> multipart(String endpoint, http.MultipartRequest request) async {
    return _executeWithRefresh(() async {
      final token = await _storage.read(key: 'auth_token');
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
      final responseData = await http.Response.fromStream(streamedResponse);
      return _handleResponse(responseData);
    });
  }

  http.Response _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return response;
    if (response.statusCode == 429) throw ApiException(message: 'Slow down! Too many requests. Please wait a moment and try again.', statusCode: 429);
    var message = 'Request failed with status ${response.statusCode}';
    List<String>? errors;
    String? code;
    try {
      final errorData = jsonDecode(response.body);
      if (errorData is Map<String, dynamic>) {
        message = errorData['message']?.toString() ?? message;
        code = errorData['code']?.toString();
        if (errorData['errors'] is List) errors = List<String>.from(errorData['errors']);
      }
    } on FormatException {}
    throw ApiException(message: message, statusCode: response.statusCode, errors: errors, code: code);
  }

  Future<bool> _tryRefreshToken() async {
    if (_isRefreshing && _refreshFuture != null) return _refreshFuture!;
    _isRefreshing = true;
    _refreshFuture = _doRefresh().whenComplete(() { _isRefreshing = false; _refreshFuture = null; });
    return _refreshFuture!;
  }

  Future<bool> _doRefresh() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null || refreshToken.isEmpty) return false;
      final response = await _client.post(Uri.parse('$baseUrl/auth/refresh'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refreshToken': refreshToken})).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final newAccess = (body['accessToken'] ?? body['token'])?.toString();
        final newRefresh = body['refreshToken']?.toString();
        if (newAccess == null || newAccess.isEmpty) return false;
        await _storage.write(key: 'auth_token', value: newAccess);
        if (newRefresh != null && newRefresh.isNotEmpty) await _storage.write(key: 'refresh_token', value: newRefresh);
        try {
          await SocketService.instance.forceReconnect();
        } catch (e) {
          debugPrint('[ApiClient] Socket re-auth reconnect failed: $e');
        }
        debugPrint('[ApiClient] Token silently refreshed and socket auth rotated.');
        return true;
      }
      await clearAuthData();
      return false;
    } catch (e) {
      debugPrint('[ApiClient] Token refresh error: $e');
      return false;
    }
  }

  Future<bool> isAuthenticated() async {
    final token = await _storage.read(key: 'auth_token');
    final userId = await _storage.read(key: 'user_id');
    if (token == null || userId == null) return false;
    try { await get('/auth/me/$userId'); return true; } catch (e) { debugPrint('[ApiClient] isAuthenticated check failed: $e'); return false; }
  }

  Future<void> logout() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _client.post(Uri.parse('$baseUrl/auth/logout'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refreshToken': refreshToken}),).timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('[ApiClient] Server logout failed (local logout continues): $e');
      }
    }
    await clearAuthData();
  }

  Future<void> clearAuthData() async {
    await Future.wait([
      _storage.delete(key: 'auth_token'),
      _storage.delete(key: 'refresh_token'),
      _storage.delete(key: 'user_id'),
      _storage.delete(key: 'user_role'),
    ]);
  }
}

/// The caller's durable retry handle for ONE operation flow.
///
/// [ApiClient.postFinancial] writes the live operation-instance id into the
/// ref BEFORE the first request leaves the device and clears it when the
/// operation reaches a terminal state. Pass the SAME ref on the next
/// attempt of the SAME flow — postFinancial retries the SAME instance and
/// reuses the SAME key (tap-again-to-safely-retry). A materially different
/// body automatically begins a genuinely new instance and leaves the old
/// one untouched and recoverable.
///
/// The ref is the in-session link; the durable record is the process-death
/// horizon. After process death, recover unfinished instances with
/// [DurableOperationRegistry.pending] and seed a ref with an instance id
/// (see [adoptPending]) to resume them.
class FinancialOperationRef {
  /// The live operation instance id, armed by postFinancial. Non-null while
  /// an instance of this flow is unresolved (may still have committed
  /// server-side); null after terminal completion / definitive release.
  String? operationId;

  FinancialOperationRef({this.operationId});

  /// Process-death recovery: adopt the NEWEST unfinished instance of
  /// [type] in [account]'s namespace (if any) so the user's next attempt of
  /// the same body resumes THAT instance (same key) instead of beginning a
  /// duplicate. A materially different body begins a new instance; the
  /// adopted record is never lost.
  static Future<FinancialOperationRef> adoptPending(
      {required String account, required String type}) async {
    final pending = await DurableOperationRegistry.pending(
        account: account, type: type);
    return FinancialOperationRef(
        operationId: pending.isEmpty ? null : pending.first.operationId);
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String? code;
  final List<String>? errors;
  ApiException({required this.message, required this.statusCode, this.errors, this.code});
  @override
  String toString() => errors != null && errors!.isNotEmpty ? '$message: ${errors!.join(', ')}' : message;
}

final ApiClient apiClient = ApiClient();
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
