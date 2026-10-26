// test/services/deposit_recovery_service_test.dart
// =============================================================================
// INTERRUPTED-DEPOSIT RECOVERY (PR #202 item 1) — service-level regressions.
//
// DepositRecoveryService resolves a persisted payment reference (the
// backend's unique txHash) to the durable state of its deposit:
//   Step 1  GET /finance/transactions?q=<ref>   — reference -> ledger row
//   Step 2  GET /deposit/fiat/status/<rowId>   — Backend F continuation
//
// Cases pinned here:
//   1. pending row + status 200   -> pending + continuation + row id
//   2. settled row                -> settled, and NO status call (a
//      completed deposit has nothing left to continue)
//   3. failed row                 -> failed, NO status call
//   4. frozen row                 -> frozen, continuation attempted
//   5. contains-only txHash match -> unknown (substring search must not
//      resolve a DIFFERENT deposit)
//   6. no match at all            -> unknown
//   7. status endpoint 404 (backend without #375) -> pending,
//      continuation null — the ledger row alone told the truth
//   8. history GET 500 / throws   -> unknown, never an exception
//   9. blank reference             -> unknown, zero HTTP calls
//  10. unrecognised row status    -> unknown, never mapped onto a claim
//  11. exact call sequence: history first, status only for live rows
// =============================================================================
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/deposit_recovery_service.dart';

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

class _ScriptedCall {
  _ScriptedCall(this.path, this.status, this.body);
  final String path; // matched by suffix
  final int status;
  final Map<String, dynamic> body;
}

class _FakeClient extends ApiClient {
  _FakeClient(this.script, {this.throwOn = const <String>[]});
  final List<_ScriptedCall> script;
  final List<String> throwOn;

  /// Every GET this client served, in order — the exact wire sequence.
  final List<String> calls = [];

  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers, bool requireAuth = true}) async {
    for (final c in script) {
      if (endpoint.contains(c.path)) {
        if (throwOn.contains(c.path)) {
          throw http.ClientException('network refused', Uri.parse(endpoint));
        }
        calls.add(endpoint);
        return _json(c.status, c.body);
      }
    }
    throw StateError('recovery test: unexpected GET $endpoint');
  }
}

const _ref = 'MOOLRE_DEP_12_1712345678_a1b2c3d4';

Map<String, dynamic> _row(String id, String status, {String? txHash}) => {
      'id': id,
      'txHash': txHash ?? _ref,
      'status': status,
      'type': 'DEPOSIT_FIAT',
    };

