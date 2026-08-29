import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:azaman/config.dart';
import 'package:azaman/data/demo_interceptor.dart';

/// A centralized API client for handling HTTP requests to the Azaman backend.
/// Provides consistent error handling, authentication headers, timeouts,
/// and base URL management.
class ApiClient {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final http.Client _client = http.Client();

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

  Future<http.Response> post(String endpoint, Map<String, dynamic> body, {Map<String, String>? headers, bool requireAuth = true}) async {
    if (AppConfig.demoMode) { final m = DemoInterceptor.tryPost(endpoint, body); if (m != null) return m; }
    final requestHeaders = <String, String>{'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true', ...?headers};
    return _executeWithRefresh(() async {
      if (requireAuth) {
        final token = await _storage.read(key: 'auth_token');
        if (token != null) requestHeaders['Authorization'] = 'Bearer $token';
      }
      final response = await _client.post(Uri.parse('$baseUrl$endpoint'), headers: Map.of(requestHeaders), body: jsonEncode(body)).timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    });
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
        debugPrint('[ApiClient] Token silently refreshed.');
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

  /// Best-effort server-side refresh-token revocation. Local credentials are
  /// always cleared by this method, even when the backend is unreachable.
  Future<void> logout() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _client.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refreshToken}),
        ).timeout(const Duration(seconds: 10));
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

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String? code;
  final List<String>? errors;
  ApiException({required this.message, required this.statusCode, this.code, this.errors});
  @override
  String toString() => errors != null && errors!.isNotEmpty ? '$message: ${errors!.join(', ')}' : message;
}

final ApiClient apiClient = ApiClient();
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());