// =============================================================================
// AZAMAN V2 — APPLICATION BOOTSTRAP
//
// The consumer application is a native Android/iOS client. Riverpod is the
// sole state-management layer and ProviderScope is the composition root.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/push_notification_service.dart';

import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/screens/p2p/p2p_marketplace_screen.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';
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
import 'package:azaman/services/webrtc_service.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/startup_coordinator.dart';
import 'package:azaman/config.dart';
import 'package:azaman/widgets/azaman_connectivity_banner.dart';
import 'package:azaman/widgets/themed_app_backdrop.dart';
import 'package:azaman/widgets/in_app_push_banner.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/theme/motion_tokens.dart';

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

ValueNotifier<List<P2POrder>> openTransactionsNotifier = ValueNotifier<List<P2POrder>>([]);
ValueNotifier<List<P2POrder>> completedTransactionsNotifier = ValueNotifier<List<P2POrder>>([]);

const storage = FlutterSecureStorage();

Future<void> syncTradeHistory() async {
  try {
    final response = await apiClient.get('/trades/history');
    if (response.statusCode != 200) return;

    final Map<String, dynamic> data = json.decode(response.body);
    final List historyData = data['history'];

    completedTransactionsNotifier.value = historyData
        .where((item) => item['status'] == 'COMPLETED' || item['status'] == 'CANCELLED')
        .map((item) => P2POrder(
              id: item['id'].toString(),
              coin: item['crypto'] ?? 'USDT',
              rate: 0.0,
              totalAmount: (item['amountCrypto'] as num).toDouble(),
              paymentMethod: item['paymentMethod'] ?? 'Bank Transfer',
              timestamp: DateTime.parse(item['completedAt'] ?? item['createdAt']),
              status: item['status'] ?? 'COMPLETED',
            ))
        .toList();

    openTransactionsNotifier.value = historyData
        .where((item) => item['status'] != 'COMPLETED' && item['status'] != 'CANCELLED')
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
  } catch (e) {
    debugPrint('Error syncing trade history: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StartupCoordinator.registerBackgroundMessageHandler();

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

Future<void> _bootstrap() async {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[AZM-FATAL] ${details.exception}');
    _lastFrameworkError.value = details.exception;
  };

  Isolate.current.addErrorListener(RawReceivePort((dynamic data) {
    final list = data as List;
    debugPrint('[AZM-ISOLATE] ${list[0]}: ${list[1]}');
  }).sendPort);

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return const Material(
      color: Color(0xFF1A1A2E),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              SizedBox(height: 16),
              Text('Something went wrong', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Pull down to refresh, or restart the app.', style: TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  };

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));

  runZonedGuarded<Future<void>>(
    () async {
      runApp(const ProviderScope(child: AzamanApp()));
    },
    (Object error, StackTrace stack) {
      debugPrint('[AZM-ZONE] Uncaught async error: $error\n$stack');
    },
  );
}

final ValueNotifier<Object?> _lastFrameworkError = ValueNotifier<Object?>(null);

class AzamanApp extends ConsumerWidget {
  const AzamanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = ref.watch(theme_pkg.themeProvider.select((t) => t.themeData));
    final colors = ref.watch(theme_pkg.themeProvider.select((t) => t.colors));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: colors.isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: colors.isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: colors.surface,
        systemNavigationBarIconBrightness: colors.isDark ? Brightness.light : Brightness.dark,
      ),
      child: MaterialApp.router(
        title: 'Azaman P2P',
        debugShowCheckedModeBanner: false,
        theme: themeData,
        routerConfig: appRouter,
        builder: (context, child) => ThemedAppBackdrop(
          child: AzamanConnectivityBanner(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}

class MainWrapper extends ConsumerStatefulWidget {
  const MainWrapper({super.key});
  @override
  ConsumerState<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends ConsumerState<MainWrapper> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final List<Widget?> _pages;
  late final AnimationController _fadeCtrl;
  int _displayedIndex = 0;

  @override
  void initState() {
    super.initState();
    _pages = [
      const AzamanHomePage(),
      null,
      null,
      null,
    ];

    _fadeCtrl = AnimationController(vsync: this, duration: MotionTokens.standard)..value = 1.0;
    _fadeCtrl.addListener(() {
      if (_fadeCtrl.value >= 0.25 && _displayedIndex != _selectedIndex) {
        setState(() => _displayedIndex = _selectedIndex);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initUnifiedSocket();
      _initPostFrameStartup();
    });
  }

  Widget _pageFor(int index) {
    switch (index) {
      case 1:
        return const FriendsHubScreen();
      case 2:
        return const P2PMarketplaceScreen();
      case 3:
        return const MarketplaceHomeScreen();
      default:
        return const AzamanHomePage();
    }
  }

  void _onNavItemSelected(int i) {
    if (i == _selectedIndex) return;
    final page = _pages[i] ?? _pageFor(i);
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    setState(() {
      _pages[i] = page;
      _selectedIndex = i;
      if (disableAnimations) {
        _displayedIndex = i;
      }
    });

    if (!disableAnimations) {
      _fadeCtrl.forward(from: 0);
    }
  }

  double get _tabFadeOpacity {
    final v = _fadeCtrl.value;
    if (v < 0.25) return (1 - (v / 0.25)).clamp(0.0, 1.0);
    return ((v - 0.25) / 0.75).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _initPostFrameStartup() {
    StartupCoordinator.instance.start(
      onNotificationTap: (data) {
        final action = data['action']?.toString() ?? '';
        if (action.isEmpty) return;
        final actionPayload = <String, dynamic>{};
        data.forEach((k, v) {
          if (k != 'action') actionPayload[k] = v;
        });
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          handleNotificationTap(action: action, actionPayload: actionPayload);
        });
      },
      onForegroundMessage: (message) {
        final notification = message.notification;
        if (notification == null || !mounted) return;
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null) return;
        InAppPushBanner.show(
          ctx,
          title: notification.title ?? '',
          body: notification.body ?? '',
          onTap: () {
            final data = <String, dynamic>{};
            message.data.forEach((k, v) => data[k] = v);
            final action = data['action']?.toString() ?? '';
            if (action.isNotEmpty) {
              final payload = <String, dynamic>{};
              data.forEach((k, v) {
                if (k != 'action') payload[k] = v;
              });
              handleNotificationTap(action: action, actionPayload: payload);
            }
          },
        );
      },
    );

    StartupCoordinator.instance.hydrateBusinessState(
      loadBusiness: () => ref.read(myBusinessProvider.notifier).load(),
      loadUnreadCount: () async {
        final biz = ref.read(myBusinessProvider).profile;
        if (biz == null || !mounted) return;
        try {
          final count = await BusinessService().getUnreadCount();
          if (mounted) {
            ref.read(bizUnreadCountProvider.notifier).state = count;
          }
        } catch (e) {
          debugPrint('[Startup] business unread count failed: $e');
        }
      },
      isMounted: () => mounted,
    );
  }

  void _initUnifiedSocket() {
    final socketService = ref.read(socketServiceProvider);
    socketService.init(ref);
    final webrtcService = ref.read(webrtcServiceProvider);
    webrtcService.initialize();
    webrtcService.setSocket(socketService);

    final auth = ref.read(auth_pkg.authProvider);
    if (auth.user != null) {
      socketService.joinUserRoom(auth.user!.id.toString());
      ref.read(trade_pkg.tradeProvider).syncRoleFromAuth(auth.user!.role);
    }

    socketService.onNewNotification((data) {
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ref.read(trade_pkg.tradeProvider).incrementNotificationCount();
      final colors = ref.read(theme_pkg.themeProvider).colors;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(data['title'] ?? 'New Message', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
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
        content: Text('\u{1F514} New Trade: ${data['buyerName'] ?? 'Buyer'} wants to trade \$${data['amount'] ?? ''} USD', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
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
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(theme_pkg.themeProvider.select((t) => t.colors));
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: colors.surface,
      endDrawer: const SettingsDrawer(),
      extendBody: true,
      bottomNavigationBar: PremiumBottomNav(selectedIndex: _selectedIndex, onItemSelected: _onNavItemSelected),
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _fadeCtrl,
            builder: (context, child) => Opacity(opacity: _tabFadeOpacity, child: child),
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (var index = 0; index < _pages.length; index++)
                  if (_pages[index] != null)
                    Offstage(
                      offstage: index != _displayedIndex,
                      child: _pages[index],
                    ),
              ],
            ),
          ),
          if (_displayedIndex == 2 && ref.watch(settings_pkg.settingsProvider).vendorTagEnabled) const VendorPullTab(),
          DrawerPeekHint(onOpenDrawer: () => _scaffoldKey.currentState?.openEndDrawer()),
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
