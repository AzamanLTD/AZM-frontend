// =============================================================================
// AZAMAN — GOROUTER CONFIGURATION
//
// Phase M (2026-05-25) expansion: every deep-linkable surface that an FCM
// notification or external URL might target now has a named route here. The
// rest of the app still uses `Navigator.push(MaterialPageRoute(...))` for
// imperative navigation between sibling screens — that is fine. The point
// of GoRoute promotion is *deep linking*, not *all navigation*. A screen
// only needs a GoRoute if:
//
//   * an FCM `actionPayload` can target it (`OPEN_TRADE`, `OPEN_DISPUTE`,
//     `OPEN_FRIEND_REQUEST`, `OPEN_REFERRAL`, etc.)
//   * a settings deep-link is desirable (`/settings`, `/profile/edit`)
//   * a shareable URL would land users there (`/leaderboard`, `/referral`)
//
// Sibling-to-sibling navigation inside a feature (e.g. settings → child
// picker, marketplace → ad detail) stays imperative.
//
// Action → route mapping for `handleNotificationTap` mirrors the
// `actionPayload.action` strings the BE emits in
// notificationService.sendNotification calls.
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/screens/splash_screen.dart';
import 'package:azaman/screens/notification_hub_screen.dart';
import 'package:azaman/screens/active_trade_screen.dart';
import 'package:azaman/screens/waiting_room_screen.dart';
import 'package:azaman/screens/account_activity_screen.dart';
import 'package:azaman/screens/account_deactivation_screen.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/screens/azm_auction/azm_auction_screen.dart';
import 'package:azaman/screens/leaderboard_screen.dart';
import 'package:azaman/screens/messages_hub_screen.dart';
import 'package:azaman/screens/profile_details_screen.dart';
import 'package:azaman/screens/referral_screen.dart';
import 'package:azaman/screens/savings_screen.dart';
import 'package:azaman/screens/settings_screen.dart';
import 'package:azaman/screens/p2p/p2p_market_list_screen.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';
import 'package:azaman/screens/susu/invite_landing_screen.dart';
import 'package:azaman/screens/susu/liability_acceptance_screen.dart';
import 'package:azaman/screens/susu/proof_of_residency_screen.dart';
import 'package:azaman/screens/susu/susu_dashboard_screen.dart';
import 'package:azaman/screens/susu/susu_hub_screen.dart';
import 'package:azaman/screens/transaction_history_screen.dart';
// V3 Marketplace Sprint (2026-06-21) — Premium Marketplace surfaces.
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
import 'package:azaman/screens/marketplace/business_search_screen.dart';
import 'package:azaman/screens/marketplace/saved_businesses_screen.dart';
import 'package:azaman/screens/marketplace/business_register_screen.dart';
import 'package:azaman/screens/marketplace/business_notifications_screen.dart';
import 'package:azaman/screens/marketplace/business_products_screen.dart';
import 'package:azaman/screens/marketplace/my_orders_screen.dart';
import 'package:azaman/screens/marketplace/my_invoices_screen.dart';
import 'package:azaman/screens/marketplace/invoice_detail_screen.dart';
import 'package:azaman/screens/marketplace/business_dashboard_screen.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';

