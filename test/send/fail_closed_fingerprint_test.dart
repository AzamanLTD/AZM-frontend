// =============================================================================
// AZAMAN — FAIL-CLOSED PENDING FINGERPRINT TESTS (PR #165 review finding 3)
//
// The contract under test:
//   • FriendService.sendFunds opts into
//     `failClosedOnPendingFingerprintChange`: while the send flow of a
//     friendship holds an UNRESOLVED durable instance, a MATERIALLY
//     DIFFERENT send request is REFUSED with
//     PendingFinancialOperationException and ZERO wire traffic — never a
//     silent replacement of the unresolved operation.
//   • The UNCHANGED retry converges on the SAME durable identity.
//   • Fail-closed is opt-in per flow: flows without the flag keep the
//     legacy semantics (a changed request begins a genuinely new
//     instance, the old one stays pending and recoverable).
//   • Once the pending instance is retired (2xx answered), a changed
//     request is a genuinely new action again.
// =============================================================================

import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/friend_service.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

class _Recorder {
  final requests = <http.Request>[];
  http.Response? reply;
  Object? throwOnNext;

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (throwOnNext != null) {
      final Object t = throwOnNext!;
      throwOnNext = null;
      throw t;
    }
    return reply ??
        http.Response(
          jsonEncode({'success': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
  });
}

const _storageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void _mockSecureStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
    if (call.method == 'read') return 'mock-token';
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _mockSecureStorage();
    ApiClient.operationAccountOverride = () async => 'test-account';
    SharedPreferences.setMockInitialValues({});
    DurableOperationRegistry.storageWriterOverride = null;
  });

  tearDown(() {
    ApiClient.operationAccountOverride = null;
    DurableOperationRegistry.storageWriterOverride = null;
  });

  test(
      'sendFunds: a changed fingerprint while the send flow holds a PENDING '
      'instance FAILS CLOSED — zero wire traffic, the instance survives',
      () async {
    final rec = _Recorder();
    final svc = FriendService.forTesting(ApiClient(client: rec.client));

    // First attempt: the response is lost mid-flight — the durable
    // instance stays pending.
    rec.throwOnNext = http.ClientException('Server unreachable');
    await expectLater(
        svc.sendFunds('fs-cc', 5.0, null, 'tok'), throwsA(anything));
    expect(rec.requests, hasLength(1));
    final pendingAfterDrop =
        await DurableOperationRegistry.pending(type: 'friend.transfer.send.fs-cc');
    expect(pendingAfterDrop, hasLength(1),
        reason: 'the dropped attempt left exactly one unresolved instance');

    // A MATERIALLY different send on the same friendship while that
    // instance is unresolved: refused, nothing on the wire.
    await expectLater(
        svc.sendFunds('fs-cc', 6.0, null, 'tok'),
        throwsA(isA<PendingFinancialOperationException>().having(
            (e) => e.operationId, 'operationId', pendingAfterDrop.single.operationId)));
    expect(rec.requests, hasLength(1),
        reason: 'fail-closed refusal means ZERO new wire traffic');

    // The pending instance is untouched — still recoverable.
    final stillPending =
        await DurableOperationRegistry.pending(type: 'friend.transfer.send.fs-cc');
    expect(stillPending, hasLength(1));
    expect(stillPending.single.operationId, pendingAfterDrop.single.operationId);
  });

  test(
      'sendFunds: the UNCHANGED retry converges on the SAME durable '
      'identity, then a changed send is genuinely new after retirement',
      () async {
    final rec = _Recorder();
    final svc = FriendService.forTesting(ApiClient(client: rec.client));

    rec.throwOnNext = http.ClientException('dropped');
    await expectLater(
        svc.sendFunds('fs-rr', 5.0, null, 'tok'), throwsA(anything));

    // Unchanged retry: SAME identity, succeeds, the instance retires.
    await svc.sendFunds('fs-rr', 5.0, null, 'tok');
    expect(rec.requests, hasLength(2));
    expect(rec.requests[1].headers['Idempotency-Key'],
        rec.requests[0].headers['Idempotency-Key'],
        reason: 'the unchanged retry converges on the same operation');
    expect(await DurableOperationRegistry.pending(type: 'friend.transfer.send.fs-rr'),
        isEmpty,
        reason: 'a 2xx retires the instance');

    // Resolved flow: a changed request is now a genuinely new action.
    await svc.sendFunds('fs-rr', 7.0, null, 'tok');
    expect(rec.requests, hasLength(3));
    expect(rec.requests[2].headers['Idempotency-Key'],
        isNot(rec.requests[0].headers['Idempotency-Key']),
        reason: 'a new logical transfer gets a fresh identity');
  });

  test(
      'fail-closed is OPT-IN: a flow without the flag keeps the legacy '
      'semantics — a changed fingerprint begins a genuinely new instance, '
      'both remain recoverable',
      () async {
    final rec = _Recorder();
    final api = ApiClient(client: rec.client);
    final ref = FinancialOperationRef();

    // Flow WITHOUT failClosedOnPendingFingerprintChange (legacy default).
    rec.throwOnNext = http.ClientException('dropped');
    await expectLater(
        api.postFinancial('/legacy/flow', {'value': 'A'},
            operationType: 'legacy.flow', ref: ref),
        throwsA(anything));
    expect(rec.requests, hasLength(1));

    // A materially different request: NO exception — a new instance is
    // begun and the request goes out on the wire.
    await api.postFinancial('/legacy/flow', {'value': 'B'},
        operationType: 'legacy.flow', ref: ref);
    expect(rec.requests, hasLength(2), reason: 'legacy flows do not block');
    expect(rec.requests[1].headers['Idempotency-Key'],
        isNot(rec.requests[0].headers['Idempotency-Key']),
        reason: 'the changed request is a genuinely new instance');

    // The changed request SUCCEEDED — its own instance retired on the
    // 2xx. The PRIOR instance (the dropped attempt A) is still pending,
    // untouched: legacy semantics replace nothing, orphan nothing.
    final pending =
        await DurableOperationRegistry.pending(type: 'legacy.flow');
    expect(pending, hasLength(1),
        reason: 'only the dropped attempt is outstanding');
    expect(pending.single.fingerprint,
        DurableOperationRegistry.fingerprintOf({'value': 'A'}),
        reason: 'the surviving instance is the ORIGINAL request A — '
            'the legacy flow never replaced or orphaned it');
  });

  test(
      'a DIFFERENT flow is never blocked by another flow\'s pending '
      'instance — the namespaces are per operation type',
      () async {
    final rec = _Recorder();
    final svc = FriendService.forTesting(ApiClient(client: rec.client));
    final api = ApiClient(client: rec.client);

    // Leave a send of fs-x unresolved.
    rec.throwOnNext = http.ClientException('dropped');
    await expectLater(
        svc.sendFunds('fs-x', 5.0, null, 'tok'), throwsA(anything));
    expect(rec.requests, hasLength(1));

    // A different operation type proceeds normally while it is pending.
    await api.postFinancial('/other/flow', {'value': 'A'},
        operationType: 'other.flow');
    expect(rec.requests, hasLength(2),
        reason: 'fail-closed scopes to the flow, not to the account');
  });
}
