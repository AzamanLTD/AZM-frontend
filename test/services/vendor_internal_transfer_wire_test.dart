// =============================================================================
// VENDOR INTERNAL TRANSFER — WIRE CONTRACT (§r42.2 client half)
//
// These tests assert the REQUEST as it actually leaves the device, through the
// real ApiClient with a mocked HTTP transport:
//
//   1. `amount` is a JSON STRING on the wire.
//   2. An 8-dp entry survives serialisation digit for digit.
//   3. The value is never a JSON number, so no double conversion happened.
//   4. Invalid text cannot produce a request at all (no instance exists).
//   5. A retry of the same operation reuses its identity.
//   6. A genuinely new transfer gets a new identity.
//   7. The success line reports the submitted amount exactly.
//
// SCOPE: a mocked transport proves CLIENT request behaviour. It is NOT proof
// of backend settlement, and until the backend's exact-decimal parser (PR
// #399) is integrated the deployed server still runs `parseFloat` on this
// string.
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/screens/vendor_dashboard.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/durable_operation_registry.dart';
import 'package:azaman/utils/exact_usdc_amount.dart';

/// Records every outgoing request so the exact wire bytes can be inspected.
class _Recorder {
  final requests = <http.Request>[];
  final int status;
  final String replyBody;

  _Recorder({this.status = 200, this.replyBody = '{"success":true}'});

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    return http.Response(
      replyBody,
      status,
      headers: {'content-type': 'application/json'},
    );
  });

  Map<String, dynamic> get lastJson =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;
}

