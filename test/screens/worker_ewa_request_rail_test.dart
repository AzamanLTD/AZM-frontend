// =============================================================================
// EWA withdrawal rail contract (path + Phase H12 idempotency identity)
// =============================================================================
// POST /api/business-os/employees/my-ewa-request is a money-minting mutation:
// the backend REQUIRES a stable clientRequestId (EWA_IDEMPOTENCY_KEY_REQUIRED
// otherwise) so an exact retry replays the committed outcome instead of
// minting a second payout.
//
// This widget test pins BOTH halves of the corrected contract:
//   1. the exact POST path (no double /api prefix — the old bug 404'd),
//   2. the idempotency identity: a failed attempt retried at the SAME amount
//      reuses the SAME clientRequestId; a new amount mints a new key.
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/screens/worker/worker_ewa_screen.dart';
import 'package:azaman/services/api_client.dart';

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _EwaRailClient extends ApiClient {
  final List<String> getPaths = [];
  final List<Map<String, dynamic>> postBodies = [];
  int postCount = 0;
  http.Response Function(int attempt) respond = (n) =>
      _json(500, {'success': false, 'message': 'network error'});

  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    getPaths.add(endpoint);
    if (endpoint == '/business-os/employees/my-earnings') {
      return _json(200, {
        'success': true,
        'ewaAvailable': 30,
        'accruedWages': 100,
        'withdrawnEarly': 0,
        'ewaEligible': true,
        'ewaHistory': [],
      });
    }
    return _json(200, {'success': true, 'dashboard': null});
  }

  @override
  Future<http.Response> post(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    bool requireAuth = true,
    String? idempotencyKey,
  }) async {
    expect(
      endpoint,
      '/business-os/employees/my-ewa-request',
      reason: 'the corrected rail, exactly once-prefixed',
    );
    postBodies.add(Map<String, dynamic>.from(body));
    postCount++;
    return respond(postCount);
  }
}

Widget _app(WorkerEwaScreen screen, ApiClient client) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(client)],
    child: MaterialApp(home: screen),
  );
}

void main() {
  testWidgets(
    'EWA withdrawal posts to the real rail with a stable clientRequestId per action',
    (tester) async {
      final client = _EwaRailClient();

      await tester.pumpWidget(_app(const WorkerEwaScreen(), client));
      await tester.pumpAndSettle();

      // The screen's data rail is the EWA summary (my-earnings).
      expect(client.getPaths, contains('/business-os/employees/my-earnings'));

      // Enter an amount and submit — first attempt FAILS (lost response).
      await tester.enterText(find.byType(TextField), '12.50');
      await tester.tap(find.text('Withdraw Now'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(client.postBodies, hasLength(1));
      expect(client.postBodies.first['amount'], 12.5);
      final firstKey = client.postBodies.first['clientRequestId'];
      expect(firstKey, isA<String>());
      expect(
        (firstKey as String).isNotEmpty,
        isTrue,
        reason:
            'backend rejects an empty clientRequestId '
            '(EWA_IDEMPOTENCY_KEY_REQUIRED)',
      );

      // Retry the SAME amount after the failure: Phase H12 requires the SAME
      // logical request identity, or the retry mints a second payout.
      await tester.tap(find.text('Withdraw Now'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(client.postBodies, hasLength(2));
      expect(
        client.postBodies[1]['clientRequestId'],
        firstKey,
        reason: 'a same-amount retry must reuse the request identity',
      );

      // Succeed, then submit a DIFFERENT amount: a new action mints a new key.
      client.respond = (n) => _json(200, {'success': true});
      await tester.enterText(find.byType(TextField), '5');
      await tester.tap(find.text('Withdraw Now'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(client.postBodies, hasLength(3));
      expect(client.postBodies[2]['amount'], 5);
      expect(
        client.postBodies[2]['clientRequestId'],
        isNot(firstKey),
        reason: 'a new withdrawal action is a new request identity',
      );
    },
  );

  testWidgets('the EWA rail path is never double-prefixed', (tester) async {
    final client = _EwaRailClient()
      ..respond = (n) => _json(200, {'success': true});

    await tester.pumpWidget(_app(const WorkerEwaScreen(), client));
    await tester.pumpAndSettle();

    for (final path in [...client.getPaths]) {
      expect(
        path.startsWith('/api/'),
        isFalse,
        reason: 'ApiClient baseUrl already ends in /api — saw $path',
      );
    }
  });
}