/// Global navigator key — set on the GoRouter so notification handlers
/// can access the navigation stack from outside the widget tree.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  navigatorKey: rootNavigatorKey,
  routes: [
    // ── Boot & shell ────────────────────────────────────────────────────────
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const SplashScreen(),
    ),

    // ── Notifications ───────────────────────────────────────────────────────
    GoRoute(
      path: '/notifications',
      name: 'notifications',
      builder: (context, state) => const NotificationHubScreen(),
    ),

    // ── Trade lifecycle (keys: OPEN_TRADE / OPEN_DISPUTE) ───────────────────
    GoRoute(
      path: '/trade/:tradeId',
      name: 'trade',
      builder: (context, state) {
        final tradeId = state.pathParameters['tradeId']!;
        return ActiveTradeScreen(orderId: '#$tradeId');
      },
    ),
    GoRoute(
      path: '/dispute/:disputeId',
      name: 'dispute',
      builder: (context, state) {
        final disputeId = state.pathParameters['disputeId']!;
        return _DisputeScreen(disputeId: disputeId);
      },
    ),

    // ── Queue / Waiting Room (key: OPEN_QUEUE) ──────────────────────────────
    GoRoute(
      path: '/queue',
      name: 'queue',
      builder: (context, state) {
        final queueId = state.uri.queryParameters['queueId'] ?? '';
        final position = int.tryParse(
                state.uri.queryParameters['position'] ?? '') ?? 1;
        final adId = state.uri.queryParameters['adId'] ?? '';
        return WaitingRoomScreen(
          queueId: queueId,
          queuePosition: position,
          adId: adId,
        );
      },
    ),

    // ── Settings & account (Phase M expansion) ──────────────────────────────
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/profile/edit',
      name: 'profile-edit',
      builder: (context, state) => const ProfileDetailsScreen(),
    ),
    GoRoute(
      path: '/account/activity',
      name: 'account-activity',
      builder: (context, state) => const AccountActivityScreen(),
    ),
    GoRoute(
      path: '/account/delete',
      name: 'account-delete',
      builder: (context, state) => const AccountDeactivationScreen(),
    ),
    GoRoute(
      path: '/transactions',
      name: 'transactions',
      builder: (context, state) => const TransactionHistoryScreen(),
    ),

    // ── Social: friends, messages, referral, leaderboard ────────────────────
    GoRoute(
      path: '/friends',
      name: 'friends',
      builder: (context, state) => const FriendsHubScreen(),
    ),
    GoRoute(
      path: '/messages',
      name: 'messages',
      builder: (context, state) => const MessagesHubScreen(),
    ),
    GoRoute(
      path: '/referral',
      name: 'referral',
      builder: (context, state) => const ReferralScreen(),
    ),
    GoRoute(
      path: '/leaderboard',
      name: 'leaderboard',
      builder: (context, state) => const LeaderboardScreen(),
    ),
    GoRoute(
      path: '/azm-auction',
      name: 'azm-auction',
      builder: (context, state) => const AzmAuctionScreen(),
    ),

    // ── Marketplace + savings (deep-linkable from FCM "trade match"
    //    / savings reminder notifications) ────────────────────────────────
    GoRoute(
      path: '/marketplace',
      name: 'marketplace',
      builder: (context, state) => const P2PMarketListScreen(),
    ),
    GoRoute(
      path: '/savings',
      name: 'savings',
      builder: (context, state) => const SavingsScreen(),
    ),

    // ── Deposit (Phase 4 / Susu Sprint, 2026-05-31) ─────────────────────
    // Susu T-24h shortfall reminders deep-link into this route with
    //   /deposit?amount=12.34&memo=susu:<susuId>
    // and the screen pre-fills the Mobile Money tab on receive (Req 12.4).
    GoRoute(
      path: '/deposit',
      name: 'deposit',
      builder: (context, state) => DepositScreen(
        prefillAmount: state.uri.queryParameters['amount'],
        memo: state.uri.queryParameters['memo'],
      ),
    ),

    // ── Private Susu Ecosystem (Phase 4) ────────────────────────────────
    // /susu/invite/:token is the **public** route — calls the BE preview
    // endpoint without a JWT. Other susu routes are auth-gated by the
    // standard auth middleware on each underlying API call.
    GoRoute(
      path: '/susu',
      name: 'susu-hub',
      builder: (context, state) => const SusuHubScreen(),
    ),
    GoRoute(
      path: '/proof-of-residency',
      name: 'proof-of-residency',
      builder: (context, state) => const ProofOfResidencyScreen(),
    ),
    GoRoute(
      path: '/susu/invite/:token',
      name: 'susu-invite',
      builder: (context, state) => InviteLandingScreen(
        token: state.pathParameters['token']!,
      ),
    ),
    GoRoute(
      path: '/susu/:id',
      name: 'susu-detail',
      builder: (context, state) => SusuDashboardScreen(
        susuId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/susu/:id/contract',
      name: 'susu-contract',
      builder: (context, state) => LiabilityAcceptanceScreen(
        susuId: state.pathParameters['id']!,
      ),
    ),

    // ── V3 Premium Marketplace (2026-06-21) ─────────────────────────────────
    // NOTE: the existing `/marketplace` route is the P2P crypto market (FCM
    // `OPEN_AD` targets it), so the new *business* marketplace is mounted under
    // `/business-market` to avoid hijacking it. The `/business/:bizId`
    // catch-style route MUST stay last among the `/business/...` group so the
    // literal sub-routes (search / register / notifications / :bizId/products)
    // win over it.
    GoRoute(
      path: '/business-market',
      name: 'business-market',
      builder: (_, __) => const MarketplaceHomeScreen(),
    ),
    GoRoute(
      path: '/business-market/orders',
      name: 'business-market-orders',
      builder: (_, __) => const MyOrdersScreen(),
    ),
    GoRoute(
      path: '/business-market/invoices',
      name: 'business-market-invoices',
      builder: (_, __) => const MyInvoicesScreen(),
    ),
    GoRoute(
      path: '/business-market/invoices/:invoiceId',
      name: 'invoice-detail',
      builder: (_, state) => InvoiceDetailScreen(
        invoiceId: state.pathParameters['invoiceId']!,
      ),
    ),
    GoRoute(
      path: '/business-market/dashboard',
      name: 'business-market-dashboard',
      builder: (_, __) => const BusinessDashboardScreen(),
    ),
    GoRoute(
      path: '/business/search',
      name: 'business-search',
      builder: (_, __) => const BusinessSearchScreen(),
    ),
    // Saved businesses wishlist (Marketplace Premium Upgrade, 2026-06-21).
    // Mounted under /biz/ (not /business/) so it never collides with the
    // `/business/:bizId` catch route below.
    GoRoute(
      path: '/biz/saved',
      name: 'saved-businesses',
      builder: (_, __) => const SavedBusinessesScreen(),
    ),
    GoRoute(
      path: '/business/register',
      name: 'business-register',
      builder: (_, __) => const BusinessRegisterScreen(),
    ),
    GoRoute(
      path: '/business/notifications',
      name: 'business-notifications',
      builder: (_, __) => const BusinessNotificationsScreen(),
    ),
    GoRoute(
      path: '/business/:bizId/products',
      name: 'business-products',
      builder: (_, state) => BusinessProductsScreen(
        bizId: state.pathParameters['bizId']!,
        businessName: state.uri.queryParameters['name'],
      ),
    ),
    GoRoute(
      path: '/business/:bizId',
      name: 'business-profile',
      builder: (_, state) => BusinessProfileScreen(
        bizId: state.pathParameters['bizId']!,
      ),
    ),
  ],
);

