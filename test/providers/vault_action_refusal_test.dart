// WP-L — the vault action refusals must survive the provider layer intact.
//
// These exercise the real VaultsNotifier against a stubbed financial client, so
// they prove the backend code and the action type reach the screen boundary
// instead of being flattened into a string (which is what breakEarly used to
// do).
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/providers/vault_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/money_refusal_copy.dart';

class _VaultApi extends ApiClient {
  _VaultApi({this.status = 400, this.body = const {}});

  final int status;
  final Map<String, dynamic> body;

  @override
  Future<http.Response> postFinancial(
    String endpoint,
    Map<String, dynamic> payload, {
    required String operationType,
    FinancialOperationRef? ref,
    bool requireAuth = true,
    Map<String, String>? headers,
    bool failClosedOnPendingFingerprintChange = false,
  }) async =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  @override
  Future<http.Response> get(String endpoint,
          {Map<String, String>? headers, bool requireAuth = true}) async =>
      http.Response(
        jsonEncode({'success': true, 'vaults': <dynamic>[]}),
        200,
        headers: {'content-type': 'application/json'},
      );
}

ProviderContainer _container(ApiClient api) {
  final c = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(api)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('a refused deposit keeps its code and is typed as a deposit', () async {
    final c = _container(_VaultApi(body: {
      'success': false,
      'code': 'INSUFFICIENT_BALANCE',
      'message': 'raw backend text',
    }));

    await expectLater(
      c.read(vaultsProvider.notifier).deposit('vault-1', 10),
      throwsA(
        isA<VaultActionRefused>()
            .having((e) => e.code, 'code', 'INSUFFICIENT_BALANCE')
            .having((e) => e.action, 'action', VaultAction.deposit)
            .having((e) => e.statusCode, 'statusCode', 400),
      ),
    );
  });

  test('a refused break keeps its code and is typed as a break', () async {
    final c = _container(_VaultApi(status: 409, body: {
      'success': false,
      'code': 'IDEMPOTENCY_IN_PROGRESS',
      'message': 'raw backend text',
    }));

    await expectLater(
      c.read(vaultsProvider.notifier).breakEarly('vault-1'),
      throwsA(
        isA<VaultActionRefused>()
            .having((e) => e.code, 'code', 'IDEMPOTENCY_IN_PROGRESS')
            .having((e) => e.action, 'action', VaultAction.breakEarly)
            .having((e) => e.statusCode, 'statusCode', 409),
      ),
    );
  });

  test('the two actions never share a refusal identity', () async {
    final deposit = VaultActionRefused(
      VaultAction.deposit,
      'INSUFFICIENT_BALANCE',
      'x',
      400,
    );
    final breakEarly = VaultActionRefused(
      VaultAction.breakEarly,
      'INSUFFICIENT_BALANCE',
      'x',
      400,
    );
    // Same backend code, different action: the screen must be able to tell them
    // apart so the fallback copy is deposit- or break-specific.
    expect(deposit.action, isNot(breakEarly.action));
  });

  group('certainty carried to the screen', () {
    test('an in-progress break never invites a second break', () {
      final copy = refusalCopyFor('IDEMPOTENCY_IN_PROGRESS')!;
      expect(copy.certainty, RefusalCertainty.stillProcessing);
      expect(copy.retryIsSafe, isFalse);
      expect(copy.nextStep.toLowerCase(), contains('activity'));
      expect(copy.display.toLowerCase(), isNot(contains('failed')));
    });

    test('an insufficient balance is a definitive, retry-safe refusal', () {
      final copy = refusalCopyFor('INSUFFICIENT_BALANCE')!;
      expect(copy.certainty, RefusalCertainty.refusedBeforeMoney);
      expect(copy.retryIsSafe, isTrue);
      expect(copy.display.toLowerCase(), contains('nothing was sent'));
    });

    test('an unproven code yields no claim either way', () {
      // A break that fails with an unrecognised code must fall back to the
      // screen's honest unknown-outcome copy, not a definite failure.
      expect(refusalCopyFor('SOME_UNMAPPED_BREAK_CODE'), isNull);
      final fallback = preparedAuthorityUnavailableCopy();
      expect(fallback.certainty, RefusalCertainty.unknownOutcome);
      expect(fallback.display.toLowerCase(), isNot(contains('failed')));
    });
  });

  test('a raw exception never escapes as the refusal message', () async {
    final c = _container(_VaultApi(body: {'message': 'internal detail'}));
    try {
      await c.read(vaultsProvider.notifier).breakEarly('vault-1');
      fail('expected a structured refusal');
    } on VaultActionRefused catch (e) {
      // toString is for logs only and must not leak the backend message.
      expect(e.toString(), isNot(contains('internal detail')));
      expect(refusalCopyFor(e.code), isNull);
    }
  });
}
