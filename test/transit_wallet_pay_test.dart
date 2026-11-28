// Transit wallet pay, app side: the second factor and the wire.
//
//   1. withSecondFactor asks once and sends; a challenge for the other factor
//      re-asks with that one; a refused factor re-asks with the reason;
//      cancel returns null; any other error is the caller's, unchanged.
//   2. bookSeats(payWithWallet) sends payWith WALLET and the factor, with an
//      Idempotency-Key; the durable journal on disk never holds the factor.
//   3. A 401 challenge keeps the durable instance armed: the retry with the
//      factor reuses the same key (one economic intent, one identity).
//   4. payForSeats rethrows challenges with the state idle, and lands a short
//      balance in state with its code.
//   5. The quote and the paid result parse what the backend sends.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/utils/durable_operation_registry.dart';
import 'package:azaman/widgets/security/second_factor.dart';

ApiException _err(int status, {String? code, String message = 'nope'}) =>
    ApiException(message: message, statusCode: status, code: code);

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

final _paid = _json(201, {
  'success': true,
  'booking': {'id': 'b-1', 'bookingRef': 'TRN-1', 'status': 'CONFIRMED'},
  'seatIds': ['1A'],
  'totalFare': 0.6,
  'payment': {
    'method': 'WALLET',
    'escrowId': 'e-1',
    'amountUsdc': 0.6,
    'feeUsdc': 0.003,
    'totalUsdc': 0.603,
  },
});

