// =============================================================================
// AZAMAN V2 — APPLICATION BOOTSTRAP
//
// The consumer application is a native Android/iOS client. Riverpod is the
// sole state-management layer and ProviderScope is the composition root.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:azaman/services/api_client.dart';

import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/screens/withdrawal_screen.dart';
import 'package:azaman/screens/send_money_screen.dart';
import 'package:azaman/widgets/home/plus_action_launcher.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/router/route_registry.dart';
import 'package:azaman/widgets/nav_transitions.dart'
    as nav_transitions_pkg;
import 'package:azaman/screens/friends/friends_hub_screen.dart';
import 'package:azaman/widgets/settings_drawer.dart';
import 'package:azaman/widgets/drawer_peek_hint.dart';
import 'package:azaman/widgets/liquid/liquid_launcher.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';
import 'package:azaman/widgets/contextual_nav_band.dart';
import 'package:azaman/router/app_router.dart';
import 'package:azaman/router/route_depth.dart';

import 'package:azaman/providers/auth_provider.dart' as auth_pkg;
import 'package:azaman/providers/trade_provider.dart' as trade_pkg;
import 'package:azaman/providers/theme_provider.dart' as theme_pkg;
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/sensory_provider.dart';
import 'package:azaman/providers/home_shell_active_provider.dart';
import 'package:azaman/providers/settings_provider.dart' as settings_pkg;
import 'package:azaman/widgets/vendor_pull_tab.dart';
import 'package:azaman/services/az_sound.dart';

