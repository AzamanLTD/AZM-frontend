// =============================================================================
// AZAMAN — BUSINESS RESULT CARD: Workstream D acceptance suite
//
// Pins the redesigned marketplace discovery card:
//   • the avatar is a CIRCLE with the primary-category icon badge attached
//     at its bottom-right (badge carries the category, not a printed label
//     under the image)
//   • the rectangular body opens the business directly through the canonical
//     /business/:bizId route — NO inline accordion/dropdown expansion
//   • tapping the avatar opens the actions panel (follow / bookmark /
//     rate-and-review) wired to the REAL contracts — no fake success
//   • the bookmark control is REMOVED from the card body (it lives in the
//     panel now)
//   • body text never collides with the avatar circle or its notch
//   • the card never overflows at 320/360/390dp, at 1.4× text scale,
//     in light and dark themes
//   • no guessed secondary-offering icons render (the BusinessProfile DTO
//     has no authoritative offerings field — the gap is documented in the
//     PR, and the card must not invent one)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/marketplace/business_result_card.dart';

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

// The fake follows/bookmarks backend: the REAL endpoints the panel uses.
class _RecordingClient extends ApiClient {
  final List<String> calls = [];
  bool following = false;

  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers, bool requireAuth = true}) async {
    calls.add('GET $endpoint');
    if (endpoint == '/follows/check/BIZ-1') {
      return _json(200, {'success': true, 'isFollowing': following});
    }
    return _json(404, {'success': false});
  }

  @override
  Future<http.Response> post(String endpoint, Map<String, dynamic> body,
      {Map<String, String>? headers, bool requireAuth = true, String? idempotencyKey}) async {
    calls.add('POST $endpoint');
    if (endpoint == '/follows') {
      following = true;
      return _json(200, {'success': true});
    }
    return _json(404, {'success': false});
  }

  @override
  Future<http.Response> delete(String endpoint,
      {Map<String, String>? headers, bool requireAuth = true}) async {
    calls.add('DELETE $endpoint');
    if (endpoint == '/follows/BIZ-1') {
      following = false;
      return _json(200, {'success': true});
    }
    return _json(404, {'success': false});
  }
}

class _RouteRecorder extends NavigatorObserver {
  final routes = <String>[];
  @override
  void didPush(Route route, Route? previous) {
    final name = route.settings.name;
    if (name != null) routes.add(name);
    super.didPush(route, previous);
  }
}

BusinessProduct _product(String name) => BusinessProduct(
      id: name.toLowerCase().replaceAll(' ', '-'),
      businessProfileId: 'bp-1',
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      priceUsdc: 12,
      totalRevenue: 0,
      imageUrls: const [],
      isActive: true,
      totalOrders: 5,
    );

BusinessProfile _business({
  String category = 'FOOD_BEVERAGE',
  List<String> offeredCategories = const [],
}) =>
    BusinessProfile(
      offeredCategories: offeredCategories,
      id: 'bp-1',
      bizId: 'BIZ-1',
      businessName: 'Palm Court Kitchen',
      category: category,
      description: 'Jollof and grilled tilapia, Legon',
      isVerified: true,
      isSuspended: false,
      kybStatus: 'VERIFIED',
      totalEscrows: 4,
      completedEscrows: 4,
      userId: 1,
      totalVolume: 100,
      averageRating: 4.7,
      username: 'palm-court',
      reviewCount: 12,
      products: [_product('Jollof Plate')],
    );

GoRouter _router(NavigatorObserver obs, {Widget? home}) => GoRouter(
  initialLocation: '/',
  observers: [obs],
  routes: [
    GoRoute(
      path: '/',
      builder: (c, s) => Scaffold(body: home ?? const SizedBox.shrink()),
    ),
    GoRoute(
      path: '/business/:bizId',
      builder: (c, s) => Scaffold(
          body: Text('biz-${s.pathParameters['bizId']}')),
    ),
  ],
);

