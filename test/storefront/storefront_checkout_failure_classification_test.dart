// =============================================================================
// RETAIL CHECKOUT RECOVERY — deep-dive step 2: failure classification.
//
// Step 1 (PR #130) fixed the durable lifecycle DISPOSITION of the live
// production checkout. This suite pins the ERROR TAXONOMY on top of that
// identity contract: the caller must be able to tell a DEFINITIVE
// pre-economic failure (safe to correct + retry as a NEW logical action)
// from an AMBIGUOUS/UNCONFIRMED outcome (may have committed; the same
// durable key must be reused) from AUTH/RATE-LIMIT/DOMAIN-CONFLICT states.
//
// Wire semantics pinned here were traced in backend
// routes/storefrontRoutes.js (2026-10-01): the checkout and order routes
// answer 400/403/404 for explicit pre-economic validation, 401 for auth
// (TOKEN_EXPIRED is auto-refreshed inside ApiClient before it can surface
// here), 409 ONLY for an idempotency-key fingerprint mismatch (an exact
// replay answers 200 with `idempotent: true`), and 201/200 with
// data:{order} on success.
//
// These tests run the REAL durable wiring (no mocked StorefrontService):
// classification must never contradict the identity lifecycle, so every
// class is pinned together with the ref/instance outcome it must leave
// behind.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/storefront/services/storefront_service.dart';
import 'package:azaman/storefront/core/checkout_failure_message.dart';
import 'package:azaman/storefront/services/storefront_conflict_exception.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

/// Records every outgoing request and replays a scripted sequence of
/// replies: each entry is either an [http.Response] or an exception to
/// throw. When the script is exhausted, replies 200/success.
class _ScriptedClient {
  final requests = <http.Request>[];
  final script = <Object>[];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (script.isNotEmpty) {
      final next = script.removeAt(0);
      if (next is http.Response) return next;
      throw next;
    }
    return _okOrder;
  });

  static final http.Response _okOrder = http.Response(
    jsonEncode({
      'success': true,
      'data': {
        'order': {'id': 'order-1', 'orderRef': 'R-001'},
      },
    }),
    200,
    headers: {'content-type': 'application/json'},
  );

  /// The backend's exact-replay answer (storefrontReplayOrConflict).
  static final http.Response okReplay = http.Response(
    jsonEncode({
      'success': true,
      'data': {
        'order': {'id': 'order-1', 'orderRef': 'R-001'},
        'idempotent': true,
      },
    }),
    200,
    headers: {'content-type': 'application/json'},
  );

  /// 2xx WITHOUT the order result — the malformed-success unknown state.
  static final http.Response malformedSuccess = http.Response(
    jsonEncode({'success': true, 'data': <String, dynamic>{}}),
    200,
    headers: {'content-type': 'application/json'},
  );

  /// WP-1.10 refusal: the backend sends an honest message AND a code.
  static http.Response refused(String code, String message) => http.Response(
    jsonEncode({'message': message, 'code': code}),
    409,
    headers: {'content-type': 'application/json'},
  );

  static http.Response status(int code, {String message = 'boom'}) =>
      http.Response(
        jsonEncode({'message': message}),
        code,
        headers: {'content-type': 'application/json'},
      );
}

const _type = 'storefront.cart.checkout';
const _biz = 'biz-001';

final _cartA = <Map<String, dynamic>>[
  {'productId': 'p1', 'quantity': 2},
];

StorefrontService _service(_ScriptedClient rec) =>
    StorefrontService(apiClient: ApiClient(client: rec.client));

