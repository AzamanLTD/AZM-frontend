// =============================================================================
// BUSINESS SERVICE — Flutter V3 Marketplace Sprint (2026-06-21)
//
// The single REST entry point for the entire Premium Marketplace (mounted at
// /api/business, plus the customer invoice list on /api/users/invoices).
//
// Mirrors `TicketService`: an `ApiClient` on the instance, `jsonDecode` of the
// body, a thrown `BusinessServiceException` on non-2xx. The backend wraps every
// payload in `{ success: true, ... }`; we unwrap the relevant key.
//
// Pagination: most list endpoints are cursor-based ({ hasMore, nextCursor });
// `searchNearby` is the lone offset-based endpoint ({ hasMore, nextPage }) so
// it has its own record shape with an `int? nextPage`.
//
// Return shapes use NAMED records (e.g. `.businesses`, `.hasMore`,
// `.nextCursor`) so call sites read clearly.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/services/api_client.dart';

typedef BusinessPage = ({
  List<BusinessProfile> businesses,
  bool hasMore,
  String? nextCursor
});
typedef ProductPage = ({
  List<BusinessProduct> products,
  bool hasMore,
  String? nextCursor
});
typedef ReviewPage = ({
  List<BusinessReview> reviews,
  bool hasMore,
  String? nextCursor
});
typedef InvoicePage = ({
  List<BusinessInvoice> invoices,
  bool hasMore,
  String? nextCursor
});
typedef OrderPage = ({
  List<BusinessOrder> orders,
  bool hasMore,
  String? nextCursor
});
typedef NearbyPage = ({
  List<BusinessLocation> locations,
  bool hasMore,
  int? nextPage
});

class BusinessService {
  final ApiClient _client;
  BusinessService() : _client = ApiClient();

  // ── IMAGE UPLOAD ───────────────────────────────────────────────────────────

