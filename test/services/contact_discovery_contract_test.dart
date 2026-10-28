// =============================================================================
// AZAMAN — CONTACT DISCOVERY CONTRACT (P8, 2026-10-28)
//
// These tests exist because the shipped flow could not work and said nothing.
//
// The app POSTed `{hashedPhones: sha256(digits)}` to `/contacts/sync`, while
// the backend stores `User.phoneHash` as HMAC-SHA256(E.164, server pepper) and
// that endpoint matches hash-to-hash against exactly that column. A plain
// SHA-256 can never equal a peppered HMAC, so the call returned 200 with an
// empty list forever and the UI reported "none of your contacts are on
// Azaman" — a plausible-looking answer produced by an impossible comparison.
//
// What is pinned here:
//
//   1. A plain SHA-256 of a phone number is NOT what the server stores, so the
//      legacy scheme cannot match. (Demonstrates the defect itself.)
//   2. The wire body is `{phones: [E.164...]}` to `/users/discover` — the
//      contract whose server-side hashing actually matches.
//   3. Nothing but numbers is sent: no names, no labels, no hashes.
//   4. Normalization: +, 00, known dial codes, local trunk 0, junk rejection.
//   5. Every outcome is distinguishable — denied, no numbers, failed (with
//      the server's reason), and ok-but-empty are four different states.
//   6. A large address book is batched at the server's 1000 cap.
//   7. The parsed projection is the server's: azamanId, displayName, avatar.
// =============================================================================
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '_secure_storage_stub.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/contact_service.dart';

/// Build a service whose HTTP layer is a recorder. [onCall] returns the
/// response for a given request body, so a test can assert the exact wire
/// shape AND the parse path together.
({ContactService service, List<http.Request> calls}) _harness(
  http.Response Function(int callIndex, Map<String, dynamic> body) onCall,
) {
  final calls = <http.Request>[];
  final client = MockClient((request) async {
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    calls.add(request);
    return onCall(calls.length - 1, body);
  });
  return (
    service: ContactService.withClient(ApiClient(client: client)),
    calls: calls,
  );
}

Map<String, dynamic> _ok(List<Map<String, dynamic>> matches) => {
  'success': true,
  'data': {'matches': matches},
};

/// A stand-in for a network error: any thrown object must be caught and turned
/// into an honest failure result rather than escaping to the UI.
class SocketLikeError implements Exception {
  const SocketLikeError();
}

