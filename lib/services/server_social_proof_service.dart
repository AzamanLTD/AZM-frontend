// lib/services/server_social_proof_service.dart
// =============================================================================
// Server Social Proof — typed client for the friends/friends-of-friends
// follow-count contract (AZM-backend PR #372, "Backend C").
//
// Wire contract (docs/marketplace-social-proof-contract.md):
//   GET  /api/social-proof/:businessProfileId   (Bearer required)
//
// PATH NOTE (2026-10-25 review 4.3): ApiClient.baseUrl is AppConfig.apiUrl
// which ALREADY ends in '/api'. The paths below are therefore the
// ApiClient-relative '/social-proof/...' forms — never '/api/...' again,
// which produced .../api/api/social-proof/... (404) on device.
//     200 → { success, businessProfileId,
//             friendsFollowingCount,
//             friendsOfFriendsFollowingCount }
//     400 VALIDATION_ERROR · 404 BUSINESS_NOT_FOUND · 401 protect
//   POST /api/social-proof                      (batch, ≤50 ids)
//     200 → { success, proofs: { "<id>": { friendsFollowingCount,
//              friendsOfFriendsFollowingCount }, ... } }
//     Unknown ids are honest zeros in the batch; only the single route
//     distinguishes 404.
//
// Honesty rules encoded here:
//  * Only aggregate NUMBERS are returned by the API — never identities
//    or lists. A follow is NOT a visit: no visitation claim is made or
//    implied anywhere downstream.
//  * All identifiers are canonical BusinessProfile.id values.
//  * ANY failure (401 anonymous, 404, network, malformed) surfaces as
//    SocialProofUnavailable — the caller renders NOTHING. Social proof
//    is a bonus signal: absence is honest, never "zero friends".
// =============================================================================
import 'dart:convert';

import 'package:azaman/services/api_client.dart';
import 'package:http/http.dart' as http;

class ServerSocialProof {
  final String businessProfileId;
  final int friendsFollowingCount;
  final int friendsOfFriendsFollowingCount;

  const ServerSocialProof({
    required this.businessProfileId,
    required this.friendsFollowingCount,
    required this.friendsOfFriendsFollowingCount,
  });

  factory ServerSocialProof.fromJson(Map<String, dynamic> json) {
    return ServerSocialProof(
      businessProfileId: json['businessProfileId']?.toString() ?? '',
      friendsFollowingCount:
          (json['friendsFollowingCount'] as num?)?.toInt() ?? 0,
      friendsOfFriendsFollowingCount:
          (json['friendsOfFriendsFollowingCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Thrown for any non-2xx or malformed response. The caller must treat
/// ALL of these as "no social proof to show" — never as zero friends.
class SocialProofUnavailable implements Exception {
  final int? statusCode;
  SocialProofUnavailable([this.statusCode]);
  @override
  String toString() => 'SocialProofUnavailable(${statusCode ?? 'network'})';
}

class ServerSocialProofService {
  final ApiClient _client;
  ServerSocialProofService({ApiClient? client})
    : _client = client ?? ApiClient();

  /// Single-business proof. A 404 means the business id is unknown to
  /// the contract — honest absence, no retry, no local guess.
  Future<ServerSocialProof> fetch(String businessProfileId) async {
    final http.Response r;
    try {
      r = await _client.get(
        '/social-proof/$businessProfileId',
        requireAuth: true,
      );
    } catch (_) {
      throw SocialProofUnavailable();
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw SocialProofUnavailable(r.statusCode);
    }
    return ServerSocialProof.fromJson(_decodeObject(r.body));
  }

  /// Batch fetch (≤50 ids) for multi-card rendering. Ids absent from the
  /// returned map have no data — the caller must not read absence as
  /// zero friends.
  Future<Map<String, ServerSocialProof>> fetchBatch(
    List<String> businessProfileIds,
  ) async {
    if (businessProfileIds.isEmpty) return const {};
    final ids = businessProfileIds.take(50).toList(growable: false);
    final http.Response r;
    try {
      r = await _client.post('/social-proof', {
        'businessProfileIds': ids,
      }, requireAuth: true);
    } catch (_) {
      throw SocialProofUnavailable();
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw SocialProofUnavailable(r.statusCode);
    }
    final body = _decodeObject(r.body);
    final proofs = body['proofs'];
    if (proofs is! Map<String, dynamic>) {
      throw SocialProofUnavailable(r.statusCode);
    }
    return proofs.map((id, raw) {
      if (raw is! Map<String, dynamic>) throw SocialProofUnavailable(null);
      return MapEntry(id, ServerSocialProof.fromJson(raw));
    });
  }
}

Map<String, dynamic> _decodeObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {
    // fall through
  }
  throw SocialProofUnavailable(null);
}
