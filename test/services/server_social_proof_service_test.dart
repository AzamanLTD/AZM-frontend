// =============================================================================
// AZAMAN — SERVER SOCIAL PROOF (AZM-backend PR #372, "Backend C")
//
// Pins the typed client + presentation seam:
//   • single GET parses real counts; 404/400/401/network are
//     SocialProofUnavailable (honest absence, never "zero friends")
//   • batch POST caps at 50, maps ids to proofs, rejects malformed
//   • the label seam renders NOTHING for zero friends, friends-of-
//     friends without a direct anchor, or anything it was not given
//   • a follow is never presented as a visit — the only verb is
//     "Followed by"
// =============================================================================
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/services/api_client.dart';
import 'package:azaman/providers/server_social_proof_provider.dart';
import 'package:azaman/services/server_social_proof_service.dart';

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

class _FakeClient extends ApiClient {
  final int getStatus;
  final Map<String, dynamic> Function(String id)? singleBody;
  final Map<String, dynamic> batchBody;
  final List<String> endpoints = [];
  _FakeClient({
    this.getStatus = 200,
    this.singleBody,
    this.batchBody = const {},
  });

  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers, bool requireAuth = true}) async {
    endpoints.add(endpoint);
    if (getStatus != 200) return _json(getStatus, {'success': false});
    final id = endpoint.split('/').last;
    return _json(200, {
      'success': true,
      'businessProfileId': id,
      ...(singleBody?.call(id) ?? const {}),
    });
  }

  @override
  Future<http.Response> post(String endpoint, Map<String, dynamic> body,
      {Map<String, String>? headers,
      bool requireAuth = true,
      String? idempotencyKey}) async {
    endpoints.add(endpoint);
    if (getStatus != 200) return _json(getStatus, {'success': false});
    // A real server echoes proofs only for the ids in the request body.
    final requested =
        List<String>.from(body['businessProfileIds'] as List);
    return _json(200, {
      'success': true,
      'proofs': {
        for (final id in requested)
          if (batchBody.containsKey(id)) id: batchBody[id],
      },
    });
  }
}

class _NetworkFailClient extends ApiClient {
  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers, bool requireAuth = true}) async {
    throw Exception('network down');
  }
}

void main() {
  group('service fetch', () {
    test('parses real counts from the single route', () async {
      final svc = ServerSocialProofService(client: _FakeClient(
        singleBody: (id) => {
          'friendsFollowingCount': 3,
          'friendsOfFriendsFollowingCount': 7,
        },
      ));
      final proof = await svc.fetch('bp-1');
      expect(proof.businessProfileId, 'bp-1');
      expect(proof.friendsFollowingCount, 3);
      expect(proof.friendsOfFriendsFollowingCount, 7);
    });

    test('404 is honest absence, not zero friends', () async {
      final svc = ServerSocialProofService(
          client: _FakeClient(getStatus: 404));
      await expectLater(svc.fetch('bp-404'),
          throwsA(isA<SocialProofUnavailable>()));
    });

    test('401 (anonymous) is honest absence', () async {
      final svc = ServerSocialProofService(
          client: _FakeClient(getStatus: 401));
      await expectLater(svc.fetch('bp-1'),
          throwsA(isA<SocialProofUnavailable>()));
    });

    test('network failure is honest absence', () async {
      final svc = ServerSocialProofService(client: _NetworkFailClient());
      await expectLater(svc.fetch('bp-1'),
          throwsA(isA<SocialProofUnavailable>()));
    });

    test('batch maps ids to proofs and caps at 50', () async {
      final proofs = {
        for (final id in List.generate(60, (i) => 'bp-$i'))
          id: {
            'friendsFollowingCount': 1,
            'friendsOfFriendsFollowingCount': 0,
          }
      };
      final svc = ServerSocialProofService(
          client: _FakeClient(batchBody: proofs));
      final result = await svc.fetchBatch(
          List.generate(60, (i) => 'bp-$i'));
      expect(result.length, 50, reason: 'the contract caps a batch at 50');
      expect(result['bp-0']!.friendsFollowingCount, 1);
    });

    test('empty batch request makes no call', () async {
      final svc = ServerSocialProofService(client: _FakeClient());
      expect(await svc.fetchBatch(const []), isEmpty);
    });

    test('malformed batch body is honest absence', () async {
      // A proof value that is not an object → unavailable, never a
      // guessed zero.
      final svc = ServerSocialProofService(
          client: _FakeClient(batchBody: {'bp-1': 'garbage-string'}));
      await expectLater(svc.fetchBatch(['bp-1']),
          throwsA(isA<SocialProofUnavailable>()));
    });
  });

  // PATH CONTRACT (review 4.3) — AppConfig.apiUrl already ends in '/api';
  // the ApiClient-relative paths must be exactly '/social-proof/...' with
  // NO second '/api' segment. These tests pin the ACTUAL request path,
  // not just parsing of the mocked response.
  group('request paths', () {
    test('single fetch requests exactly /social-proof/<id> — no double /api',
        () async {
      final fake = _FakeClient(singleBody: (id) => const {});
      await ServerSocialProofService(client: fake).fetch('BIZ-PROFILE-9');
      expect(fake.endpoints, ['/social-proof/BIZ-PROFILE-9']);
    });

    test('batch requests exactly /social-proof — no double /api', () async {
      final fake = _FakeClient(batchBody: const {});
      await ServerSocialProofService(client: fake)
          .fetchBatch(['a', 'b']);
      expect(fake.endpoints, ['/social-proof']);
    });

    test('no request path ever contains /api twice', () async {
      final fake = _FakeClient(singleBody: (id) => const {});
      final svc = ServerSocialProofService(client: fake);
      await svc.fetch('x');
      await svc.fetchBatch(['x', 'y']);
      for (final e in fake.endpoints) {
        expect(e.contains('/api/api/'), isFalse,
            reason: 'doubled /api segment would 404 on device');
      }
    });
  });

  group('presentation seam', () {
    test('real friends render a "Followed by" line — never a visit claim',
        () {
      const proof = ServerSocialProof(
        businessProfileId: 'bp-1',
        friendsFollowingCount: 3,
        friendsOfFriendsFollowingCount: 0,
      );
      final line = socialProofLine(proof);
      expect(line, 'Followed by 3 friends');
      expect(line!.toLowerCase(), isNot(contains('visit')));
    });

    test('singular friend grammar', () {
      const proof = ServerSocialProof(
        businessProfileId: 'bp-1',
        friendsFollowingCount: 1,
        friendsOfFriendsFollowingCount: 0,
      );
      expect(socialProofLine(proof), 'Followed by 1 friend');
    });

    test('friends-of-friends render only beside a direct anchor', () {
      const both = ServerSocialProof(
        businessProfileId: 'bp-1',
        friendsFollowingCount: 2,
        friendsOfFriendsFollowingCount: 4,
      );
      expect(socialProofLine(both), 'Followed by 2 friends · 4 friends of friends');

      const fofOnly = ServerSocialProof(
        businessProfileId: 'bp-1',
        friendsFollowingCount: 0,
        friendsOfFriendsFollowingCount: 9,
      );
      expect(socialProofLine(fofOnly), isNull,
          reason: 'FoF without a direct anchor adds no social weight');
    });

    test('honest zeros render NOTHING — no broken-looking zero row', () {
      const zero = ServerSocialProof(
        businessProfileId: 'bp-1',
        friendsFollowingCount: 0,
        friendsOfFriendsFollowingCount: 0,
      );
      expect(socialProofLine(zero), isNull);
    });
  });
}