class _DisputeScreen extends ConsumerWidget {
  final String disputeId;

  const _DisputeScreen({required this.disputeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Dispute #$disputeId',
            style: TextStyle(color: colors.textPrimary, fontSize: 16)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(HugeIconsSolid.judge, size: 64, color: colors.danger),
              const SizedBox(height: 16),
              Text('Dispute #$disputeId',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('This dispute is being reviewed.',
                  style:
                      TextStyle(color: colors.textSecondary, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// FCM action → route resolver
//
// Phase M expanded the action vocabulary. The full set of `actionPayload.action`
// strings the BE currently emits (per `notificationService.sendNotification`
// callsites grepped in 2026-05) is:
//
//   OPEN_TRADE             tradeId           → /trade/:id
//   OPEN_DISPUTE           disputeId         → /dispute/:id
//   OPEN_FRIEND_REQUEST    friendshipId      → /friends
//   OPEN_FRIEND_CHAT       friendshipId      → /friends  (FriendsHub picks the chat)
//   PING_TOPUP             tradeId           → /trade/:id
//   VIEW_SAVINGS           goalId            → /savings
//   OPEN_AD                adId              → /marketplace
//
// Unknown actions silently no-op so a future BE-only rollout doesn't crash
// older clients in the wild.
// =============================================================================

void handleNotificationTap({
  required String action,
  Map<String, dynamic>? actionPayload,
}) {
  // For deep links from notifications, use Navigator.push on the root navigator
  // so the screen is added to the existing navigation stack (not GoRouter's
  // separate stack). Pressing back will return to wherever the user was.
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) {
    // Navigator not ready yet (app cold-starting from notification)
    // Fall back to GoRouter which will handle the route after splash
    _fallbackToRouter(action, actionPayload);
    return;
  }

  Widget? targetScreen;
  switch (action) {
    case 'OPEN_TRADE':
    case 'PING_TOPUP': {
      final tradeId = actionPayload?['tradeId']?.toString();
      if (tradeId != null) {
        // Push the active trade screen on top of whatever's there
        navigator.push(MaterialPageRoute(
          builder: (_) => _LazyTradeScreenLoader(tradeId: tradeId),
        ));
      }
      break;
    }
    case 'OPEN_DISPUTE': {
      final disputeId = actionPayload?['disputeId']?.toString();
      if (disputeId != null) {
        navigator.push(MaterialPageRoute(
          builder: (_) => _DisputeScreen(disputeId: disputeId),
        ));
      }
      break;
    }
    case 'OPEN_FRIEND_REQUEST':
    case 'OPEN_FRIEND_CHAT':
      navigator.push(MaterialPageRoute(builder: (_) => const FriendsHubScreen()));
      break;
    case 'VIEW_SAVINGS':
      navigator.push(MaterialPageRoute(builder: (_) => const SavingsScreen()));
      break;
    case 'OPEN_AD':
      navigator.push(MaterialPageRoute(builder: (_) => const P2PMarketListScreen()));
      break;
    // Phase 4 (Susu Sprint, 2026-05-31) — three new susu deep-link
    // actions. All mirror the existing OPEN_TRADE / PING_TOPUP shape.
    case 'OPEN_SUSU': {
      final susuId = actionPayload?['susuId']?.toString();
      if (susuId != null) {
        navigator.push(MaterialPageRoute(
          builder: (_) => SusuDashboardScreen(susuId: susuId),
        ));
      } else {
        navigator.push(MaterialPageRoute(
          builder: (_) => const SusuHubScreen(),
        ));
      }
      break;
    }
    case 'OPEN_SUSU_INVITE': {
      // The BE may emit either a SusuInvite id (FRIEND/PHONE channels)
      // or a token (LINK channel). The token path is the public-route
      // redemption flow; the id path opens the dashboard for the bound
      // member. We prefer the token if present.
      final token = actionPayload?['token']?.toString();
      final susuId = actionPayload?['susuId']?.toString();
      if (token != null && token.isNotEmpty) {
        navigator.push(MaterialPageRoute(
          builder: (_) => InviteLandingScreen(token: token),
        ));
      } else if (susuId != null) {
        navigator.push(MaterialPageRoute(
          builder: (_) => SusuDashboardScreen(susuId: susuId),
        ));
      } else {
        navigator.push(MaterialPageRoute(
          builder: (_) => const SusuHubScreen(),
        ));
      }
      break;
    }
    case 'OPEN_DEPOSIT_FOR_SUSU': {
      final amount = actionPayload?['amount']?.toString();
      final susuId = actionPayload?['susuId']?.toString();
      navigator.push(MaterialPageRoute(
        builder: (_) => DepositScreen(
          prefillAmount: amount,
          memo: susuId == null ? null : 'susu:$susuId',
        ),
      ));
      break;
    }
    case 'OPEN_PROOF_OF_RESIDENCY':
      navigator.push(MaterialPageRoute(
        builder: (_) => const ProofOfResidencyScreen(),
      ));
      break;
    default:
      // Unknown action — no-op
      break;
  }
}

void _fallbackToRouter(String action, Map<String, dynamic>? actionPayload) {
  String? route;
  switch (action) {
    case 'OPEN_TRADE':
    case 'PING_TOPUP': {
      final tradeId = actionPayload?['tradeId']?.toString();
      if (tradeId != null) route = '/trade/$tradeId';
      break;
    }
    case 'OPEN_DISPUTE': {
      final disputeId = actionPayload?['disputeId']?.toString();
      if (disputeId != null) route = '/dispute/$disputeId';
      break;
    }
    case 'OPEN_FRIEND_REQUEST':
    case 'OPEN_FRIEND_CHAT':
      route = '/friends';
      break;
    case 'VIEW_SAVINGS':
      route = '/savings';
      break;
    case 'OPEN_AD':
      route = '/marketplace';
      break;
    // Phase 4 (Susu Sprint, 2026-05-31) — cold-start fallback for the
    // three new actions. We use the GoRouter route forms because the
    // navigator key isn't yet attached when this branch fires.
    case 'OPEN_SUSU': {
      final susuId = actionPayload?['susuId']?.toString();
      route = susuId == null ? '/susu' : '/susu/$susuId';
      break;
    }
    case 'OPEN_SUSU_INVITE': {
      final token = actionPayload?['token']?.toString();
      final susuId = actionPayload?['susuId']?.toString();
      if (token != null && token.isNotEmpty) {
        route = '/susu/invite/$token';
      } else if (susuId != null) {
        route = '/susu/$susuId';
      } else {
        route = '/susu';
      }
      break;
    }
    case 'OPEN_DEPOSIT_FOR_SUSU': {
      final amount = actionPayload?['amount']?.toString();
      final susuId = actionPayload?['susuId']?.toString();
      final qs = <String>[
        if (amount != null) 'amount=${Uri.encodeQueryComponent(amount)}',
        if (susuId != null) 'memo=${Uri.encodeQueryComponent('susu:$susuId')}',
      ].join('&');
      route = qs.isEmpty ? '/deposit' : '/deposit?$qs';
      break;
    }
    case 'OPEN_PROOF_OF_RESIDENCY':
      route = '/proof-of-residency';
      break;
  }
  if (route != null) {
    appRouter.push(route);
  }
}

// Lazy loader wrapper so we don't import ActiveTradeScreen at module scope
// (avoids potential circular imports)
class _LazyTradeScreenLoader extends StatelessWidget {
  final String tradeId;
  const _LazyTradeScreenLoader({required this.tradeId});

  @override
  Widget build(BuildContext context) {
    return ActiveTradeScreen(orderId: '#$tradeId');
  }
}

Map<String, dynamic>? parseFcmPayload(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map<String, dynamic>) return raw;
  if (raw is String) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
  }
  return null;
}