class _Wire {
  final requests = <http.Request>[];
  final script = <http.Response>[];
  late final http.Client client = MockClient((r) async {
    requests.add(r);
    return script.isNotEmpty ? script.removeAt(0) : _paid;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async => null);
    ApiClient.operationAccountOverride = () async => 'acct-test';
    SharedPreferences.setMockInitialValues({});
    DurableOperationRegistry.storageWriterOverride = null;
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
    ApiClient.operationAccountOverride = null;
  });

  group('withSecondFactor', () {
    // A scripted prompt: answers in order, records what it was asked for.
    ({
      Future<SecondFactor?> Function({
        required SecondFactorKind kind,
        String? errorText,
      })
      ask,
      List<(SecondFactorKind, String?)> asked,
    })
    script(List<SecondFactor?> answers) {
      final asked = <(SecondFactorKind, String?)>[];
      Future<SecondFactor?> ask({
        required SecondFactorKind kind,
        String? errorText,
      }) async {
        asked.add((kind, errorText));
        return answers.removeAt(0);
      }

      return (ask: ask, asked: asked);
    }

    Future<T?> run<T>(
      BuildContext context,
      Future<T> Function(SecondFactor) attempt,
      List<SecondFactor?> answers, {
      SecondFactorKind initial = SecondFactorKind.password,
      List<(SecondFactorKind, String?)>? record,
    }) async {
      final s = script(answers);
      final out = await withSecondFactor<T>(
        context,
        initial: initial,
        title: 'Pay',
        actionLabel: 'Pay',
        ask: s.ask,
        attempt: attempt,
      );
      record?.addAll(s.asked);
      return out;
    }

    testWidgets('asks once and sends', (tester) async {
      final context = await _ctx(tester);
      final sent = <SecondFactor>[];
      final out = await run<String>(context, (f) async {
        sent.add(f);
        return 'ok';
      }, [const SecondFactor.password('pw')]);
      expect(out, 'ok');
      expect(sent.single.toWire(), {'password': 'pw'});
    });

    testWidgets('a challenge for the other factor re-asks with that one', (
      tester,
    ) async {
      final context = await _ctx(tester);
      final asked = <(SecondFactorKind, String?)>[];
      var calls = 0;
      final out = await run<String>(
        context,
        (f) async {
          calls++;
          if (f.kind == SecondFactorKind.password) {
            throw _err(401, code: '2FA_REQUIRED');
          }
          return 'ok';
        },
        [
          const SecondFactor.password('pw'),
          const SecondFactor.authenticator('123456'),
        ],
        record: asked,
      );
      expect(out, 'ok');
      expect(calls, 2);
      expect(asked.map((a) => a.$1), [
        SecondFactorKind.password,
        SecondFactorKind.authenticator,
      ]);
      expect(asked.last.$2, contains('authenticator'));
    });

    testWidgets('a refused factor re-asks with the reason', (tester) async {
      final context = await _ctx(tester);
      final asked = <(SecondFactorKind, String?)>[];
      var calls = 0;
      await run<String>(
        context,
        (f) async {
          if (calls++ == 0) throw _err(401, message: 'Invalid password.');
          return 'ok';
        },
        [
          const SecondFactor.password('bad'),
          const SecondFactor.password('good'),
        ],
        record: asked,
      );
      expect(asked.last.$2, 'That password did not match. Try again.');
    });

    testWidgets('cancel returns null without sending', (tester) async {
      final context = await _ctx(tester);
      var calls = 0;
      final out = await run<String>(context, (f) async {
        calls++;
        return 'ok';
      }, [null]);
      expect(out, isNull);
      expect(calls, 0);
    });

    testWidgets('any other error passes through unchanged', (tester) async {
      final context = await _ctx(tester);
      await expectLater(
        run<String>(
          context,
          (f) async => throw _err(402, code: 'INSUFFICIENT_BALANCE'),
          [const SecondFactor.password('pw')],
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'INSUFFICIENT_BALANCE',
          ),
        ),
      );
    });

    test('an expired session is not a refused factor', () {
      expect(isSecondFactorRefused(_err(401, code: 'TOKEN_EXPIRED')), isFalse);
      expect(isSecondFactorRefused(_err(401)), isTrue);
    });

    test('the factor never prints itself', () {
      expect(
        '${const SecondFactor.password('hunter2')}',
        isNot(contains('hunter2')),
      );
    });

    test('the first factor follows the profile', () {
      User u(bool? on) => User(
        id: '1',
        username: 'a',
        email: '',
        token: '',
        role: 'USER',
        isTwoFactorEnabled: on,
      );
      expect(secondFactorKindFor(u(true)), SecondFactorKind.authenticator);
      expect(secondFactorKindFor(u(false)), SecondFactorKind.password);
      expect(secondFactorKindFor(u(null)), SecondFactorKind.password);
      expect(
        User.fromJson({'id': 1, 'isTwoFactorEnabled': true}).isTwoFactorEnabled,
        isTrue,
      );
    });
  });

  group('bookSeats with wallet pay', () {
    test(
      'sends payWith and the factor; the journal never holds the factor',
      () async {
        final wire = _Wire();
        final svc = MarketplaceBookingService(
          apiClient: ApiClient(client: wire.client),
        );
        final opRef = FinancialOperationRef();
        final result = await svc.bookSeats(
          tripId: 't-1',
          seatIds: const ['1A'],
          operationType: 'transit.book_seats',
          ref: opRef,
          payWithWallet: true,
          secondFactor: const SecondFactor.password('s3cret-pw'),
        );
        final req = wire.requests.single;
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['payWith'], 'WALLET');
        expect(body['password'], 's3cret-pw');
        expect(req.headers['Idempotency-Key'], isNotEmpty);
        expect(result.paid, isTrue);
        expect(result.paidTotalUsdc, 0.603);
        expect(result.status, 'CONFIRMED');

        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getKeys().map((k) => '${prefs.get(k)}').join('\n');
        expect(stored, isNot(contains('s3cret-pw')));
      },
    );

    test(
      'a 401 challenge keeps the instance; the retry reuses the key',
      () async {
        final wire = _Wire()
          ..script.add(
            _json(401, {
              'success': false,
              'code': 'PASSWORD_REQUIRED',
              'message': 'Password required to confirm this operation.',
            }),
          );
        final svc = MarketplaceBookingService(
          apiClient: ApiClient(client: wire.client),
        );
        final opRef = FinancialOperationRef();
        Future<BookSeatResult> attempt(SecondFactor? f) => svc.bookSeats(
          tripId: 't-1',
          seatIds: const ['1A'],
          operationType: 'transit.book_seats',
          ref: opRef,
          payWithWallet: true,
          secondFactor: f,
        );
        await expectLater(
          attempt(const SecondFactor.authenticator('123456')),
          throwsA(isA<ApiException>()),
        );
        await attempt(const SecondFactor.password('pw'));
        expect(wire.requests, hasLength(2));
        expect(
          wire.requests[1].headers['Idempotency-Key'],
          wire.requests[0].headers['Idempotency-Key'],
        );
      },
    );

    test('quoteSeats asks for the selection and parses the total', () async {
      final wire = _Wire()
        ..script.add(
          _json(200, {
            'success': true,
            'seatIds': ['1A', '1B'],
            'fareUsdc': 1.2,
            'feeUsdc': 0.006,
            'feePct': 0.005,
            'totalUsdc': 1.206,
            'availableUsdc': 1,
            'canPay': false,
          }),
        );
      final q = await MarketplaceBookingService(
        apiClient: ApiClient(client: wire.client),
      ).quoteSeats(tripId: 't-1', seatIds: const ['1A', '1B']);
      expect(
        wire.requests.single.url.path,
        endsWith('/marketplace/transit/trips/t-1/quote'),
      );
      expect(wire.requests.single.url.queryParameters['seats'], '1A,1B');
      expect(q.totalUsdc, 1.206);
      expect(q.canPay, isFalse);
      expect(q.shortfallUsdc, closeTo(0.206, 1e-9));
    });
  });

  group('BookingActionNotifier.payForSeats', () {
    test('rethrows a challenge with the state idle', () async {
      final wire = _Wire()
        ..script.add(_json(401, {'success': false, 'code': '2FA_REQUIRED'}));
      final n = BookingActionNotifier(
        MarketplaceBookingService(apiClient: ApiClient(client: wire.client)),
      );
      await expectLater(
        n.payForSeats(
          tripId: 't-1',
          seatIds: const ['1A'],
          secondFactor: const SecondFactor.password('pw'),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(n.state.isLoading, isFalse);
      expect(n.state.error, isNull);
    });

    test('a short balance lands in state with its code', () async {
      final wire = _Wire()
        ..script.add(
          _json(402, {
            'success': false,
            'code': 'INSUFFICIENT_BALANCE',
            'message': 'Insufficient balance.',
          }),
        );
      final n = BookingActionNotifier(
        MarketplaceBookingService(apiClient: ApiClient(client: wire.client)),
      );
      await n.payForSeats(
        tripId: 't-1',
        seatIds: const ['1A'],
        secondFactor: const SecondFactor.password('pw'),
      );
      expect(n.state.errorCode, 'INSUFFICIENT_BALANCE');
      expect(n.state.result, isNull);
    });
  });
}

/// A real BuildContext for withSecondFactor (the scripted prompt never uses
/// it to show a sheet).
Future<BuildContext> _ctx(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  return tester.element(find.byType(SizedBox));
}
