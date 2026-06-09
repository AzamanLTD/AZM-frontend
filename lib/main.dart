// =============================================================================
// AZAMAN V2 — APPLICATION BOOTSTRAP  (Phase 0b complete — Root Strip)
//
// V2 ground rules (AZAMAN_MASTER_SOUL.md §3):
//   * Riverpod is the sole state-management layer. `ProviderScope` is mounted
//     as the outermost composition root.
//   * The `provider` package and its `MultiProvider` block have been removed.
//     Every callsite now reads through `ref.watch(...)` / `ref.read(...)`
//     against the canonical Riverpod handles declared in
//     `lib/providers/*.dart` (and `lib/logic/vendor_provider.dart`).
//   * Theme is read via `ref.watch(themeProvider.select((t) => t.themeData))`
//     so the app shell does not repaint when an unrelated theme field flips.
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/push_notification_service.dart';

import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/screens/p2p/p2p_marketplace_screen.dart';
import 'package:azaman/screens/trades_tab_screen.dart';
import 'package:azaman/screens/savings_screen.dart';
import 'package:azaman/screens/profile_screen.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';
import 'package:azaman/widgets/settings_drawer.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';
import 'package:azaman/widgets/vendor_pull_tab.dart';
import 'package:azaman/router/app_router.dart';

import 'package:azaman/providers/auth_provider.dart' as auth_pkg;
import 'package:azaman/providers/settings_provider.dart' as settings_pkg;
import 'package:azaman/providers/trade_provider.dart' as trade_pkg;
import 'package:azaman/providers/theme_provider.dart' as theme_pkg;

import 'package:azaman/services/socket_service.dart';
import 'package:azaman/config.dart';
import 'package:azaman/screens/notification_hub_screen.dart';
import 'package:azaman/widgets/azaman_connectivity_banner.dart';
import 'package:azaman/widgets/themed_app_backdrop.dart';
import 'package:hugeicons_pro/hugeicons.dart';

// =============================================================================
// MODELS — preserved verbatim from previous main.dart
// =============================================================================

class P2POrder {
  final String id;
  final String coin;
  final double rate;
  final double totalAmount;
  final String paymentMethod;
  final DateTime timestamp;
  final String status;
  bool isProofUploaded;

  P2POrder({
    required this.id,
    required this.coin,
    required this.rate,
    required this.totalAmount,
    required this.paymentMethod,
    required this.timestamp,
    required this.status,
    this.isProofUploaded = false,
  });
}

ValueNotifier<List<P2POrder>> openTransactionsNotifier =
    ValueNotifier<List<P2POrder>>([]);
ValueNotifier<List<P2POrder>> completedTransactionsNotifier =
    ValueNotifier<List<P2POrder>>([]);

const storage = FlutterSecureStorage();

Future<void> syncTradeHistory() async {
  try {
    final response = await apiClient.get('/trades/history');

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      final List historyData = data['history'];

      completedTransactionsNotifier.value = historyData
          .where((item) =>
              item['status'] == 'COMPLETED' || item['status'] == 'CANCELLED')
          .map((item) => P2POrder(
                id: item['id'].toString(),
                coin: item['crypto'] ?? 'USDT',
                rate: 0.0,
                totalAmount: (item['amountCrypto'] as num).toDouble(),
                paymentMethod: item['paymentMethod'] ?? 'Bank Transfer',
                timestamp:
                    DateTime.parse(item['completedAt'] ?? item['createdAt']),
                status: item['status'] ?? 'COMPLETED',
              ))
          .toList();

      openTransactionsNotifier.value = historyData
          .where((item) =>
              item['status'] != 'COMPLETED' && item['status'] != 'CANCELLED')
          .map((item) => P2POrder(
                id: item['id'].toString(),
                coin: item['crypto'] ?? 'USDT',
                rate: 0.0,
                totalAmount: (item['amountCrypto'] as num).toDouble(),
                paymentMethod: item['paymentMethod'] ?? 'Bank Transfer',
                timestamp: DateTime.parse(item['createdAt']),
                status: item['status'] ?? 'PENDING',
              ))
          .toList();
    }
  } catch (e) {
    debugPrint('Error syncing trade history: $e');
  }
}

// =============================================================================
// ENTRY POINT
// =============================================================================

/// Top-level background message handler (must be a top-level function).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM] Background message: ${message.messageId}');
}

void main() async {
  // F-05: when a SENTRY_DSN is provided at build time, initialise Sentry and
  // run the app inside its zone so uncaught errors are captured. When it's
  // empty (dev/CI/default), skip Sentry entirely and boot exactly as before —
  // no behavioural change, no network calls.
  if (AppConfig.sentryEnabled) {
    await SentryFlutter.init(
      (options) {
        options.dsn = AppConfig.sentryDsn;
        options.release = AppConfig.appVersion;
        options.environment = AppConfig.environment;
        // 20% transaction sampling in prod; full sampling elsewhere.
        options.tracesSampleRate = AppConfig.isProduction ? 0.2 : 1.0;
        // Don't ship PII (tokens, balances) to Sentry by default.
        options.sendDefaultPii = false;
      },
      appRunner: _bootstrap,
    );
  } else {
    await _bootstrap();
  }
}

