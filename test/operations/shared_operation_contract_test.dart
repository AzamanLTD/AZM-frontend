// =============================================================================
// SHARED ECONOMIC OPERATION CONTRACT — cross-surface e2e pins
// (retail checkout recovery deep-dive, step 6 — 2026-10-06).
//
// Step 6 declaration: the deep-dive's shared operation contract is ONE
// system, not four ad-hoc implementations. The per-surface suites pin each
// domain in isolation (test/storefront/checkout_cart_operation_identity_
// test.dart — retail checkout; test/transit_booking_identity_test.dart —
// transit booking; test/hotel_reservation_identity_test.dart — hotel
// reservation; test/dinein_authoritative_refresh_test.dart — dine-in pay).
// This suite pins what NO single per-surface suite can express: that the
// surfaces actually SHARE the contract, on the real production paths,
// through the real durable wiring:
//
//   1. THE DISPOSITION PREDICATE IS ONE LAW. All three FinancialOperationRef
//      surfaces classify the SAME status codes into the SAME economic
//      classes — 401 → authenticationRequired, 429 → rateLimited,
//      409 → domainConflict, other definitive 4xx → definitivePreEconomic,
//      408/425/429/5xx/transport/malformed-2xx → ambiguousOrUnknown. A
//      silent divergence in ANY service (a service-local predicate tweak)
//      fails this suite, because classification that contradicts the
//      identity lifecycle is the step-2 defect class all over again.
//
//   2. ONE REGISTRY, INDEPENDENT OPERATIONS. A pending retail checkout, a
//      pending transit booking and a pending hotel reservation coexist
//      under one account — each with its own key — and completing or
//      retrying one NEVER touches the others' identities.
//
//   3. THE KEY TRANSPORT MATCHES EACH BACKEND'S AUTHORITY (the cross-repo
//      pairing rule): retail checkout carries the instance key in the
//      legacy `idempotencyKey` BODY field (the storefront checkout route's
//      authority), transit and hotel carry the `Idempotency-Key` HEADER
//      (their routes' mounted middleware). A client that moves the key to
//      the wrong transport would arm identities the backend never sees.
//
// The fourth economic surface, DINE-IN PAY, deliberately has a DIFFERENT
// contract shape — server-side durable replay + the client re-reading the
// authoritative tab on failure instead of a client-side journal (traced in
// the deep-dive step-5 outcome; pinned by test/dinein_authoritative_
// refresh_test.dart and the backend dine-in replay suites). It is
// cross-referenced here, NOT re-tested — re-deriving its proof would
// duplicate the dedicated suites (operating-contract law 4).
// =============================================================================

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/hotel_marketplace_service.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/storefront/services/storefront_service.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

/// Records every outgoing request and replays a scripted sequence of
/// replies: each entry is either an [http.Response] or an exception to
/// throw. When the script is exhausted, replies with [fallback] (200).
class _ScriptedClient {
  _ScriptedClient(this.fallback);
  final http.Response fallback;
  final requests = <http.Request>[];
  final script = <Object>[];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (script.isNotEmpty) {
      final next = script.removeAt(0);
      if (next is http.Response) return next;
      throw next;
    }
    return fallback;
  });
}

http.Response _json(Object body, [int code = 200]) => http.Response(
    jsonEncode(body), code,
    headers: {'content-type': 'application/json'});

const _account = 'acct-contract';

