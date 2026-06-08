// =============================================================================
// P2P MARKETPLACE SCREEN — Phase 3.2 | Azaman V2
//
// Architecture:
//   • ConsumerStatefulWidget — watches filteredAdsProvider + aiFilterProvider
//   • CustomScrollView with two sliver zones:
//       1. SliverPersistentHeader — sticky header (AI toggle + filter chips)
//       2. SliverList — ad cards via _StackingCardDelegate
//
// Apple Wallet stacking effect:
//   Each card is wrapped in a SliverPersistentHeader with a custom delegate.
//   As the user scrolls UP past a card, the delegate clamps the card's
//   top position so it "stacks" at an increasing vertical offset — visually
//   identical to Apple Wallet cards collapsing at the top of the viewport.
//   The delegate uses a simple scroll-position listener to drive a per-card
//   opacity fade and scale-down so deeper cards appear to recede behind
//   the top-most pinned card.
// =============================================================================


import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/marketplace_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/screens/vendor_ad_creator.dart';
import 'package:azaman/screens/waiting_room_screen.dart';
import 'package:azaman/screens/active_trade_screen.dart';
import 'package:azaman/widgets/vendor_ad_card.dart';
import 'package:azaman/widgets/ad_detail_flip_card.dart';
import 'package:azaman/widgets/dashboard_balance_card.dart';
import 'package:azaman/widgets/quick_actions_row.dart';
import 'package:azaman/widgets/milestone_progress.dart';
import 'package:azaman/widgets/live_milestone_progress.dart';
import 'package:hugeicons_pro/hugeicons.dart';


// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────
const double _kCardFullHeight = 168.0; // natural height (slender)
const double _kStackOffset = 10.0; // vertical peek between stacked cards
const double _kStickyHeaderHeight = 72.0;


// ─────────────────────────────────────────────────────────────────────────────
// Screen root
// ─────────────────────────────────────────────────────────────────────────────
class P2PMarketplaceScreen extends ConsumerStatefulWidget {
  const P2PMarketplaceScreen({super.key});

  @override
  ConsumerState<P2PMarketplaceScreen> createState() =>
      _P2PMarketplaceScreenState();
}

