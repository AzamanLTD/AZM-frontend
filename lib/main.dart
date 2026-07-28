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

import 'dart:isolate';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/widgets/settings_drawer.dart';
import 'package:azaman/widgets/drawer_peek_hint.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';
import 'package:azaman/widgets/vendor_pull_tab.dart';
import 'package:azaman/router/app_router.dart';

import 'package:azaman/providers/auth_provider.dart' as auth_pkg;
import 'package:azaman/providers/settings_provider.dart' as settings_pkg;
import 'package:azaman/providers/trade_provider.dart' as trade_pkg;
import 'package:azaman/providers/theme_provider.dart' as theme_pkg;
import 'package:azaman/providers/business_provider.dart';

import 'package:azaman/services/socket_service.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/config.dart';
import 'package:azaman/widgets/azaman_connectivity_banner.dart';
import 'package:azaman/widgets/themed_app_backdrop.dart';


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

  // ── 1. GLOBAL ERROR BOUNDARY ─────────────────────────────────────────────
  // Capture framework-level errors (build/layout failures) so they NEVER
  // produce a red screen that bounces the user to home. Instead we log and
  // show a recoverable error widget.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[AZM-FATAL] ${details.exception}');
    _lastFrameworkError.value = details.exception;
  };

  // ── 2. ISOLATE ERROR GUARD ───────────────────────────────────────────────
  // Errors thrown in separate isolates (image decoding, JSON parsing in
  // compute()) don't reach FlutterError.onError. This catches them.
  Isolate.current.addErrorListener(RawReceivePort((dynamic data) {
    final list = data as List;
    debugPrint('[AZM-ISOLATE] ${list[0]}: ${list[1]}');
  }).sendPort);

  // ── 3. ERROR WIDGET BUILDER (no red screen) ──────────────────────────────
  // Replace the default red error screen with a themed fallback that lets
  // the user retry instead of being bounced to home.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text('Something went wrong',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Pull down to refresh, or restart the app.',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  };

  // ── 5. IMMERSIVE EDGE-TO-EDGE ────────────────────────────────────────────
  // Remove the Android status-bar/nav-bar tint so content flows edge-to-edge.
  // Each Scaffold already sets transparent backgrounds via ThemedAppBackdrop.
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));

  // ── 4. ZONE GUARD for async errors outside Flutter ───────────────────────
  runZonedGuarded<Future<void>>(
    () async {
      if (!kIsWeb) {
        try {
          await Firebase.initializeApp();
          FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
        } catch (e) {
          debugPrint('[Bootstrap] Firebase init failed: $e');
        }
      }

      if (!kIsWeb) {
        await PushNotificationService.instance.init();
      }

      PushNotificationService.instance.onNotificationTap = (data) {
        final action = data['action']?.toString() ?? '';
        if (action.isEmpty) return;
        final actionPayload = <String, dynamic>{};
        data.forEach((k, v) {
          if (k != 'action') actionPayload[k] = v;
        });
        Future.delayed(const Duration(milliseconds: 1500), () {
          handleNotificationTap(action: action, actionPayload: actionPayload);
        });
      };

      runApp(const ProviderScope(child: AzamanApp()));
    },
    (Object error, StackTrace stack) {
      debugPrint('[AZM-ZONE] Uncaught async error: $error\n$stack');
    },
  );
}

/// ValueNotifier holding the last framework error, for optional display.
final ValueNotifier<Object?> _lastFrameworkError = ValueNotifier<Object?>(null);

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

class _MainWrapperState extends ConsumerState<MainWrapper>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final List<Widget> _pages;

  // 2026-07-08: fade-through transition between Home/Chat/P2P (Material
  // "fade through" pattern — the animations package's canonical use case
  // for bottom-nav tab switches). Deliberately hand-rolled instead of
  // wrapping IndexedStack in a PageTransitionSwitcher: that would swap the
  // whole widget subtree on every tab change, which fully unmounts/remounts
  // each page (losing scroll position, in-flight requests, etc). Instead
  // the IndexedStack itself never changes identity — only its `index` and
  // an Opacity wrapper animate — so all 3 tabs stay alive exactly as
  // before, and the visual timing still matches the spec (fade the old tab
  // out over the first ~25% of 300ms, then fade+the new tab in over the
  // rest).
  late final AnimationController _fadeCtrl;
  int _displayedIndex = 0;

  @override
  void initState() {
    super.initState();

    _pages = [
      const AzamanHomePage(),
      const FriendsHubScreen(),
      const P2PMarketplaceScreen(),
    ];

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..value = 1.0;
    _fadeCtrl.addListener(() {
      if (_fadeCtrl.value >= 0.25 && _displayedIndex != _selectedIndex) {
        setState(() => _displayedIndex = _selectedIndex);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initUnifiedSocket();
    });
  }

  void _onNavItemSelected(int i) {
    if (i == _selectedIndex) return;
    setState(() => _selectedIndex = i);
    _fadeCtrl.forward(from: 0);
  }

  double get _tabFadeOpacity {
    final v = _fadeCtrl.value;
    if (v < 0.25) return (1 - (v / 0.25)).clamp(0.0, 1.0);
    return ((v - 0.25) / 0.75).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    // Phase P3: No per-screen socket.off() needed — SocketService owns
    // the callbacks via registered closures, disposed with the service.
    _fadeCtrl.dispose();
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

    // ── V3 Marketplace Sprint (2026-06-21): business owner real-time wiring ──
    // A new business notification bumps the badge; an authoritative
    // unread-count push (multi-device sync) replaces it outright.
    socketService.onBizNotification((data) {
      if (!mounted) return;
      ref.read(bizUnreadCountProvider.notifier).state++;
    });
    socketService.onBizNotificationsUpdated((count) {
      if (!mounted) return;
      ref.read(bizUnreadCountProvider.notifier).state = count;
    });

    // Load the signed-in user's own business (if any) so the home-screen
    // notification bell + dashboard entry know whether to show, then seed the
    // unread badge from the REST count.
    ref.read(myBusinessProvider.notifier).load().then((_) async {
      if (!mounted) return;
      final biz = ref.read(myBusinessProvider).profile;
      if (biz != null) {
        try {
          final count = await BusinessService().getUnreadCount();
          if (!mounted) return;
          ref.read(bizUnreadCountProvider.notifier).state = count;
        } catch (_) {}
      }
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
          Icon(Icons.check_circle_outline, color: colors.success, size: 80),
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
      key: _scaffoldKey,
      backgroundColor: colors.surface,
      endDrawer: const SettingsDrawer(),
      extendBody: true,


      bottomNavigationBar: PremiumBottomNav(
        selectedIndex: _selectedIndex,
        onItemSelected: _onNavItemSelected,
      ),

      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _fadeCtrl,
            builder: (context, child) => Opacity(
              opacity: _tabFadeOpacity,
              child: child,
            ),
            child: IndexedStack(
              index: _displayedIndex,
              children: [
                _pages[0],
                _pages[1],
                _pages[2],
              ],
            ),
          ),
          // Vendor Pull Tab — only visible on the P2P tab AND only when
          // the user has explicitly opted in via Settings → "Show vendor
          // pull tab" (off by default). Casual buyers no longer have the
          // tab nudging them every time they open the marketplace.
          if (_displayedIndex == 2 &&
              ref.watch(settings_pkg.settingsProvider).vendorTagEnabled)
            const VendorPullTab(),

          // First-load hint: nudges the user that the settings drawer
          // exists (previously only reachable via an undiscoverable
          // edge-swipe gesture). Shows once, ever.
          DrawerPeekHint(
            onOpenDrawer: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
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