const _statuses = [400, 401, 402, 403, 404, 408, 409, 422, 425, 429, 500, 503];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
    ApiClient.operationAccountOverride = () async => _account;
    SharedPreferences.setMockInitialValues({});
    DurableOperationRegistry.storageWriterOverride = null;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    ApiClient.operationAccountOverride = null;
    DurableOperationRegistry.storageWriterOverride = null;
  });

  group('the disposition predicate is ONE law across all '
      'FinancialOperationRef surfaces', () {
    test('the SAME status code classifies into the SAME economic class on '
        'retail checkout, transit booking and hotel reservation', () {
      for (final code in _statuses) {
        final retail = StorefrontService.classifyStorefrontFailure(
            ApiException(message: 'boom', statusCode: code));
        final transit =
            MarketplaceBookingService.classifyTransitBookingFailure(
                ApiException(message: 'boom', statusCode: code));
        final hotel =
            HotelMarketplaceService.classifyHotelReservationFailure(
                ApiException(message: 'boom', statusCode: code));

        // Same economic class NAME across the three taxonomies.
        expect(retail.index, transit.index,
            reason: 'status $code: retail and transit disagree — the '
                'surfaces must share ONE predicate so a class can never '
                'contradict the armed/retired state');
        expect(transit.index, hotel.index,
            reason: 'status $code: transit and hotel disagree — the '
                'surfaces must share ONE predicate');

        // And the classes mean what the lifecycle requires: the disposition
        // RELEASES exactly the definitive pre-economic set; everything else
        // keeps the instance armed (ambiguous/unproven).
        final isDefinitive = retail ==
            StorefrontFailureClass.definitivePreEconomic;
        expect(isDefinitive, code == 400 || (code >= 402 && code < 500 && code != 408 && code != 409 && code != 425 && code != 429),
            reason: 'status $code: the definitive set is the r42 predicate —'
                ' 401/408/409/425/429/5xx stay armed');
      }
    });

    test('an UNPROVEN failure (transport loss, malformed 2xx) is never '
        'definitive on ANY surface', () {
      final unproven = <Object>[
        const FormatException('malformed success'),
        http.ClientException('response lost'),
      ];
      for (final error in unproven) {
        expect(
            StorefrontService.classifyStorefrontFailure(error),
            StorefrontFailureClass.ambiguousOrUnknown,
            reason: 'an unproven outcome must keep the instance armed on '
                'retail checkout');
        expect(
            MarketplaceBookingService.classifyTransitBookingFailure(error),
            TransitBookingFailureClass.ambiguousOrUnknown,
            reason: 'an unproven outcome must keep the instance armed on '
                'transit booking');
        expect(
            HotelMarketplaceService.classifyHotelReservationFailure(error),
            HotelBookingFailureClass.ambiguousOrUnknown,
            reason: 'an unproven outcome must keep the instance armed on '
                'hotel reservation');
      }
    });
  });

  test('ONE registry: a pending retail checkout, transit booking and hotel '
      'reservation coexist under one account and never collide', () async {
    final retailRec = _ScriptedClient(_json({
      'success': true,
      'order': {'id': 'order-1', 'orderRef': 'SO-001', 'status': 'CONFIRMED'},
    }));
    final transitRec = _ScriptedClient(_json({
      'success': true,
      'booking': {
        'id': 'booking-1',
        'bookingRef': 'TB-001',
        'status': 'PENDING',
      },
    }, 201));
    final hotelRec = _ScriptedClient(_json({
      'success': true,
      'reservation': {
        'id': 'resv-1',
        'reservationRef': 'HR-001',
        'status': 'CONFIRMED',
      },
    }, 201));

    final retail =
        StorefrontService(apiClient: ApiClient(client: retailRec.client));
    final transit = MarketplaceBookingService(
        apiClient: ApiClient(client: transitRec.client));
    final hotel = HotelMarketplaceService(
        apiClient: ApiClient(client: hotelRec.client));

    final retailRef = FinancialOperationRef();
    final transitRef = FinancialOperationRef();
    final hotelRef = FinancialOperationRef();

    // Arm all three with an ambiguous transport loss each — every logical
    // operation is in flight, none answered.
    retailRec.script.add(http.ClientException('lost'));
    transitRec.script.add(http.ClientException('lost'));
    hotelRec.script.add(http.ClientException('lost'));
    await expectLater(
        retail.checkoutCart(
            businessProfileId: 'biz-1',
            items: [
              {'productId': 'p1', 'quantity': 2}
            ],
            operationType: 'storefront.cart.checkout',
            ref: retailRef),
        throwsA(isA<http.ClientException>()));
    await expectLater(
        transit.bookSeats(
            tripId: 'trip-1',
            seatIds: const ['s1'],
            operationType: 'transit.book_seats',
            ref: transitRef),
        throwsA(isA<http.ClientException>()));
    await expectLater(
        hotel.reserve(
            bizId: 'biz-2',
            roomId: 'room-1',
            checkIn: DateTime(2026, 11, 3),
            checkOut: DateTime(2026, 11, 5),
            operationType: 'hotel.reserve_room',
            ref: hotelRef),
        throwsA(isA<http.ClientException>()));

    // Each type's pending set holds EXACTLY its own instance — the three
    // operations share the registry but never each other's identity.
    final pendingRetail = await DurableOperationRegistry.pending(
        account: _account, type: 'storefront.cart.checkout');
    final pendingTransit = await DurableOperationRegistry.pending(
        account: _account, type: 'transit.book_seats');
    final pendingHotel = await DurableOperationRegistry.pending(
        account: _account, type: 'hotel.reserve_room');
    expect(pendingRetail, hasLength(1));
    expect(pendingTransit, hasLength(1));
    expect(pendingHotel, hasLength(1));
    final keys = {
      pendingRetail.single.key,
      pendingTransit.single.key,
      pendingHotel.single.key,
    };
    expect(keys, hasLength(3),
        reason: 'each logical operation holds its OWN durable identity');

    // Completing the TRANSIT booking retires ONLY the transit instance:
    // the other two stay armed, byte-identical.
    await transit.bookSeats(
        tripId: 'trip-1',
        seatIds: const ['s1'],
        operationType: 'transit.book_seats',
        ref: transitRef);
    expect(
        (await DurableOperationRegistry.pending(
                account: _account, type: 'transit.book_seats'))
            .length,
        0);
    expect(
        (await DurableOperationRegistry.pending(
                account: _account, type: 'storefront.cart.checkout'))
            .single
            .key,
        pendingRetail.single.key,
        reason: 'a completed sibling never touches another surface\'s '
            'armed identity');
    expect(
        (await DurableOperationRegistry.pending(
                account: _account, type: 'hotel.reserve_room'))
            .single
            .key,
        pendingHotel.single.key);

    // And the HOTEL retry converges on its own SAME key — cross-surface
    // registry traffic never corrupts the converging retry.
    final reservation = await hotel.reserve(
        bizId: 'biz-2',
        roomId: 'room-1',
        checkIn: DateTime(2026, 11, 3),
        checkOut: DateTime(2026, 11, 5),
        operationType: 'hotel.reserve_room',
        ref: hotelRef);
    expect(reservation['id'], 'resv-1');
    expect(hotelRec.requests[1].headers['idempotency-key'],
        pendingHotel.single.key,
        reason: 'the retry reuses the SAME identity so the backend replays '
            'the committed reservation — one logical operation, one '
            'authoritative economic result');
  });

  test('the key TRANSPORT matches each backend\'s mounted authority (the '
      'cross-repo pairing rule)', () async {
    final retailRec = _ScriptedClient(_json({
      'success': true,
      'data': {
        'order': {'id': 'order-1', 'orderRef': 'SO-001'},
      },
    }));
    final transitRec = _ScriptedClient(_json({
      'success': true,
      'booking': {'id': 'b1', 'bookingRef': 'TB-001'},
    }, 201));
    final hotelRec = _ScriptedClient(_json({
      'success': true,
      'reservation': {'id': 'r1', 'reservationRef': 'HR-001'},
    }, 201));

    // Retail checkout: the durable path arms and completes in one call.
    await StorefrontService(apiClient: ApiClient(client: retailRec.client))
        .checkoutCart(
            businessProfileId: 'biz-1',
            items: [
              {'productId': 'p1', 'quantity': 1}
            ],
            operationType: 'storefront.cart.checkout',
            ref: FinancialOperationRef());
    final retailBody =
        jsonDecode(retailRec.requests[0].body) as Map<String, dynamic>;
    expect(retailBody['idempotencyKey'], isA<String>(),
        reason: 'the storefront checkout route reads the legacy '
            'idempotencyKey BODY field — that is its authority');
    expect(retailRec.requests[0].headers.containsKey('idempotency-key'),
        isFalse,
        reason: 'the storefront route has no header middleware — a header '
            'key would be armed identity the backend never sees');

    // Transit + hotel: the routes read the Idempotency-Key HEADER.
    await MarketplaceBookingService(
            apiClient: ApiClient(client: transitRec.client))
        .bookSeats(
            tripId: 'trip-1',
            seatIds: const ['s1'],
            operationType: 'transit.book_seats',
            ref: FinancialOperationRef());
    expect(transitRec.requests[0].headers['idempotency-key'], isA<String>(),
        reason: 'the transit booking route mounts the shared idempotency '
            'MIDDLEWARE — it reads the HEADER');
    expect(
        (jsonDecode(transitRec.requests[0].body)
                as Map<String, dynamic>)
            .containsKey('idempotencyKey'),
        isFalse);

    await HotelMarketplaceService(apiClient: ApiClient(client: hotelRec.client))
        .reserve(
            bizId: 'biz-2',
            roomId: 'room-1',
            checkIn: DateTime(2026, 11, 3),
            checkOut: DateTime(2026, 11, 5),
            operationType: 'hotel.reserve_room',
            ref: FinancialOperationRef());
    expect(hotelRec.requests[0].headers['idempotency-key'], isA<String>(),
        reason: 'the canonical createReservation reads the Idempotency-Key '
            'HEADER — a body key would never reach the dedupe authority');
    expect(
        (jsonDecode(hotelRec.requests[0].body)
                as Map<String, dynamic>)
            .containsKey('idempotencyKey'),
        isFalse);
  });
}
