// =============================================================================
// AZAMAN — DEPTH-AWARE CONTEXTUAL NAV BAND  (NEW-C, closes F-025)
//
// Spec §2.3 ("make the nav aware of depth"):
//
//   Give the nav a `depth` value (0 on root tabs, 1+ on pushed routes). At
//   depth ≥ 1 the pill morphs into a contextual bar: the active tab is
//   replaced by the current route's title + a back chevron, and the other
//   tabs collapse into a single "…" that reopens the pill on tap.
//
// Depth comes from the router and ONLY from the router — NEW-A's
// [RouteDepthTracker] owns the answer (never infer depth from screen
// names or scaffolding; see router/route_depth.dart for the contract).
//
// WHERE THIS MOUNTS AND WHY
// -------------------------
// The 3-tab shell ([MainWrapper]) is an imperative route pushed above the
// router's base page, and router pushes land ABOVE that shell (the
// sanctioned stacking semantics recorded in notification_hub_screen.dart).
// A pushed route therefore COVERS the shell — including its bottom nav —
// and the shell's [PremiumBottomNav] can never be visible at depth ≥ 1.
// This band mounts in the MaterialApp builder, ABOVE the navigator, so it
// is the one piece of chrome that can still own the bottom edge while a
// pushed route owns the screen. It shows exactly when ALL of these hold:
//
//   * the shell is engaged ([AppShellBus.engaged] — MainWrapper mounted;
//     a cold deep link with no shell keeps the app's current honest
//     behaviour: full-screen page, no chrome),
//   * the router reports depth ≥ 1 ([RouteDepthTracker.depth]),
//   * the topmost route is a router-owned page — nothing imperative
//     (sanctioned sibling screen, sheet, dialog) covers it
//     ([TopRouteKindObserver.topRouteIsRouterPage]).
//
// The second half of NEW-C — tap-active-tab scroll-to-top with
// `kHouseSpring` + the already-here lift — lives at depth 0 in the shell
// ([NavRetapController], wired in MainWrapper), not here.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_depth.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/router/top_route_observer.dart';
import 'package:azaman/theme/az_elevation.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';

/// Human titles for the contextual bar, keyed by GoRouter route name.
///
/// The bar shows the CURRENT page's title; the breadcrumb's last name is
/// the current page. Unknown names fall back to the prettified route name
/// (segments split on '-', capitalised) — never an invented label.
abstract final class AzRouteTitles {
  static const Map<String, String> _titles = {
    AzRouteNames.home: 'Home',
    AzRouteNames.notifications: 'Notifications',
    AzRouteNames.trade: 'Trade',
    AzRouteNames.dispute: 'Dispute',
    AzRouteNames.queue: 'Waiting Room',
    AzRouteNames.settings: 'Settings',
    AzRouteNames.profileEdit: 'Edit Profile',
    AzRouteNames.accountActivity: 'Account Activity',
    AzRouteNames.accountDelete: 'Delete Account',
    AzRouteNames.transactions: 'Transactions',
    AzRouteNames.friends: 'Friends',
    AzRouteNames.messages: 'Messages',
    AzRouteNames.referral: 'Referral',
    AzRouteNames.leaderboard: 'Leaderboard',
    AzRouteNames.azmAuction: 'Auction',
    AzRouteNames.marketplace: 'Marketplace',
    AzRouteNames.savings: 'Savings',
    AzRouteNames.deposit: 'Add Cash',
    AzRouteNames.susuHub: 'Susu',
    AzRouteNames.proofOfResidency: 'Proof of Residency',
    AzRouteNames.susuInvite: 'Susu Invite',
    AzRouteNames.susuDetail: 'Susu Group',
    AzRouteNames.susuContract: 'Susu Contract',
    AzRouteNames.susuPositionPicker: 'Choose Your Position',
    AzRouteNames.susuCompletion: 'Susu Completion',
    AzRouteNames.businessMarketHome: 'Business Portal',
    AzRouteNames.checkinQr: 'Check-in QR',
    AzRouteNames.businessCheckin: 'Check-ins',
    AzRouteNames.transitTrips: 'Transit Trips',
    AzRouteNames.businessTransitTrips: 'Transit Trips',
    AzRouteNames.transitSeatSelection: 'Select Seats',
    AzRouteNames.hotelBooking: 'Book a Room',
    AzRouteNames.dineInTab: 'Dine In',
    AzRouteNames.businessStories: 'Stories',
    AzRouteNames.businessMarketOrders: 'Orders',
    AzRouteNames.businessMarketInvoices: 'Invoices',
    AzRouteNames.invoiceDetail: 'Invoice',
    AzRouteNames.businessMarketDashboard: 'Dashboard',
    AzRouteNames.businessSearch: 'Search',
    AzRouteNames.savedBusinesses: 'Saved Places',
    AzRouteNames.businessRegister: 'Register a Business',
    AzRouteNames.businessNotifications: 'Notifications',
    AzRouteNames.businessProducts: 'Products',
    AzRouteNames.businessProfile: 'Business Profile',
    AzRouteNames.workerHub: 'Work',
    AzRouteNames.workerShifts: 'My Shifts',
    AzRouteNames.workerPayroll: 'Payroll',
    AzRouteNames.workerTeam: 'My Team',
    AzRouteNames.workerTimeOff: 'Time Off',
    AzRouteNames.workerFeedback: 'Feedback',
    AzRouteNames.workerEwa: 'Earned Wage Access',
    AzRouteNames.workerSwaps: 'Shift Swaps',
    AzRouteNames.storefrontStaking: 'Storefront Staking',
    AzRouteNames.storefront: 'Storefront',
    AzRouteNames.storefrontDiscovery: 'Discover',
    AzRouteNames.storefrontOrderHistory: 'Order History',
    AzRouteNames.universalSearch: 'Search',
    AzRouteNames.spendingInsights: 'Spending Insights',
    AzRouteNames.roundUpSavings: 'Round-Up Savings',
    AzRouteNames.storyHighlights: 'Story Highlights',
    AzRouteNames.closeFriends: 'Close Friends',
    AzRouteNames.storyCamera: 'New Story',
    AzRouteNames.storyEditor: 'Story Editor',
    AzRouteNames.storyAnalytics: 'Story Analytics',
    AzRouteNames.storyCreation: 'New Story',
    AzRouteNames.loyaltyCards: 'Loyalty Cards',
    AzRouteNames.notificationPreferences: 'Notification Preferences',
    AzRouteNames.messageSearch: 'Search Messages',
    AzRouteNames.walletPass: 'Wallet',
    AzRouteNames.orderTracking: 'Track Order',
    AzRouteNames.vaultYield: 'Vault Yield',
  };