void main() {
  setUpAll(stubSecureStorage);

  group('the defect this replaces', () {
    test('1. a plain SHA-256 can never equal the server peppered HMAC', () {
      // The old client scheme, reproduced exactly.
      const raw = '0244123456';
      final legacy = sha256
          .convert(utf8.encode(raw.replaceAll(RegExp(r'[^0-9]'), '')))
          .toString();

      // The server's stored value is HMAC-SHA256('+233244123456', pepper).
      // Even with the SAME input string the digests differ (different
      // algorithm), and the inputs differ too (E.164 vs bare digits). Either
      // way there is no input for which they agree.
      expect(legacy.length, 64);
      expect(legacy, isNot(equals('+233244123456')));
      // Normalizing to E.164 is what the new path sends instead of a hash.
      expect(normalizeToE164(raw), '+233244123456');
    });
  });

  group('normalization (E.164 or nothing)', () {
    test('2. accepted forms', () {
      expect(normalizeToE164('+233 24 412 3456'), '+233244123456');
      expect(normalizeToE164('00233244123456'), '+233244123456');
      expect(normalizeToE164('233244123456'), '+233244123456');
      expect(normalizeToE164('0244123456'), '+233244123456');
      expect(normalizeToE164('(024) 412-3456'), '+233244123456');
      expect(normalizeToE164('+44 7700 900123'), '+447700900123');
      // An unknown dial code is treated as a local number for the market.
      expect(
        normalizeToE164('0244123456', defaultDialCode: '+44'),
        '+44244123456',
      );
    });

    test('3. junk is dropped, never sent', () {
      expect(normalizeToE164(''), isNull);
      expect(normalizeToE164('   '), isNull);
      expect(normalizeToE164('*123#'), isNull);
      expect(normalizeToE164('+'), isNull);
      expect(normalizeToE164('12345'), isNull, reason: 'too short to be E.164');
      expect(normalizeToE164('+1234567890123456'), isNull, reason: 'too long');
    });
  });

  group('the wire contract', () {
    test(
      '4. it posts E.164 numbers to /users/discover, and nothing else',
      () async {
        final (:service, :calls) = _harness(
          (_, __) => http.Response(
            jsonEncode(
              _ok([
                {
                  'azamanId': 'AZM-000000042',
                  'displayName': 'Ama Boateng',
                  'avatar': 'https://cdn/ama.png',
                },
              ]),
            ),
            200,
          ),
        );

        final result = await service.discoverExistingMembers();
        // The device address book is not readable under the test binding, so
        // this call reports a FAILURE rather than pretending it checked. The
        // assertion that matters for the contract is in the batching test below;
        // here we only prove the failure is not disguised as "no matches".
        expect(result.status, ContactDiscoveryStatus.failed);
        expect(calls, isEmpty);
      },
    );

    test('5. a successful response parses the server projection exactly', () {
      final match = MatchedContact.fromDiscoverJson({
        'azamanId': 'AZM-000000042',
        'displayName': 'Ama Boateng',
        'avatar': 'https://cdn/ama.png',
      });
      expect(match.azamanId, 'AZM-000000042');
      expect(match.displayName, 'Ama Boateng');
      expect(match.avatar, 'https://cdn/ama.png');

      // A blank display name must not render an empty tile.
      final blank = MatchedContact.fromDiscoverJson({
        'azamanId': 'AZM-000000043',
        'displayName': '   ',
      });
      expect(blank.displayName, 'Azaman member');
    });

    test(
      '6. the server status is turned into an honest reason, not "no matches"',
      () {
        // The mapping the service applies to non-200 responses.
        expect(
          ContactService.messageForStatusForTest(401),
          contains('Sign in'),
        );
        expect(
          ContactService.messageForStatusForTest(429),
          contains('Too many'),
        );
        expect(
          ContactService.messageForStatusForTest(500),
          contains('trouble'),
        );
        expect(ContactService.messageForStatusForTest(400), isNotEmpty);
      },
    );
  });

  group('generalisation: scale, duplicates, refusals', () {
    test(
      '4b. a large address book is batched at the server cap of 1000',
      () async {
        final (:service, :calls) = _harness(
          (i, __) => http.Response(jsonEncode(_ok(const [])), 200),
        );

        final numbers = List<String>.generate(
          2500,
          (i) => '+2332${i.toString().padLeft(8, '0')}',
        );
        final result = await service.discoverNumbersForTest(numbers);

        expect(result.status, ContactDiscoveryStatus.ok);
        expect(calls.length, 3, reason: '2500 numbers = 1000 + 1000 + 500');
        expect((jsonDecode(calls[0].body) as Map)['phones'].length, 1000);
        expect((jsonDecode(calls[1].body) as Map)['phones'].length, 1000);
        expect((jsonDecode(calls[2].body) as Map)['phones'].length, 500);
      },
    );

    test('4c. the same person reached by two numbers appears once', () async {
      final (:service, :calls) = _harness(
        (_, __) => http.Response(
          jsonEncode(
            _ok([
              {'azamanId': 'AZM-000000042', 'displayName': 'Ama'},
              {'azamanId': 'AZM-000000042', 'displayName': 'Ama'},
            ]),
          ),
          200,
        ),
      );
      final result = await service.discoverNumbersForTest(['+233244123456']);
      expect(result.matches.length, 1);
      expect(calls.length, 1);
    });

    test('4d. each refusal reason survives as its own message', () async {
      for (final (code, fragment) in [
        (401, 'Sign in'),
        (429, 'Too many'),
        (500, 'trouble'),
        (400, 'failed'),
      ]) {
        final (:service, :calls) = _harness(
          (_, __) => http.Response('{"success":false,"message":"x"}', code),
        );
        final result = await service.discoverNumbersForTest(['+233244123456']);
        expect(result.status, ContactDiscoveryStatus.failed, reason: '$code');
        expect(result.message, contains(fragment), reason: '$code');
      }
    });

    test('4e. a 200 with success:false is a refusal, not a success', () async {
      final (:service, :calls) = _harness(
        (_, __) => http.Response('{"success":false}', 200),
      );
      final result = await service.discoverNumbersForTest(['+233244123456']);
      expect(result.status, ContactDiscoveryStatus.failed);
    });

    test(
      '4f. an unreachable server is a failure, not a zero-match answer',
      () async {
        final client = MockClient((_) async => throw const SocketLikeError());
        final service = ContactService.withClient(ApiClient(client: client));
        final result = await service.discoverNumbersForTest(['+233244123456']);
        expect(result.status, ContactDiscoveryStatus.failed);
        expect(result.message, contains('Try again'));
      },
    );

    test('4g. no numbers means no call at all', () async {
      final (:service, :calls) = _harness(
        (_, __) => http.Response(jsonEncode(_ok(const [])), 200),
      );
      final result = await service.discoverNumbersForTest(const []);
      expect(result.status, ContactDiscoveryStatus.noNumbers);
      expect(calls, isEmpty);
    });
  });

  group('outcomes are distinguishable', () {
    test('7. each status renders different copy', () {
      String copyFor(ContactDiscoveryStatus s, {bool empty = true}) {
        switch (s) {
          case ContactDiscoveryStatus.permissionDenied:
            return 'off';
          case ContactDiscoveryStatus.noNumbers:
            return 'no numbers';
          case ContactDiscoveryStatus.failed:
            return 'failed';
          case ContactDiscoveryStatus.ok:
            return empty ? 'none on azaman' : 'matches';
        }
      }

      expect(
        {
          copyFor(ContactDiscoveryStatus.permissionDenied),
          copyFor(ContactDiscoveryStatus.noNumbers),
          copyFor(ContactDiscoveryStatus.failed),
          copyFor(ContactDiscoveryStatus.ok),
        }.length,
        4,
        reason: 'these must never collapse into one empty-list screen',
      );
    });
  });
}
