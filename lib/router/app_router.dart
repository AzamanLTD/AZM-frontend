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

import 'dart:io';
import 'package:azaman/screens/story_camera_screen.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:azaman/router/auth_guard.dart';
import 'package:azaman/router/deep_link.dart';
import 'package:azaman/router/route_depth.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/screens/marketplace/hotel_booking_screen.dart';
import 'package:azaman/screens/marketplace/dinein_tab_screen.dart';
import 'package:azaman/screens/marketplace/business_stories_screen.dart'; // Commented if not exists yet

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
import 'package:azaman/screens/friends/friend_chat_screen.dart';
import 'package:azaman/screens/profile_details_screen.dart';
import 'package:azaman/screens/referral_screen.dart';
import 'package:azaman/screens/savings_screen.dart';
import 'package:azaman/screens/settings_screen.dart';
import 'package:azaman/screens/storefront_staking_screen.dart';
import 'package:azaman/screens/storefront_screen.dart';
import 'package:azaman/screens/storefront_discovery_screen.dart';
import 'package:azaman/screens/storefront_order_history_screen.dart';
import 'package:azaman/screens/universal_search_screen.dart';
import 'package:azaman/screens/spending_insights_screen.dart';
import 'package:azaman/screens/round_up_settings_screen.dart';
import 'package:azaman/screens/notification_preferences_screen.dart';
import 'package:azaman/screens/story_highlights_screen.dart';
import 'package:azaman/screens/story_editor_screen.dart';
import 'package:azaman/screens/close_friends_screen.dart';
import 'package:azaman/screens/story_analytics_screen.dart';
import 'package:azaman/screens/loyalty_cards_screen.dart';
import 'package:azaman/screens/susu/susu_position_picker_screen.dart';
import 'package:azaman/screens/susu/susu_completion_screen.dart';
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
import 'package:azaman/router/transitions.dart';
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
import 'package:azaman/screens/marketplace/checkin_qr_screen.dart';
import 'package:azaman/screens/marketplace/business_checkin_screen.dart';
import 'package:azaman/screens/marketplace/transit_trip_list_screen.dart';
import 'package:azaman/screens/marketplace/transit_seat_selection_screen.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/worker/worker_hub_screen.dart';
import 'package:azaman/screens/worker/worker_shifts_screen.dart';
import 'package:azaman/screens/worker/worker_payroll_screen.dart';
import 'package:azaman/screens/worker/worker_team_screen.dart';
import 'package:azaman/screens/worker/worker_time_off_screen.dart';
import 'package:azaman/screens/worker/worker_feedback_screen.dart';
import 'package:azaman/screens/worker/worker_ewa_screen.dart';
import 'package:azaman/screens/worker/worker_swaps_screen.dart';

import 'package:azaman/screens/chat/message_search_screen.dart';
import 'package:azaman/screens/wallet/wallet_pass_screen.dart';
import 'package:azaman/screens/orders/order_tracking_screen.dart';
import 'package:azaman/screens/vault/vault_yield_screen.dart';
import 'package:azaman/screens/story_creation_screen.dart';
import 'package:azaman/config.dart';

