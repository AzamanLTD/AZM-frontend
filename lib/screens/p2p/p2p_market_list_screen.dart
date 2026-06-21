import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/marketplace_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/screens/vendor_ad_creator.dart';
import 'package:azaman/screens/waiting_room_screen.dart';
import 'package:azaman/screens/active_trade_screen.dart';
import 'package:azaman/screens/p2p/p2p_filter_sheet.dart';
import 'package:azaman/widgets/vendor_ad_card.dart';
import 'package:azaman/widgets/ad_detail_flip_card.dart';
import 'package:azaman/widgets/p2p_market_summary_bar.dart';
import 'package:hugeicons_pro/hugeicons.dart';

const double _kSegmentHeaderHeight = 64.0;

class P2PMarketListScreen extends ConsumerStatefulWidget {
  const P2PMarketListScreen({super.key});

  @override
  ConsumerState<P2PMarketListScreen> createState() =>
      _P2PMarketListScreenState();
}

class _P2PMarketListScreenState extends ConsumerState<P2PMarketListScreen> {
  final ScrollController _scrollController = ScrollController();
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01,
              color: colors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Text(
          'Buy & sell USDC',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          // Advanced filter button with a live active-count badge.
          Consumer(
            builder: (_, ref, __) {
              final filters = ref.watch(p2pFiltersProvider);
              final count = filters.activeCount;
              return Stack(
                children: [
                  IconButton(
                    icon: Icon(HugeIconsSolid.filterHorizontal,
                        color: colors.textPrimary, size: 20),
                    onPressed: () => P2PFilterSheet.show(context),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 16,
                        height: 16,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: colors.isDark ? Colors.black : Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: colors.accent,
        backgroundColor: colors.card,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _SegmentHeaderDelegate(colors: colors),
            ),
            // Market depth / liquidity summary (P2P Premium Sprint).
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 10),
                child: P2PMarketSummaryBar(),
              ),
            ),
            adsAsync.when(
              loading: () => const SliverToBoxAdapter(child: _LoadingShimmer()),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: _ErrorView(message: e.toString(), onRetry: _onRefresh),
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
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => KeyedSubtree(
                      key: _keyFor(ads[index].id),
                      child: VendorAdCard(
                        ad: ads[index],
                        onTap: () => _onCardTapped(
                          context,
                          ads[index],
                          colors,
                          cardKey: _keyFor(ads[index].id),
                        ),
                      ),
                    ),
                    childCount: ads.length,
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  void _onCardTapped(
    BuildContext ctx,
    AdListing ad,
    AzamanColors colors, {
    required GlobalKey cardKey,
  }) {
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

  Rect? _rectFromKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

  Future<void> _initiateTradeFromFlip(
    BuildContext ctx,
    AdListing ad,
    double amountFiat,
    Map<String, String> buyerDetails,
  ) async {
    try {
      final result = await ref.read(adsProvider.notifier).initiateTrade(
            adId: ad.id.toString(),
            amountFiat: amountFiat,
            amountCrypto: amountFiat,
            paymentMethod: ad.paymentMethod,
            buyerPaymentDetails: buyerDetails.isEmpty ? null : buyerDetails,
          );
      if (!ctx.mounted) return;

      if (result.queued) {
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
}

class _SegmentHeaderDelegate extends SliverPersistentHeaderDelegate {
  final AzamanColors colors;
  const _SegmentHeaderDelegate({required this.colors});

  @override
  double get minExtent => _kSegmentHeaderHeight;
  @override
  double get maxExtent => _kSegmentHeaderHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: colors.background,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      alignment: Alignment.centerLeft,
      child: const _UserSideSegment(),
    );
  }

  @override
  bool shouldRebuild(_SegmentHeaderDelegate old) => old.colors != colors;
}

class _UserSideSegment extends ConsumerWidget {
  const _UserSideSegment();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final side = ref.watch(userSideProvider);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            colors: colors,
            label: 'Buy',
            selected: side == UserSide.buy,
            activeColor: colors.success,
            onTap: () {
              if (side == UserSide.buy) return;
              HapticFeedback.selectionClick();
              ref.read(userSideProvider.notifier).state = UserSide.buy;
            },
          ),
          _segment(
            colors: colors,
            label: 'Sell',
            selected: side == UserSide.sell,
            activeColor: colors.danger,
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

  Widget _segment({
    required AzamanColors colors,
    required String label,
    required bool selected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? activeColor : colors.textTertiary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}

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
      builder: (_, __) => Column(
        children: List.generate(
          4,
          (i) => Container(
            height: 150,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment(_anim.value - 1, 0),
                end: Alignment(_anim.value + 1, 0),
                colors: [
                  colors.softSurface,
                  colors.card,
                  colors.softSurface,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.softSurface,
              ),
              child: Icon(HugeIconsSolid.cloud,
                  size: 32, color: colors.textTertiary),
            ),
            const SizedBox(height: 18),
            Text('Could not load markets',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textTertiary, fontSize: 13)),
            const SizedBox(height: 20),
            _SoftPill(
              colors: colors,
              label: 'Try again',
              primary: true,
              onTap: onRetry,
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

  const _EmptyState({required this.onCreateAd, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final isVendor = ref.watch(isVendorProvider);
    final side = ref.watch(userSideProvider);
    final isBuyTab = side == UserSide.buy;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.softSurface,
                ),
                child: Icon(
                  HugeIconsSolid.store01,
                  size: 34,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                isBuyTab ? 'No buy markets yet' : 'No sell markets yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isVendor
                    ? (isBuyTab
                        ? 'Be the first to sell USDC. Post a sell ad and your inventory shows up here for buyers.'
                        : 'Be the first to buy USDC. Post a buy ad and your bid shows up here for sellers.')
                    : (isBuyTab
                        ? 'No vendors selling USDC right now. Pull to refresh, or check back in a moment.'
                        : 'No vendors buying USDC right now. Pull to refresh, or switch to the Buy tab.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 13.5,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              if (isVendor)
                _SoftPill(
                  colors: colors,
                  label: 'Create first ad',
                  primary: true,
                  onTap: onCreateAd,
                )
              else
                _SoftPill(
                  colors: colors,
                  label: 'Refresh markets',
                  primary: false,
                  onTap: onRefresh,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftPill extends StatefulWidget {
  final AzamanColors colors;
  final String label;
  final bool primary;
  final FutureOr<void> Function() onTap;

  const _SoftPill({
    required this.colors,
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  State<_SoftPill> createState() => _SoftPillState();
}

class _SoftPillState extends State<_SoftPill> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final fg = widget.primary
        ? (c.isDark ? Colors.black : Colors.white)
        : c.textPrimary;
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
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          decoration: BoxDecoration(
            color: widget.primary ? c.accent : c.softSurface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: fg,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}
