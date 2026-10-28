// =============================================================================
// AZM Auction "my ads" rail contract
// =============================================================================
// The auction screen's ad picker previously fetched '/p2p/my-ads' — a route
// that does not exist on the backend, so the vendor's ad list was always
// empty and bidding was impossible. The real rail is the ad-management
// endpoint GET /api/ads/mine (controllers/adController.getMyAds), whose
// envelope is {success:true, ads:[...]} with the caller's ads only.
//
// This widget test pins the EXACT GET path the screen constructs and that
// the picker renders from the real envelope (ACTIVE ads only).
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/providers/azm_auction_provider.dart';
import 'package:azaman/screens/azm_auction/azm_auction_screen.dart';
import 'package:azaman/services/api_client.dart';

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _AuctionRailClient extends ApiClient {
  final List<String> getPaths = [];

  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    getPaths.add(endpoint);
    if (endpoint == '/ads/mine') {
      return _json(200, {
        'success': true,
        'ads': [
          {'id': 7, 'status': 'ACTIVE', 'paymentMethod': 'MTN MoMo'},
          {'id': 9, 'status': 'PAUSED', 'paymentMethod': 'Vodafone Cash'},
          {'id': 11, 'status': 'ACTIVE', 'paymentMethod': 'AirtelTigo'},
        ],
      });
    }
    return _json(404, {'success': false});
  }
}

Widget _app(AzmAuctionScreen screen, ApiClient client) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      // The auction-state rails use the global apiClient singleton; override
      // the providers themselves so the widget test never touches the network.
      auctionStateProvider.overrideWith((ref) async => null),
      myAuctionBidProvider.overrideWith((ref) async => MyBid()),
      promotedAdsProvider.overrideWith((ref) async => const []),
    ],
    child: MaterialApp(home: screen),
  );
}

void main() {
  testWidgets(
    'the ad picker loads from the real /ads/mine rail and shows ACTIVE ads only',
    (tester) async {
      final client = _AuctionRailClient();

      await tester.pumpWidget(_app(const AzmAuctionScreen(), client));
      await tester.pumpAndSettle();

      // The exact corrected path — not '/p2p/my-ads' (nonexistent) and not a
      // double-prefixed '/api/ads/mine'.
      expect(client.getPaths, contains('/ads/mine'));
      expect(client.getPaths.any((p) => p.startsWith('/api/')), isFalse);

      // The picker renders from the {success, ads} envelope, filtered to
      // status == 'ACTIVE'. While closed a DropdownButton renders only the
      // selected item — the default selection is the FIRST active ad (#7).
      expect(find.byType(DropdownButton<int>), findsOneWidget);
      expect(find.text('Ad #7 · MTN MoMo'), findsOneWidget);

      // Open the dropdown: every ACTIVE ad is selectable, the PAUSED ad
      // never entered the list.
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      expect(find.text('Ad #11 · AirtelTigo'), findsOneWidget);
      expect(find.text('Ad #9 · Vodafone Cash'), findsNothing);
    },
  );
}