const _actionId = 'vendor.wallet.internal-transfer';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ApiClient.operationAccountOverride = null;
    SharedPreferences.setMockInitialValues({});
    DurableOperationRegistry.storageWriterOverride = null;
  });

  tearDown(() {
    ApiClient.operationAccountOverride = null;
    DurableOperationRegistry.storageWriterOverride = null;
  });

  group('request body', () {
    test('amount is transmitted as a JSON STRING, not a number', () async {
      final rec = _Recorder();
      final api = ApiClient(client: rec.client);
      final amount = ExactUsdcAmount.parse('0.12345678').value!;

      await api.postFinancial(
        '/wallet/internal-transfer',
        buildVendorInternalTransferBody('TO_POOL', amount),
        operationType: _actionId,
        requireAuth: false,
      );

      final body = rec.lastJson;
      expect(body['direction'], 'TO_POOL');
      expect(
        body['amount'],
        isA<String>(),
        reason: 'a JSON number lets the server re-read a double',
      );
      // The authority is the raw wire TEXT: quotes around the amount.
      expect(rec.requests.last.body, contains('"amount":"0.12345678"'));
    });

    test(
      'eight-decimal precision survives serialisation digit for digit',
      () async {
        for (final input in <String>[
          '0.12345678',
          '1.00000001',
          '0.00000001',
          '999999999999.99999999',
        ]) {
          final rec = _Recorder();
          final api = ApiClient(client: rec.client);
          final amount = ExactUsdcAmount.parse(input).value!;

          await api.postFinancial(
            '/wallet/internal-transfer',
            buildVendorInternalTransferBody('TO_POOL', amount),
            operationType: _actionId,
            requireAuth: false,
          );

          expect(rec.lastJson['amount'], input, reason: input);
          expect(
            rec.requests.last.body,
            contains('"amount":"$input"'),
            reason: '$input must arrive quoted',
          );
        }
      },
    );

    test('FROM_POOL carries the same string shape', () async {
      final rec = _Recorder();
      final api = ApiClient(client: rec.client);
      final amount = ExactUsdcAmount.parse('12.34').value!;

      await api.postFinancial(
        '/wallet/internal-transfer',
        buildVendorInternalTransferBody('FROM_POOL', amount),
        operationType: _actionId,
        requireAuth: false,
      );

      expect(rec.lastJson, {'direction': 'FROM_POOL', 'amount': '12.34'});
    });

    test('the body carries exactly the two documented keys', () {
      final amount = ExactUsdcAmount.parse('1.5').value!;
      final body = buildVendorInternalTransferBody('TO_POOL', amount);
      expect(body.keys.toSet(), {'direction', 'amount'});
    });

    test('the request targets the existing endpoint — no new field', () async {
      final rec = _Recorder();
      final api = ApiClient(client: rec.client);
      final amount = ExactUsdcAmount.parse('5').value!;

      await api.postFinancial(
        '/wallet/internal-transfer',
        buildVendorInternalTransferBody('TO_POOL', amount),
        operationType: _actionId,
        requireAuth: false,
      );

      expect(
        rec.requests.single.url.path,
        endsWith('/api/wallet/internal-transfer'),
      );
      expect(
        rec.requests.single.headers['Idempotency-Key'],
        isNotEmpty,
        reason: 'the financial-operation identity is unchanged',
      );
    });
  });

  group('invalid input cannot reach the request layer', () {
    test('no exact amount exists for any refused entry', () {
      const invalid = <String>[
        '',
        '   ',
        '0',
        '0.00000000',
        '-1',
        '-0.5',
        '0.123456789',
        '1e-7',
        'abc',
        '1,5',
        '1 2',
        '1000000000000',
      ];
      for (final input in invalid) {
        expect(
          ExactUsdcAmount.tryParse(input),
          isNull,
          reason: '"$input" must not produce a submittable amount',
        );
      }
      // buildVendorInternalTransferBody takes an ExactUsdcAmount, so with no
      // instance there is nothing to send: invalid text cannot be smuggled in.
    });

    test('a nine-dp entry is refused rather than truncated to eight', () {
      final parsed = ExactUsdcAmount.parse('0.123456789');
      expect(parsed.isValid, isFalse);
      expect(parsed.refusal, UsdcAmountRefusal.tooManyDecimals);
      // What a truncating client would have submitted instead:
      expect(
        ExactUsdcAmount.parse('0.12345678').value!.wireAmount,
        '0.12345678',
      );
    });
  });

  group('idempotency identity', () {
    /// The retry cases must FAIL first: r42 retires an instance the moment the
    /// operation is answered, so a same-key retry only exists while the
    /// instance is still pending (5xx or an unanswered request).
    Future<void> expectThrows(Future<void> Function() call) async {
      try {
        await call();
      } catch (_) {
        return;
      }
      fail('the transport was expected to fail');
    }

    test('a retry after a 5xx keeps the SAME key', () async {
      final failing = _Recorder(
        status: 500,
        replyBody: '{"success":false,"message":"boom"}',
      );
      final api = ApiClient(client: failing.client);
      final ref = FinancialOperationRef();
      final amount = ExactUsdcAmount.parse('0.5').value!;

      for (var i = 0; i < 2; i++) {
        await expectThrows(
          () => api.postFinancial(
            '/wallet/internal-transfer',
            buildVendorInternalTransferBody('TO_POOL', amount),
            operationType: _actionId,
            ref: ref,
            requireAuth: false,
          ),
        );
      }

      expect(failing.requests, hasLength(2));
      expect(
        failing.requests[1].headers['Idempotency-Key'],
        failing.requests[0].headers['Idempotency-Key'],
        reason: 'a 5xx keeps the instance pending for a same-key retry',
      );
      expect(failing.requests[1].body, failing.requests[0].body);
    });

    test('a retry after an UNANSWERED request keeps the SAME key', () async {
      final sunk = <http.Request>[];
      final api = ApiClient(
        client: MockClient((request) async {
          sunk.add(request);
          throw http.ClientException('Server unreachable');
        }),
      );
      final ref = FinancialOperationRef();
      final amount = ExactUsdcAmount.parse('0.12345678').value!;

      for (var i = 0; i < 2; i++) {
        await expectThrows(
          () => api.postFinancial(
            '/wallet/internal-transfer',
            buildVendorInternalTransferBody('TO_POOL', amount),
            operationType: _actionId,
            ref: ref,
            requireAuth: false,
          ),
        );
      }

      expect(
        sunk[1].headers['Idempotency-Key'],
        sunk[0].headers['Idempotency-Key'],
        reason: 'network loss retains the instance for a same-key retry',
      );
    });

    test('a genuinely new transfer gets a new identity', () async {
      final rec = _Recorder();
      final api = ApiClient(client: rec.client);
      final amount = ExactUsdcAmount.parse('5').value!;

      for (var i = 0; i < 2; i++) {
        await api.postFinancial(
          '/wallet/internal-transfer',
          buildVendorInternalTransferBody('TO_POOL', amount),
          operationType: _actionId,
          ref: FinancialOperationRef(),
          requireAuth: false,
        );
      }

      expect(
        rec.requests[0].headers['Idempotency-Key'],
        isNot(rec.requests[1].headers['Idempotency-Key']),
      );
    });

    test(
      'an ANSWERED transfer retires its identity (next move is new)',
      () async {
        // Documents the lifecycle the retry tests above depend on: a 200 means
        // the operation is answered, so reusing the ref must NOT replay it.
        final rec = _Recorder();
        final api = ApiClient(client: rec.client);
        final ref = FinancialOperationRef();
        final amount = ExactUsdcAmount.parse('7').value!;

        for (var i = 0; i < 2; i++) {
          await api.postFinancial(
            '/wallet/internal-transfer',
            buildVendorInternalTransferBody('TO_POOL', amount),
            operationType: _actionId,
            ref: ref,
            requireAuth: false,
          );
        }

        expect(rec.requests, hasLength(2));
        expect(
          rec.requests[1].headers['Idempotency-Key'],
          isNot(rec.requests[0].headers['Idempotency-Key']),
        );
      },
    );
  });

  group('confirmation copy', () {
    test('the success line shows the submitted amount exactly', () {
      final amount = ExactUsdcAmount.parse('0.12345678').value!;
      expect(
        vendorTransferSuccessLine('Trading Pool', amount),
        r'$0.12345678 moved to Trading Pool',
        reason: 'the old formatter said 0.12 — a different amount of money',
      );
    });

    test('the fractional tail the customer typed is kept', () {
      final amount = ExactUsdcAmount.parse('5.000').value!;
      expect(
        vendorTransferSuccessLine('Available Wallet', amount),
        r'$5.000 moved to Available Wallet',
      );
    });

    test('the confirmed amount equals the submitted amount', () async {
      final rec = _Recorder();
      final api = ApiClient(client: rec.client);
      final amount = ExactUsdcAmount.parse('0.12345678').value!;

      await api.postFinancial(
        '/wallet/internal-transfer',
        buildVendorInternalTransferBody('TO_POOL', amount),
        operationType: _actionId,
        requireAuth: false,
      );

      final submitted = rec.lastJson['amount'] as String;
      expect(
        vendorTransferSuccessLine('Trading Pool', amount),
        contains(submitted),
        reason: 'request amount and success message must agree',
      );
    });
  });
}