class _P2PMarketplaceScreenState
    extends ConsumerState<P2PMarketplaceScreen> {
  final ScrollController _scrollController = ScrollController();

  /// Per-ad GlobalKeys so we can capture the source row's screen rect at
  /// tap time and hand it to the in-place flip overlay. Keyed by ad id
  /// so list rebuilds preserve the same key per row.
  final Map<String, GlobalKey> _cardKeys = {};

  GlobalKey _keyFor(String adId) =>
      _cardKeys.putIfAbsent(adId, () => GlobalKey(debugLabel: 'ad-$adId'));

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    HapticFeedback.mediumImpact();
    await ref.read(adsProvider.notifier).refresh();
  }


  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final adsAsync = ref.watch(filteredAdsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: colors.glow,
        backgroundColor: colors.surface,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // ── 1. Slender Black Card at top ────────────────────────────
            const SliverToBoxAdapter(
              child: DashboardBalanceCard(),
            ),

            // ── 1b. Quick Actions row — directly below the card ─────────
            const SliverToBoxAdapter(
              child: QuickActionsRow(),
            ),

            // ── 1c. Gamification / loyalty milestone progress ───────────
            //   Placed between the dashboard chrome and the market feed
            //   so the user's tier progression sits in the natural
            //   "what's next for me" zone of the screen hierarchy.
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(5, 4, 5, 8),
                child: LiveMilestoneProgress(),
              ),
            ),

            // ── 2. Sticky AI Filter Header ──────────────────────────────
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyFilterHeaderDelegate(colors: colors, ref: ref),
            ),


            // ── 3. Body: loading / error / list ────────────────────────
            adsAsync.when(
              loading: () => const SliverFillRemaining(
                child: _LoadingShimmer(),
              ),
              error: (e, _) => SliverFillRemaining(
                child: _ErrorView(
                  message: e.toString(),
                  onRetry: _onRefresh,
                ),
              ),
              data: (ads) {
                if (ads.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      onCreateAd: () {
                        HapticFeedback.mediumImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const VendorAdCreator()),
                        );
                      },
                      onRefresh: _onRefresh,
                    ),
                  );
                }
                // Apple Wallet stacking: one SliverPersistentHeader per card
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _StackingCard(
                      index: index,
                      totalCards: ads.length,
                      scrollController: _scrollController,
                      child: KeyedSubtree(
                        key: _keyFor(ads[index].id),
                        child: VendorAdCard(
                          ad: ads[index],
                          // Phase UI-1 (2026-05-26): the "Trade Now" /
                          // "Wait in Queue" buttons were removed from
                          // VendorAdCard. Tapping the card body opens
                          // the flip overlay where both flows live —
                          // submitting the trade form on the back face
                          // routes through `_initiateTradeFromFlip`.
                          onTap: () => _onCardTapped(
                              context, ads[index], colors,
                              cardKey: _keyFor(ads[index].id)),
                        ),
                      ),
                    ),
                    childCount: ads.length,
                  ),
                );
              },
            ),


            // ── 4. Bottom breathing room ────────────────────────────────
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  void _onTrade(
      BuildContext ctx, AdListing ad, AzamanColors colors) {
    // Retained for backwards-compat with any sibling surface that still
    // wants the legacy bottom-sheet trade form. Phase UI-1 removed the
    // primary "Trade Now" CTA from VendorAdCard, so this is no longer
    // wired in the marketplace feed itself — the flip overlay's back
    // face is the canonical entry point now.
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TradeConfirmSheet(ad: ad, colors: colors),
    );
  }

  /// Tapping the card body opens the in-place flip overlay. The card
  /// flips from its origin row position into the centre of the screen
  /// with the rest of the feed blurred behind it. The trade form lives
  /// on the back face — submitting the form fires the existing trade
  /// initiation HTTP call (so retries, queue handling, error surfacing
  /// stay exactly as they were before).
  void _onCardTapped(
      BuildContext ctx, AdListing ad, AzamanColors colors,
      {required GlobalKey cardKey}) {
    HapticFeedback.selectionClick();
    final originRect = _rectFromKey(cardKey) ??
        Rect.fromLTWH(
          16,
          MediaQuery.of(ctx).size.height * 0.4,
          MediaQuery.of(ctx).size.width - 32,
          120,
        );
    showInPlaceFlipCard(
      context: ctx,
      ad: ad,
      originRect: originRect,
      onConfirmTrade: ({
        required double amountFiat,
        required Map<String, String> buyerDetails,
      }) async {
        await _initiateTradeFromFlip(ctx, ad, amountFiat, buyerDetails);
      },
    );
  }

  /// Best-effort screen-space rect for a card key. Returns null if the
  /// widget hasn't laid out yet (e.g. tapped during a rebuild) — the
  /// caller falls back to a sensible default so we never crash.
  Rect? _rectFromKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

  /// Trade initiation from the flip card's back face. Mirrors the work
  /// the legacy _TradeConfirmSheet does — left as an inline body here so
  /// the flip flow is self-contained. Replaces the legacy "Pop the
  /// flip-card overlay first, then open the trade-confirm sheet" path.
  ///
  /// BUGFIX (2026-05-27): the previous version handled ONLY the queued
  /// branch (with a snackbar). When the vendor was available and the
  /// trade went straight through, the user got NO success feedback and
  /// was stranded back on the marketplace with no way to reach the
  /// active trade chat. Now mirrors `_TradeConfirmSheet`'s handler:
  /// queued → push WaitingRoomScreen, immediate → push ActiveTradeScreen.
  Future<void> _initiateTradeFromFlip(
    BuildContext ctx,
    AdListing ad,
    double amountFiat,
    Map<String, String> buyerDetails,
  ) async {
    try {
      // For global-fiat P2P, USDC ↔ USD is 1:1 so amountCrypto == amountFiat.
      final result = await ref.read(adsProvider.notifier).initiateTrade(
            adId: ad.id.toString(),
            amountFiat: amountFiat,
            amountCrypto: amountFiat,
            paymentMethod: ad.paymentMethod,
            buyerPaymentDetails:
                buyerDetails.isEmpty ? null : buyerDetails,
          );
      if (!ctx.mounted) return;

      if (result.queued) {
        // Vendor at capacity — push the WaitingRoomScreen so the user
        // can see their queue position update in real time.
        ScaffoldMessenger.of(ctx).clearSnackBars();
        Navigator.of(ctx).push(
          MaterialPageRoute(
            builder: (_) => WaitingRoomScreen(
              queuePosition: result.queuePosition ?? 1,
              queueId: result.queueId ?? '',
              adId: result.adId ?? ad.id.toString(),
            ),
          ),
        );
      } else {
        // Immediate trade — push the ActiveTradeScreen so the user lands
        // in the trade chat with the countdown timer running.
        ScaffoldMessenger.of(ctx).clearSnackBars();
        if (result.tradeId != null && result.tradeId!.isNotEmpty) {
          Navigator.of(ctx).push(
            MaterialPageRoute(
              builder: (_) => ActiveTradeScreen(
                orderId: '#${result.tradeId}',
                amount: amountFiat,
                paymentMethod: ad.paymentMethod,
              ),
            ),
          );
        } else {
          // BE returned 200/201 but didn't send a trade id back. Surface
          // the success without leaving them stranded.
          final colors = ref.read(themeProvider).colors;
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text(
              'Trade initiated! Check Active Trades.',
              style: TextStyle(color: colors.textPrimary),
            ),
            backgroundColor: colors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ));
        }
      }
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('Trade failed: $e'),
        backgroundColor: ref.read(themeProvider).colors.danger,
      ));
      rethrow;
    }
  }

  // ignore: unused_element
  void _onJoinQueue(
      BuildContext ctx, AdListing ad, AzamanColors colors) {
    // Phase UI-1 (2026-05-26): no longer wired from VendorAdCard. The
    // queue flow now triggers from the flip-overlay back face when a
    // user submits against a queue-full ad. Retained as a private
    // helper so the snackbar copy is in one place if a future surface
    // re-introduces a queue affordance.
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(
        'Added to queue for ${ad.vendorUsername} · ${ad.queueDepth} ahead',
        style: TextStyle(color: colors.textPrimary),
      ),
      backgroundColor: colors.card,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Apple Wallet Stacking Card Wrapper
//
// Each card listens to the shared ScrollController.
// When the card's top edge would scroll above `stackTop` (the pinned header
// height + (index × _kStackOffset)), we clamp it there and scale/fade it
// slightly so it appears to "dock" behind the card above.
// ─────────────────────────────────────────────────────────────────────────────
class _StackingCard extends StatefulWidget {
  final int index;
  final int totalCards;
  final ScrollController scrollController;
  final Widget child;

  const _StackingCard({
    required this.index,
    required this.totalCards,
    required this.scrollController,
    required this.child,
  });

  @override
  State<_StackingCard> createState() => _StackingCardState();
}

class _StackingCardState extends State<_StackingCard> {
  double _scale = 1.0;
  double _opacity = 1.0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    final scroll = widget.scrollController.offset;
    // How far this card's natural top is from the viewport top
    final cardNaturalTop = _kStickyHeaderHeight +
        widget.index * (_kCardFullHeight + 12.0); // 12 = vertical margin
    final stackTop =
        _kStickyHeaderHeight + widget.index * _kStackOffset;

    final overScroll = (scroll - (cardNaturalTop - stackTop)).clamp(0.0, _kCardFullHeight);
    final t = (overScroll / _kCardFullHeight).clamp(0.0, 1.0);

    final newScale = 1.0 - t * 0.04;   // max 4% shrink
    final newOpacity = 1.0 - t * 0.35; // max 35% fade

    if ((newScale - _scale).abs() > 0.001 ||
        (newOpacity - _opacity).abs() > 0.005) {
      setState(() {
        _scale = newScale;
        _opacity = newOpacity.clamp(0.0, 1.0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: _scale,
      alignment: Alignment.topCenter,
      child: Opacity(
        opacity: _opacity,
        child: widget.child,
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Sticky Filter Header Delegate
// ─────────────────────────────────────────────────────────────────────────────
class _StickyFilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  final AzamanColors colors;
  final WidgetRef ref;
  const _StickyFilterHeaderDelegate({required this.colors, required this.ref});

  @override
  double get minExtent => _kStickyHeaderHeight;
  @override
  double get maxExtent => _kStickyHeaderHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: colors.background.withOpacity(overlapsContent ? 0.92 : 1.0),
        border: overlapsContent
            ? Border(
                bottom: BorderSide(
                    color: colors.divider, width: 0.5))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            // ── Left: title + live badge + user-side subtitle ─────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      'P2P Market',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _LiveDot(colors: colors),
                  ],
                ),
                const SizedBox(height: 2),
                _UserSideSubtitle(colors: colors, ref: ref),
              ],
            ),
            const Spacer(),
            // ── Right: Buy/Sell segmented control (PRIMARY focal point).
            // The AI Filter pill has been removed from this header per the
            // P2P UI Sprint brief — the AI re-rank is now opt-in inside
            // the trade flip card / detail view rather than a top-level
            // toggle. Buy is the default tab because the vast majority
            // of users come to the app to buy USDC.
            _UserSideSegment(colors: colors, ref: ref),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_StickyFilterHeaderDelegate old) =>
      old.colors != colors;
}


// ─────────────────────────────────────────────────────────────────────────────
// User-side Buy/Sell segmented control — featured ahead of the AI filter so
// the buying/selling decision is the first thing the user sees on the
// marketplace screen. "Buy" is the default tab because the vast majority of
// users come to the app to buy USDC.
// ─────────────────────────────────────────────────────────────────────────────
class _UserSideSegment extends StatelessWidget {
  final AzamanColors colors;
  final WidgetRef ref;
  const _UserSideSegment({required this.colors, required this.ref});

  @override
  Widget build(BuildContext context) {
    final side = ref.watch(userSideProvider);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.glow.withOpacity(0.18), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segmentButton(
            label: 'Buy',
            selected: side == UserSide.buy,
            color: colors.success,
            onTap: () {
              if (side == UserSide.buy) return;
              HapticFeedback.selectionClick();
              ref.read(userSideProvider.notifier).state = UserSide.buy;
            },
          ),
          _segmentButton(
            label: 'Sell',
            selected: side == UserSide.sell,
            color: colors.danger,
            onTap: () {
              if (side == UserSide.sell) return;
              HapticFeedback.selectionClick();
              ref.read(userSideProvider.notifier).state = UserSide.sell;
            },
          ),
        ],
      ),
    );
  }

  Widget _segmentButton({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? (colors.isDark ? Colors.black : Colors.white)
                : colors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Subtitle that flips with the user-side segment so the screen states what
// the user is actually doing in plain English. Avoids the previous
// hardcoded "Buy USDC from verified vendors" line that was misleading on
// the Sell tab.
// ─────────────────────────────────────────────────────────────────────────────
class _UserSideSubtitle extends StatelessWidget {
  final AzamanColors colors;
  final WidgetRef ref;
  const _UserSideSubtitle({required this.colors, required this.ref});

  @override
  Widget build(BuildContext context) {
    final side = ref.watch(userSideProvider);
    final text = side == UserSide.buy
        ? 'Buy USDC — pay with global fiat'
        : 'Sell USDC — receive global fiat';
    return Text(
      text,
      style: TextStyle(
          color: colors.textTertiary, fontSize: 11, letterSpacing: 0.2),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// AI Smart Filter Toggle — premium pill with animated label
// ─────────────────────────────────────────────────────────────────────────────
class _AiFilterToggle extends StatelessWidget {
  final bool aiOn;
  final AzamanColors colors;
  final WidgetRef ref;
  const _AiFilterToggle(
      {required this.aiOn, required this.colors, required this.ref});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(aiFilterProvider.notifier).state = !aiOn;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: aiOn
              ? const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF00E5FF)],
                )
              : null,
          color: aiOn ? null : colors.surface,
          border: Border.all(
            color: aiOn
                ? Colors.transparent
                : colors.glow.withOpacity(0.20),
            width: 1.0,
          ),
          boxShadow: aiOn
              ? [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              HugeIconsSolid.sparkles,
              size: 13,
              color: aiOn ? Colors.white : colors.textTertiary,
            ),
            const SizedBox(width: 5),
            Text(
              'AI Filter',
              style: TextStyle(
                color: aiOn ? Colors.white : colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 6),
            // Inline CupertinoSwitch — compact
            SizedBox(
              width: 36,
              height: 20,
              child: FittedBox(
                fit: BoxFit.fill,
                child: CupertinoSwitch(
                  value: aiOn,
                  activeColor: Colors.white.withOpacity(0.30),
                  thumbColor: aiOn ? Colors.white : null,
                  onChanged: (_) {
                    HapticFeedback.selectionClick();
                    ref.read(aiFilterProvider.notifier).state = !aiOn;
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Pulsing live dot
// ─────────────────────────────────────────────────────────────────────────────
class _LiveDot extends StatefulWidget {
  final AzamanColors colors;
  const _LiveDot({required this.colors});
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.colors.success
              .withOpacity(0.5 + 0.5 * _ctrl.value),
          boxShadow: [
            BoxShadow(
              color: widget.colors.success
                  .withOpacity(0.4 * _ctrl.value),
              blurRadius: 6,
            )
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Loading shimmer — 3 skeleton cards
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingShimmer extends ConsumerStatefulWidget {
  const _LoadingShimmer();
  @override
  ConsumerState<_LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends ConsumerState<_LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _anim = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => SingleChildScrollView(
        child: Column(
          children: List.generate(
            4,
            (i) => Container(
              height: _kCardFullHeight,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment(_anim.value - 1, 0),
                  end: Alignment(_anim.value + 1, 0),
                  colors: [
                    colors.surface,
                    colors.card.withOpacity(0.5),
                    colors.surface,
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


// ─────────────────────────────────────────────────────────────────────────────
// Error + Empty states
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorView extends ConsumerWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HugeIconsSolid.cloud,
                size: 56, color: colors.danger.withOpacity(0.60)),
            const SizedBox(height: 16),
            Text('Could not load ads',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: colors.textTertiary, fontSize: 12)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(HugeIconsSolid.refresh01, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  final VoidCallback onCreateAd;
  final Future<void> Function() onRefresh;

  const _EmptyState({
    required this.onCreateAd,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final isVendor = ref.watch(isVendorProvider);
    final side = ref.watch(userSideProvider);
    final isBuyTab = side == UserSide.buy;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Hero glyph: layered glass orb (no CustomPainter) ──
              _MarketEmptyGlyph(colors: colors, isVendor: isVendor),

              const SizedBox(height: 32),

              // ── Headline ──
              Text(
                isBuyTab
                    ? 'No Buy Markets Yet'
                    : 'No Sell Markets Yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 10),

              // ── Sub-copy switches based on role + tab ──
              Text(
                isVendor
                    ? (isBuyTab
                        ? 'Be the first vendor to sell USDC. Post a SELL ad '
                            'and your inventory shows up here for buyers '
                            'paying with global fiat.'
                        : 'Be the first vendor to buy USDC from users. Post '
                            'a BUY ad and your bid shows up here for users '
                            'who want fiat sent to their accounts.')
                    : (isBuyTab
                        ? 'No vendors selling USDC right now. Pull to '
                            'refresh, or check back in a moment.'
                        : 'No vendors buying USDC right now. Pull to '
                            'refresh, or switch to the Buy tab.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13.5,
                  height: 1.5,
                  letterSpacing: 0.1,
                ),
              ),

              const SizedBox(height: 28),

              // ── Primary CTA — vendor sees "Create First Ad",
              //     buyer sees "Refresh Markets". ──
              if (isVendor)
                _PrimaryCta(
                  colors: colors,
                  icon: HugeIconsSolid.store01,
                  label: 'Create First Ad',
                  onTap: onCreateAd,
                  emphasised: true,
                )
              else
                _PrimaryCta(
                  colors: colors,
                  icon: HugeIconsSolid.refresh01,
                  label: 'Refresh Markets',
                  onTap: onRefresh,
                  emphasised: false,
                ),

              const SizedBox(height: 14),

              // ── Secondary line ──
              Text(
                isVendor
                    ? 'You\'ll earn the spread on every fill.'
                    : 'Pull down to refresh',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 11,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty-state hero glyph — pure widgets, no CustomPainter.
// Three concentric soft rings + an icon, with a subtle ambient glow.
// ─────────────────────────────────────────────────────────────────────────────
class _MarketEmptyGlyph extends StatelessWidget {
  final AzamanColors colors;
  final bool isVendor;
  const _MarketEmptyGlyph({required this.colors, required this.isVendor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer halo — radial gradient ring
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  colors.glow.withOpacity(0.10),
                  colors.glow.withOpacity(0.0),
                ],
              ),
            ),
          ),
          // Mid ring — thin border circle
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.06),
                width: 1.0,
              ),
            ),
          ),
          // Inner glass disc
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.06),
                  Colors.white.withOpacity(0.01),
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.10),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          ),
          // Icon — switches based on role
          Icon(
            isVendor
                ? HugeIconsSolid.store01
                : HugeIconsSolid.store01,
            size: 38,
            color: colors.glow.withOpacity(0.85),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Primary CTA button used inside the empty state.
// `emphasised=true` paints the gold-tinted vendor variant.
// ─────────────────────────────────────────────────────────────────────────────
class _PrimaryCta extends StatefulWidget {
  final AzamanColors colors;
  final IconData icon;
  final String label;
  final FutureOr<void> Function() onTap;
  final bool emphasised;

  const _PrimaryCta({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.emphasised,
  });

  @override
  State<_PrimaryCta> createState() => _PrimaryCtaState();
}

class _PrimaryCtaState extends State<_PrimaryCta> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () async {
        HapticFeedback.lightImpact();
        await widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: widget.emphasised
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      c.glow,
                      c.glow.withOpacity(0.78),
                    ],
                  )
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.08),
                      Colors.white.withOpacity(0.03),
                    ],
                  ),
            border: Border.all(
              color: widget.emphasised
                  ? c.glow.withOpacity(0.0)
                  : Colors.white.withOpacity(0.10),
              width: 1.0,
            ),
            boxShadow: widget.emphasised
                ? [
                    BoxShadow(
                      color: c.glow.withOpacity(0.32),
                      blurRadius: 22,
                      spreadRadius: -4,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: widget.emphasised
                    ? Colors.black
                    : Colors.white.withOpacity(0.92),
              ),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.emphasised
                      ? Colors.black
                      : Colors.white.withOpacity(0.92),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Trade Confirm Bottom Sheet
// Phase F2: USD input (1:1 with USDC). No GHS oracle conversion.
// For SELL ads: collects buyer's payment details (where vendor sends fiat).
// For BUY ads: buyer is selling their USDC to the vendor (no buyer details needed).
// ─────────────────────────────────────────────────────────────────────────────
class _TradeConfirmSheet extends ConsumerStatefulWidget {
  final AdListing ad;
  final AzamanColors colors;
  const _TradeConfirmSheet({required this.ad, required this.colors});

  @override
  ConsumerState<_TradeConfirmSheet> createState() => _TradeConfirmSheetState();
}

class _TradeConfirmSheetState extends ConsumerState<_TradeConfirmSheet> {
  final TextEditingController _usdCtrl = TextEditingController();
  double _usdcAmount = 0.0;
  bool _showPaymentFields = false;

  // Buyer payment detail controllers (for SELL ads)
  final Map<String, TextEditingController> _paymentControllers = {};

  void _calc(String val) {
    final usd = double.tryParse(val) ?? 0.0;
    // Phase F2: 1:1 parity — USD amount = USDC amount
    setState(() => _usdcAmount = usd);
  }

  @override
  void dispose() {
    _usdCtrl.dispose();
    for (final ctrl in _paymentControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  /// Get the fields the buyer needs to fill for this SELL ad's payment method
  List<String> _getBuyerFields() {
    final method = widget.ad.paymentMethod.toUpperCase();
    switch (method) {
      case 'ZELLE':
        return ['email', 'phone'];
      case 'CASHAPP':
        return ['cashtag'];
      case 'VENMO':
        return ['username', 'phone'];
      case 'PAYPAL':
        return ['email'];
      case 'APPLE_PAY':
        return ['phone'];
      case 'GOOGLE_PAY':
        return ['email', 'phone'];
      case 'WISE':
        return ['email'];
      case 'REVOLUT':
        return ['username', 'phone'];
      case 'GIFT_CARD':
        return ['cardType'];
      case 'WESTERN_UNION':
        return ['fullName', 'country'];
      case 'WIRE_TRANSFER':
        return ['bankName', 'accountNumber'];
      default:
        return ['email'];
    }
  }

  String _fieldLabel(String field) {
    switch (field) {
      case 'email': return 'Your Email';
      case 'phone': return 'Your Phone (+1...)';
      case 'cashtag': return 'Your \$Cashtag';
      case 'username': return 'Your @Username';
      case 'fullName': return 'Your Full Name';
      case 'country': return 'Your Country';
      case 'cardType': return 'Card Type';
      case 'bankName': return 'Your Bank Name';
      case 'accountNumber': return 'Your Account Number';
      default: return field;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final ad = widget.ad;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isSellAd = ad.isSellAd;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + keyboardHeight),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: c.glow.withOpacity(0.15), width: 1),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Trade with ${ad.vendorUsername}',
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            // Phase F2: Show ad type badge + payment method (no GHS rate)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSellAd
                        ? c.success.withOpacity(0.15)
                        : c.danger.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isSellAd ? 'BUY USDC' : 'SELL USDC',
                    style: TextStyle(
                      color: isSellAd ? c.success : c.danger,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'via ${ad.paymentMethod}  ·  2% fee',
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Primary currency input (USD)
            TextField(
              controller: _usdCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: _calc,
              style: TextStyle(color: c.textPrimary, fontSize: 18),
              decoration: InputDecoration(
                labelText: 'Amount (USD)',
                labelStyle: TextStyle(color: c.textTertiary, fontSize: 13),
                prefixText: '\$ ',
                prefixStyle: TextStyle(color: c.glow, fontWeight: FontWeight.w600),
                hintText: '${ad.minLimit.toStringAsFixed(0)} – ${ad.maxLimit.toStringAsFixed(0)}',
                hintStyle: TextStyle(color: c.textTertiary, fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),
            // USDC equivalent (1:1 parity)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.glow.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.glow.withOpacity(0.15), width: 0.8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSellAd ? 'You receive' : 'You send',
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '1 USDC = 1 USD (stable)',
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${_usdcAmount.toStringAsFixed(2)} USDC',
                    style: TextStyle(
                        color: c.glow,
                        fontSize: 16,
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),

            // Phase F2: For SELL ads, buyer must provide their payment details
            // (so the vendor knows where to validate the inbound payment).
            //
            // SELL ad direction = vendor SELLs USDC, user BUYs USDC by sending
            // fiat externally. Earlier copy here ("The vendor will send fiat
            // to this account.") was inverted; corrected below.
            if (isSellAd) ...[
              const SizedBox(height: 20),
              Text(
                'Your Payment Details',
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'You will send fiat from this account to the vendor — '
                'they verify the inbound payment, then release USDC to you.',
                style: TextStyle(color: c.textTertiary, fontSize: 11),
              ),
              const SizedBox(height: 12),
              ..._getBuyerFields().map((field) {
                _paymentControllers.putIfAbsent(field, () => TextEditingController());
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _paymentControllers[field],
                    style: TextStyle(color: c.textPrimary, fontSize: 14),
                    keyboardType: field == 'phone' || field == 'accountNumber'
                        ? TextInputType.phone
                        : field == 'email'
                            ? TextInputType.emailAddress
                            : TextInputType.text,
                    decoration: InputDecoration(
                      labelText: _fieldLabel(field),
                      labelStyle: TextStyle(color: c.textTertiary, fontSize: 12),
                      filled: true,
                      fillColor: c.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.glow),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                );
              }),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _usdcAmount > 0 ? () => _submitTrade(context) : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Confirm Trade',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitTrade(BuildContext context) async {
    final usd = double.tryParse(_usdCtrl.text) ?? 0.0;
    
    // Validation
    if (usd < widget.ad.minLimit || usd > widget.ad.maxLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Amount must be between \$${widget.ad.minLimit.toStringAsFixed(0)} and \$${widget.ad.maxLimit.toStringAsFixed(0)}',
            style: TextStyle(color: widget.colors.textPrimary),
          ),
          backgroundColor: widget.colors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Phase F2: For SELL ads, validate buyer payment details
    Map<String, dynamic>? buyerDetails;
    if (widget.ad.isSellAd) {
      buyerDetails = {};
      for (final entry in _paymentControllers.entries) {
        final val = entry.value.text.trim();
        if (val.isNotEmpty) {
          buyerDetails[entry.key] = val;
        }
      }
      // Must have at least one field filled
      if (buyerDetails.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please provide your payment details so the vendor can send you fiat.',
              style: TextStyle(color: widget.colors.textPrimary),
            ),
            backgroundColor: widget.colors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // Show loading state
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(widget.colors.glow),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Initiating trade...',
              style: TextStyle(color: widget.colors.textPrimary),
            ),
          ],
        ),
        backgroundColor: widget.colors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      // Phase N: initiateTrade now returns a result distinguishing queued vs immediate
      final result = await ref.read(adsProvider.notifier).initiateTrade(
        adId: widget.ad.id,
        amountFiat: usd,
        amountCrypto: _usdcAmount,
        paymentMethod: widget.ad.paymentMethod,
        buyerPaymentDetails: buyerDetails,
      );

      if (!context.mounted) return;

      if (result.queued) {
        // Phase N: Navigate to WaitingRoomScreen when vendor is at capacity
        ScaffoldMessenger.of(context).clearSnackBars();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WaitingRoomScreen(
              queuePosition: result.queuePosition ?? 1,
              queueId: result.queueId ?? '',
              adId: result.adId ?? widget.ad.id,
            ),
          ),
        );
      } else {
        // Immediate trade — navigate to ActiveTradeScreen
        ScaffoldMessenger.of(context).clearSnackBars();
        if (result.tradeId != null && result.tradeId!.isNotEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ActiveTradeScreen(
                orderId: '#${result.tradeId}',
                amount: _usdcAmount,
                paymentMethod: widget.ad.paymentMethod,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Trade initiated successfully! Check your active trades.',
                style: TextStyle(color: widget.colors.textPrimary),
              ),
              backgroundColor: widget.colors.success,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      // Error feedback
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to initiate trade: ${e.toString()}',
              style: TextStyle(color: widget.colors.textPrimary),
            ),
            backgroundColor: widget.colors.danger,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}