  /// Upload an image to the business Cloudinary folder.
  ///
  /// [folder] determines the Cloudinary destination:
  ///   'products' → azaman/business/products/  (product images)
  ///   'logos'    → azaman/business/logos/     (business logo)
  ///   'kyb'      → azaman/business/kyb/       (KYB documents)
  ///
  /// Returns the permanent Cloudinary secure_url.
  /// Throws on failure (via ApiClient._handleResponse / _ok).
  Future<String> uploadBusinessImage(File file, {String folder = 'products'}) async {
    final uri =
        Uri.parse('${ApiClient.baseUrl}/business/upload/image?folder=$folder');
    final request = http.MultipartRequest('POST', uri);

    // Determine mime type from extension
    final ext = file.path.toLowerCase().split('.').last;
    MediaType? contentType;
    if (ext == 'jpg' || ext == 'jpeg') {
      contentType = MediaType('image', 'jpeg');
    } else if (ext == 'png') {
      contentType = MediaType('image', 'png');
    } else if (ext == 'webp') {
      contentType = MediaType('image', 'webp');
    } else if (ext == 'gif') {
      contentType = MediaType('image', 'gif');
    } else if (ext == 'heic') {
      contentType = MediaType('image', 'heic');
    }

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: contentType,
      ),
    );

    final response =
        await _client.multipart('/business/upload/image?folder=$folder', request);
    final body = _ok(response.body, response.statusCode, 'Image upload failed');
    return body['url'].toString();
  }

  // ── BUSINESS PROFILE ───────────────────────────────────────────────────────

  /// POST /business/register
  Future<BusinessProfile> registerBusiness(Map<String, dynamic> data) async {
    final res = await _client.post('/business/register', data);
    final body = _ok(res.body, res.statusCode, 'Registration failed');
    return BusinessProfile.fromJson(
        body['businessProfile'] as Map<String, dynamic>);
  }

  /// GET /business/me — null when the user has no business yet.
  Future<BusinessProfile?> getMyBusiness() async {
    try {
      final res = await _client.get('/business/me');
      final body = jsonDecode(res.body);
      final biz = body['business'];
      return biz is Map<String, dynamic> ? BusinessProfile.fromJson(biz) : null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// GET /business/:bizId (public) — null on 404.
  Future<BusinessProfile?> getBusinessByBizId(String bizId) async {
    try {
      final res = await _client.get('/business/$bizId', requireAuth: false);
      final body = jsonDecode(res.body);
      final biz = body['business'];
      return biz is Map<String, dynamic> ? BusinessProfile.fromJson(biz) : null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// GET /business/search (public).
  Future<BusinessPage> searchBusinesses({
    String? q,
    String? category,
    bool? verified,
    String? subcategory,
    int limit = 20,
    String? cursor,
  }) async {
    final query = _qs({
      if (q != null && q.isNotEmpty) 'q': q,
      if (category != null && category.isNotEmpty) 'category': category,
      if (verified != null) 'verified': '$verified',
      if (subcategory != null && subcategory.isNotEmpty)
        'subcategory': subcategory,
      'limit': '$limit',
      if (cursor != null) 'cursor': cursor,
    });
    final res = await _client.get('/business/search$query', requireAuth: false);
    final body = _ok(res.body, res.statusCode, 'Search failed');
    return (
      businesses: _list(body['businesses'], BusinessProfile.fromJson),
      hasMore: body['hasMore'] == true,
      nextCursor: body['nextCursor']?.toString(),
    );
  }

  /// PATCH /business/profile
  Future<BusinessProfile> updateProfile(Map<String, dynamic> updates) async {
    final res = await _client.patch('/business/profile', body: updates);
    final body = _ok(res.body, res.statusCode, 'Update failed');
    return BusinessProfile.fromJson(
        body['businessProfile'] as Map<String, dynamic>);
  }

  // ── PRODUCTS ─────────────────────────────────────────────────────────────

  /// GET /business/:bizId/products (public).
  Future<ProductPage> getBusinessProducts(
    String bizId, {
    int limit = 20,
    String? cursor,
  }) async {
    final query = _qs({'limit': '$limit', if (cursor != null) 'cursor': cursor});
    final res =
        await _client.get('/business/$bizId/products$query', requireAuth: false);
    final body = _ok(res.body, res.statusCode, 'Products failed');
    return _productPage(body);
  }

  /// GET /business/products/:productId (public) — null on 404.
  Future<BusinessProduct?> getProductById(String productId) async {
    try {
      final res =
          await _client.get('/business/products/$productId', requireAuth: false);
      final body = jsonDecode(res.body);
      final p = body['product'];
      return p is Map<String, dynamic> ? BusinessProduct.fromJson(p) : null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// GET /business/products (owner's own products).
  Future<ProductPage> getMyProducts({int limit = 20, String? cursor}) async {
    final query = _qs({'limit': '$limit', if (cursor != null) 'cursor': cursor});
    final res = await _client.get('/business/products$query');
    final body = _ok(res.body, res.statusCode, 'Products failed');
    return _productPage(body);
  }

  /// POST /business/products
  Future<BusinessProduct> createProduct(Map<String, dynamic> data) async {
    final res = await _client.post('/business/products', data);
    final body = _ok(res.body, res.statusCode, 'Create product failed');
    return BusinessProduct.fromJson(body['product'] as Map<String, dynamic>);
  }

  /// PATCH /business/products/:id
  Future<BusinessProduct> updateProduct(
      String id, Map<String, dynamic> data) async {
    final res = await _client.patch('/business/products/$id', body: data);
    final body = _ok(res.body, res.statusCode, 'Update product failed');
    return BusinessProduct.fromJson(body['product'] as Map<String, dynamic>);
  }

  /// DELETE /business/products/:id
  Future<void> deleteProduct(String id) async {
    final res = await _client.delete('/business/products/$id');
    _ok(res.body, res.statusCode, 'Delete product failed');
  }

  // ── LOCATIONS (public) ─────────────────────────────────────────────────────

  /// GET /business/search/nearby (public, offset pagination).
  Future<NearbyPage> searchNearby({
    required double lat,
    required double lng,
    double radiusKm = 10,
    String? category,
    String? q,
    bool? verified,
    int limit = 20,
    int page = 0,
  }) async {
    final query = _qs({
      'lat': '$lat',
      'lng': '$lng',
      'radiusKm': '$radiusKm',
      if (category != null && category.isNotEmpty) 'category': category,
      if (q != null && q.isNotEmpty) 'q': q,
      if (verified != null) 'verified': '$verified',
      'limit': '$limit',
      'page': '$page',
    });
    final res =
        await _client.get('/business/search/nearby$query', requireAuth: false);
    final body = _ok(res.body, res.statusCode, 'Nearby search failed');
    final nextPageRaw = body['nextPage'];
    return (
      locations: _list(body['locations'], BusinessLocation.fromJson),
      hasMore: body['hasMore'] == true,
      nextPage: nextPageRaw == null
          ? null
          : (nextPageRaw is int
              ? nextPageRaw
              : int.tryParse(nextPageRaw.toString())),
    );
  }

  /// GET /business/:bizId/locations (public).
  Future<List<BusinessLocation>> getPublicLocations(String bizId) async {
    final res =
        await _client.get('/business/$bizId/locations', requireAuth: false);
    final body = _ok(res.body, res.statusCode, 'Locations failed');
    return _list(body['locations'], BusinessLocation.fromJson);
  }

  // ── REVIEWS (public) ─────────────────────────────────────────────────────

  /// GET /business/:bizId/reviews (public).
  Future<ReviewPage> getReviews(
    String bizId, {
    int limit = 20,
    String? cursor,
  }) async {
    final query = _qs({'limit': '$limit', if (cursor != null) 'cursor': cursor});
    final res =
        await _client.get('/business/$bizId/reviews$query', requireAuth: false);
    final body = _ok(res.body, res.statusCode, 'Reviews failed');
    return (
      reviews: _list(body['reviews'], BusinessReview.fromJson),
      hasMore: body['hasMore'] == true,
      nextCursor: body['nextCursor']?.toString(),
    );
  }

  /// POST /business/reviews
  Future<BusinessReview> createReview(Map<String, dynamic> data) async {
    final res = await _client.post('/business/reviews', data);
    final body = _ok(res.body, res.statusCode, 'Create review failed');
    return BusinessReview.fromJson(body['review'] as Map<String, dynamic>);
  }

  // ── INVOICES (customer-facing) ─────────────────────────────────────────────

  /// GET /users/invoices (customer's invoices live on the USER routes).
  Future<InvoicePage> getMyInvoices({
    String? status,
    int limit = 20,
    String? cursor,
  }) async {
    final query = _qs({
      if (status != null && status.isNotEmpty) 'status': status,
      'limit': '$limit',
      if (cursor != null) 'cursor': cursor,
    });
    final res = await _client.get('/users/invoices$query');
    final body = _ok(res.body, res.statusCode, 'Invoices failed');
    return (
      invoices: _list(body['invoices'], BusinessInvoice.fromJson),
      hasMore: body['hasMore'] == true,
      nextCursor: body['nextCursor']?.toString(),
    );
  }

  /// GET /business/invoices/:invoiceId
  Future<BusinessInvoice> getInvoice(String invoiceId) async {
    final res = await _client.get('/business/invoices/$invoiceId');
    final body = _ok(res.body, res.statusCode, 'Invoice failed');
    return BusinessInvoice.fromJson(body['invoice'] as Map<String, dynamic>);
  }

  /// POST /business/invoices/:invoiceId/pay
  Future<BusinessInvoice> payInvoice({
    required String invoiceId,
    double tipUsdc = 0,
    String? customerNote,
    bool customerCoveredFee = false,
  }) async {
    final res = await _client.post('/business/invoices/$invoiceId/pay', {
      'tipUsdc': tipUsdc,
      if (customerNote != null && customerNote.isNotEmpty)
        'customerNote': customerNote,
      'customerCoveredFee': customerCoveredFee,
    });
    final body = _ok(res.body, res.statusCode, 'Payment failed');
    return BusinessInvoice.fromJson(body['invoice'] as Map<String, dynamic>);
  }

  // ── ORDERS (customer-facing) ─────────────────────────────────────────────

  /// GET /business/my-orders
  Future<OrderPage> getMyOrders({int limit = 20, String? cursor}) async {
    final query = _qs({'limit': '$limit', if (cursor != null) 'cursor': cursor});
    final res = await _client.get('/business/my-orders$query');
    final body = _ok(res.body, res.statusCode, 'Orders failed');
    return (
      orders: _list(body['orders'], BusinessOrder.fromJson),
      hasMore: body['hasMore'] == true,
      nextCursor: body['nextCursor']?.toString(),
    );
  }

  // ── NOTIFICATIONS (owner only) ─────────────────────────────────────────────

  /// GET /business/notifications
  Future<BizNotificationFeed> getNotifications({
    bool unreadOnly = false,
    int limit = 20,
    String? cursor,
  }) async {
    final query = _qs({
      if (unreadOnly) 'unreadOnly': 'true',
      'limit': '$limit',
      if (cursor != null) 'cursor': cursor,
    });
    final res = await _client.get('/business/notifications$query');
    final body = _ok(res.body, res.statusCode, 'Notifications failed');
    return BizNotificationFeed(
      notifications: _list(body['notifications'], BizNotification.fromJson),
      hasMore: body['hasMore'] == true,
      nextCursor: body['nextCursor']?.toString(),
      unreadCount: body['unreadCount'] is int
          ? body['unreadCount'] as int
          : int.tryParse(body['unreadCount']?.toString() ?? '') ?? 0,
    );
  }

  /// GET /business/notifications/unread-count — backend returns `{ count }`.
  Future<int> getUnreadCount() async {
    final res = await _client.get('/business/notifications/unread-count');
    final body = _ok(res.body, res.statusCode, 'Unread count failed');
    final c = body['count'] ?? body['unreadCount'];
    return c is int ? c : int.tryParse(c?.toString() ?? '') ?? 0;
  }

  /// POST /business/notifications/read-all
  Future<void> markAllNotificationsRead() async {
    final res = await _client.post('/business/notifications/read-all', const {});
    _ok(res.body, res.statusCode, 'Mark-all failed');
  }

  /// POST /business/notifications/read/:id
  Future<void> markNotificationRead(String id) async {
    final res = await _client.post('/business/notifications/read/$id', const {});
    _ok(res.body, res.statusCode, 'Mark-read failed');
  }

  // ── KYB (owner only) ─────────────────────────────────────────────────────

  /// GET /business/kyb/status
  Future<({String kybStatus, List<Map<String, dynamic>> documents})>
      getKybStatus() async {
    final res = await _client.get('/business/kyb/status');
    final body = _ok(res.body, res.statusCode, 'KYB status failed');
    return (
      kybStatus: (body['kybStatus'] ?? 'UNVERIFIED').toString(),
      documents: (body['documents'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(),
    );
  }

  /// POST /business/kyb/submit { documents: [{documentType, documentUrl}] }
  Future<void> submitKybDocuments(
      List<Map<String, dynamic>> documents) async {
    final res =
        await _client.post('/business/kyb/submit', {'documents': documents});
    _ok(res.body, res.statusCode, 'KYB submit failed');
  }

  // ── STATS (owner only) ─────────────────────────────────────────────────────

  /// GET /business/orders/stats
  Future<BusinessStats> getBusinessStats() async {
    final res = await _client.get('/business/orders/stats');
    final body = _ok(res.body, res.statusCode, 'Stats failed');
    final stats = body['stats'];
    return BusinessStats.fromJson(
        stats is Map<String, dynamic> ? stats : body);
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  ProductPage _productPage(Map<String, dynamic> body) => (
        products: _list(body['products'], BusinessProduct.fromJson),
        hasMore: body['hasMore'] == true,
        nextCursor: body['nextCursor']?.toString(),
      );

  /// Build a `?a=b&c=d` query string from a map (URL-encoded). Empty → ''.
  String _qs(Map<String, String> params) {
    if (params.isEmpty) return '';
    final q = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '?$q';
  }

  List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) {
    return (raw as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList();
  }

  /// Decode + assert 2xx. Returns the decoded Map. Throws otherwise.
  Map<String, dynamic> _ok(String rawBody, int statusCode, String fallback) {
    dynamic decoded;
    try {
      decoded = jsonDecode(rawBody);
    } catch (_) {
      decoded = null;
    }
    if (statusCode < 200 || statusCode >= 300) {
      final message = (decoded is Map ? decoded['message']?.toString() : null) ??
          fallback;
      throw BusinessServiceException(statusCode: statusCode, message: message);
    }
    if (decoded is! Map<String, dynamic>) {
      throw BusinessServiceException(
          statusCode: statusCode, message: 'Malformed response');
    }
    return decoded;
  }
}

class BusinessServiceException implements Exception {
  final int statusCode;
  final String message;
  const BusinessServiceException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() => message;
}

/// Riverpod handle for the marketplace service.
final businessServiceProvider =
    Provider<BusinessService>((ref) => BusinessService());