/// All app initialisation, factored out so it can run with or without the
/// Sentry zone wrapper above.
Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase before anything else
  // await Firebase.initializeApp();

  // Register background message handler
  // FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize push notification service (permissions, foreground handling)
  // await PushNotificationService.instance.init();

  // Phase Q22 (2026-05-31): wire the FCM notification-tap callback so
  // cold-start (`getInitialMessage`) and warm-from-bg (`onMessageOpenedApp`)
  // both deep-link via the canonical `handleNotificationTap` resolver.
  // Defer with a 1.5s delay on cold start so the SplashScreen has time
  // to settle MainWrapper underneath the deep-link target — otherwise
  // the destination ends up on top of an unsettled navigator and back
  // pops to a blank screen.
  /*
  PushNotificationService.instance.onNotificationTap = (data) {
    final action = data['action']?.toString() ?? '';
    if (action.isEmpty) return;
    // Coerce the rest of the payload (everything except `action`).
    final actionPayload = <String, dynamic>{};
    data.forEach((k, v) {
      if (k != 'action') actionPayload[k] = v;
    });
    // Allow the navigator to settle. 1500ms covers the splash 2s delay
    // worst-case race; in practice the navigator is ready well before
    // then. handleNotificationTap itself uses Navigator.push on the
    // root navigator key, so it's a no-op until the key has a state.
    Future.delayed(const Duration(milliseconds: 1500), () {
      handleNotificationTap(action: action, actionPayload: actionPayload);
    });
  };
  */

  runApp(
    const ProviderScope(
      child: AzamanApp(),
    ),
  );
}

// =============================================================================
// ROOT APP
// =============================================================================
class AzamanApp extends ConsumerWidget {
  const AzamanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Granular: only repaint when ThemeData actually changes (not on
    // unrelated SettingsProvider/AuthProvider ticks).
    final themeData = ref.watch(theme_pkg.themeProvider.select((t) => t.themeData));
    // Phase H — pull the active palette so we can sync the status bar
    // and navigation-bar overlay style to the theme. Otherwise switching
    // to a Light theme leaves a white status bar with white icons (invisible).
    final colors = ref.watch(theme_pkg.themeProvider.select((t) => t.colors));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            colors.isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness:
            colors.isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: colors.surface,
        systemNavigationBarIconBrightness:
            colors.isDark ? Brightness.light : Brightness.dark,
      ),
      child: MaterialApp.router(
        title: 'Azaman P2P',
        debugShowCheckedModeBanner: false,
        theme: themeData,
        routerConfig: appRouter,
        // Phase H4 — wrap every routed screen in the connectivity banner so
        // a single overlay handles the offline / reconnected affordance for
        // the whole app (rather than every screen rolling its own).
        //
        // Master Sprint v2 (2026-05-27) — also wraps every screen in a
        // themed gradient backdrop so theme switches genuinely transform
        // the look of the app. Each theme paints its own glow halos +
        // accent wash behind the route. Scaffolds set
        // backgroundColor: Colors.transparent (or use ThemedScaffold) to
        // let the backdrop show through.
        builder: (context, child) {
          return ThemedAppBackdrop(
            child: AzamanConnectivityBanner(child: child ?? const SizedBox.shrink()),
          );
        },
      ),
    );
  }
}