/// Global navigator key — set on the GoRouter so notification handlers
/// can access the navigation stack from outside the widget tree.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// NEW-A (Step 6): the app-scoped route-depth signal. NEW-C's depth-aware
/// nav chrome reads this — never infer depth from screen names.
final RouteDepthTracker routeDepthTracker = RouteDepthTracker(appRouter);

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  navigatorKey: rootNavigatorKey,
  // NEW-A (restoration): gives the Navigator a stable restoration scope so
  // the page stack participates in Flutter's restoration system. Combined
  // with every page's restorationId (its stable route name, set by the
  // transition families) routes are deemed restorable and each route
  // subtree gets its own RestorationScope from ModalRoute.
  restorationScopeId: 'azm-router',
  redirect: (context, state) {
    // NEW-A (Step 5): normalize azaman:// deep links into app paths BEFORE
    // any other check, so a cold-start or runtime deep link resolves
    // through the same route table as a warm push. The normalized
    // location re-enters the redirect with the http(s)/path scheme the
    // rest of this function (and every auth check) already understands.
    if (state.uri.scheme == kAzamanDeepLinkScheme) {
      return azamanDeepLinkToLocation(state.uri);
    }
    final path = state.uri.path;
    // Public routes always pass
    if (path == '/' || path.startsWith('/susu/invite/')) return null;
    // Demo mode: bypass auth gating entirely — demo build has no real session to protect.
    if (AppConfig.demoMode) return null;
    // Crash-safe auth check: if AuthGuard throws, treat as NOT authenticated
    // and go to splash rather than letting a red error screen bounce home.
    try {
      if (!AuthGuard.isAuthenticated) return '/';
    } catch (_) {
      return '/';
    }
    return null;
  },
  errorBuilder: (context, state) => _AzamanRouteErrorScreen(error: state.error),
  routes: [
    // ── Boot & shell ────────────────────────────────────────────────────────
    GoRoute(
      path: '/',
      name: AzRouteNames.home,
      builder: (context, state) => const SplashScreen(),
    ),

    // ── Notifications ───────────────────────────────────────────────────────
    GoRoute(
      path: '/notifications',
      name: AzRouteNames.notifications,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const NotificationHubScreen(),
      ),
    ),

    // ── Trade lifecycle (keys: OPEN_TRADE / OPEN_DISPUTE) ───────────────────
    GoRoute(
      path: '/trade/:tradeId',
      name: AzRouteNames.trade,
      builder: (context, state) {
        final tradeId = state.pathParameters['tradeId']!;
        // Warm pushes (and only they) may carry amount/paymentMethod via
        // extra; deep links land with the screen's defaults.
        final extra = state.extra as Map<String, dynamic>?;
        return ActiveTradeScreen(
          orderId: '#$tradeId',
          amount: (extra?['amount'] as num?)?.toDouble() ?? 0.0,
          paymentMethod: extra?['paymentMethod'] as String? ?? 'Bank Transfer',
        );
      },
    ),
    GoRoute(
      path: '/dispute/:disputeId',
      name: AzRouteNames.dispute,
      builder: (context, state) {
        final disputeId = state.pathParameters['disputeId']!;
        return _DisputeScreen(disputeId: disputeId);
      },
    ),

    // ── Queue / Waiting Room (key: OPEN_QUEUE) ──────────────────────────────
    GoRoute(
      path: '/queue',
      name: AzRouteNames.queue,
      builder: (context, state) {
        final queueId = state.uri.queryParameters['queueId'] ?? '';
        final position =
            int.tryParse(state.uri.queryParameters['position'] ?? '') ?? 1;
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
      name: AzRouteNames.settings,
      pageBuilder: (context, state) => traversePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const SettingsScreen(),
      ),
    ),
    GoRoute(
      path: '/profile/edit',
      name: AzRouteNames.profileEdit,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const ProfileDetailsScreen(),
      ),
    ),
    GoRoute(
      path: '/account/activity',
      name: AzRouteNames.accountActivity,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const AccountActivityScreen(),
      ),
    ),
    GoRoute(
      path: '/account/delete',
      name: AzRouteNames.accountDelete,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const AccountDeactivationScreen(),
      ),
    ),
    GoRoute(
      path: '/transactions',
      name: AzRouteNames.transactions,
      pageBuilder: (context, state) => traversePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const TransactionHistoryScreen(),
      ),
    ),

    // ── Social: friends, messages, referral, leaderboard ────────────────────
    GoRoute(
      path: '/friends',
      name: AzRouteNames.friends,
      pageBuilder: (context, state) => traversePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const FriendsHubScreen(),
      ),
    ),
    GoRoute(
      path: '/messages',
      name: AzRouteNames.messages,
      pageBuilder: (context, state) => traversePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const MessagesHubScreen(),
      ),
    ),
    GoRoute(
      path: '/referral',
      name: AzRouteNames.referral,
      pageBuilder: (context, state) => traversePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const ReferralScreen(),
      ),
    ),
    GoRoute(
      path: '/leaderboard',
      name: AzRouteNames.leaderboard,
      pageBuilder: (context, state) => traversePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const LeaderboardScreen(),
      ),
    ),
    GoRoute(
      path: '/azm-auction',
      name: AzRouteNames.azmAuction,
      pageBuilder: (context, state) => traversePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const AzmAuctionScreen(),
      ),
    ),

    // ── Marketplace + savings (deep-linkable from FCM "trade match"
    //    / savings reminder notifications) ────────────────────────────────
    GoRoute(
      path: '/marketplace',
      name: AzRouteNames.marketplace,
      pageBuilder: (context, state) => traversePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const P2PMarketListScreen(),
      ),
    ),
    GoRoute(
      path: '/savings',
      name: AzRouteNames.savings,
      pageBuilder: (context, state) => traversePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const SavingsScreen(),
      ),
    ),

    // ── Deposit (Phase 4 / Susu Sprint, 2026-05-31) ─────────────────────
    // Susu T-24h shortfall reminders deep-link into this route with
    //   /deposit?amount=12.34&memo=susu:<susuId>
    // and the screen pre-fills the Mobile Money tab on receive (Req 12.4).
    GoRoute(
      path: '/deposit',
      name: AzRouteNames.deposit,
      // Rise family: deposit is a layered push (the destination rises
      // from a lower layer) — the same vertical semantics the + launcher's
      // old imperative helper provided, now at the ROUTE level so every
      // entry point (launcher, activity, deep link) transitions alike.
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: DepositScreen(
          prefillAmount: state.uri.queryParameters['amount'],
          memo: state.uri.queryParameters['memo'],
        ),
      ),
    ),

    // ── Private Susu Ecosystem (Phase 4) ────────────────────────────────
    // /susu/invite/:token is the **public** route — calls the BE preview
    // endpoint without a JWT. Other susu routes are auth-gated by the
    // standard auth middleware on each underlying API call.
    GoRoute(
      path: '/susu',
      name: AzRouteNames.susuHub,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const SusuHubScreen(),
      ),
    ),
    GoRoute(
      path: '/proof-of-residency',
      name: AzRouteNames.proofOfResidency,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const ProofOfResidencyScreen(),
      ),
    ),
    GoRoute(
      path: '/susu/invite/:token',
      name: AzRouteNames.susuInvite,
      builder: (context, state) =>
          InviteLandingScreen(token: state.pathParameters['token']!),
    ),
    GoRoute(
      path: '/susu/:id',
      name: AzRouteNames.susuDetail,
      builder: (context, state) =>
          SusuDashboardScreen(susuId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/susu/:id/contract',
      name: AzRouteNames.susuContract,
      builder: (context, state) =>
          LiabilityAcceptanceScreen(susuId: state.pathParameters['id']!),
    ),

    // ── V3 Premium Marketplace (2026-06-21) ─────────────────────────────────
    // NOTE: the existing `/marketplace` route is the P2P crypto market (FCM
    // `OPEN_AD` targets it), so the new *business* marketplace is mounted under
    // `/business-market` to avoid hijacking it. The `/business/:bizId`
    // catch-style route MUST stay last among the `/business/...` group so the
    // literal sub-routes (search / register / notifications / :bizId/products)
    // win over it.
    GoRoute(
      path: '/marketplace/booking/checkin-qr/:reservationId',
      name: AzRouteNames.checkinQr,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: CheckInQrScreen(
          reservationId: state.pathParameters['reservationId']!,
        ),
      ),
    ),
    GoRoute(
      path: '/marketplace/business/checkin',
      name: AzRouteNames.businessCheckin,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const BusinessCheckInScreen(),
      ),
    ),
    GoRoute(
      path: '/marketplace/transit',
      name: AzRouteNames.transitTrips,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const TransitTripListScreen(),
      ),
    ),
    GoRoute(
      path: '/business-market/:bizId/transit',
      name: AzRouteNames.businessTransitTrips,
      builder: (context, state) => TransitTripListScreen(
        businessProfileId: state.pathParameters['bizId'],
      ),
    ),
    GoRoute(
      path: '/marketplace/transit/:tripId/seats',
      name: AzRouteNames.transitSeatSelection,
      builder: (context, state) =>
          TransitSeatSelectionScreen(tripId: state.pathParameters['tripId']!),
    ),
    GoRoute(
      path: '/business-market',
      name: AzRouteNames.businessMarketHome,
      builder: (_, __) => const MarketplaceHomeScreen(),
    ),
    GoRoute(
      path: '/business-market/:bizId/hotel-booking',
      name: AzRouteNames.hotelBooking,
      builder: (context, state) =>
          HotelBookingScreen(bizId: state.pathParameters['bizId']!),
    ),
    GoRoute(
      path: '/business-market/dine-in/:tabId',
      name: AzRouteNames.dineInTab,
      builder: (context, state) =>
          DineInTabScreen(tabId: state.pathParameters['tabId']!),
    ),
    GoRoute(
      path: '/business-market/:bizId/stories',
      name: AzRouteNames.businessStories,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return BusinessStoriesScreen(
          bizId: state.pathParameters['bizId']!,
          businessName: extra['businessName'] as String? ?? 'Business Story',
          logoUrl: extra['logoUrl'] as String?,
          storyUrls: extra['storyUrls'] is List
              ? (extra['storyUrls'] as List).map((e) => e.toString()).toList()
              : ['https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800'],
        );
      },
    ),

    GoRoute(
      path: '/business-market/orders',
      name: AzRouteNames.businessMarketOrders,
      builder: (_, __) => const MyOrdersScreen(),
    ),
    GoRoute(
      path: '/business-market/invoices',
      name: AzRouteNames.businessMarketInvoices,
      builder: (_, __) => const MyInvoicesScreen(),
    ),
    GoRoute(
      path: '/business-market/invoices/:invoiceId',
      name: AzRouteNames.invoiceDetail,
      builder: (_, state) =>
          InvoiceDetailScreen(invoiceId: state.pathParameters['invoiceId']!),
    ),
    GoRoute(
      path: '/business-market/dashboard',
      name: AzRouteNames.businessMarketDashboard,
      builder: (_, __) => const BusinessDashboardScreen(),
    ),
    GoRoute(
      path: '/business/search',
      name: AzRouteNames.businessSearch,
      builder: (_, __) => const BusinessSearchScreen(),
    ),
    // Saved businesses wishlist (Marketplace Premium Upgrade, 2026-06-21).
    // Mounted under /biz/ (not /business/) so it never collides with the
    // `/business/:bizId` catch route below.
    GoRoute(
      path: '/biz/saved',
      name: AzRouteNames.savedBusinesses,
      builder: (_, __) => const SavedBusinessesScreen(),
    ),
    GoRoute(
      path: '/business/register',
      name: AzRouteNames.businessRegister,
      builder: (_, __) => const BusinessRegisterScreen(),
    ),
    GoRoute(
      path: '/business/notifications',
      name: AzRouteNames.businessNotifications,
      builder: (_, __) => const BusinessNotificationsScreen(),
    ),
    GoRoute(
      path: '/business/:bizId/products',
      name: AzRouteNames.businessProducts,
      builder: (_, state) => BusinessProductsScreen(
        bizId: state.pathParameters['bizId']!,
        businessName: state.uri.queryParameters['name'],
      ),
    ),
    GoRoute(
      path: '/business/:bizId',
      name: AzRouteNames.businessProfile,
      builder: (_, state) =>
          BusinessProfileScreen(bizId: state.pathParameters['bizId']!),
    ),

    // ── Worker Sub-Portal (Business OS, 2026-07-06) ────────────────────────
    GoRoute(
      path: '/worker',
      name: AzRouteNames.workerHub,
      builder: (_, __) => const WorkerHubScreen(),
    ),
    GoRoute(
      path: '/worker/shifts',
      name: AzRouteNames.workerShifts,
      builder: (_, __) => const WorkerShiftsScreen(),
    ),
    GoRoute(
      path: '/worker/payroll',
      name: AzRouteNames.workerPayroll,
      builder: (_, __) => const WorkerPayrollScreen(),
    ),
    GoRoute(
      path: '/worker/team',
      name: AzRouteNames.workerTeam,
      builder: (_, __) => const WorkerTeamScreen(),
    ),
    GoRoute(
      path: '/worker/time-off',
      name: AzRouteNames.workerTimeOff,
      builder: (_, __) => const WorkerTimeOffScreen(),
    ),
    GoRoute(
      path: '/worker/feedback',
      name: AzRouteNames.workerFeedback,
      builder: (_, __) => const WorkerFeedbackScreen(),
    ),
    GoRoute(
      path: '/worker/ewa',
      name: AzRouteNames.workerEwa,
      builder: (_, __) => const WorkerEwaScreen(),
    ),
    GoRoute(
      path: '/worker/swaps',
      name: AzRouteNames.workerSwaps,
      builder: (_, __) => const WorkerSwapsScreen(),
    ),
    GoRoute(
      path: '/storefront/staking',
      name: AzRouteNames.storefrontStaking,
      builder: (_, __) => const StorefrontStakingScreen(),
    ),
    GoRoute(
      path: '/storefront/:businessProfileId',
      name: AzRouteNames.storefront,
      builder: (context, state) => StorefrontScreen(
        businessProfileId: state.pathParameters['businessProfileId']!,
        businessName: state.uri.queryParameters['name'],
      ),
    ),
    GoRoute(
      path: '/discover/storefronts',
      name: AzRouteNames.storefrontDiscovery,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const StorefrontDiscoveryScreen(),
      ),
    ),
    GoRoute(
      path: '/my-orders',
      name: AzRouteNames.storefrontOrderHistory,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const StorefrontOrderHistoryScreen(),
      ),
    ),
    GoRoute(
      path: '/search',
      name: AzRouteNames.universalSearch,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const UniversalSearchScreen(),
      ),
    ),
    GoRoute(
      path: '/spending-insights',
      name: AzRouteNames.spendingInsights,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const SpendingInsightsScreen(),
      ),
    ),
    GoRoute(
      path: '/round-up',
      name: AzRouteNames.roundUpSavings,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const RoundUpSettingsScreen(),
      ),
    ),
    GoRoute(
      path: '/story-highlights',
      name: AzRouteNames.storyHighlights,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const StoryHighlightsScreen(),
      ),
    ),
    GoRoute(
      path: '/close-friends',
      name: AzRouteNames.closeFriends,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const CloseFriendsScreen(),
      ),
    ),
    GoRoute(
      path: '/story-camera',
      name: AzRouteNames.storyCamera,
      builder: (context, state) => StoryCameraScreen(
        onCaptured: (mediaFile, isVideo, filter) {
          context.pushNamed(
            'story-editor',
            extra: {
              'mediaFile': mediaFile,
              'isVideo': isVideo,
              'filter': filter,
            },
          );
        },
      ),
    ),
    GoRoute(
      path: '/story-editor',
      name: AzRouteNames.storyEditor,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return StoryEditorScreen(
          mediaFile: extra['mediaFile'] as File,
          isVideo: extra['isVideo'] as bool? ?? false,
          initialFilter: extra['filter'] as StoryFilter? ?? StoryFilter.none,
          onPublish: (mediaFile, isVideo) {
            context.pop();
          },
        );
      },
    ),
    GoRoute(
      path: '/story-analytics/:businessId',
      name: AzRouteNames.storyAnalytics,
      builder: (context, state) => StoryAnalyticsScreen(
        businessId: state.pathParameters['businessId']!,
        businessName: state.uri.queryParameters['name'] ?? 'Business',
      ),
    ),
    GoRoute(
      path: '/loyalty-cards',
      name: AzRouteNames.loyaltyCards,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const LoyaltyCardsScreen(),
      ),
    ),
    GoRoute(
      path: '/notification-preferences',
      name: AzRouteNames.notificationPreferences,
      pageBuilder: (context, state) => risePage(
        key: state.pageKey,
        restorationId: state.name,
        child: const NotificationPreferencesScreen(),
      ),
    ),
    GoRoute(
      path: '/susu/position-picker',
      name: AzRouteNames.susuPositionPicker,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return SusuPositionPicker(
          totalPositions: extra['totalPositions'] as int? ?? 10,
          selectedPosition: extra['selectedPosition'] as int?,
          members: (extra['members'] as List? ?? [])
              .cast<Map<String, dynamic>>(),
          onPositionSelected:
              extra['onPositionSelected'] as ValueChanged<int>? ?? (_) {},
        );
      },
    ),
    GoRoute(
      path: '/susu/completion',
      name: AzRouteNames.susuCompletion,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return SusuCompletionScreen(
          groupName: extra['groupName'] as String? ?? 'Susu Group',
          totalContributed: extra['totalContributed'] as double? ?? 0,
          totalPayout: extra['totalPayout'] as double? ?? 0,
          members: (extra['members'] as List? ?? [])
              .cast<Map<String, dynamic>>(),
          currency: extra['currency'] as String? ?? 'GHS',
        );
      },
    ),
    GoRoute(
      path: '/chat/:conversationId/search',
      name: AzRouteNames.messageSearch,
      builder: (context, state) => MessageSearchScreen(
        conversationId: state.pathParameters['conversationId']!,
        // Warm pushes carry the scoping context ('direct' | 'group') via
        // extra; deep links land with the screen's 'all' default.
        conversationContext:
            (state.extra as Map<String, dynamic>?)?['conversationContext']
                as String?,
      ),
    ),
    GoRoute(
      path: '/wallet-pass/:passType/:itemId',
      name: AzRouteNames.walletPass,
      builder: (context, state) => WalletPassScreen(
        passType: state.pathParameters['passType']!,
        itemId: state.pathParameters['itemId']!,
        title: state.uri.queryParameters['title'] ?? '',
        subtitle: state.uri.queryParameters['subtitle'] ?? '',
      ),
    ),
    GoRoute(
      path: '/orders/:orderId/tracking',
      name: AzRouteNames.orderTracking,
      builder: (context, state) => OrderTrackingScreen(
        orderId: state.pathParameters['orderId']!,
        // The notification warm path always had the human order ref; keep
        // the same default (ref == id) when a deep link omits it.
        orderRef:
            state.uri.queryParameters['orderRef'] ??
            state.pathParameters['orderId']!,
      ),
    ),
    GoRoute(
      path: '/vault/:vaultId/yield',
      name: AzRouteNames.vaultYield,
      builder: (context, state) =>
          VaultYieldScreen(vaultId: state.pathParameters['vaultId']!),
    ),
    GoRoute(
      path: '/story-create',
      name: AzRouteNames.storyCreation,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return StoryCreationScreen(
          mediaFile: extra['mediaFile'] as File,
          isVideo: extra['isVideo'] as bool? ?? false,
        );
      },
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
        title: Text(
          'Dispute #$disputeId',
          style: TextStyle(color: colors.textPrimary, fontSize: 16),
        ),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gavel, size: 64, color: colors.danger),
              const SizedBox(height: 16),
              Text(
                'Dispute #$disputeId',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This dispute is being reviewed.',
                style: TextStyle(color: colors.textSecondary, fontSize: 14),
              ),
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
  // NEW-A (Step 3, category 4): notification navigation now resolves every
  // action through the GoRouter table (AzRoutes) and pushes the route —
  // warm and cold paths share one destination source. Pushing (not going)
  // preserves the original contract: back returns the user to wherever
  // they were, and the router's auth redirect stays authoritative.
  switch (action) {
    case 'OPEN_TRADE':
    case 'PING_TOPUP':
      {
        final tradeId = actionPayload?['tradeId']?.toString();
        if (tradeId != null) {
          appRouter.push(AzRoutes.trade(tradeId));
        }
        break;
      }
    case 'OPEN_DISPUTE':
      {
        final disputeId = actionPayload?['disputeId']?.toString();
        if (disputeId != null) {
          appRouter.push(AzRoutes.dispute(disputeId));
        }
        break;
      }
    case 'OPEN_FRIEND_REQUEST':
    case 'OPEN_FRIEND_CHAT':
      appRouter.push(AzRoutes.friends);
      break;
    case 'VIEW_SAVINGS':
      appRouter.push(AzRoutes.savings);
      break;
    case 'OPEN_AD':
      appRouter.push(AzRoutes.marketplace);
      break;
    // Phase 4 (Susu Sprint, 2026-05-31) — susu deep-link actions.
    case 'OPEN_SUSU':
      {
        final susuId = actionPayload?['susuId']?.toString();
        appRouter.push(
          susuId == null ? AzRoutes.susuHub : AzRoutes.susuDetail(susuId),
        );
        break;
      }
    case 'OPEN_SUSU_INVITE':
      {
        // The BE may emit either a SusuInvite id (FRIEND/PHONE channels)
        // or a token (LINK channel). We prefer the token — the public-route
        // redemption flow.
        final token = actionPayload?['token']?.toString();
        final susuId = actionPayload?['susuId']?.toString();
        if (token != null && token.isNotEmpty) {
          appRouter.push(AzRoutes.susuInvite(token));
        } else if (susuId != null) {
          appRouter.push(AzRoutes.susuDetail(susuId));
        } else {
          appRouter.push(AzRoutes.susuHub);
        }
        break;
      }
    case 'OPEN_DEPOSIT_FOR_SUSU':
      {
        final amount = actionPayload?['amount']?.toString();
        final susuId = actionPayload?['susuId']?.toString();
        appRouter.push(
          AzRoutes.deposit(
            amount: amount,
            memo: susuId == null ? null : 'susu:$susuId',
          ),
        );
        break;
      }
    case 'OPEN_CHAT':
      {
        final conversationId =
            actionPayload?['conversationId']?.toString() ??
            actionPayload?['roomId']?.toString();
        if (conversationId != null) {
          // RETAINED (documented in the NEW-A migration inventory): chat has
          // no canonical route yet — FriendChatScreen needs friendship state
          // (friendUsername/friendId) that has no URL representation. The
          // push stays on the router-owned root navigator; the fallback path
          // below keeps the old cold-start behaviour (hub, not nothing).
          final navigator = rootNavigatorKey.currentState;
          if (navigator != null) {
            navigator.push(
              MaterialPageRoute(
                builder: (_) => FriendChatScreen(
                  friendshipId: conversationId,
                  friendUsername:
                      actionPayload?['friendName']?.toString() ?? 'Friend',
                  friendId:
                      int.tryParse(
                        actionPayload?['friendId']?.toString() ?? '',
                      ) ??
                      0,
                ),
              ),
            );
          } else {
            appRouter.push(AzRoutes.messages);
          }
        } else {
          appRouter.push(AzRoutes.messages);
        }
        break;
      }
    case 'OPEN_ORDER':
      {
        final orderId = actionPayload?['orderId']?.toString();
        if (orderId != null) {
          appRouter.push(
            AzRoutes.orderTracking(
              orderId,
              orderRef: actionPayload?['orderRef']?.toString() ?? orderId,
            ),
          );
        }
        break;
      }
    case 'OPEN_PROOF_OF_RESIDENCY':
      appRouter.push(AzRoutes.proofOfResidency);
      break;
    default:
      // Unknown action — no-op so a future BE-only rollout doesn't crash
      // older clients in the wild.
      break;
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

// ── Phase 1.2: Crash-safe route error screen ──────────────────────────────
class _AzamanRouteErrorScreen extends ConsumerWidget {
  final Object? error;
  const _AzamanRouteErrorScreen({this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Page not found'),
        backgroundColor: colors.surface,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.explore_off, size: 56, color: colors.textTertiary),
              const SizedBox(height: 16),
              Text(
                'This page could not be loaded.',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (error != null)
                Text(
                  '$error',
                  style: TextStyle(color: colors.textTertiary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
