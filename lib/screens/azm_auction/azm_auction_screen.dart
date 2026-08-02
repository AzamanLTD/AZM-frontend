// =============================================================================
// AZM AUCTION SCREEN  (Master Sprint, 2026-05-27)
//
// Vendor-facing auction surface:
//   • Window countdown + participant count
//   • "Place / Update Bid" form (vendor picks one of their active ads + AZM)
//   • Current standing bid + status
//   • Promoted ads strip (top 3 boosted)
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/azm_auction_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';


class AzmAuctionScreen extends ConsumerStatefulWidget {
  const AzmAuctionScreen({super.key});

  @override
  ConsumerState<AzmAuctionScreen> createState() => _AzmAuctionScreenState();
}

class _AzmAuctionScreenState extends ConsumerState<AzmAuctionScreen> {
  final _amount = TextEditingController();
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  int? _selectedAdId;
  List<Map<String, dynamic>> _myAds = [];
  bool _loadingAds = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _loadMyAds();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _amount.dispose();
    super.dispose();
  }

  void _tick() {
    final state = ref.read(auctionStateProvider).asData?.value;
    if (state == null) return;
    final remaining = state.windowEnd.difference(DateTime.now());
    if (mounted) {
      setState(() => _remaining = remaining.isNegative ? Duration.zero : remaining);
    }
  }

  Future<void> _loadMyAds() async {
    try {
      final res = await apiClient.get('/p2p/my-ads');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (body['ads'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .where((a) => a['status'] == 'ACTIVE')
            .toList();
        if (mounted) {
          setState(() {
            _myAds = list;
            _loadingAds = false;
            if (list.isNotEmpty) _selectedAdId = (list.first['id'] as num).toInt();
          });
        }
      } else {
        if (mounted) setState(() => _loadingAds = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAds = false);
    }
  }

  Future<void> _placeBid() async {
    final amt = double.tryParse(_amount.text.trim());
    if (amt == null || amt <= 0 || _selectedAdId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick an ad and enter a positive AZM bid.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(auctionActionsProvider)
          .placeBid(adId: _selectedAdId!, amountAzm: amt);
      _amount.clear();
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bid locked. Settlement at midnight.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdrawBid() async {
    setState(() => _busy = true);
    try {
      await ref.read(auctionActionsProvider).withdrawBid();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bid withdrawn.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmtRemaining(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final auctionAsync = ref.watch(auctionStateProvider);
    final myBidAsync = ref.watch(myAuctionBidProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('AZM Auction',
            style: TextStyle(
                color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: AzPullToRefresh(
        onRefresh: () async {
          ref.invalidate(auctionStateProvider);
          ref.invalidate(myAuctionBidProvider);
          ref.invalidate(promotedAdsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            auctionAsync.when(
              loading: () => Column(
                children: [
                  SkeletonBlock(height: 160, width: double.infinity, borderRadius: BorderRadius.circular(16)),
                  const SizedBox(height: 12),
                  SkeletonBlock(height: 48, width: double.infinity, borderRadius: BorderRadius.circular(12)),
                ],
              ),
              error: (e, _) => Text(e.toString()),
              data: (state) {
                if (state == null) {
                  return Text('No active auction', style: TextStyle(color: colors.textTertiary));
                }
                return _Hero(
                  remaining: _fmtRemaining(_remaining),
                  participants: state.participantCount,
                  status: state.status,
                  colors: colors,
                ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.05, end: 0);
              },
            ),
            const SizedBox(height: 18),
            myBidAsync.when(
              loading: () => const SizedBox(height: 60),
              error: (_, __) => const SizedBox(),
              data: (bid) => _MyBidCard(
                bid: bid,
                colors: colors,
                onWithdraw: bid.hasBid ? _withdrawBid : null,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Place / Update Bid',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            _BidForm(
              colors: colors,
              loadingAds: _loadingAds,
              myAds: _myAds,
              selectedAdId: _selectedAdId,
              onAdSelected: (id) => setState(() => _selectedAdId = id),
              amount: _amount,
              busy: _busy,
              onSubmit: _placeBid,
            ),
            const SizedBox(height: 20),
            Text(
              'Currently Boosted',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            _PromotedStrip(colors: colors),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final String remaining;
  final int participants;
  final String status;
  final AzamanColors colors;

  const _Hero({
    required this.remaining,
    required this.participants,
    required this.status,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF6C63FF).withValues(alpha: 0.18),
                const Color(0xFF00E5FF).withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.30),
              width: 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF9D8FFF), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'AZM Auction',
                    style: TextStyle(
                        color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.success.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.success.withValues(alpha: 0.30), width: 0.7),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: colors.success,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                remaining,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text('Until next settlement',
                  style: TextStyle(color: colors.textTertiary, fontSize: 11)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.group_outlined, color: colors.textTertiary, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '$participants vendors bidding',
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
                  const Spacer(),
                  Icon(Icons.local_fire_department_outlined, color: colors.warning, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Top 3 burn AZM, get 24h boost',
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyBidCard extends StatelessWidget {
  final MyBid bid;
  final AzamanColors colors;
  final VoidCallback? onWithdraw;

  const _MyBidCard({required this.bid, required this.colors, required this.onWithdraw});

  @override
  Widget build(BuildContext context) {
    if (!bid.hasBid) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.gavel, color: colors.textTertiary, size: 16),
            const SizedBox(width: 8),
            Text('No active bid', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: colors.accent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Your Bid: ${bid.bidAmountAzm?.toStringAsFixed(2)} AZM',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Ad #${bid.adId}',
                  style: TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
          if (onWithdraw != null)
            TextButton(
              onPressed: onWithdraw,
              child: Text('Withdraw', style: TextStyle(color: colors.danger)),
            ),
        ],
      ),
    );
  }
}

class _BidForm extends StatelessWidget {
  final AzamanColors colors;
  final bool loadingAds;
  final List<Map<String, dynamic>> myAds;
  final int? selectedAdId;
  final ValueChanged<int> onAdSelected;
  final TextEditingController amount;
  final bool busy;
  final VoidCallback onSubmit;

  const _BidForm({
    required this.colors,
    required this.loadingAds,
    required this.myAds,
    required this.selectedAdId,
    required this.onAdSelected,
    required this.amount,
    required this.busy,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    if (loadingAds) {
      return Column(
        children: [
          SkeletonBlock(height: 48, width: double.infinity, borderRadius: BorderRadius.circular(12)),
          const SizedBox(height: 8),
          SkeletonBlock(height: 40, width: double.infinity, borderRadius: BorderRadius.circular(10)),
        ],
      );
    }
    if (myAds.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.divider),
        ),
        child: Text(
          'You need an active P2P ad to bid in the auction.',
          style: TextStyle(color: colors.textTertiary, fontSize: 12),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.divider),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: selectedAdId,
              isExpanded: true,
              dropdownColor: colors.card,
              style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
              items: myAds
                  .map((a) => DropdownMenuItem<int>(
                        value: (a['id'] as num).toInt(),
                        child: Text('Ad #${a['id']} · ${a['paymentMethod'] ?? 'P2P'}'),
                      ))
                  .toList(),
              onChanged: (v) => v != null ? onAdSelected(v) : null,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.divider),
          ),
          child: TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
                color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Bid (AZM)',
              hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
              prefixIcon: Icon(Icons.bolt_outlined, color: colors.accentSecondary, size: 18),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: busy ? null : onSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.accent,
            foregroundColor: colors.isDark ? Colors.black : Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: Text(
            busy ? 'Locking…' : 'Lock Bid',
            style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4),
          ),
        ),
      ],
    );
  }
}

class _PromotedStrip extends ConsumerWidget {
  final AzamanColors colors;
  const _PromotedStrip({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ads = ref.watch(promotedAdsProvider);
    return ads.when(
      loading: () => const SizedBox(height: 60),
      error: (e, _) => Text(e.toString()),
      data: (list) {
        if (list.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.divider),
            ),
            child: Text(
              'No boosted ads right now. Be the first when settlement runs.',
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
          );
        }
        return Column(
          children: list
              .map(
                (a) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.divider, width: 0.6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.local_fire_department_outlined,
                          color: colors.warning, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        'Ad #${a.id}',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        a.paymentMethod,
                        style: TextStyle(color: colors.textTertiary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}
