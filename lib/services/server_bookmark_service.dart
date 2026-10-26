// lib/services/server_bookmark_service.dart
// =============================================================================
// Server Bookmarks — typed client for the durable business-bookmark
// contract (AZM-backend PR #370, "Backend A").
//
// Wire contract (docs/marketplace-personalisation-contracts.md):
//   POST   /api/bookmarks                  201 new / 200 idempotent repeat
//        → { success, state: "BOOKMARKED", alreadyBookmarked,
//            bookmark: { businessProfileId, savedAt } }
//   DELETE /api/bookmarks/:businessProfileId
//        → 200 { success, state: "NOT_BOOKMARKED", removed: true|false }
//   GET    /api/bookmarks/check/:businessProfileId
//        → 200 { success, bookmarked: boolean }
//   GET    /api/bookmarks?limit=&offset=
//        → 200 { success, total, bookmarks: [ { businessProfileId,
//              businessName, logoUrl, category, isVerified,
//              averageRating, savedAt } ] }   (savedAt DESC)
//
// Honesty rules encoded here:
//  * All identifiers are canonical BusinessProfile.id values — NEVER
//    product, location or display "BIZ-..." codes.
//  * A 404 on save/delete means the business id is wrong: the caller
//    must NOT retry and must NOT simulate a local save.
//  * DELETE is idempotent: removed:false still means the durable end
//    state is NOT_BOOKMARKED (there was nothing to remove).
//  * `state` is the stable client-facing signal; `alreadyBookmarked`
//    distinguishes a fresh save from an idempotent repeat.
// =============================================================================
import 'dart:convert';

import 'package:azaman/services/api_client.dart';
import 'package:http/http.dart' as http;

class ServerBookmark {
  /// Canonical BusinessProfile.id — the ONLY key the contract accepts.
  final String businessProfileId;
  final String businessName;
  final String? logoUrl;
  final String category;
  final bool isVerified;
  final double? averageRating;
  final DateTime savedAt;

  const ServerBookmark({
    required this.businessProfileId,
    required this.businessName,
    this.logoUrl,
    required this.category,
    this.isVerified = false,
    this.averageRating,
    required this.savedAt,
  });

  factory ServerBookmark.fromJson(Map<String, dynamic> json) {
    return ServerBookmark(
      businessProfileId: json['businessProfileId']?.toString() ?? '',
      businessName: json['businessName']?.toString() ?? '',
      logoUrl: json['logoUrl']?.toString(),
      category: json['category']?.toString() ?? '',
      isVerified: json['isVerified'] as bool? ?? false,
      averageRating: (json['averageRating'] as num?)?.toDouble(),
      savedAt: DateTime.tryParse(json['savedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Optimistic placeholder used between the local toggle and the
  /// server's confirmation — display fields are unknown until the
  /// next hydrate, which the UI must never present as fact.
  static ServerBookmark placeholder(String businessProfileId) =>
      ServerBookmark(
        businessProfileId: businessProfileId,
        businessName: '',
        category: '',
        savedAt: DateTime.now(),
      );
}

class BookmarkSaveResult {
  /// The DURABLE end state after the call (always true on 200/201 —
  /// the caller is expected to check `ok` first).
  final bool bookmarked;
  final bool alreadyBookmarked;
  final String businessProfileId;
  final DateTime? savedAt;

  const BookmarkSaveResult({
    required this.bookmarked,
    required this.alreadyBookmarked,
    required this.businessProfileId,
    this.savedAt,
  });
}

class BookmarkRemoveResult {
  /// The durable end state is NOT_BOOKMARKED on ANY 200 (removed:true
  /// or the idempotent removed:false).
  final bool notBookmarked;
  /// Whether the server actually removed a row this call.
  final bool removed;

  const BookmarkRemoveResult(
      {required this.notBookmarked, required this.removed});
}

class ServerBookmarkPage {
  final int total;
  final List<ServerBookmark> bookmarks;

  const ServerBookmarkPage({required this.total, required this.bookmarks});
}

/// Thrown for any non-2xx or malformed response — including the 404
/// "wrong business id" case the contract forbids retrying/simulating.
class BookmarkContractException implements Exception {
  final int statusCode;
  final String reason;
  BookmarkContractException(this.statusCode, [this.reason = '']);

  @override
  String toString() =>
      'BookmarkContractException($statusCode${reason.isEmpty ? '' : ': $reason'})';
}

class ServerBookmarkService {
  final ApiClient _api;

  ServerBookmarkService({ApiClient? client}) : _api = client ?? apiClient;

  Map<String, dynamic> _decode(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw BookmarkContractException(r.statusCode);
    }
    final body = jsonDecode(r.body);
    if (body is! Map<String, dynamic>) {
      throw BookmarkContractException(r.statusCode, 'non-object body');
    }
    return body;
  }

  /// POST /api/bookmarks — save a business. Idempotent: a repeat save
  /// for an already-bookmarked business returns 200 (not an error).
  Future<BookmarkSaveResult> save(String businessProfileId) async {
    final r = await _api.post(
      '/bookmarks',
      {'businessProfileId': businessProfileId},
    );
    final body = _decode(r);
    final bookmark = (body['bookmark'] as Map<String, dynamic>?) ?? {};
    final state = body['state']?.toString() ?? '';
    return BookmarkSaveResult(
      // `state` is the stable client-facing signal.
      bookmarked: state == 'BOOKMARKED',
      alreadyBookmarked: body['alreadyBookmarked'] as bool? ?? false,
      businessProfileId:
          bookmark['businessProfileId']?.toString() ?? businessProfileId,
      savedAt: bookmark['savedAt'] != null
          ? DateTime.tryParse(bookmark['savedAt'].toString())
          : null,
    );
  }

  /// DELETE /api/bookmarks/:id — idempotent removal. ANY 200 means the
  /// durable end state is NOT_BOOKMARKED; only transport/5xx errors
  /// (thrown) leave the previous state standing.
  Future<BookmarkRemoveResult> remove(String businessProfileId) async {
    final r =
        await _api.delete('/bookmarks/$businessProfileId');
    final body = _decode(r);
    final state = body['state']?.toString() ?? '';
    return BookmarkRemoveResult(
      notBookmarked: state == 'NOT_BOOKMARKED',
      removed: body['removed'] as bool? ?? false,
    );
  }

  /// GET /api/bookmarks/check/:id — the ONLY way to learn a single
  /// business's bookmark state (isBookmarked is not derivable from any
  /// other field in any DTO).
  Future<bool> check(String businessProfileId) async {
    final r = await _api.get('/bookmarks/check/$businessProfileId');
    final body = _decode(r);
    return body['bookmarked'] as bool? ?? false;
  }

  /// GET /api/bookmarks — the caller's full bookmark list, newest
  /// first. Contains ONLY the caller's bookmarks.
  Future<ServerBookmarkPage> list({int limit = 50, int offset = 0}) async {
    final r =
        await _api.get('/bookmarks?limit=$limit&offset=$offset');
    final body = _decode(r);
    final items = (body['bookmarks'] as List<dynamic>? ?? [])
        .map((e) => ServerBookmark.fromJson(e as Map<String, dynamic>))
        .toList();
    return ServerBookmarkPage(
      total: (body['total'] as num?)?.toInt() ?? items.length,
      bookmarks: items,
    );
  }
}
