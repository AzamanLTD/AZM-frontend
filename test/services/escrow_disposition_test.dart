// r42 ESCROW DISPOSITION REGRESSION (independent audit pass 3).
//
// Every EscrowService mutation flows through _withDurableKey, whose
// disposition must mirror ApiClient.postFinancial's contract EXACTLY:
//
//   2xx                                   → retire (authoritative answer)
//   definitive pre-economic 4xx            → retire (nothing committed)
//   401 / 409 / 429                        → retain (retry same key)
//   5xx                                   → retain (may have committed)
//   network loss / timeout                 → retain (no answer at all)
//
// The pre-pass-3 code caught only EscrowServiceException — but ApiClient
// maps every non-2xx HTTP answer to ApiException, which escaped the catch
// entirely: definitive 4xx left zombie instances pending forever, and a
// malformed-2xx EscrowServiceException RETIRED an instance whose fund may
// have committed (a re-tap would mint a NEW key and fund a SECOND time).
//
// These tests pin the corrected behavior on the wire with the REAL service.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/escrow_service.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const account = 'user-1';
  const type = 'escrow.dispute.esc-1';

  // EscrowService posts with requireAuth (production default), so the
  // secure-storage channel must answer instead of throwing
  // MissingPluginException.
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
    ApiClient.operationAccountOverride = () async => account;
    SharedPreferences.setMockInitialValues({});
    DurableOperationRegistry.storageWriterOverride = null;
  });

  tearDown(() {
    ApiClient.operationAccountOverride = null;
    DurableOperationRegistry.storageWriterOverride = null;
  });

  http.Response _json(Object body, int status) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  test('5xx RETAINS the durable instance — the retry reuses the SAME key '
      '(a 5xx may have committed the dispute)', () async {
    final sent = <http.Request>[];
    var calls = 0;
    final service = EscrowService(client: ApiClient(client: MockClient((r) async {
      sent.add(r);
      calls += 1;
      if (calls == 1) {
        return _json({'message': 'internal error'}, 500);
      }
      return _json({
        'escrow': {'id': 'esc-1', 'status': 'DISPUTED'},
      }, 200);
    })));

    await expectLater(
        service.raiseDispute(escrowId: 'esc-1', reason: 'damaged goods'),
        throwsA(isA<ApiException>()));
    expect(sent, hasLength(1));

    // The instance must STILL be pending — not retired, not replaced.
    var ops = await DurableOperationRegistry.pending(account: account, type: type);
    expect(ops, hasLength(1));

    // The user's retry: SAME instance, SAME key.
    final escrow = await service.raiseDispute(
        escrowId: 'esc-1', reason: 'damaged goods');
    expect(escrow.id, 'esc-1');
    expect(sent, hasLength(2));
    expect(sent[0].headers['Idempotency-Key'],
        sent[1].headers['Idempotency-Key'],
        reason: 'a 5xx must never mint a second identity');

    // The answered 2xx retires it.
    ops = await DurableOperationRegistry.pending(account: account, type: type);
    expect(ops, isEmpty);
  });

  test('definitive pre-economic 4xx RETIRES the instance — the next '
      'genuinely new action may mint a fresh key', () async {
    final sent = <http.Request>[];
    var calls = 0;
    final service = EscrowService(client: ApiClient(client: MockClient((r) async {
      sent.add(r);
      calls += 1;
      if (calls == 1) {
        return _json({'message': 'escrow already settled'}, 400);
      }
      return _json({
        'escrow': {'id': 'esc-1', 'status': 'DISPUTED'},
      }, 200);
    })));

    await expectLater(
        service.raiseDispute(escrowId: 'esc-1', reason: 'damaged goods'),
        throwsA(isA<ApiException>()));
    expect(sent, hasLength(1));

    // A definitive 400 means the handler refused BEFORE any economic
    // effect: the instance retires and does not linger as a zombie.
    final ops =
        await DurableOperationRegistry.pending(account: account, type: type);
    expect(ops, isEmpty);

    // A genuinely new dispute action mints a fresh key.
    await service.raiseDispute(escrowId: 'esc-1', reason: 'damaged goods');
    expect(sent, hasLength(2));
    expect(sent[0].headers['Idempotency-Key'],
        isNot(sent[1].headers['Idempotency-Key']));
  });

  test('409 RETAINS the instance — the backend replay conflict is an '
      'authoritative in-progress answer, not a failure', () async {
    final sent = <http.Request>[];
    final service = EscrowService(client: ApiClient(client: MockClient((r) async {
      sent.add(r);
      return _json({'message': 'operation already in progress'}, 409);
    })));

    await expectLater(
        service.raiseDispute(escrowId: 'esc-1', reason: 'damaged goods'),
        throwsA(isA<ApiException>()));

    final ops =
        await DurableOperationRegistry.pending(account: account, type: type);
    expect(ops, hasLength(1),
        reason: 'a 409 idempotency replay keeps the instance armed');
  });

  test('malformed 2xx RETAINS the instance — the HTTP answer was '
      'successful, so the dispute may have committed', () async {
    final sent = <http.Request>[];
    final service = EscrowService(client: ApiClient(client: MockClient((r) async {
      sent.add(r);
      // 2xx but the body is not an escrow payload.
      return _json({'unexpected': true}, 200);
    })));

    await expectLater(
        service.raiseDispute(escrowId: 'esc-1', reason: 'damaged goods'),
        throwsA(isA<EscrowServiceException>()));

    final ops =
        await DurableOperationRegistry.pending(account: account, type: type);
    expect(ops, hasLength(1),
        reason: 'a successful HTTP answer with a garbage body may still '
            'have committed — retiring would let a re-tap fund twice');
  });
}
