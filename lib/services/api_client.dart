import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:azaman/config.dart';

/// A centralized API client for handling HTTP requests to the Azaman backend.
/// Provides consistent error handling, authentication headers, timeouts,
/// and base URL management.
///
/// Usage:
///   final response = await apiClient.get('/auth/me/1');
///   final response = await apiClient.post('/auth/login', {'email': '...', 'password': '...'});
class ApiClient {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final http.Client _client = http.Client();

  // Token refresh state — prevents concurrent refresh storms.
  // Only one refresh call is in-flight at a time; all others wait for it.
  bool _isRefreshing = false;
  Future<bool>? _refreshFuture;

  /// Base API URL from configuration (resolved at runtime, not compile-time).
  static String get baseUrl => AppConfig.apiUrl;


  // ── Retry-on-token-expired wrapper ─────────────────────────────────────────
  // Executes [makeRequest], and if it throws ApiException with code
  // TOKEN_EXPIRED (401), attempts a silent refresh then retries exactly once.
  Future<http.Response> _executeWithRefresh(
    Future<http.Response> Function() makeRequest,
  ) async {
    try {
      return await makeRequest();
    } on ApiException catch (e) {
      if (e.statusCode == 401 && e.code == 'TOKEN_EXPIRED') {
        final refreshed = await _tryRefreshToken();
        if (refreshed) {
          // One retry with the new access token.
          return await makeRequest();
        }
        // Refresh failed — re-throw so the UI shows the login screen.
        rethrow;
      }
      rethrow;
    }
  }

  /// Generic GET request with authentication
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    final Map<String, String> requestHeaders = {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      ...?headers,
    };