String? _sentKey(http.Request request) =>
    (jsonDecode(request.body) as Map<String, dynamic>)['idempotencyKey']
        as String?;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    // The production checkout POST reads the auth token from secure
    // storage; answer null like an unauthenticated cold start.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
    ApiClient.operationAccountOverride = () async => 'acct-test';
    SharedPreferences.setMockInitialValues({});
    DurableOperationRegistry.storageWriterOverride = null;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    ApiClient.operationAccountOverride = null;
    DurableOperationRegistry.storageWriterOverride = null;
  });

  group('classifyStorefrontFailure — the pure classification matrix', () {
    test('answered statuses map to their economic classes', () {
      expect(
        StorefrontService.classifyStorefrontFailure(
          ApiException(message: 'Invalid cart', statusCode: 400),
        ),
        StorefrontFailureClass.definitivePreEconomic,
      );
      expect(
        StorefrontService.classifyStorefrontFailure(
          ApiException(message: 'Not found', statusCode: 404),
        ),
        StorefrontFailureClass.definitivePreEconomic,
      );
      expect(
        StorefrontService.classifyStorefrontFailure(
          ApiException(message: 'Forbidden', statusCode: 403),
        ),
        StorefrontFailureClass.definitivePreEconomic,
      );
      expect(
        StorefrontService.classifyStorefrontFailure(
          ApiException(
            message: 'Token expired',
            statusCode: 401,
            code: 'TOKEN_EXPIRED',
          ),
        ),
        StorefrontFailureClass.authenticationRequired,
      );
      expect(
        StorefrontService.classifyStorefrontFailure(
          ApiException(message: 'Slow down', statusCode: 429),
        ),
        StorefrontFailureClass.rateLimited,
      );
      expect(
        StorefrontService.classifyStorefrontFailure(
          ApiException(
            message: 'Key already used for different contents',
            statusCode: 409,
          ),
        ),
        StorefrontFailureClass.domainConflict,
      );
      expect(
        StorefrontService.classifyStorefrontFailure(
          ApiException(message: 'Request timeout', statusCode: 408),
        ),
        StorefrontFailureClass.ambiguousOrUnknown,
        reason:
            'an answered 408 does not prove the backend never '
            'received the request — same fail-safe as 5xx',
      );
      expect(
        StorefrontService.classifyStorefrontFailure(
          ApiException(message: 'Too early', statusCode: 425),
        ),
        StorefrontFailureClass.ambiguousOrUnknown,
        reason:
            'an answered 425 does not prove the backend never '
            'received the request — same fail-safe as 5xx',
      );
      expect(
        StorefrontService.classifyStorefrontFailure(
          ApiException(message: 'Internal', statusCode: 500),
        ),
        StorefrontFailureClass.ambiguousOrUnknown,
      );
      expect(
        StorefrontService.classifyStorefrontFailure(
          ApiException(message: 'Bad gateway', statusCode: 502),
        ),
        StorefrontFailureClass.ambiguousOrUnknown,
      );
    });

    test(
      'unproven outcomes fail safe as ambiguousOrUnknown — never definitive',
      () {
        expect(
          StorefrontService.classifyStorefrontFailure(
            const FormatException('successful but carried no order result'),
          ),
          StorefrontFailureClass.ambiguousOrUnknown,
        );
        expect(
          StorefrontService.classifyStorefrontFailure(
            http.ClientException('connection lost'),
          ),
          StorefrontFailureClass.ambiguousOrUnknown,
        );
        expect(
          StorefrontService.classifyStorefrontFailure(
            const HttpException('socket closed'),
          ),
          StorefrontFailureClass.ambiguousOrUnknown,
        );
        expect(
          StorefrontService.classifyStorefrontFailure(
            TimeoutException('request timeout'),
          ),
          StorefrontFailureClass.ambiguousOrUnknown,
        );
        expect(
          StorefrontService.classifyStorefrontFailure(
            StateError('anything unrecognized'),
          ),
          StorefrontFailureClass.ambiguousOrUnknown,
        );
      },
    );

    test('defense-in-depth direct-response types classify the same way', () {
      expect(
        StorefrontService.classifyStorefrontFailure(
          const StorefrontApiException(statusCode: 409, message: 'conflict'),
        ),
        StorefrontFailureClass.domainConflict,
      );
      expect(
        StorefrontService.classifyStorefrontFailure(
          const StorefrontApiException(statusCode: 400, message: 'invalid'),
        ),
        StorefrontFailureClass.definitivePreEconomic,
      );
      expect(
        StorefrontService.classifyStorefrontFailure(
          const StorefrontConflictException(message: 'draft conflict'),
        ),
        StorefrontFailureClass.domainConflict,
      );
    });

    test('isUnconfirmed marks exactly the class whose outcome is unproven', () {
      expect(StorefrontFailureClass.ambiguousOrUnknown.isUnconfirmed, isTrue);
      for (final c in [
        StorefrontFailureClass.definitivePreEconomic,
        StorefrontFailureClass.authenticationRequired,
        StorefrontFailureClass.rateLimited,
        StorefrontFailureClass.domainConflict,
      ]) {
        expect(
          c.isUnconfirmed,
          isFalse,
          reason: '$c is an answered class — its outcome is proven',
        );
      }
    });
  });

  group('the live durable path leaves the identity the class requires', () {
    test(
      'definitive 400 → definitivePreEconomic AND the instance is retired',
      () async {
        final rec = _ScriptedClient();
        final ref = FinancialOperationRef();
        rec.script.add(
          _ScriptedClient.status(400, message: 'Maximum 50 items per order.'),
        );

        final err = await _errOf(
          () => _service(rec).checkoutCart(
            businessProfileId: _biz,
            items: _cartA,
            operationType: _type,
            ref: ref,
          ),
        );

        expect(
          StorefrontService.classifyStorefrontFailure(err),
          StorefrontFailureClass.definitivePreEconomic,
        );
        expect(
          ref.operationId,
          isNull,
          reason:
              'the disposition retired the instance — a corrected retry '
              'is a new logical action with a new identity',
        );

        // The corrected retry must NOT reuse the retired key.
        final second = await _service(rec).checkoutCart(
          businessProfileId: _biz,
          items: _cartA,
          operationType: _type,
          ref: ref,
        );
        expect(second['order']['orderRef'], 'R-001');
        expect(_sentKey(rec.requests[1]), isNot(_sentKey(rec.requests[0])));
      },
    );

    test(
      '401 → authenticationRequired AND the instance stays armed for the same-key retry',
      () async {
        final rec = _ScriptedClient();
        final ref = FinancialOperationRef();
        rec.script.add(_ScriptedClient.status(401, message: 'Not authorized'));

        final err = await _errOf(
          () => _service(rec).checkoutCart(
            businessProfileId: _biz,
            items: _cartA,
            operationType: _type,
            ref: ref,
          ),
        );

        expect(
          StorefrontService.classifyStorefrontFailure(err),
          StorefrontFailureClass.authenticationRequired,
        );
        expect(ref.operationId, isNotNull);

        // Re-auth then retry the SAME logical operation → SAME key, and the
        // backend converges (exact replay answers 200 idempotent).
        rec.script.add(_ScriptedClient.okReplay);
        await _service(rec).checkoutCart(
          businessProfileId: _biz,
          items: _cartA,
          operationType: _type,
          ref: ref,
        );
        expect(_sentKey(rec.requests[1]), _sentKey(rec.requests[0]));
        expect(ref.operationId, isNull, reason: 'success retires the instance');
      },
    );

    test(
      '409 → domainConflict AND retained; the retry keeps the same identity',
      () async {
        final rec = _ScriptedClient();
        final ref = FinancialOperationRef();
        rec.script.add(
          _ScriptedClient.status(
            409,
            message:
                'This checkout idempotency key was already used for different cart contents.',
          ),
        );

        final err = await _errOf(
          () => _service(rec).checkoutCart(
            businessProfileId: _biz,
            items: _cartA,
            operationType: _type,
            ref: ref,
          ),
        );

        expect(
          StorefrontService.classifyStorefrontFailure(err),
          StorefrontFailureClass.domainConflict,
        );
        expect(
          err,
          isA<ApiException>(),
          reason:
              'ApiClient maps every non-2xx to ApiException before the service parses it',
        );
        expect(ref.operationId, isNotNull);

        rec.script.add(_ScriptedClient.okReplay);
        await _service(rec).checkoutCart(
          businessProfileId: _biz,
          items: _cartA,
          operationType: _type,
          ref: ref,
        );
        expect(_sentKey(rec.requests[1]), _sentKey(rec.requests[0]));
      },
    );

    test('429 → rateLimited AND retained for the same-key retry', () async {
      final rec = _ScriptedClient();
      final ref = FinancialOperationRef();
      rec.script.add(_ScriptedClient.status(429, message: 'Too many requests'));

      final err = await _errOf(
        () => _service(rec).checkoutCart(
          businessProfileId: _biz,
          items: _cartA,
          operationType: _type,
          ref: ref,
        ),
      );

      expect(
        StorefrontService.classifyStorefrontFailure(err),
        StorefrontFailureClass.rateLimited,
      );
      expect(ref.operationId, isNotNull);

      rec.script.add(_ScriptedClient.okReplay);
      await _service(rec).checkoutCart(
        businessProfileId: _biz,
        items: _cartA,
        operationType: _type,
        ref: ref,
      );
      expect(_sentKey(rec.requests[1]), _sentKey(rec.requests[0]));
    });

    test(
      '408 → ambiguousOrUnknown AND retained; the retry reuses the SAME key (isRetryable parity)',
      () async {
        final rec = _ScriptedClient();
        final ref = FinancialOperationRef();
        rec.script.add(_ScriptedClient.status(408, message: 'Request timeout'));

        final err = await _errOf(
          () => _service(rec).checkoutCart(
            businessProfileId: _biz,
            items: _cartA,
            operationType: _type,
            ref: ref,
          ),
        );

        // Independent review 2026-10-01: StorefrontApiException.isRetryable
        // treats 408 as retryable, so the lifecycle must NOT retire it —
        // classification and disposition stay consistent.
        expect(
          StorefrontService.classifyStorefrontFailure(err),
          StorefrontFailureClass.ambiguousOrUnknown,
        );
        expect(
          const StorefrontApiException(
            statusCode: 408,
            message: 'x',
          ).isRetryable,
          isTrue,
          reason: 'consistency precondition: 408 is retryable',
        );
        expect(
          ref.operationId,
          isNotNull,
          reason:
              'the 408 instance stays ARMED — the backend may have '
              'committed before the gateway answered',
        );

        rec.script.add(_ScriptedClient.okReplay);
        await _service(rec).checkoutCart(
          businessProfileId: _biz,
          items: _cartA,
          operationType: _type,
          ref: ref,
        );
        expect(
          _sentKey(rec.requests[1]),
          _sentKey(rec.requests[0]),
          reason: 'the same-key retry converges on the committed order',
        );
      },
    );

    test(
      '425 → ambiguousOrUnknown AND retained; the retry reuses the SAME key (isRetryable parity)',
      () async {
        final rec = _ScriptedClient();
        final ref = FinancialOperationRef();
        rec.script.add(_ScriptedClient.status(425, message: 'Too early'));

        final err = await _errOf(
          () => _service(rec).checkoutCart(
            businessProfileId: _biz,
            items: _cartA,
            operationType: _type,
            ref: ref,
          ),
        );

        expect(
          StorefrontService.classifyStorefrontFailure(err),
          StorefrontFailureClass.ambiguousOrUnknown,
        );
        expect(
          const StorefrontApiException(
            statusCode: 425,
            message: 'x',
          ).isRetryable,
          isTrue,
          reason: 'consistency precondition: 425 is retryable',
        );
        expect(
          ref.operationId,
          isNotNull,
          reason: 'the 425 instance stays ARMED',
        );

        rec.script.add(_ScriptedClient.okReplay);
        await _service(rec).checkoutCart(
          businessProfileId: _biz,
          items: _cartA,
          operationType: _type,
          ref: ref,
        );
        expect(
          _sentKey(rec.requests[1]),
          _sentKey(rec.requests[0]),
          reason: 'the same-key retry converges on the committed order',
        );
      },
    );

    test(
      '5xx → ambiguousOrUnknown AND retained; the same-key retry converges',
      () async {
        final rec = _ScriptedClient();
        final ref = FinancialOperationRef();
        rec.script.add(_ScriptedClient.status(500, message: 'Internal error'));

        final err = await _errOf(
          () => _service(rec).checkoutCart(
            businessProfileId: _biz,
            items: _cartA,
            operationType: _type,
            ref: ref,
          ),
        );

        expect(
          StorefrontService.classifyStorefrontFailure(err),
          StorefrontFailureClass.ambiguousOrUnknown,
        );
        expect(ref.operationId, isNotNull);

        rec.script.add(_ScriptedClient.okReplay);
        await _service(rec).checkoutCart(
          businessProfileId: _biz,
          items: _cartA,
          operationType: _type,
          ref: ref,
        );
        expect(_sentKey(rec.requests[1]), _sentKey(rec.requests[0]));
      },
    );

    test(
      'transport loss → ambiguousOrUnknown AND retained; the same-key retry converges',
      () async {
        final rec = _ScriptedClient();
        final ref = FinancialOperationRef();
        rec.script.add(http.ClientException('Connection closed while sending'));

        final err = await _errOf(
          () => _service(rec).checkoutCart(
            businessProfileId: _biz,
            items: _cartA,
            operationType: _type,
            ref: ref,
          ),
        );

        expect(
          StorefrontService.classifyStorefrontFailure(err),
          StorefrontFailureClass.ambiguousOrUnknown,
        );
        expect(ref.operationId, isNotNull);

        rec.script.add(_ScriptedClient.okReplay);
        await _service(rec).checkoutCart(
          businessProfileId: _biz,
          items: _cartA,
          operationType: _type,
          ref: ref,
        );
        expect(_sentKey(rec.requests[1]), _sentKey(rec.requests[0]));
      },
    );

    test(
      'malformed 2xx (no order result) → FormatException, classified unknown AND retained',
      () async {
        final rec = _ScriptedClient();
        final ref = FinancialOperationRef();
        rec.script.add(_ScriptedClient.malformedSuccess);

        final err = await _errOf(
          () => _service(rec).checkoutCart(
            businessProfileId: _biz,
            items: _cartA,
            operationType: _type,
            ref: ref,
          ),
        );

        expect(
          err,
          isA<FormatException>(),
          reason:
              'a successful HTTP answer without the order result is an '
              'unknown economic state, never surfaced as success',
        );
        expect(
          StorefrontService.classifyStorefrontFailure(err),
          StorefrontFailureClass.ambiguousOrUnknown,
        );
        expect(ref.operationId, isNotNull);

        rec.script.add(_ScriptedClient.okReplay);
        await _service(rec).checkoutCart(
          businessProfileId: _biz,
          items: _cartA,
          operationType: _type,
          ref: ref,
        );
        expect(_sentKey(rec.requests[1]), _sentKey(rec.requests[0]));
      },
    );

    test(
      'partial/malformed order objects are NEVER success — unknown, retained, same-key retry',
      () async {
        // Independent review 2026-10-01: the old guard accepted any
        // {order: Map}, so {order: {}} was surfaced as success and retired
        // the instance. The guard now requires the minimum AUTHORITATIVE
        // shape both backend success paths guarantee and the caller's
        // confirmation contract requires: non-empty id + orderRef.
        final partialOrderBodies = <String, Map<String, dynamic>>{
          'empty order object': <String, dynamic>{},
          'order without id': {'orderRef': 'R-001'},
          'order without orderRef': {'id': 'order-1'},
          'order with empty-string id': {'id': '', 'orderRef': 'R-001'},
          'order with empty-string orderRef': {'id': 'order-1', 'orderRef': ''},
          'order with non-string id': {'id': 123, 'orderRef': 'R-001'},
          'order as a list, not a map': <String, dynamic>{},
        };

        for (var i = 0; i < partialOrderBodies.length; i++) {
          final label = partialOrderBodies.keys.elementAt(i);
          var body = partialOrderBodies.values.elementAt(i);
          if (label == 'order as a list, not a map') {
            body = <String, dynamic>{
              'order': ['not', 'a', 'map'],
            };
          } else {
            body = <String, dynamic>{'order': body};
          }

          final rec = _ScriptedClient();
          final ref = FinancialOperationRef();
          rec.script.add(
            http.Response(
              jsonEncode({'success': true, 'data': body}),
              200,
              headers: {'content-type': 'application/json'},
            ),
          );

          final err = await _errOf(
            () => _service(rec).checkoutCart(
              businessProfileId: _biz,
              items: _cartA,
              operationType: _type,
              ref: ref,
            ),
          );

          expect(
            err,
            isA<FormatException>(),
            reason:
                '$label: a 2xx without the authoritative order shape is '
                'an unknown economic state, never success',
          );
          expect(
            StorefrontService.classifyStorefrontFailure(err),
            StorefrontFailureClass.ambiguousOrUnknown,
            reason: label,
          );
          expect(
            ref.operationId,
            isNotNull,
            reason: '$label: the durable instance stays ARMED',
          );

          rec.script.add(_ScriptedClient.okReplay);
          await _service(rec).checkoutCart(
            businessProfileId: _biz,
            items: _cartA,
            operationType: _type,
            ref: ref,
          );
          expect(
            _sentKey(rec.requests[1]),
            _sentKey(rec.requests[0]),
            reason:
                '$label: the same-key retry converges on the committed order',
          );
        }
      },
    );

    test(
      'success returns the UNWRAPPED data map — order at result["order"], not result["data"]["order"]',
      () async {
        final rec = _ScriptedClient();
        final ref = FinancialOperationRef();

        final result = await _service(rec).checkoutCart(
          businessProfileId: _biz,
          items: _cartA,
          operationType: _type,
          ref: ref,
        );

        expect(result['order'], isA<Map<String, dynamic>>());
        expect(result['order']['orderRef'], 'R-001');
        expect(
          result['data'],
          isNull,
          reason:
              '_parseResponse already unwrapped {success:true,data:...} — '
              'the old result["data"]["order"] read in CartScreen was always null',
        );
        expect(ref.operationId, isNull);
      },
    );

    test(
      'placeStorefrontOrder shares the taxonomy and the malformed-success unknown state',
      () async {
        final rec = _ScriptedClient();
        final ref = FinancialOperationRef();
        rec.script.add(_ScriptedClient.malformedSuccess);

        final err = await _errOf(
          () => _service(rec).placeStorefrontOrder(
            businessProfileId: _biz,
            productId: 'p1',
            quantity: 1,
            operationType: 'storefront.order.place',
            ref: ref,
          ),
        );

        expect(err, isA<FormatException>());
        expect(
          StorefrontService.classifyStorefrontFailure(err),
          StorefrontFailureClass.ambiguousOrUnknown,
        );
        expect(ref.operationId, isNotNull);
      },
    );

    test(
      'placeStorefrontOrder: a partial order object ({} — no id/orderRef) is never success either',
      () async {
        final rec = _ScriptedClient();
        final ref = FinancialOperationRef();
        rec.script.add(
          http.Response(
            jsonEncode({
              'success': true,
              'data': {'order': <String, dynamic>{}},
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );

        final err = await _errOf(
          () => _service(rec).placeStorefrontOrder(
            businessProfileId: _biz,
            productId: 'p1',
            quantity: 1,
            operationType: 'storefront.order.place',
            ref: ref,
          ),
        );

        expect(
          err,
          isA<FormatException>(),
          reason:
              '{order: {}} passes the OLD Map-only guard but is not an '
              'authoritative order result',
        );
        expect(
          StorefrontService.classifyStorefrontFailure(err),
          StorefrontFailureClass.ambiguousOrUnknown,
        );
        expect(
          ref.operationId,
          isNotNull,
          reason: 'the durable instance stays ARMED',
        );
      },
    );
  });

  // ── WP-1.10F: the documented GHS refusals arrive as a 409 by TRANSPORT,
  // but are a DEFINITIVE PRE-ECONOMIC outcome by CODE. Two things must agree:
  // the customer-facing class, and the durable identity (an already-released
  // instance must not stay armed). Every test below runs the real service
  // against the real registry, so a disagreement would fail here.
  group('WP-1.10 GHS refusals — code, not status, decides', () {
    const unavailable =
        'GHS checkout is not available for this item yet. '
        'No order was created and nothing was charged.';
    const unresolved =
        'The item price could not be resolved. '
        'No order was created and nothing was charged.';

    test('409 + GHS_CHECKOUT_UNAVAILABLE is definitive pre-economic', () {
      final e = ApiException(
        message: unavailable,
        statusCode: 409,
        code: 'GHS_CHECKOUT_UNAVAILABLE',
      );
      expect(
        StorefrontService.classifyStorefrontFailure(e),
        StorefrontFailureClass.definitivePreEconomic,
      );
      // The defense-in-depth type carries the same code field.
      expect(
        StorefrontService.classifyStorefrontFailure(
          const StorefrontApiException(
            statusCode: 409,
            code: 'GHS_CHECKOUT_UNAVAILABLE',
            message: unavailable,
          ),
        ),
        StorefrontFailureClass.definitivePreEconomic,
      );
    });

    test('409 + GHS_PRICE_STATE_UNRESOLVED is definitive pre-economic', () {
      final e = ApiException(
        message: unresolved,
        statusCode: 409,
        code: 'GHS_PRICE_STATE_UNRESOLVED',
      );
      expect(
        StorefrontService.classifyStorefrontFailure(e),
        StorefrontFailureClass.definitivePreEconomic,
      );
      expect(
        StorefrontService.classifyStorefrontFailure(
          const StorefrontApiException(
            statusCode: 409,
            code: 'GHS_PRICE_STATE_UNRESOLVED',
            message: unresolved,
          ),
        ),
        StorefrontFailureClass.definitivePreEconomic,
      );
    });

    test('409 with an unrelated code still remains a domainConflict', () {
      for (final code in <String>[
        'IDEMPOTENCY_KEY_REUSED',
        'CART_VERSION_CONFLICT',
        'ghs_checkout_unavailable', // case matters: exact match only
        'GHS_CHECKOUT_UNAVAILABLE_EXTRA',
      ]) {
        expect(
          StorefrontService.classifyStorefrontFailure(
            ApiException(message: 'conflict', statusCode: 409, code: code),
          ),
          StorefrontFailureClass.domainConflict,
          reason: 'code "$code" must not be reclassified',
        );
      }
    });

    test('a generic 409 with no code still remains a domainConflict', () {
      expect(
        StorefrontService.classifyStorefrontFailure(
          ApiException(message: 'Key already used', statusCode: 409),
        ),
        StorefrontFailureClass.domainConflict,
      );
      expect(
        StorefrontService.classifyStorefrontFailure(
          const StorefrontApiException(statusCode: 409, message: 'conflict'),
        ),
        StorefrontFailureClass.domainConflict,
      );
      // The neighbouring statuses keep their economic treatment too.
      for (final status in <int>[408, 425, 429, 500, 503]) {
        expect(
          StorefrontService.classifyStorefrontFailure(
            ApiException(message: 'x', statusCode: status),
          ),
          status == 429
              ? StorefrontFailureClass.rateLimited
              : StorefrontFailureClass.ambiguousOrUnknown,
          reason: 'status $status must not be reclassified by the code branch',
        );
      }
    });

    test('both GHS codes surface the backend refusal message', () {
      for (final pair in <MapEntry<String, String>>[
        const MapEntry('GHS_CHECKOUT_UNAVAILABLE', unavailable),
        const MapEntry('GHS_PRICE_STATE_UNRESOLVED', unresolved),
      ]) {
        final e = ApiException(
          message: pair.value,
          statusCode: 409,
          code: pair.key,
        );
        final copy = storefrontFailureMessage(
          StorefrontService.classifyStorefrontFailure(e),
          e,
        );
        expect(copy, contains(pair.value));
        expect(copy, contains('No order was created and nothing was charged'));
        // The prohibitions, stated as assertions.
        expect(copy.toLowerCase(), isNot(contains('may have gone through')));
        expect(copy.toLowerCase(), isNot(contains('different cart version')));
        expect(copy.toLowerCase(), isNot(contains('converted')));
        expect(copy.toLowerCase(), isNot(contains('usdc')));
      }
    });

    test(
      'a definitive GHS refusal RETIRES the instance and clears the ref',
      () async {
        for (final entry in <MapEntry<String, String>>[
          const MapEntry('GHS_CHECKOUT_UNAVAILABLE', unavailable),
          const MapEntry('GHS_PRICE_STATE_UNRESOLVED', unresolved),
        ]) {
          final rec = _ScriptedClient();
          final ref = FinancialOperationRef();
          rec.script.add(_ScriptedClient.refused(entry.key, entry.value));

          final err = await _errOf(
            () => _service(rec).checkoutCart(
              businessProfileId: _biz,
              items: _cartA,
              operationType: _type,
              ref: ref,
            ),
          );

          expect(
            StorefrontService.classifyStorefrontFailure(err),
            StorefrontFailureClass.definitivePreEconomic,
            reason: entry.key,
          );
          expect(ref.operationId, isNull, reason: 'the ref must be cleared');
          expect(
            await DurableOperationRegistry.pending(account: 'acct-test'),
            isEmpty,
            reason: 'an already-released instance must not stay recoverable',
          );
        }
      },
    );

    test('placeStorefrontOrder retires on a GHS refusal too', () async {
      final rec = _ScriptedClient();
      final ref = FinancialOperationRef();
      rec.script.add(
        _ScriptedClient.refused('GHS_PRICE_STATE_UNRESOLVED', unresolved),
      );

      final err = await _errOf(
        () => _service(rec).placeStorefrontOrder(
          businessProfileId: _biz,
          productId: 'p1',
          quantity: 1,
          operationType: _type,
          ref: ref,
        ),
      );

      expect(
        StorefrontService.classifyStorefrontFailure(err),
        StorefrontFailureClass.definitivePreEconomic,
      );
      expect(ref.operationId, isNull);
      expect(
        await DurableOperationRegistry.pending(account: 'acct-test'),
        isEmpty,
      );
    });

    test(
      'a generic idempotency 409 stays ARMED with the conflict copy',
      () async {
        final rec = _ScriptedClient();
        final ref = FinancialOperationRef();
        rec.script.add(
          _ScriptedClient.status(
            409,
            message:
                'This checkout idempotency key was already used for different '
                'cart contents.',
          ),
        );

        final err = await _errOf(
          () => _service(rec).checkoutCart(
            businessProfileId: _biz,
            items: _cartA,
            operationType: _type,
            ref: ref,
          ),
        );

        expect(
          StorefrontService.classifyStorefrontFailure(err),
          StorefrontFailureClass.domainConflict,
        );
        expect(
          ref.operationId,
          isNotNull,
          reason: 'a generic 409 may still be in flight — keep the identity',
        );
        expect(
          await DurableOperationRegistry.pending(account: 'acct-test'),
          isNotEmpty,
          reason: 'the instance must remain recoverable',
        );
        final copy = storefrontFailureMessage(
          StorefrontService.classifyStorefrontFailure(err),
          err,
        );
        expect(copy, contains('different cart version'));
      },
    );
  });
}

/// Captures the thrown object of [fn]'s future (expected to throw).
Future<Object> _errOf(Future<Object?> Function() fn) async {
  try {
    await fn();
  } catch (e) {
    return e;
  }
  fail('expected the operation to throw');
}
