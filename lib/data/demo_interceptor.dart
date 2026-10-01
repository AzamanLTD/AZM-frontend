// =============================================================================
// AZAMAN — DEMO INTERCEPTOR
//
// When demo mode is active, this intercepts all ApiClient requests and
// returns mock data from DemoSeedData instead of making real HTTP calls.
// The interceptor matches endpoint patterns (with path params) and
// returns a synthetic http.Response with the appropriate JSON body.
//
// This keeps ALL existing providers, services, and screens working
// without modification — they just get mock data from the API layer.
// =============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:azaman/data/demo_seed_data.dart';
import 'package:azaman/data/demo_seed_marketplace.dart';

class DemoInterceptor {
  DemoInterceptor._();

  /// Returns a synthetic 200 OK response with JSON body, or null if
  /// the endpoint isn't mocked (caller falls through to real HTTP).
  static http.Response? tryGet(String endpoint) {
    final body = _matchGet(endpoint);
    if (body == null) return null;
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  /// Returns a synthetic 200 OK for POST, or null if not mocked.
  static http.Response? tryPost(String endpoint, Map<String, dynamic> body) {
    final mock = _matchPost(endpoint, body);
    if (mock == null) return null;
    final path = endpoint.split('?').first;
    // /saved-momo POST expects 201 Created with an 'account' key.
    final status = path == '/saved-momo' ? 201 : 200;
    return http.Response(
      jsonEncode(mock),
      status,
      headers: {'content-type': 'application/json'},
    );
  }

  /// Returns a synthetic 200 OK for PUT, or null if not mocked.
  static http.Response? tryPut(String endpoint, Map<String, dynamic> body) {
    return _simpleSuccess();
  }

  /// Returns a synthetic 200 OK for PATCH, or null if not mocked.
  static http.Response? tryPatch(String endpoint) {
    return _simpleSuccess();
  }

  /// Returns a synthetic 200 OK for DELETE, or null if not mocked.
  static http.Response? tryDelete(String endpoint) {
    return _simpleSuccess();
  }

  // ── GET endpoint matching ─────────────────────────────────────────────
  static Map<String, dynamic>? _matchGet(String endpoint) {
    // Strip query params for matching
    final path = endpoint.split('?').first;

    // Paginated demo endpoint — needs the raw query, not just the path.
    if (path == '/users/me/security-logs') {
      final query = Uri.parse(endpoint).queryParameters;
      final page = int.tryParse(query['page'] ?? '') ?? 1;
      final limit = int.tryParse(query['limit'] ?? '') ?? 20;
      return DemoSeedData.securityLogs(page, limit);
    }

    // ── Exact matches ────────────────────────────────────────────────────
    switch (path) {
      // ── Health/version gate (fail-open in demo) ──────────────────────
      case '/health':
        return {'status': 'ok', 'versionGate': null};
      case '/friends':
        return {'friends': DemoSeedData.friends()};
      case '/friends/requests':
        return DemoSeedData.friendRequests();
      case '/friends/chat/unread-count':
        return DemoSeedData.unreadCount();
      case '/friends/chat/conversations':
        return DemoSeedData.personalChatConversations();
      case '/group-chats':
        return {'groups': DemoSeedData.groupChats()};
      case '/oracle/rates':
        return DemoSeedData.oracleRates();
      case '/trades/active':
        return DemoSeedData.activeTrades();
      case '/trades/history':
        return DemoSeedData.tradeHistory();
      case '/wallet/history':
        return DemoSeedData.walletHistory();
      case '/finance/transactions':
        return DemoSeedData.financeTransactions();
      case '/notifications':
        return DemoSeedData.notifications();
      case '/notifications/unread-count':
        return DemoSeedData.unreadNotifications();
      case '/savings/overview':
        return DemoSeedData.savingsOverview();
      case '/vaults':
        return DemoSeedData.vaults();
      case '/susu/me':
        return DemoSeedData.susuGroups();
      case '/azm/summary':
        return DemoSeedData.azmSummary();
      case '/azm/rates':
        return DemoSeedData.azmRates();
      case '/azm/spend/options':
        return DemoSeedData.spendOptions();
      case '/azm/spend/card-skins':
        return DemoSeedData.cardSkins();
      case '/azm/spend/history':
        return DemoSeedData.spendHistory();
      case '/azm/friends-leaderboard':
        return DemoSeedData.leaderboard();
      case '/azm/history':
        return DemoSeedData.emptyData();
      case '/azm-stake/tier':
        return DemoSeedData.stakingTier();
      case '/azm-stake/stakes':
        return DemoSeedData.stakes();
      case '/azm-auction/current':
        return DemoSeedData.auctionCurrent();
      case '/p2p/ads':
        return DemoSeedData.p2pAds();
      case '/p2p/my-ads':
        return DemoSeedData.emptyData();
      case '/ads/mine':
        return DemoSeedData.myAds();
      case '/stories/feed':
        return DemoSeedData.storiesFeed();
      case '/stories/highlights':
        return DemoSeedData.emptyData();
      case '/stories/close-friends':
        return DemoSeedData.emptyData();
      case '/storefront/discover':
        return DemoSeedData.storefrontDiscover();
      case '/storefront/me/draft':
        return DemoSeedData.nullData();
      case '/storefront/me/published':
        return DemoSeedData.nullData();
      case '/storefront/me/eligibility':
        return {
          'data': {'eligible': false},
        };
      case '/storefront/me/history':
        return DemoSeedData.emptyData();
      case '/storefront/templates':
        return DemoSeedData.emptyData();
      case '/storefront/themes':
        return DemoSeedData.emptyData();
      case '/storefront/widgets':
        return DemoSeedData.emptyData();
      case '/trade-accounts':
        return DemoSeedData.emptyData();
      case '/trade-accounts/approved':
        return DemoSeedData.emptyData();
      case '/trade-accounts/supported-methods':
        return DemoSeedData.supportedMethods();
      case '/saved-momo':
        return DemoSeedData.savedMomoAccounts();
      case '/wallet/saved':
        return {
          'wallets': [],
        }; // No legacy wallets in demo — all MoMo via /saved-momo
      case '/smart-routes':
        return DemoSeedData.emptyData();
      case '/round-up':
        return DemoSeedData.roundUp();
      case '/kyc/status':
        return DemoSeedData.kycStatus();
      case '/security/sessions':
        return DemoSeedData.emptyData();
      case '/security/data-export':
        return {
          'data': {'status': 'NONE'},
        };
      case '/contacts/recent':
        return DemoSeedData.emptyData();
      case '/contacts':
        return DemoSeedData.emptyData();
      case '/contacts/invite':
        return {
          'data': {'link': 'https://azaman.app/invite/kwesi123'},
        };
      case '/vendor/applications':
        return DemoSeedData.emptyData();
      case '/users/onboarding':
        return DemoSeedData.onboarding();
      case '/users/preferences':
        return DemoSeedData.preferences();
      case '/users/profile':
        return DemoSeedData.userProfile();
      case '/users/me/milestones':
        return DemoSeedData.milestones();
      case '/users/dashboard':
        return DemoSeedData.dashboard();
      case '/users/proof-of-residency/me':
        return {
          'data': {'status': 'VERIFIED'},
        };
      case '/susu/vouches/pending':
        return DemoSeedData.emptyData();
      case '/friends/transfer/pending':
        return DemoSeedData.emptyData();
      case '/liability-contract/active':
        return DemoSeedData.nullData();
      case '/wallet/deposit-address/polygon':
        return DemoSeedData.depositAddress();
      case '/vaults/yield/strategies':
        return DemoSeedData.yieldStrategies();
      case '/shared-vaults':
        return DemoSeedData.emptyData();
      case '/loyalty/me/cards':
        return DemoSeedData.emptyData();
      case '/business/subcategories':
        return {
          'data': [
            {'id': 'cat-1', 'name': 'Crypto', 'parentWire': 'CRYPTO'},
            {'id': 'cat-2', 'name': 'Food & Drink', 'parentWire': 'FOOD'},
            {'id': 'cat-3', 'name': 'Fashion', 'parentWire': 'FASHION'},
            {'id': 'cat-4', 'name': 'Electronics', 'parentWire': 'ELECTRONICS'},
          ],
        };
      case '/friends/search':
        return {'results': []};
      case '/showcases':
        return DemoSeedData.emptyData();
      // ── Marketplace endpoints (exact) ─────────────────────────────
      // Demo search honours the REAL query string (category / verified /
      // q / limit / cursor) so marketplace selections genuinely change
      // the result set instead of always returning the same page.
      case '/business/search':
        final q = _queryOf(endpoint);
        return DemoMarketplaceSeed.searchBusinesses(
          q: q['q'],
          category: q['category'],
          verified: q['verified'] == 'true'
              ? true
              : (q['verified'] == 'false' ? false : null),
          limit: int.tryParse(q['limit'] ?? '') ?? 20,
          cursor: q['cursor'],
        );
      case '/business/me':
        return {'business': null};
      // ── Marketplace owner surfaces (demo user owns no business —
      // zero/empty responses here are the deliberate, truthful seeds) ──
      case '/business/kyb/status':
        return DemoMarketplaceSeed.getKybStatus();
      case '/business/my-orders':
        return DemoMarketplaceSeed.getMyOrders();
      case '/business/notifications':
        return DemoMarketplaceSeed.getOwnerNotifications();
      case '/business/notifications/unread-count':
        return {'count': 0};
      case '/business/orders/stats':
        return DemoMarketplaceSeed.getOwnerStats();
      case '/business/products':
        return DemoMarketplaceSeed.getMyProducts();
      case '/users/invoices':
        return DemoMarketplaceSeed.getMyInvoices();
    }

    // ── Pattern matches (with path params) ──────────────────────────────

    // /auth/me/{id}
    if (path.startsWith('/auth/me/')) {
      return DemoSeedData.authMe();
    }

    // /friends/chat/{friendshipId}/messages
    final friendMsgMatch = RegExp(
      r'^/friends/chat/(\d+)/messages$',
    ).firstMatch(path);
    if (friendMsgMatch != null) {
      return DemoSeedData.friendMessages(friendMsgMatch.group(1)!);
    }

    // /group-chats/{groupId}/messages
    final groupMsgMatch = RegExp(
      r'^/group-chats/([^/]+)/messages$',
    ).firstMatch(path);
    if (groupMsgMatch != null) {
      return DemoSeedData.groupMessages(groupMsgMatch.group(1)!);
    }

    // /group-chats/{groupId}
    final groupMatch = RegExp(r'^/group-chats/([^/]+)$').firstMatch(path);
    if (groupMatch != null) {
      final groups = DemoSeedData.groupChats();
      final grp = groups.firstWhere(
        (g) => g['id'] == groupMatch.group(1),
        orElse: () => groups.first,
      );
      return {'group': grp};
    }

    // /stories/business/{bizId}
    final bizStoryMatch = RegExp(r'^/stories/business/(.+)$').firstMatch(path);
    if (bizStoryMatch != null) {
      return DemoMarketplaceSeed.getBusinessStories(bizStoryMatch.group(1)!);
    }

    // /group-chats/{groupId}/susu/status
    if (path.contains('/group-chats/') && path.endsWith('/susu/status')) {
      return {'status': 'ACTIVE', 'cycle': 2, 'totalCycles': 4};
    }

    // /vaults/{vaultId}
    if (RegExp(r'^/vaults/[^/]+$').hasMatch(path)) {
      final vaults = DemoSeedData.vaults()['data'] as List;
      return {'data': vaults.first};
    }

    // /vaults/{vaultId}/deposits
    if (path.contains('/vaults/') && path.endsWith('/deposits')) {
      return DemoSeedData.emptyData();
    }

    // /vaults/{vaultId}/yield/earnings
    if (path.contains('/vaults/') && path.endsWith('/yield/earnings')) {
      return {
        'data': {'totalEarned': 85.00, 'apy': 8.5},
      };
    }

    // /susu/{susuId}
    if (RegExp(r'^/susu/[^/]+$').hasMatch(path)) {
      final groups = DemoSeedData.susuGroups()['data'] as List;
      return {'data': groups.first};
    }

    // /susu/{susuId}/members, /cycles, /contract
    if (path.contains('/susu/') &&
        (path.endsWith('/members') ||
            path.endsWith('/cycles') ||
            path.endsWith('/contract'))) {
      if (path.endsWith('/contract')) {
        return {
          'data': {'signed': true},
        };
      }
      return DemoSeedData.emptyData();
    }

    // /susu/groups/{susuId}
    if (path.startsWith('/susu/groups/')) {
      final groups = DemoSeedData.susuGroups()['data'] as List;
      return {'data': groups.first};
    }

    // /friends/{friendshipId}/profile, /media, /receipts, /trust-metrics, /docs-links
    if (path.contains('/friends/') &&
        !path.startsWith('/friends/chat') &&
        !path.startsWith('/friends/requests') &&
        !path.startsWith('/friends/search') &&
        !path.startsWith('/friends/transfer')) {
      if (path.endsWith('/profile')) {
        return {
          'data': {'trustScore': 0.85, 'totalTrades': 12, 'sharedGroups': 1},
        };
      }
      if (path.endsWith('/media') ||
          path.endsWith('/receipts') ||
          path.endsWith('/docs-links')) {
        return DemoSeedData.emptyData();
      }
      if (path.endsWith('/trust-metrics')) {
        return {
          'data': {'trustScore': 0.85, 'totalTrades': 12},
        };
      }
    }

    // /marketplace/business/{bizId}/stories — same rail as /stories/business/.
    final bizStoriesMatch = RegExp(
      r'^/marketplace/business/([^/]+)/stories$',
    ).firstMatch(path);
    if (bizStoriesMatch != null) {
      return DemoMarketplaceSeed.getBusinessStories(bizStoriesMatch.group(1)!);
    }

    // /marketplace/business/dine-in/{tabId} (legacy booking-service path).
    final dineInMatch = RegExp(
      r'^/marketplace/business/dine-in/([^/]+)$',
    ).firstMatch(path);
    if (dineInMatch != null) {
      return DemoMarketplaceSeed.getDineInTab(dineInMatch.group(1)!);
    }

    // /marketplace/trust-score/{azamanId}
    final trustScoreMatch = RegExp(
      r'^/marketplace/trust-score/([^/]+)$',
    ).firstMatch(path);
    if (trustScoreMatch != null) {
      return DemoMarketplaceSeed.getTrustScore(trustScoreMatch.group(1)!);
    }

    // /business/products/{productId} (public single-product lookup).
    final productMatch = RegExp(
      r'^/business/products/([^/]+)$',
    ).firstMatch(path);
    if (productMatch != null) {
      return DemoMarketplaceSeed.getProductById(productMatch.group(1)!);
    }

    // /marketplace/business/{bizId}
    final bizMatch = RegExp(
      r'^/marketplace/business/([^/]+)$',
    ).firstMatch(path);
    if (bizMatch != null) {
      return DemoMarketplaceSeed.getBusinessByBizId(bizMatch.group(1)!);
    }

    // /business/{bizId}/menu
    final menuMatch = RegExp(r'^/business/([^/]+)/menu$').firstMatch(path);
    if (menuMatch != null) {
      return DemoMarketplaceSeed.getMenu(menuMatch.group(1)!);
    }

    // /business/{bizId}/products
    final productsMatch = RegExp(
      r'^/business/([^/]+)/products$',
    ).firstMatch(path);
    if (productsMatch != null) {
      return DemoMarketplaceSeed.getProducts(productsMatch.group(1)!);
    }

    // /business/{bizId}/locations
    final locationsMatch = RegExp(
      r'^/business/([^/]+)/locations$',
    ).firstMatch(path);
    if (locationsMatch != null) {
      return DemoMarketplaceSeed.getLocations(locationsMatch.group(1)!);
    }

    // /business/{bizId}/reviews — real seeded reviews per business.
    final reviewsMatch = RegExp(
      r'^/business/([^/]+)/reviews$',
    ).firstMatch(path);
    if (reviewsMatch != null) {
      return DemoMarketplaceSeed.getReviews(reviewsMatch.group(1)!);
    }

    // /business/invoices/{invoiceId}
    final invoiceMatch = RegExp(r'^/business/invoices/(.+)$').firstMatch(path);
    if (invoiceMatch != null) {
      return DemoMarketplaceSeed.getInvoice(invoiceMatch.group(1)!);
    }

    // /business/{bizId} (but NOT /business/{bizId}/menu etc.)
    final businessMatch = RegExp(r'^/business/([^/]+)$').firstMatch(path);
    if (businessMatch != null) {
      return DemoMarketplaceSeed.getBusinessByBizId(businessMatch.group(1)!);
    }

    // /business/search/nearby — query-aware (category/verified/q/limit/cursor).
    if (path == '/business/search/nearby') {
      final q = _queryOf(endpoint);
      return DemoMarketplaceSeed.searchNearby(
        q: q['q'],
        category: q['category'],
        verified: q['verified'] == 'true'
            ? true
            : (q['verified'] == 'false' ? false : null),
        limit: int.tryParse(q['limit'] ?? '') ?? 20,
        cursor: q['cursor'],
      );
    }

    // /showcases/{bizId}
    final showcaseMatch = RegExp(r'^/showcases/(.+)$').firstMatch(path);
    if (showcaseMatch != null) {
      return DemoMarketplaceSeed.getShowcase(showcaseMatch.group(1)!);
    }

    // /marketplace/transit/trips
    if (path == '/marketplace/transit/trips') {
      return DemoMarketplaceSeed.getTransitTrips();
    }

    // /marketplace/transit/trips/{tripId}/seats
    final transitSeatsMatch = RegExp(
      r'^/marketplace/transit/trips/([^/]+)/seats$',
    ).firstMatch(path);
    if (transitSeatsMatch != null) {
      return DemoMarketplaceSeed.getTripSeats(transitSeatsMatch.group(1)!);
    }

    // /marketplace/reservations/{reservationId}/checkin-qr — seeded
    // reservation only; unknown refs are not seeded, not faked.
    if (path.contains('/marketplace/reservations/') &&
        path.endsWith('/checkin-qr')) {
      final reservationId = path
          .split('/marketplace/reservations/')[1]
          .split('/checkin-qr')[0];
      if (!DemoMarketplaceSeed.isSeededId(
        reservationId,
        DemoMarketplaceSeed.seededReservationRefs,
      )) {
        throw DemoEndpointNotSeededException(
          'GET',
          '/marketplace/reservations/$reservationId/checkin-qr',
        );
      }
      return {
        'success': true,
        'token': 'demo-token-123',
        'qrPayload': 'azaman:checkin:demo',
        'azamanId': 'AZM-000123456',
        'reservationRef': 'AZM-RES-001',
        'expiresAt': DateTime.now()
            .add(const Duration(hours: 24))
            .toUtc()
            .toIso8601String(),
      };
    }

    // /storefront/{id}/render, /theme
    if (path.contains('/storefront/') &&
        (path.endsWith('/render') || path.endsWith('/theme'))) {
      return DemoSeedData.nullData();
    }

    // /follows/following
    if (path == '/follows/following') {
      return {'following': DemoMarketplaceSeed.getFollowing()};
    }

    // /follows/check/{bizId} — seeded businesses only.
    if (path.startsWith('/follows/check/')) {
      final bizId = path.substring('/follows/check/'.length);
      if (!DemoMarketplaceSeed.isSeededId(
        bizId,
        DemoMarketplaceSeed.seededBusinessIds,
      )) {
        throw DemoEndpointNotSeededException('GET', '/follows/check/$bizId');
      }
      return {'isFollowing': false};
    }

    // /stories/analytics/business/{bizId} — seeded businesses only.
    if (path.startsWith('/stories/analytics/business/')) {
      final bizId = path.substring('/stories/analytics/business/'.length);
      if (!DemoMarketplaceSeed.isSeededId(
        bizId,
        DemoMarketplaceSeed.seededBusinessIds,
      )) {
        throw DemoEndpointNotSeededException(
          'GET',
          '/stories/analytics/business/$bizId',
        );
      }
      return {
        'data': {'views': 340, 'replies': 12, 'boosts': 5},
      };
    }

    // /trades/{tradeId}
    if (RegExp(r'^/trades/[^/]+$').hasMatch(path)) {
      final trades = DemoSeedData.tradeHistory()['trades'] as List;
      return {'data': trades.first};
    }

    // /tickets/{id}
    if (path.startsWith('/tickets/')) {
      return DemoSeedData.nullData();
    }

    // /orders/{orderId}/tracking
    if (path.contains('/orders/') && path.endsWith('/tracking')) {
      return DemoSeedData.nullData();
    }

    // /oracle/yellowcard-rate
    if (path == '/oracle/yellowcard-rate') {
      return {
        'data': {
          'rate': 15.42,
          'lastSync': DateTime.now()
              .subtract(const Duration(minutes: 3))
              .toUtc()
              .toIso8601String(),
        },
      };
    }

    // Admin endpoints
    if (path.startsWith('/admin/')) {
      return DemoSeedData.emptyData();
    }

    // ── Marketplace-family coverage guard ────────────────────────────────
    // A GET in a Marketplace-related family that reaches this point has
    // NO seeded coverage. Returning fake-empty data here would let a
    // missing demo implementation masquerade as a successful "nothing
    // exists" response (e.g. "No businesses found"). Fail explicitly with
    // a typed signal instead — providers surface it as an error state.
    if (path == '/business' ||
        path == '/marketplace' ||
        path == '/showcases' ||
        path.startsWith('/business/') ||
        path.startsWith('/marketplace/') ||
        path.startsWith('/follows/') ||
        path.startsWith('/showcases/')) {
      throw DemoEndpointNotSeededException('GET', path);
    }

    // Unknown non-marketplace endpoint — return empty data to avoid crashes
    return DemoSeedData.emptyData();
  }

  /// Parses `?a=1&b=2` off an endpoint string into a flat map.
  static Map<String, String> _queryOf(String endpoint) {
    final qIndex = endpoint.indexOf('?');
    if (qIndex < 0) return const {};
    final out = <String, String>{};
    for (final part in endpoint.substring(qIndex + 1).split('&')) {
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      if (eq < 0) {
        out[Uri.decodeQueryComponent(part)] = '';
      } else {
        out[Uri.decodeQueryComponent(part.substring(0, eq))] =
            Uri.decodeQueryComponent(part.substring(eq + 1));
      }
    }
    return out;
  }

  // ── POST endpoint matching ────────────────────────────────────────────
  static Map<String, dynamic>? _matchPost(
    String endpoint,
    Map<String, dynamic> body,
  ) {
    final path = endpoint.split('?').first;

    // /marketplace/transit/trips/{tripId}/book
    final bookMatch = RegExp(
      r'^/marketplace/transit/trips/([^/]+)/book$',
    ).firstMatch(path);
    if (bookMatch != null) {
      return {
        'success': true,
        'bookingRef':
            'AZM-BOOK-${DateTime.now().millisecondsSinceEpoch.toString().substring(0, 8)}',
        'seatIds': ['1A', '1B'],
      };
    }

    // /business/invoices/{invoiceId}/pay
    final payMatch = RegExp(r'^/business/invoices/(.+)/pay$').firstMatch(path);
    if (payMatch != null) {
      return {
        'invoice': DemoMarketplaceSeed.getInvoice(
          payMatch.group(1)!,
        )['invoice'],
      };
    }

    // Stories view/reply/boost
    if (path.startsWith('/stories/') &&
        (path.endsWith('/view') ||
            path.endsWith('/reply') ||
            path.endsWith('/boost'))) {
      return DemoSeedData.okSuccess();
    }

    // /saved-momo — create a new saved MoMo account
    if (path == '/saved-momo') {
      return {
        'account': {
          'id': 'momo-${DateTime.now().millisecondsSinceEpoch}',
          'nickname': body['nickname'] ?? 'New Account',
          'provider': body['provider'] ?? 'MTN',
          'phoneNumber': body['phoneNumber'] ?? '',
          'accountName': body['nickname'] ?? 'Verified User',
          'isVerified': true,
          'isPrimary': body['isPrimary'] ?? false,
          'lastUsedAt': null,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      };
    }

    // /deposit/validate-name — name lookup for MoMo account
    if (path == '/deposit/validate-name') {
      return DemoSeedData.depositValidateName();
    }

    // /deposit/fiat/initiate/moolre — start a MoMo deposit
    if (path == '/deposit/fiat/initiate/moolre') {
      final result = DemoSeedData.depositInitiated();
      // Inject the amount from the request body if available
      final amountGhs = body['amountGhs'];
      if (amountGhs != null) {
        (result['data'] as Map<String, dynamic>)['amountGhs'] = amountGhs;
      }
      return result;
    }

    // /deposit/fiat/initiate/moolre/otp — confirm deposit with OTP
    if (path == '/deposit/fiat/initiate/moolre/otp') {
      return DemoSeedData.depositOtpConfirmed();
    }

    // Any other POST — return generic success
    return DemoSeedData.okSuccess();
  }

  // ── Generic success for PUT/PATCH/DELETE ──────────────────────────────
  static http.Response _simpleSuccess() {
    return http.Response(
      jsonEncode(DemoSeedData.okSuccess()),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