void main() {
  group('DepositRecoveryService.recover', () {
    test('pending row -> pending with row id and Backend F continuation',
        () async {
      final client = _FakeClient([
        _ScriptedCall('/finance/transactions', 200, {
          'success': true,
          'transactions': [_row('row-1', 'PENDING')],
        }),
        _ScriptedCall('/deposit/fiat/status/row-1', 200, {
          'success': true,
          'transaction': {'id': 'row-1', 'status': 'PENDING'},
          'continuation': {
            'provider': 'MTN',
            'amountGhs': '50.00',
            'quoteExpiresAt': '2026-10-25T21:20:00.000Z',
            'payerPhoneMasked': '0244***222',
          },
        }),
      ]);
      final out = await DepositRecoveryService(client).recover(_ref);

      expect(out.status, DepositRecoveryStatus.pending);
      expect(out.transactionId, 'row-1');
      expect(out.continuation?['provider'], 'MTN');
      expect(out.continuation?['amountGhs'], '50.00');
      expect(out.isLive, isTrue);
      // Wire shape: the reference rides the history search as an
      // encoded query parameter; the status call rides the ROW ID.
      expect(client.calls.first, contains('q=$_ref'));
      expect(client.calls.last, '/deposit/fiat/status/row-1');
      expect(client.calls.length, 2);
    });

    test('settled row -> settled, and NO continuation call is made',
        () async {
      final client = _FakeClient([
        _ScriptedCall('/finance/transactions', 200, {
          'success': true,
          'transactions': [_row('row-2', 'COMPLETED')],
        }),
        // No status route scripted: any call would throw StateError.
      ]);
      final out = await DepositRecoveryService(client).recover(_ref);

      expect(out.status, DepositRecoveryStatus.settled);
      expect(out.transactionId, 'row-2');
      expect(out.continuation, isNull);
      expect(client.calls, hasLength(1));
    });

    test('failed row -> failed, no continuation call', () async {
      final client = _FakeClient([
        _ScriptedCall('/finance/transactions', 200, {
          'success': true,
          'transactions': [_row('row-3', 'FAILED')],
        }),
      ]);
      final out = await DepositRecoveryService(client).recover(_ref);

      expect(out.status, DepositRecoveryStatus.failed);
      expect(out.isLive, isFalse);
      expect(client.calls, hasLength(1));
    });

    test('frozen row -> frozen with continuation (dispute flow owns it)',
        () async {
      final client = _FakeClient([
        _ScriptedCall('/finance/transactions', 200, {
          'success': true,
          'transactions': [_row('row-4', 'FROZEN_DISPUTE')],
        }),
        _ScriptedCall('/deposit/fiat/status/row-4', 200, {
          'success': true,
          'continuation': {'provider': 'MTN'},
        }),
      ]);
      final out = await DepositRecoveryService(client).recover(_ref);

      expect(out.status, DepositRecoveryStatus.frozen);
      expect(out.isLive, isTrue);
      expect(out.continuation?['provider'], 'MTN');
    });

    test('a CONTAINS-only txHash match must not resolve a foreign deposit',
        () async {
      // The backend q= search is a substring search: another deposit's
      // hash ending in the same characters must not be adopted.
      final client = _FakeClient([
        _ScriptedCall('/finance/transactions', 200, {
          'success': true,
          'transactions': [
            _row('row-other', 'PENDING', txHash: 'XX_$_ref'),
          ],
        }),
      ]);
      final out = await DepositRecoveryService(client).recover(_ref);

      expect(out.status, DepositRecoveryStatus.unknown);
      expect(out.transactionId, isNull);
      expect(client.calls, hasLength(1));
    });

    test('no matching row at all -> unknown', () async {
      final client = _FakeClient([
        _ScriptedCall('/finance/transactions', 200, {
          'success': true,
          'transactions': <Map<String, dynamic>>[],
        }),
      ]);
      final out = await DepositRecoveryService(client).recover(_ref);

      expect(out.status, DepositRecoveryStatus.unknown);
    });

    test('status endpoint absent (404) -> pending, continuation null',
        () async {
      final client = _FakeClient([
        _ScriptedCall('/finance/transactions', 200, {
          'success': true,
          'transactions': [_row('row-5', 'PENDING')],
        }),
        _ScriptedCall('/deposit/fiat/status/row-5', 404,
            {'success': false, 'message': 'Not found.'}),
      ]);
      final out = await DepositRecoveryService(client).recover(_ref);

      expect(out.status, DepositRecoveryStatus.pending);
      expect(out.continuation, isNull);
      // The ledger row still told the truth — degradation, not failure.
      expect(out.transactionId, 'row-5');
    });

    test('history GET 500 -> unknown, never throws', () async {
      final client = _FakeClient([
        _ScriptedCall('/finance/transactions', 500,
            {'success': false, 'message': 'internal'}),
      ]);
      final out = await DepositRecoveryService(client).recover(_ref);

      expect(out.status, DepositRecoveryStatus.unknown);
    });

    test('network refusal on history -> unknown, never throws', () async {
      final client = _FakeClient(
        [_ScriptedCall('/finance/transactions', 200, {})],
        throwOn: ['/finance/transactions'],
      );
      final out = await DepositRecoveryService(client).recover(_ref);

      expect(out.status, DepositRecoveryStatus.unknown);
      expect(client.calls, isEmpty);
    });

    test('blank reference -> unknown with ZERO HTTP calls', () async {
      final client = _FakeClient([]);
      final out = await DepositRecoveryService(client).recover('   ');

      expect(out.status, DepositRecoveryStatus.unknown);
      expect(client.calls, isEmpty);
    });

    test('unrecognised row status -> unknown, never mapped onto a claim',
        () async {
      final client = _FakeClient([
        _ScriptedCall('/finance/transactions', 200, {
          'success': true,
          'transactions': [_row('row-6', 'SOMETHING_NEW')],
        }),
      ]);
      final out = await DepositRecoveryService(client).recover(_ref);

      expect(out.status, DepositRecoveryStatus.unknown);
    });
  });
}