// =============================================================================
// MAIN WRAPPER — 5-tab layout (Home | Chat | P2P | Savings | Profile)
//
// Phase H review pass: comment was stale ("4-tab Home | P2P | Trades |
// Profile" referenced the pre-Phase-0 layout). Bottom nav is rendered
// by `PremiumBottomNav` against `_kNavItems` defined further down.
// =============================================================================
class MainWrapper extends ConsumerStatefulWidget {
  const MainWrapper({super.key});
  @override
  ConsumerState<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends ConsumerState<MainWrapper> {
  int _selectedIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    _pages = [
      const AzamanHomePage(),
      const FriendsHubScreen(),
      const P2PMarketplaceScreen(),
      const SavingsScreen(),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initUnifiedSocket();
    });
  }

  @override
  void dispose() {
    // Phase P3: No per-screen socket.off() needed — SocketService owns
    // the callbacks via registered closures, disposed with the service.
    super.dispose();
  }

  // ── Phase P3: Single unified socket initialization ───────────────────────
  void _initUnifiedSocket() {
    final socketService = ref.read(socketServiceProvider);
    socketService.init(ref);

    final auth = ref.read(auth_pkg.authProvider);
    if (auth.user != null) {
      socketService.joinUserRoom(auth.user!.id.toString());
      // Sync the trade provider's role from the authenticated user's actual role
      ref.read(trade_pkg.tradeProvider).syncRoleFromAuth(auth.user!.role);
    }

    // Register UI-level event callbacks on the unified socket
    socketService.onTradeCompleted((data) => _showSuccessReceipt(data));

    socketService.onNewNotification((data) {
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ref.read(trade_pkg.tradeProvider).incrementNotificationCount();
      final colors = ref.read(theme_pkg.themeProvider).colors;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          data['title'] ?? 'New Message',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
        ),
        backgroundColor: colors.danger,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.only(top: 50, left: 20, right: 20),
        dismissDirection: DismissDirection.up,
      ));
    });

    socketService.onNewTradeRequest((data) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ref.read(trade_pkg.tradeProvider).incrementNotificationCount();
      final colors = ref.read(theme_pkg.themeProvider).colors;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '\u{1F514} New Trade: ${data['buyerName'] ?? 'Buyer'} wants to trade \$${data['amount'] ?? ''} USD',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
        ),
        backgroundColor: colors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.only(top: 50, left: 20, right: 20),
        dismissDirection: DismissDirection.up,
      ));
    });
  }

  void _showSuccessReceipt(dynamic data) {
    final colors = ref.read(theme_pkg.themeProvider).colors;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(HugeIconsSolid.checkmarkCircle01, color: colors.success, size: 80),
          const SizedBox(height: 16),
          Text('Order Completed',
              style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Purchased ${data['amount']} ${data['crypto']}',
              style: TextStyle(color: colors.textSecondary)),
          Divider(color: colors.divider, height: 32),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Done',
                style: TextStyle(color: colors.accent, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Granular theme read — only the chrome that depends on `colors` repaints
    // on a theme switch, and `role` is selected so a balance update doesn't
    // trigger a rebuild of the Scaffold.
    final colors = ref.watch(theme_pkg.themeProvider.select((t) => t.colors));
    // Phase UI Sprint: the role-pill in the AppBar (top-right of the
    // scaffold) is now permanently "HQ" globally, regardless of the user's
    // role. The vendor-vs-user cue lives exclusively on the P2P pull tab.
    // The local `role` watch was therefore removed; if you need the role
    // again, watch `tradeProvider.select((t) => t.currentRole)`.

    return Scaffold(
      backgroundColor: colors.background,
      endDrawer: const SettingsDrawer(),

      appBar: AppBar(
        centerTitle: false,
        automaticallyImplyLeading: false,
        backgroundColor: colors.background,
        title: Text(
          'AZAMAN',
          style: TextStyle(
            color: colors.accent,
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          // Phase UI-1 (2026-05-26): the AppBar chat icon was retired.
          // The bottom nav bar's "Chat" tab is the canonical entry point
          // into the Friends Hub and already carries its own unread badge,
          // so a second affordance up here was redundant chrome and split
          // user attention. Notification bell stays as the only AppBar
          // action besides the drawer pill.
          // Notification bell
          ValueListenableBuilder<List<P2POrder>>(
            valueListenable: openTransactionsNotifier,
            builder: (context, transactions, child) {
              return Consumer(
                builder: (ctx, ref, _) {
                  final notifCount = ref.watch(trade_pkg.tradeProvider
                      .select((t) => t.notificationCount));
                  final totalNotifs = transactions.length + notifCount;
                  return Stack(alignment: Alignment.center, children: [
                    IconButton(
                      icon: Icon(HugeIconsSolid.notification01,
                          size: 26, color: colors.textPrimary),
                      onPressed: () {
                        ref.read(trade_pkg.tradeProvider).clearNotifications();
                        Navigator.push(
                          ctx,
                          MaterialPageRoute(builder: (_) => const NotificationHubScreen()),
                        );
                      },
                    ),
                    if (totalNotifs > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: colors.danger,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.background, width: 2),
                          ),
                          child: Text(
                            '$totalNotifs',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ]);
                },
              );
            },
          ),
          Builder(
            builder: (context) => InkWell(
              onTap: () => Scaffold.of(context).openEndDrawer(),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                // The drawer pill is "HQ" globally on every tab. The role
                // tag (HQ-vs-PRO) was only ever meaningful as a vendor
                // indicator, and showing it everywhere added noise. The
                // BECOME-VENDOR / FOR-VENDOR cue is now exclusively the
                // pull-tab on the P2P tab.
                child: Text(
                  'HQ',
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),

      bottomNavigationBar: PremiumBottomNav(
        selectedIndex: _selectedIndex,
        onItemSelected: (i) => setState(() => _selectedIndex = i),
      ),

      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              _pages[0],
              _pages[1],
              _pages[2],
              _pages[3],
            ],
          ),
          // Vendor Pull Tab — only visible on the P2P tab AND only when
          // the user has explicitly opted in via Settings → "Show vendor
          // pull tab" (off by default). Casual buyers no longer have the
          // tab nudging them every time they open the marketplace.
          if (_selectedIndex == 2 &&
              ref.watch(settings_pkg.settingsProvider).vendorTagEnabled)
            const VendorPullTab(),
        ],
      ),
    );
  }
}

// Legacy alias kept for any existing go_router references.
class MainNavigationWrapper extends StatelessWidget {
  const MainNavigationWrapper({super.key});
  @override
  Widget build(BuildContext context) => const MainWrapper();
}
