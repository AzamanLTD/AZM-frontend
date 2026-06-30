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


const double _kSegmentHeaderHeight = 56.0;

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
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01,
              color: colors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const SizedBox.shrink(),
        actions: [
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  'Buy & sell USDC',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.08,
                  ),
                ),
              ),
            ),
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
                child: _ErrorView(onRetry: _onRefresh),
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
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.softSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          children: [
                            for (int i = 0; i < ads.length; i++)
                              KeyedSubtree(
                                key: _keyFor(ads[i].id),
                                child: VendorAdCard(
                                  ad: ads[i],
                                  showDivider: i < ads.length - 1,
                                  onTap: () => _onCardTapped(
                                    context,
                                    ads[i],
                                    colors,
                                    cardKey: _keyFor(ads[i].id),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
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
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 0 ? constraints.maxWidth : 320.0;
        return Container(
          width: width,
          height: 36,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: colors.softSurface,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              _segment(
                colors: colors,
                label: 'Buy',
                selected: side == UserSide.buy,
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
                onTap: () {
                  if (side == UserSide.sell) return;
                  HapticFeedback.selectionClick();
                  ref.read(userSideProvider.notifier).state = UserSide.sell;
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _segment({
    required AzamanColors colors,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.textPrimary : colors.textTertiary,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingShimmer extends ConsumerWidget {
  const _LoadingShimmer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: List.generate(
            3,
            (i) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 15),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 14,
                              width: 96,
                              decoration: BoxDecoration(
                                color: colors.divider.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 11,
                              width: 140,
                              decoration: BoxDecoration(
                                color: colors.divider.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 14,
                        width: 72,
                        decoration: BoxDecoration(
                          color: colors.divider.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                if (i < 2)
                  Divider(
                    height: 0,
                    thickness: 0.5,
                    indent: 20,
                    color: colors.divider.withValues(alpha: 0.65),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HugeIconsSolid.cloud, size: 28, color: colors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'Markets unavailable',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pull to refresh.',
              style: TextStyle(color: colors.textTertiary, fontSize: 15),
            ),
            const SizedBox(height: 20),
            _SoftPill(
              colors: colors,
              label: 'Retry',
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No offers',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isVendor
                    ? 'Post the first ad to get started.'
                    : 'Check back soon or pull to refresh.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 22),
              if (isVendor)
                _SoftPill(
                  colors: colors,
                  label: 'Create ad',
                  primary: true,
                  onTap: onCreateAd,
                )
              else
                _SoftPill(
                  colors: colors,
                  label: 'Refresh',
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