  /// The display title for a route name, prettified when unknown.
  static String titleOf(String? routeName) {
    if (routeName == null || routeName.isEmpty) return '';
    final known = _titles[routeName];
    if (known != null) return known;
    return routeName
        .split('-')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

/// The app-scoped shell signal bus between the imperative shell
/// ([MainWrapper], below pushed routes) and this band (above them).
///
/// The shell ENGAGES on mount and DISENGAGES on dispose, publishes its
/// active tab on every switch, and accepts tab requests from the band's
/// reopened pill. No navigation happens here — a tab request is handed to
/// the shell's own tab handler so the shell's whole switch contract
/// (+ launcher close, home-shell-active signal, compression reset,
/// ticker budget) applies unchanged.
class AppShellBus extends ChangeNotifier {
  bool _engaged = false;
  int _activeTab = 0;
  void Function(int)? _onTabRequest;

  /// Whether the shell is mounted (visible or covered by pushed routes).
  bool get engaged => _engaged;

  /// The shell's currently active tab (Home 0 · Chat 1 · Marketplace 2).
  int get activeTab => _activeTab;

  void engage({required void Function(int) onTabRequest, int initialTab = 0}) {
    _onTabRequest = onTabRequest;
    _activeTab = initialTab;
    _engaged = true;
    notifyListeners();
  }

  void disengage() {
    _onTabRequest = null;
    _engaged = false;
    notifyListeners();
  }

  /// The shell publishes its tab on every switch.
  void setActiveTab(int tab) {
    if (tab == _activeTab || !_engaged) return;
    _activeTab = tab;
    notifyListeners();
  }

  /// The band asks the shell to switch tabs (same-index is a no-op in the
  /// shell's handler).
  void requestTab(int tab) => _onTabRequest?.call(tab);

  /// Test-only: the singleton survives across tests.
  @visibleForTesting
  void debugReset() {
    _engaged = false;
    _activeTab = 0;
    _onTabRequest = null;
    notifyListeners();
  }
}

/// The app-scoped shell bus instance.
final AppShellBus appShellBus = AppShellBus();

/// The contextual nav band. Mount once, above the navigator:
///
///   Stack(children: [navigatorChild, Positioned(left: 0, right: 0,
///     bottom: 0, child: ContextualNavBand())])
class ContextualNavBand extends ConsumerStatefulWidget {
  const ContextualNavBand({super.key});

  @override
  ConsumerState<ContextualNavBand> createState() => _ContextualNavBandState();
}

class _ContextualNavBandState extends ConsumerState<ContextualNavBand> {
  /// Whether the "…" has reopened the pill over the depth page.
  bool _pillOpen = false;

  AzamanColors get _colors => ref.watch(themeProvider.select((t) => t.colors));

  bool _visible(RouteDepthTracker tracker) =>
      appShellBus.engaged &&
      tracker.depth >= 1 &&
      topRouteObserver.topRouteIsRouterPage;

  void _openPill() {
    AzamanHaptics.selection();
    // The compression notifier's writer — the shell's scroll listener — is
    // not mounted above depth pages, so its value here is stale from the
    // page below the push. Opening the pill at anything but rest would
    // render a compressed pill over a page that never scrolled it. This is
    // the ONLY value the band ever writes: rest.
    if (navScrollCompression.value != 0) navScrollCompression.value = 0;
    setState(() => _pillOpen = true);
  }

  void _collapsePill() {
    AzamanHaptics.selection();
    setState(() => _pillOpen = false);
  }

  /// Tapping any tab in the reopened pill returns to the shell — popping
  /// every router page pushed above it — and switches the shell tab. The
  /// band never pops imperative routes: it is only interactive when the
  /// topmost route is a router page, so [GoRouter.pop] always targets the
  /// right stack.
  void _onBandTabTap(int tab) {
    final router = RouteDepthTrackerHost.of(context).router;
    _collapsePill();
    while (router.canPop()) {
      router.pop();
    }
    appShellBus.requestTab(tab);
  }

  /// The back chevron: pop one router page. A deep link with nothing under
  /// it (no shell base beneath) falls back to the canonical root — this
  /// can only happen when the shell is NOT engaged, and the band is not
  /// interactive then, but the guard keeps the contract total.
  void _onBack() {
    AzamanHaptics.navigation();
    final router = RouteDepthTrackerHost.of(context).router;
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AzRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracker = RouteDepthTrackerHost.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    final reduce = !AzMotion.of(context).travel;
    final presence = reduce ? Duration.zero : MotionTokens.control;

    // The band mounts ABOVE the navigator (MaterialApp.builder), where no
    // route Scaffold can supply a Material ancestor for its InkWells. It
    // carries its own transparent sheet so it works at any mount depth.
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: Listenable.merge([tracker, appShellBus, topRouteObserver]),
        builder: (context, _) {
          final visible = _visible(tracker);
          return IgnorePointer(
            ignoring: !visible,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 1.4),
              duration: presence,
              curve: MotionTokens.enter,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: presence,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: bottom > 0 ? bottom + AzSpace.sm : AzSpace.lg,
                  ),
                  child: AnimatedSwitcher(
                    duration: presence,
                    child: _pillOpen
                        ? _buildPill()
                        : _buildBar(context, tracker),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The collapsed contextual bar: back chevron + route title + "…".
  Widget _buildBar(BuildContext context, RouteDepthTracker tracker) {
    final colors = _colors;
    final title = AzRouteTitles.titleOf(
      tracker.routeNames.isEmpty ? null : tracker.routeNames.last,
    );
    return Container(
      key: const Key('contextual-nav-bar'),
      margin: const EdgeInsets.symmetric(
        horizontal: NavScrollCompression.expandedInset,
      ),
      height: NavScrollCompression.expandedHeight,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AzRadius.brPill,
        boxShadow: AzElevation.level3(colors.isDark),
      ),
      child: Row(
        children: [
          _BandIconAction(
            key: const Key('contextual-nav-back'),
            icon: HugeIconsStroke.arrowLeft01,
            semanticLabel: 'Go back',
            onTap: _onBack,
            iconColor: colors.textPrimary,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AzSpace.sm),
              child: Text(
                title,
                style: AzText.title.copyWith(color: colors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          _BandTextAction(
            key: const Key('contextual-nav-toggle'),
            label: '…',
            semanticLabel: 'Show tabs',
            onTap: _openPill,
          ),
        ],
      ),
    );
  }

  /// The reopened pill: the REAL [PremiumBottomNav] (the same widget the
  /// shell hosts, so identity — glass, LiquidTabBackdrop, badges — is
  /// preserved), with a collapse affordance in the trailing slot the shell
  /// reserves for a control beside the nav.
  ///
  /// The retap override is the review blocker fix: inside the contextual
  /// pill, a tap on the ALREADY-SELECTED tab must still return to the
  /// shell (pop + tab hand-off), exactly like any other tab tap. Only
  /// '…'/'Hide tabs' collapses the pill in place. This override is local
  /// to the band's pill; the shell's own depth-0 retap contract
  /// (scroll-to-top / lift) is untouched.
  Widget _buildPill() {
    return PremiumBottomNav(
      key: const Key('contextual-nav-pill'),
      selectedIndex: appShellBus.activeTab,
      onItemSelected: _onBandTabTap,
      onActiveTabRetap: () => _onBandTabTap(appShellBus.activeTab),
      trailing: _BandTextAction(
        label: '…',
        semanticLabel: 'Hide tabs',
        onTap: _collapsePill,
      ),
    );
  }
}

/// A square icon action inside the contextual bar (56×62 — the pill's full
/// height, comfortably above the 48px minimum target).
class _BandIconAction extends StatelessWidget {
  const _BandIconAction({super.key, required this.icon,
    required this.semanticLabel,
    required this.onTap,
    required this.iconColor,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: AzRadius.brPill,
        child: SizedBox(
          width: 56,
          height: NavScrollCompression.expandedHeight,
          child: Center(child: Icon(icon, size: 22, color: iconColor)),
        ),
      ),
    );
  }
}

/// A text action ("…") inside the contextual bar.
class _BandTextAction extends StatelessWidget {
  const _BandTextAction({super.key, required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final colors = ref.watch(themeProvider.select((t) => t.colors));
        return Semantics(
          button: true,
          label: semanticLabel,
          child: InkWell(
            onTap: onTap,
            borderRadius: AzRadius.brPill,
            child: SizedBox(
              width: 48,
              height: NavScrollCompression.expandedHeight,
              child: Center(
                child: Text(
                  label,
                  style: AzText.titleL.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