import 'package:azaman/services/socket_service.dart';
import 'package:azaman/services/webrtc_service.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/startup_coordinator.dart';
import 'package:azaman/config.dart';
import 'package:azaman/widgets/azaman_sheet.dart';
import 'package:azaman/widgets/azaman_connectivity_banner.dart';
import 'package:azaman/widgets/az_error_surface.dart';
import 'package:azaman/widgets/themed_app_backdrop.dart';
import 'package:azaman/widgets/in_app_push_banner.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_vertical_accent.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/theme/az_motion.dart';

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
    if (response.statusCode != 200) return;

    final Map<String, dynamic> data = json.decode(response.body);
    final List historyData = data['history'];

    completedTransactionsNotifier.value = historyData
        .where(
          (item) =>
              item['status'] == 'COMPLETED' || item['status'] == 'CANCELLED',
        )
        .map(
          (item) => P2POrder(
            id: item['id'].toString(),
            coin: item['crypto'] ?? 'USDT',
            rate: 0.0,
            totalAmount: (item['amountCrypto'] as num).toDouble(),
            paymentMethod: item['paymentMethod'] ?? 'Bank Transfer',
            timestamp: DateTime.parse(item['completedAt'] ?? item['createdAt']),
            status: item['status'] ?? 'COMPLETED',
          ),
        )
        .toList();

    openTransactionsNotifier.value = historyData
        .where(
          (item) =>
              item['status'] != 'COMPLETED' && item['status'] != 'CANCELLED',
        )
        .map(
          (item) => P2POrder(
            id: item['id'].toString(),
            coin: item['crypto'] ?? 'USDT',
            rate: 0.0,
            totalAmount: (item['amountCrypto'] as num).toDouble(),
            paymentMethod: item['paymentMethod'] ?? 'Bank Transfer',
            timestamp: DateTime.parse(item['createdAt']),
            status: item['status'] ?? 'PENDING',
          ),
        )
        .toList();
  } catch (e) {
    debugPrint('Error syncing trade history: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StartupCoordinator.registerBackgroundMessageHandler();

  if (AppConfig.sentryEnabled) {
    await SentryFlutter.init((options) {
      options.dsn = AppConfig.sentryDsn;
      options.release = AppConfig.appVersion;
      options.environment = AppConfig.environment;
      options.tracesSampleRate = AppConfig.isProduction ? 0.2 : 1.0;
      options.sendDefaultPii = false;
    }, appRunner: _bootstrap);
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

  Isolate.current.addErrorListener(
    RawReceivePort((dynamic data) {
      final list = data as List;
      debugPrint('[AZM-ISOLATE] ${list[0]}: ${list[1]}');
    }).sendPort,
  );

  // A build failure is the ONE screen with nothing else on it — and the screen
  // a user sees when they are already frustrated. It is designed like the rest
  // of the app now: theme-derived colours, one human sentence, a way forward.
  // The old body hardcoded #1A1A2E and told the user to restart the app.
  //
  // Review correction (2026-09-30): there is no safe "re-run the failed build"
  // from inside ErrorWidget.builder — nudging a notifier from here cannot
  // re-execute the failed ancestor build and would duplicate root lifecycle
  // work if it tried. So the shell passes NO retry and the surface claims no
  // action it cannot perform. The truthful way out is the OS back gesture,
  // which is exactly what the hint copy says.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return AzErrorSurface.fromFramework();
  };

  // Sound ships silent until the shell says which backend is live (TASK-020).
  // Warm it off the critical path so the first real success is not late.
  AzSound.usePlatformSystemSounds();
  unawaited(AzSound.ensureReady());

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );

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
    // TASK-025: the shell resolves the theme through the active accent —
    // a Marketplace vertical's session accent while one is active, otherwise
    // the user's saved identity. Applied HERE (not per-screen) so nav,
    // sheets, Material framework widgets and the status bar all follow the
    // same accent; leaving the vertical clears the override and the saved
    // identity returns automatically.
    final vertical = ref.watch(verticalAccentProvider);
    final themeData = ref.watch(
      theme_pkg.themeProvider.select(
        (t) => theme_pkg.ThemeProvider.getThemeData(
          t.currentTheme,
          accent: vertical ?? t.accent,
        ),
      ),
    );
    final colors = ref.watch(resolvedAzamanColorsProvider);

    // TASK-026: eager root watch. SensoryProvider's async _load() runs at app
    // startup, so a force-quit/relaunch restores persisted sensory values
    // (haptics, sound, ambient motion, reduce-motion) into the AzSensory
    // static sink BEFORE any screen fires a haptic — not only after the user
    // opens Settings. Provider is single-instantiated by the root ProviderScope;
    // no second provider or sink is created here.
    final sensory = ref.watch(sensoryProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: colors.isDark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: colors.isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: colors.surface,
        systemNavigationBarIconBrightness: colors.isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: MaterialApp.router(
        title: 'Azaman P2P',
        debugShowCheckedModeBanner: false,
        theme: themeData,
        routerConfig: appRouter,
        // NEW-A (Step 4): enables Flutter's restoration system for the
        // router's page stack and any widget that opts in via
        // restorationId / RestorationMixin (scroll offsets, page state).
        restorationScopeId: 'root',
        builder: (context, child) => RouteDepthTrackerHost(
          tracker: routeDepthTracker,
          child: AzMotionScope(
            notifier: sensory,
            child: ThemedAppBackdrop(
              child: AzamanConnectivityBanner(
                // NEW-C: the depth-aware contextual nav band mounts ABOVE
                // the navigator so it can own the bottom edge while a
                // pushed route owns the screen (the shell's own pill is
                // covered by any router push). The band hides itself at
                // depth 0, when no shell is engaged, and whenever an
                // imperative route covers the top router page.
                child: Stack(
                  children: [
                    child ?? const SizedBox.shrink(),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ContextualNavBand(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TASK-010b — Market-tab long-press vertical launcher
//
// A deliberate long-press on the Market tab opens the vertical launcher
// sheet; picking a vertical lands on the marketplace with that vertical
// already selected (the TASK-011 `initialCategory` contract). A normal tap
// is unchanged — this is purely an additive gesture seam. TASK-018 will
// replace the sheet's body with the unified radial launcher; the seam below
// ([openVerticalLauncherForTab] + the nav's `onTabLongPress`) is what stays.
//
// WEIGHT NOTE (deviation from the brief's "Whisper-weight sheet"): five
// fixed rows plus a header (~430 logical px) exceed the grammar's whisper
// ceiling (45% of the viewport) on phone heights, and the sheet grammar's
// own rule (I.10.2) routes content that cannot fit the whisper band to the
// Panel weight. The launcher therefore ships as an AzamanSheet Panel — the
// same compact single-column list the brief intended, but bounded: it opens
// at the 45% detent, scrolls its rows, and can never extend into an
// unusable region at any screen size.
// ═════════════════════════════════════════════════════════════════════════════

/// The Marketplace tab's index in the shell (Home 0 · Chat 1 · Marketplace 2)
/// — NEW-HOME §15: P2P left the primary nav; it is reachable via the Home
/// P2P module and its canonical routes.
const int kMarketTabIndex = 2;

/// The launcher's five targets — exactly the wires TASK-011's launch allowlist
/// guards (`MarketplaceHomeScreen._launchableCategoryWires`), so a launcher
/// landing can never offer a wire the marketplace would reject or guess at.
///
/// Order mirrors the in-app category dial (Restaurants, Hotels, Transit,
/// Retail). The app carries two hotel wire variants (F-029): the dial's
/// `REAL_ESTATE` entry and the model-canonical `HOSPITALITY` wire that backend
/// records are tagged with — the launcher surfaces both as distinct targets,
/// labelled distinctly. Icons follow F-035 (only Hugeicons names verified
/// in-repo).
const List<({String wire, String label, IconData icon, String subtitle})>
kVerticalLauncherEntries = [
  (
    wire: 'FOOD_BEVERAGE',
    label: 'Restaurants',
    icon: HugeIconsSolid.store01,
    subtitle: 'Menus & tables',
  ),
  (
    wire: 'REAL_ESTATE',
    label: 'Hotels',
    icon: HugeIconsSolid.bank,
    subtitle: 'Rooms & floors',
  ),
  (
    wire: 'LOGISTICS',
    label: 'Transit',
    icon: HugeIconsSolid.arrowDataTransferHorizontal,
    subtitle: 'Trips & seats',
  ),
  (
    wire: 'RETAIL',
    label: 'Retail',
    icon: HugeIconsStroke.shoppingBag01,
    subtitle: 'Shop the shelf',
  ),
  (
    wire: 'HOSPITALITY',
    label: 'Hospitality',
    icon: HugeIconsSolid.bank,
    subtitle: 'Book rooms & check availability',
  ),
];

/// Opens the vertical launcher for a nav-tab long-press.
///
/// The gating contract lives HERE, not in the shell: only the Market tab
/// ([kMarketTabIndex]) owns a launcher, so a long-press on any other tab
/// returns `false` and nothing happens. The launcher is a single
/// Panel-weight [AzamanSheet.showPanel] route — that route is the one
/// authoritative lifecycle. There are no task-owned OverlayEntries or
/// animation controllers to leak: a cancelled/interrupted long-press simply
/// never opens the sheet, and the modal barrier makes a concurrent duplicate
/// open impossible.
///
/// On a target pick the sheet is popped exactly once, [selectTab] selects the
/// Market tab underneath, and the already-filtered marketplace is pushed as a
/// new route — back returns to the unfiltered marketplace tab.
bool openVerticalLauncherForTab(
  int index,
  BuildContext context, {
  required void Function(int index) selectTab,
}) {
  if (index != kMarketTabIndex) return false;
  AzamanSheet.showPanel<void>(
    context,
    builder: (sheetContext, scrollController) => VerticalLauncherSheet(
      scrollController: scrollController,
      onLaunch: (wire) {
        // Close the launcher exactly once: pop the SHEET route with its own
        // context, then navigate with the still-mounted shell context.
        // (TASK-018/F-051: navigation() removed — the launcher's satellite
        // already fired the pick's single confirm(); two haptics per pick is
        // the double-fire class this task removes.)
        Navigator.pop(sheetContext);
        selectTab(kMarketTabIndex);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MarketplaceHomeScreen(initialCategory: wire),
          ),
        );
      },
    ),
  );
  return true;
}

/// The launcher's Panel body: a pinned "Explore the market" header + the
/// radial vertical launcher (TASK-018). Satellites burst from the body's
/// centre with the shared liquid vocabulary — kPopSpring launch, goo-rim
/// merging, one confirm() haptic per pick. The sheet surface
/// (colour, scrim, blur, handle, safe-area, detents) is owned by
/// `AzSheetSurface`; the burst is fixed-height, and the sheet surface owns
/// the detent drag.
class VerticalLauncherSheet extends ConsumerWidget {
  const VerticalLauncherSheet({
    super.key,
    required this.scrollController,
    required this.onLaunch,
  });

  /// The DraggableScrollableSheet's own controller — the one that moves the
  /// detent when the rows are dragged.
  final ScrollController scrollController;

  /// Invoked exactly once with the picked target's wire.
  final void Function(String wire) onLaunch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(theme_pkg.themeProvider).colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AzSpace.lg,
            AzSpace.sm,
            AzSpace.lg,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Explore the market',
                style: AzText.title.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AzSpace.xxs),
              Text(
                'Jump straight into a vertical',
                style: AzText.bodyS.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
        // TASK-018: the radial burst replaces the five-row list. The launcher
        // solves its own satellite geometry inside this box (bounded
        // constraints are part of its contract) and fires exactly one
        // confirm() haptic per pick — no extra haptic here or in the entry
        // point (3e). scrollController stays in the constructor
        // contract (AzamanSheet.showPanel provides it); the fixed-height
        // burst needs no scrollable, and the sheet surface still owns the
        // detent drag.
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: LiquidLauncher(
              semanticLabel: 'Market verticals',
              items: [
                for (final entry in kVerticalLauncherEntries)
                  LiquidLauncherItem(
                    icon: entry.icon,
                    label: entry.label,
                    onTap: () => onLaunch(entry.wire),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class MainWrapper extends ConsumerStatefulWidget {
  const MainWrapper({super.key});
  @override
  ConsumerState<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends ConsumerState<MainWrapper>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;

  /// The + launcher open/close state, shared between the trigger (in the
  /// nav band) and the overlay (in the body stack).
  final PlusLauncherController _plus = PlusLauncherController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final List<Widget?> _pages;
  late final AnimationController _transitionCtrl;

  /// NEW-C: the tap-active-tab contract (scroll-to-top with the house
  /// spring + the already-here lift) and the shell's engagement on the
  /// app shell bus.
  late final NavRetapController _retap;
  // Cached in initState: `ref` is unusable from dispose() (riverpod asserts),
  // and deactivate() can fire for temporary removals that later re-insert the
  // State — deregistering there could drop listeners that are never reregistered.
  late final SocketService _shellSocketService;
  int _displayedIndex = 0;
  int _transitionDirection = 1;

  @override
  void initState() {
    super.initState();
    _shellSocketService = ref.read(socketServiceProvider);

    _pages = [const AzamanHomePage(), null, null];

    _retap = NavRetapController(vsync: this);
    // NEW-C: publish the shell's presence + active tab to the contextual
    // nav band; tab requests route through the shell's OWN handler so the
    // whole switch contract (launcher close, home-active signal,
    // compression reset, ticker budget) applies unchanged.
    appShellBus.engage(
      onTabRequest: _onNavItemSelected,
      initialTab: _selectedIndex,
    );

    _transitionCtrl = AnimationController(
      vsync: this,
      duration: MotionTokens.emphasized,
      value: 1.0,
    )..addStatusListener(_onTransitionStatus);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initUnifiedSocket();
      _initPostFrameStartup();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _transitionCtrl.duration = AzMotion.of(context).travel
        ? MotionTokens.emphasized : MotionTokens.control;
  }

  Widget _pageFor(int index) {
    switch (index) {
      case 1:
        return const FriendsHubScreen();
      case 2:
        return const MarketplaceHomeScreen();
      default:
        return const AzamanHomePage();
    }
  }

  void _onTransitionStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_displayedIndex == _selectedIndex) return;
    setState(() => _displayedIndex = _selectedIndex);
  }

  void _onNavItemSelected(int i) {
    if (i == _selectedIndex) return;
    // NEW-HOME audit §3: switching shell tabs CLOSES the + launcher. The
    // overlay belongs to the tab that opened it — an open launcher over
    // a mid-flight page transition would strand a modal on an unrelated
    // page, and the trigger sits in the nav band, not in the page, so
    // nothing else would ever close it.
    if (_plus.isOpen) _plus.close();
    // NEW-HOME audit §7: Home-local security state (unlocked card
    // details) and Home-local machines (the typewriter) must know when
    // Home stops being the displayed tab — pages stay MOUNTED, so only
    // this explicit signal separates "mounted" from "active".
    ref.read(homeShellActiveProvider.notifier).state = i == 0;
    final page = _pages[i] ?? _pageFor(i);
    // TASK-010: compression tracks the CURRENT page's offset. The incoming
    // page starts at its top, so the pill must start at rest — otherwise a
    // compressed state from the outgoing page would linger until the new page
    // scrolls.
    if (navScrollCompression.value != 0) navScrollCompression.value = 0;
    final midTransition = _displayedIndex != _selectedIndex;

    setState(() {
      _pages[i] = page;
      if (midTransition) {
        // Preserve the existing snap when the user taps mid-flight.
        _displayedIndex = i;
        _selectedIndex = i;
      } else {
        _selectedIndex = i;
        _transitionDirection = i > _displayedIndex ? 1 : -1;
      }
    });

    if (!midTransition) {
      _transitionCtrl.forward(from: 0);
    }

    // NEW-C: the contextual band's reopened pill mirrors the live tab.
    appShellBus.setActiveTab(i);
  }

  /// NEW-C (§2.3): a tap on the already-active tab springs the page's
  /// outermost scrollable to the top with `kHouseSpring`, or lifts the
  /// content (1.0 → 0.985 → 1.0) when it is already there.
  void _onActiveTabRetap() {
    _retap.handleRetap(
      tab: _selectedIndex,
      registry: TabScrollRegistry.instance,
      context: context,
    );
  }

  /// Ticker budget (milestone 2026-09-30): only the page participating in
  /// the current transition keeps its tickers enabled. Once navigation
  /// settles (_displayedIndex == _selectedIndex), exactly one page is
  /// ticker-enabled — every previously-visited, still-mounted page stops
  /// consuming animation cycles. Page state is preserved (nothing unmounts)
  /// and no new navigation state is introduced.
  Widget _withPageTickerBudget(int index, Widget child) {
    final enabled = index == _selectedIndex || index == _displayedIndex;
    return TickerMode(
      enabled: enabled,
      child: child,
    );
  }

  /// Incoming page: 6% inset slide + fade in.
  Widget _buildIncoming(int index) {
    final incoming = _selectedIndex != _displayedIndex;
    if (!incoming) {
      return _pages[index]!;
    }
    final fade = FadeTransition(
      opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _transitionCtrl, curve: MotionTokens.enter),
      ),
      child: _pages[index]!,
    );
    // Reduced motion preserves arrival as a control-tempo cross-fade only.
    if (!AzMotion.of(context).travel) return fade;
    final d = _transitionDirection;
    return SlideTransition(
      position: Tween<Offset>(begin: Offset(0.06 * d, 0), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _transitionCtrl,
              curve: MotionTokens.symmetric,
            ),
          ),
      child: fade,
    );
  }

  /// Outgoing page: fade out only, so it never ghosts over the new content.
  Widget _buildOutgoing(int index) {
    if (index == _selectedIndex) return const SizedBox.shrink();
    return FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _transitionCtrl, curve: MotionTokens.exit),
      ),
      child: _pages[index]!,
    );
  }

  @override
  void dispose() {
    // Deregister the shell's socket callbacks via the cached service — no
    // ref.read here (riverpod asserts once the element is disposed), and no
    // deactivate() deregistration (deactivation can be temporary).
    _shellSocketService.removeNewTradeRequestListener();
    _shellSocketService.removeBizNotificationListener();
    _shellSocketService.removeBizNotificationsUpdatedListener();
    _transitionCtrl.dispose();
    _retap.dispose();
    appShellBus.disengage();
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

  void _showSocketNotificationBanner({
    required Map<String, dynamic> data,
    required String title,
    required String body,
  }) {
    if (!mounted) return;
    final ctx = rootNavigatorKey.currentContext ?? context;
    if (!ctx.mounted) return;

    final action = data['action']?.toString() ?? '';
    final actionPayload = <String, dynamic>{};
    data.forEach((key, value) {
      if (key != 'action') actionPayload[key] = value;
    });

    InAppPushBanner.show(
      ctx,
      title: title,
      body: body,
      onTap: action.isEmpty
          ? null
          : () => handleNotificationTap(
              action: action,
              actionPayload: actionPayload,
            ),
    );
  }

  void _initUnifiedSocket() {
    final socketService = _shellSocketService;
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
      _showSocketNotificationBanner(
        data: Map<String, dynamic>.from(data),
        title: data['title']?.toString() ?? 'New Message',
        body: data['body']?.toString() ?? '',
      );
    });
    socketService.onNewTradeRequest((data) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ref.read(trade_pkg.tradeProvider).incrementNotificationCount();
      final buyer = data['buyerName']?.toString() ?? 'Buyer';
      final amount = data['amount']?.toString() ?? '';
      _showSocketNotificationBanner(
        data: Map<String, dynamic>.from(data),
        title: 'New Trade Request',
        body: '\u{1F514} $buyer wants to trade \$$amount USD',
      );
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
      bottomNavigationBar: PremiumBottomNav(
        // NEW-HOME §8/§10 (audit): the + action trigger sits STRUCTURALLY
        // BESIDE the nav pill — [navigation] [+] — themed by the AZM
        // accent identity, sharing the pill's band and safe-area handling.
        trailing: PlusLauncherTrigger(controller: _plus),
        selectedIndex: _selectedIndex,
        onItemSelected: _onNavItemSelected,
        // NEW-C (§2.3): tap on the already-active tab springs the page to
        // the top (or lifts it when already there) — closes F-025.
        onActiveTabRetap: _onActiveTabRetap,
        // TASK-010b: a long-press on the Market tab opens the vertical
        // launcher; the gating (Market is the only launcher-owned tab) lives
        // in [openVerticalLauncherForTab], so the shell stays a one-line
        // seam. Tabs 0..2 long-press inertly — TASK-018 owns those gestures.
        onTabLongPress: (index) => openVerticalLauncherForTab(
          index,
          context,
          selectTab: _onNavItemSelected,
        ),
      ),
      // TASK-010: the nav pill compresses while the page scrolls. ONE
      // listener above the whole shell catches every ScrollNotification
      // bubbled from every scrollable in every page, so no page needs a
      // scroll controller threaded through it. All of the policy (vertical
      // axis guard, pull-to-refresh overscroll guard, 10-step quantisation)
      // lives in `NavScrollCompression.applyTo`, which is unit-tested in
      // test/widgets/nav_scroll_compression_test.dart.
      //
      // The value tracks the page's ABSOLUTE offset, so stopping mid-page
      // keeps the pill compressed (it does not pop back on ScrollEnd) and
      // returning to the top restores it. Reduced motion is honoured by the
      // reader in the nav, not here.
      body: NotificationListener<ScrollNotification>(
        // TASK-010 compression + NEW-C per-tab scroll recording share this
        // one listener above every page. The registry keeps each tab's
        // OUTERMOST vertical scrollable so the retap contract can spring
        // the page to the top without any page owning a controller seam.
        onNotification: (n) {
          NavScrollCompression.applyTo(n);
          TabScrollRegistry.instance.record(_selectedIndex, n);
          return false;
        },
        child: ScaleTransition(
          // NEW-C: the already-here lift — a subtle 1.0 → 0.985 → 1.0
          // scale of the whole content, driven by the retap controller.
          // Rests at 1.0 and never plays under reduced motion.
          scale: _retap.lift,
          child: Stack(
            children: [
              AnimatedBuilder(
              animation: _transitionCtrl,
              builder: (context, child) => Stack(
                fit: StackFit.expand,
                children: [
                  for (var index = 0; index < _pages.length; index++)
                    if (_pages[index] != null && index != _selectedIndex)
                      _withPageTickerBudget(
                          index, _buildOutgoing(index)),
                  if (_pages[_selectedIndex] != null)
                    _withPageTickerBudget(
                      _selectedIndex,
                      _buildIncoming(_selectedIndex),
                    ),
                ],
              ),
              child: const SizedBox.expand(),
            ),
            // AUDIT §9 — the vendor-portal entry point is NOT deleted: the
            // pull tag (vendor → dashboard, non-vendor → 3-pull apply
            // flow) keeps its configured home on the HOME tab, the shell's
            // primary surface in the 3-tab layout. The settings toggle
            // (`vendorTagEnabled`) still decides whether it appears.
            if (_displayedIndex == 0 &&
                ref.watch(settings_pkg.settingsProvider).vendorTagEnabled)
              const VendorPullTab(),
            DrawerPeekHint(
              onOpenDrawer: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
            // NEW-HOME §8: the floating + action launcher, topmost in the
            // shell stack. It means "things I can DO" (Recent Activity is
            // "things that HAPPENED"). The + sits beside the bottom nav;
            // opening de-emphasizes the content and the actions appear
            // directly on screen — never inside a boxed modal.
            Positioned.fill(
              child: PlusActionLauncher(
                controller: _plus,
                actions: [
                  PlusLauncherAction(
                    icon: HugeIconsSolid.moneySend01,
                    label: 'Send',
                    onTap: () => nav_transitions_pkg.pushWithVerticalTransition(
                        context, const SendMoneyScreen()),
                  ),
                  PlusLauncherAction(
                    icon: HugeIconsSolid.moneyReceiveFlow01,
                    label: 'Receive',
                    onTap: () => showReceiveSheet(context),
                  ),
                  PlusLauncherAction(
                    icon: HugeIconsSolid.wallet01,
                    label: 'Add Cash',
                    // CANONICAL ROUTE: /deposit owns the rise transition at
                    // the route level (risePage) — the launcher pushes the
                    // location, never a bare MaterialPageRoute-equivalent.
                    // The route's builder defaults to the fiat tab, so the
                    // Add Cash behavior is unchanged.
                    onTap: () => context.push(AzRoutes.deposit()),
                  ),
                  PlusLauncherAction(
                    icon: HugeIconsSolid.bank,
                    label: 'Withdraw',
                    onTap: () => nav_transitions_pkg.pushWithVerticalTransition(
                        context, const WithdrawalScreen()),
                  ),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainNavigationWrapper extends StatelessWidget {
  const MainNavigationWrapper({super.key});
  @override
  Widget build(BuildContext context) => const MainWrapper();
}