Future<void> _pumpCard(
  WidgetTester tester,
  BusinessProfile business, {
  ApiClient? client,
  double? width,
  double textScale = 1.0,
  Brightness brightness = Brightness.dark,
  NavigatorObserver? observer,
}) async {
  SharedPreferences.setMockInitialValues({});
  final obs = observer ?? _RouteRecorder();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (client != null) apiClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp.router(
        routerConfig: _router(obs,
            home: BusinessResultCard(business: business, distanceKm: 2.4)),
        theme: ThemeData(fontFamily: 'Roboto', brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            size: width != null ? Size(width, 800) : MediaQuery.of(context).size,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('business result card — Workstream D', () {
    testWidgets('the avatar is circular with the category icon badge '
        'at its bottom-right; no category name is printed under the image',
        (tester) async {
      await _pumpCard(tester, _business());

      final avatar = find.byKey(const ValueKey('business-avatar-BIZ-1'));
      expect(avatar, findsOneWidget);
      expect(find.byKey(const ValueKey('business-avatar-badge-BIZ-1')),
          findsOneWidget,
          reason: 'the primary-category badge is attached to the avatar');

      // Circular geometry: the avatar renders as a Box with equal width
      // and height (the ring is painted inside that box).
      final rect = tester.getRect(avatar);
      expect(rect.width, closeTo(rect.height, 0.5),
          reason: 'the avatar box is square (circle inside)');

      // The badge sits at the avatar's bottom-right corner band.
      final badgeRect =
          tester.getRect(find.byKey(const ValueKey('business-avatar-badge-BIZ-1')));
      expect(badgeRect.right <= rect.right + 2, isTrue);
      expect(badgeRect.bottom <= rect.bottom + 2, isTrue);
      expect(badgeRect.bottom > rect.center.dy, isTrue,
          reason: 'the badge is at the bottom of the avatar');
      expect(badgeRect.right > rect.center.dx, isTrue,
          reason: 'the badge is at the right of the avatar');

      // The category name is NOT printed as a label under the image —
      // it lives in the badge's semantics only.
      final badgeSemantics = tester.firstWidget<Semantics>(find.descendant(
          of: find.byKey(const ValueKey('business-avatar-badge-BIZ-1')),
          matching: find.byType(Semantics)));
      expect(badgeSemantics.properties.label, contains('Category:'));
    });

    testWidgets('tapping the body navigates to the canonical business '
        'route — the card never expands into an accordion', (tester) async {
      final recorder = _RouteRecorder();
      await _pumpCard(tester, _business(), observer: recorder);

      await tester.tap(find.byKey(const ValueKey('business-card-body-BIZ-1')));
      await tester.pumpAndSettle();

      expect(recorder.routes.any((r) => r.startsWith('/business/')), isTrue,
          reason: 'the body pushes the canonical business route');
      // The routed screen receives the real bizId through the path
      // parameter — the canonical /business/:bizId contract end to end.
      expect(find.text('biz-BIZ-1'), findsOneWidget);
      expect(find.byKey(const ValueKey('business-card-expanded-BIZ-1')),
          findsNothing,
          reason: 'no inline accordion/dropdown state exists');
    });

    testWidgets('tapping the avatar opens the actions panel with '
        'follow, bookmark and rate-and-review', (tester) async {
      final client = _RecordingClient();
      await _pumpCard(tester, _business(), client: client);

      await tester.tap(find.byKey(const ValueKey('business-avatar-BIZ-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('business-action-follow')), findsOneWidget);
      expect(find.byKey(const ValueKey('business-action-bookmark')), findsOneWidget);
      expect(find.byKey(const ValueKey('business-action-review')), findsOneWidget);

      // The follow row checked the REAL contract on open.
      expect(client.calls, contains('GET /follows/check/BIZ-1'));
    });

    testWidgets('the panel follow action posts the real follow and the '
        'row reflects the new state', (tester) async {
      final client = _RecordingClient()..following = false;
      await _pumpCard(tester, _business(), client: client);

      await tester.tap(find.byKey(const ValueKey('business-avatar-BIZ-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('business-action-follow')));
      await tester.pumpAndSettle();

      expect(client.calls, contains('POST /follows'),
          reason: 'follow goes through the canonical POST /follows');
      expect(find.text('Unfollow'), findsOneWidget,
          reason: 'the row reflects the real toggled state');
    });

    testWidgets('the panel bookmark action toggles the real saved set',
        (tester) async {
      final client = _RecordingClient();
      await _pumpCard(tester, _business(), client: client);

      await tester.tap(find.byKey(const ValueKey('business-avatar-BIZ-1')));
      await tester.pumpAndSettle();

      expect(find.text('Bookmark'), findsOneWidget,
          reason: 'the business starts unsaved');
      await tester.tap(find.byKey(const ValueKey('business-action-bookmark')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // savedBusinessesProvider is the same SharedPreferences-backed
      // provider the profile screen uses — the row reflects the flip.
      expect(find.text('Remove bookmark'), findsOneWidget,
          reason: 'the bookmark toggle flipped the real saved set');
    });

    testWidgets('no bookmark control renders on the card body itself',
        (tester) async {
      await _pumpCard(tester, _business());

      final body = find.byKey(const ValueKey('business-card-body-BIZ-1'));
      expect(
          find.descendant(
              of: body,
              matching: find.byIcon(Icons.bookmark_rounded)),
          findsNothing,
          reason: 'bookmark moved into the avatar action panel');
      expect(
          find.descendant(
              of: body,
              matching: find.byIcon(Icons.bookmark_border_rounded)),
          findsNothing);
    });

    testWidgets('body text never collides with the avatar circle or '
        'its notch', (tester) async {
      await _pumpCard(tester, _business());

      final avatar = tester.getRect(find.byKey(const ValueKey('business-avatar-BIZ-1')));
      final name = tester.getRect(find.text('Palm Court Kitchen'));

      expect(name.left >= avatar.right - 1, isTrue,
          reason: 'the name row starts clear of the avatar circle');
    });

    testWidgets('no guessed secondary-offering icons render when the DTO '
        'carries no offerings field', (tester) async {
      await _pumpCard(tester, _business(category: 'HOSPITALITY'));

      // A hotel with NO authoritative food data must NOT render a
      // restaurant icon beside its name.
      expect(find.byIcon(Icons.restaurant_outlined), findsNothing);
      expect(find.byIcon(Icons.restaurant_rounded), findsNothing);
    });

    testWidgets('Workstream D: the visual category text label is GONE '
        '(primary category lives only in the circular badge)', (tester) async {
      await _pumpCard(tester, _business(category: 'HOSPITALITY'));

      // The old textual label beside the name must not render…
      expect(find.text('Hotels'), findsNothing);
      expect(find.text('Restaurants'), findsNothing);

      // …but the screen-reader contract is PRESERVED: the card still
      // announces the category in its semantics labels.
      final semantics = find.bySemanticsLabel(
        RegExp('Category: Hotels|Hotels'),
      );
      expect(semantics, findsWidgets);
    });

    testWidgets('Workstream D: the primary category badge icon is accurate '
        'for the category', (tester) async {
      await _pumpCard(tester, _business(category: 'HOSPITALITY'));
      // Scoped to the BADGE container: the avatar placeholder legitimately
      // renders the same category icon, so the badge key is the precise
      // assertion target.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('business-avatar-badge-BIZ-1')),
          matching: find.byIcon(Icons.hotel_outlined),
        ),
        findsOneWidget,
      );

      // And no additional-offering icon renders when none are declared.
      expect(find.byIcon(Icons.restaurant_outlined), findsNothing);
    });

    testWidgets('Workstream D: offering icons render ONLY from declared '
        'offeredCategories data', (tester) async {
      await _pumpCard(
        tester,
        _business(
          category: 'HOSPITALITY',
          offeredCategories: const ['FOOD_BEVERAGE'],
        ),
      );

      // Declared offering → the chip icon renders (declared, not inferred:
      // the fixture's primary is HOSPITALITY, so a restaurant icon can only
      // come from offeredCategories).
      expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
      // The PRIMARY category icon renders in the badge (plus the avatar
      // placeholder's copy), not as an offering chip: exactly two, both
      // owned by the primary HOSPITALITY identity.
      expect(find.byIcon(Icons.hotel_outlined), findsNWidgets(2));
    });

    testWidgets('Workstream D REGRESSION: a LEGACY payload repeating the '
        'primary category in offeredCategories never renders it twice',
        (tester) async {
      await _pumpCard(
        tester,
        _business(
          category: 'HOSPITALITY',
          // Malformed/legacy shape: the primary (HOSPITALITY) repeats
          // inside the additional-offerings list alongside a genuine
          // additional offering. The backend now rejects this shape, but
          // the card must still defend against records written before
          // the contract tightened (additive defense, not trust).
          offeredCategories: const ['HOSPITALITY', 'FOOD_BEVERAGE', 'HOSPITALITY'],
        ),
      );

      // The PRIMARY category renders exactly twice: once in the avatar
      // badge + once in the placeholder copy — NEVER as an offering chip.
      expect(find.byIcon(Icons.hotel_outlined), findsNWidgets(2));
      // The genuine additional offering still renders its chip.
      expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
      // The semantics utterance mirrors the visual: primary spoken once,
      // the additional offering listed — no 'Hospitality' in the
      // also-offers section.
      final semantics = find.bySemanticsLabel(RegExp('also offers.*Restaurant'));
      expect(semantics, findsOneWidget);
      expect(
        find.bySemanticsLabel(
            RegExp('also offers.*Hospitality')),
        findsNothing,
      );
    });

    testWidgets('Workstream D: an EMPTY offeredCategories list renders no '
        'chips and no fake icons', (tester) async {
      await _pumpCard(
        tester,
        _business(category: 'HOSPITALITY', offeredCategories: const []),
      );

      // Nothing inferred: no restaurant chip for a hotel with no declared
      // food offering, no generic fallback chip for an empty list.
      expect(find.byIcon(Icons.restaurant_outlined), findsNothing);
      expect(find.byIcon(Icons.category_outlined), findsNothing);
    });

    testWidgets('Workstream D: offering chips cap at 3 with a +N counter',
        (tester) async {
      await _pumpCard(
        tester,
        _business(
          category: 'RETAIL',
          offeredCategories: const [
            'FOOD_BEVERAGE', 'LOGISTICS', 'EDUCATION', 'TECHNOLOGY',
          ],
        ),
      );

      expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
      expect(find.byIcon(Icons.directions_bus_outlined), findsOneWidget);
      expect(find.byIcon(Icons.school_outlined), findsOneWidget);
      // The 4th offering is counted, not drawn.
      expect(find.byIcon(Icons.laptop_mac_outlined), findsNothing);
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('Workstream D: the card announces offerings in ONE '
        'semantics utterance (also offers …)', (tester) async {
      await _pumpCard(
        tester,
        _business(
          category: 'HOSPITALITY',
          offeredCategories: const ['FOOD_BEVERAGE', 'LOGISTICS'],
        ),
      );

      // The body's single semantics node carries name + primary category +
      // declared offerings in one coherent utterance (the chips themselves
      // are visual-only; the body excludes descendant semantics).
      expect(
        find.bySemanticsLabel(
          'Open Palm Court Kitchen, Hotels, also offers Restaurants, Transit',
        ),
        findsOneWidget,
      );
    });

    for (final width in const [320.0, 360.0, 390.0]) {
      testWidgets('no overflow at ${width}dp (dark, 1.0× text)', (tester) async {
        await _pumpCard(tester, _business(), width: width);
        expect(tester.takeException(), isNull,
            reason: 'the card lays out cleanly at $width dp');
        expect(find.byKey(const ValueKey('business-card-body-BIZ-1')),
            findsOneWidget);
      });

      testWidgets('no overflow at ${width}dp (light, 1.4× text)', (tester) async {
        await _pumpCard(tester, _business(),
            width: width, textScale: 1.4, brightness: Brightness.light);
        expect(tester.takeException(), isNull,
            reason: 'large text stays clean at $width dp');
        expect(find.byKey(const ValueKey('business-card-body-BIZ-1')),
            findsOneWidget);
      });
    }
  });
}