    return _executeWithRefresh(() async {
      if (requireAuth) {
        final token = await _storage.read(key: 'auth_token');
        if (token != null) requestHeaders['Authorization'] = 'Bearer $token';
      }
      final response = await _client
          .get(Uri.parse('$baseUrl$endpoint'), headers: Map.of(requestHeaders))
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    });
  }

  /// Generic POST request with authentication
  Future<http.Response> post(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    final Map<String, String> requestHeaders = {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      ...?headers,
    };

    return _executeWithRefresh(() async {
      if (requireAuth) {
        final token = await _storage.read(key: 'auth_token');
        if (token != null) requestHeaders['Authorization'] = 'Bearer $token';
      }
      final response = await _client
          .post(Uri.parse('$baseUrl$endpoint'),
              headers: Map.of(requestHeaders), body: jsonEncode(body))
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    });
  }

  /// Generic PUT request with authentication
  Future<http.Response> put(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    final Map<String, String> requestHeaders = {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      ...?headers,
    };

    return _executeWithRefresh(() async {
      if (requireAuth) {
        final token = await _storage.read(key: 'auth_token');
        if (token != null) requestHeaders['Authorization'] = 'Bearer $token';
      }
      final response = await _client
          .put(Uri.parse('$baseUrl$endpoint'),
              headers: Map.of(requestHeaders), body: jsonEncode(body))
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    });
  }

  /// Generic PATCH request with authentication
  Future<http.Response> patch(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    final Map<String, String> requestHeaders = {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      ...?headers,
    };

    return _executeWithRefresh(() async {
      if (requireAuth) {
        final token = await _storage.read(key: 'auth_token');
        if (token != null) requestHeaders['Authorization'] = 'Bearer $token';
      }
      final response = await _client
          .patch(Uri.parse('$baseUrl$endpoint'),
              headers: Map.of(requestHeaders),
              body: body != null ? jsonEncode(body) : null)
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    });
  }

  /// Generic DELETE request with authentication
  Future<http.Response> delete(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    final Map<String, String> requestHeaders = {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      ...?headers,
    };

    return _executeWithRefresh(() async {
      if (requireAuth) {
        final token = await _storage.read(key: 'auth_token');
        if (token != null) requestHeaders['Authorization'] = 'Bearer $token';
      }
      final response = await _client
          .delete(Uri.parse('$baseUrl$endpoint'), headers: Map.of(requestHeaders))
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    });
  }

  /// Handle multipart/form-data requests for file uploads
  Future<http.Response> multipart(
    String endpoint,
    http.MultipartRequest request,
  ) async {
    return _executeWithRefresh(() async {
      final token = await _storage.read(key: 'auth_token');
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final responseData = await http.Response.fromStream(streamedResponse);
      return _handleResponse(responseData);
    });
  }

  /// Response handler with common error checking.
  ///
  /// On success (2xx): returns the response as-is.
  /// On 429: throws a user-friendly rate-limit message.
  /// On other errors: parses the backend error message or falls back to generic.
  http.Response _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    // Rate limiting — friendly message
    if (response.statusCode == 429) {
      throw ApiException(
        message: 'Slow down! Too many requests. Please wait a moment and try again.',
        statusCode: 429,
      );
    }

    // Parse error from backend JSON body
    String message = 'Request failed with status \${response.statusCode}';
    List<String>? errors;
    String? code;

    try {
      final errorData = jsonDecode(response.body);
      if (errorData is Map<String, dynamic>) {
        message = errorData['message']?.toString() ?? message;
        code    = errorData['code']?.toString();
        if (errorData['errors'] is List) {
          errors = List<String>.from(errorData['errors']);
        }
      }
    } on FormatException {
      // Body is not JSON — use the generic message
    }

    throw ApiException(
      message: message,
      statusCode: response.statusCode,
      errors: errors,
      code: code,
    );
  }

  // ── Silent token refresh ────────────────────────────────────────────────────
  // Called when a request gets a 401 TOKEN_EXPIRED. Tries to exchange the
  // stored refresh token for a new access token via POST /auth/refresh.
  // Returns true if refresh succeeded (caller should retry the original
  // request), false if the refresh token itself is gone/expired (caller
  // should navigate to login).
  Future<bool> _tryRefreshToken() async {
    // Collapse concurrent refresh attempts into a single in-flight call.
    if (_isRefreshing && _refreshFuture != null) {
      return _refreshFuture!;
    }
    _isRefreshing = true;
    _refreshFuture = _doRefresh().whenComplete(() {
      _isRefreshing = false;
      _refreshFuture = null;
    });
    return _refreshFuture!;
  }

  Future<bool> _doRefresh() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null || refreshToken.isEmpty) return false;

      final response = await _client
          .post(
            Uri.parse('\$baseUrl/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final newAccess  = (body['accessToken'] ?? body['token'])?.toString();
        final newRefresh = body['refreshToken']?.toString();
        if (newAccess == null || newAccess.isEmpty) return false;

        await _storage.write(key: 'auth_token',    value: newAccess);
        if (newRefresh != null && newRefresh.isNotEmpty) {
          await _storage.write(key: 'refresh_token', value: newRefresh);
        }
        debugPrint('[ApiClient] Token silently refreshed.');
        return true;
      }
      // Refresh token itself is expired/revoked — clear everything.
      await clearAuth();
      return false;
    } catch (e) {
      debugPrint('[ApiClient] Token refresh error: \$e');
      return false;
    }
  }

  /// Check if user is authenticated by validating token with backend
  Future<bool> isAuthenticated() async {
    final token = await _storage.read(key: 'auth_token');
    final userId = await _storage.read(key: 'user_id');

    if (token == null || userId == null) {
      return false;
    }

    try {
      await get('/auth/me/$userId');
      return true;
    } catch (e) {
      debugPrint('[ApiClient] isAuthenticated check failed: $e');
      return false;
    }
  }

  /// Clear authentication data
  Future<void> clearAuthData() async {
    await Future.wait([
      _storage.delete(key: 'auth_token'),
      _storage.delete(key: 'refresh_token'),
      _storage.delete(key: 'user_id'),
      _storage.delete(key: 'user_role'),
    ]);
  }
}

/// Custom exception for API errors
class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String? code;
  final List<String>? errors;

  ApiException({
    required this.message,
    required this.statusCode,
    this.code,
    this.errors,
  });

  @override
  String toString() {
    if (errors != null && errors!.isNotEmpty) {
      return '$message: ${errors!.join(', ')}';
    }
    return message;
  }
}

/// Singleton instance of ApiClient
final ApiClient apiClient = ApiClient();

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
