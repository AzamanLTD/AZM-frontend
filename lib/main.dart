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
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/widgets/settings_drawer.dart';
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
  if (AppConfig.sentryEnabled) {
    await SentryFlutter.init(
      (options) {
        options.dsn = AppConfig.sentryDsn;
        options.release = AppConfig.appVersion;
        options.environment = AppConfig.environment;
        options.tracesSampleRate = AppConfig.isProduction ? 0.2 : 1.0;
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
    final themeData = ref.watch(theme_pkg.themeProvider.select((t) => t.themeData));
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
      const SafeArea(bottom: false, child: SavingsScreen()),
      const MarketplaceHomeScreen(),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initUnifiedSocket();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _initUnifiedSocket() {
    final socketService = ref.read(socketServiceProvider);
    socketService.init(ref);

    final auth = ref.read(auth_pkg.authProvider);
    if (auth.user != null) {
      socketService.joinUserRoom(auth.user!.id.toString());
      ref.read(trade_pkg.tradeProvider).syncRoleFromAuth(auth.user!.role);
    }

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

    socketService.onBizNotification((data) {
      if (!mounted) return;
      ref.read(bizUnreadCountProvider.notifier).state++;
    });
    socketService.onBizNotificationsUpdated((count) {
      if (!mounted) return;
      ref.read(bizUnreadCountProvider.notifier).state = count;
    });

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
    final colors = ref.read(theme_pkg.themeProvider.select((t) => t.colors));
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
    final colors = ref.watch(theme_pkg.themeProvider.select((t) => t.colors));

    return Scaffold(
      backgroundColor: colors.surface,
      endDrawer: const SettingsDrawer(),
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
              _pages[4],
            ],
          ),
          if (_selectedIndex == 2 &&
              ref.watch(settings_pkg.settingsProvider).vendorTagEnabled)
            const VendorPullTab(),
        ],
      ),
    );
  }
}

class MainNavigationWrapper extends StatelessWidget {
  const MainNavigationWrapper({super.key});
  @override
  Widget build(BuildContext context) => const MainWrapper();
}
