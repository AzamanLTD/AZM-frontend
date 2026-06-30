import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/screens/withdrawal_screen.dart';
import 'package:azaman/screens/savings_screen.dart';
import 'package:azaman/screens/azm_rewards_screen.dart';
import 'package:azaman/screens/profile_screen.dart';
import 'package:azaman/screens/susu/susu_hub_screen.dart';
import 'package:azaman/screens/p2p/p2p_market_list_screen.dart';
import 'package:azaman/widgets/routed_tab_surface.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/providers/azm_reward_provider.dart';
import 'package:azaman/services/azm_reward_service.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';


class P2PMarketplaceScreen extends ConsumerStatefulWidget {
  const P2PMarketplaceScreen({super.key});

  @override
  ConsumerState<P2PMarketplaceScreen> createState() =>
      _P2PMarketplaceScreenState();
}

class _P2PMarketplaceScreenState extends ConsumerState<P2PMarketplaceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(azmRewardProvider.notifier).primeIfNeeded();
    });
  }

  Future<void> _onRefresh() async {
    HapticFeedback.mediumImpact();
    final auth = ref.read(authProvider);
    if (auth.user?.id != null) {
      // ignore: discarded_futures
      auth.fetchUserDetails();
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: colors.accent,
          backgroundColor: colors.card,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const _MoneyHeader(),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: _CashBalanceCard(),
                ),
                const SizedBox(height: 24),
                const _AzmProgressBar(),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _FeatureGrid(colors: colors),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — "Money" title + profile avatar
// ─────────────────────────────────────────────────────────────────────────────
class _MoneyHeader extends ConsumerWidget {
  const _MoneyHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final username = ref.watch(
      currentUserProvider.select((a) => a.value?.username ?? ''),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 0),
      child: Row(
        children: [
          Text(
            'Money',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.softSurface,
              ),
              child: Text(
                _initials(username),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, curve: Curves.easeOut);
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'A';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cash Balance card — balance + Add money / Withdraw pills
// ─────────────────────────────────────────────────────────────────────────────
class _CashBalanceCard extends ConsumerWidget {
  const _CashBalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final balance = ref.watch(hologramBalanceProvider);
    final visible = ref.watch(balanceVisibleProvider);

    return Container(
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Cash Balance',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
                child: Row(
                  children: [
                    Text(
                      'Account details',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(HugeIconsSolid.arrowRight01,
                        size: 15, color: colors.textTertiary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'GH₵',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    visible ? _fmt(balance) : '••••••',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.4,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _BalancePill(
                  colors: colors,
                  label: 'Add money',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DepositScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BalancePill(
                  colors: colors,
                  label: 'Withdraw',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const WithdrawalScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 340.ms, curve: Curves.easeOut).slideY(
          begin: 0.06,
          end: 0,
          curve: Curves.easeOutCubic,
        );
  }

  String _fmt(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    }
    final parts = value.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? parts[1] : '00';
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    return '$buffer.$decPart';
  }
}

class _BalancePill extends StatefulWidget {
  final AzamanColors colors;
  final String label;
  final VoidCallback onTap;

  const _BalancePill({
    required this.colors,
    required this.label,
    required this.onTap,
  });

  @override
  State<_BalancePill> createState() => _BalancePillState();
}

class _BalancePillState extends State<_BalancePill> {
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
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _AzmProgressBar extends ConsumerWidget {
  const _AzmProgressBar();

  static const List<({double threshold, String label})> _milestones = [
    (threshold: 50,    label: 'Trader I'),
    (threshold: 100,   label: 'Trader II'),
    (threshold: 250,   label: 'Verified Trader'),
    (threshold: 500,   label: 'Power Trader'),
    (threshold: 1000,  label: 'Elite Trader'),
    (threshold: 2500,  label: 'Diamond Trader'),
    (threshold: 5000,  label: 'AZM Legend'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors   = ref.watch(themeProvider).colors;
    final azmBal   = ref.watch(azmBalanceProvider);
    final stateVal = ref.watch(azmRewardProvider);
    final summary  = stateVal.summary;
    final total    = summary?.totalEarned ?? azmBal;

    final next = _milestones.firstWhere(
      (m) => m.threshold > total,
      orElse: () => (threshold: _milestones.last.threshold, label: 'AZM Legend'),
    );
    final prevIdx = _milestones.indexWhere((m) => m.threshold == next.threshold) - 1;
    final prevThreshold = prevIdx >= 0 ? _milestones[prevIdx].threshold : 0.0;
    final band    = next.threshold - prevThreshold;
    final earned  = (total - prevThreshold).clamp(0.0, band);
    final progress = band > 0 ? earned / band : 1.0;
    final remaining = (next.threshold - total).clamp(0.0, double.infinity);
    final isMaxed = total >= _milestones.last.threshold;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AzmRewardsScreen()));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.accent.withOpacity(0.14),
              const Color(0xFFD4AF37).withOpacity(0.08),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.accent.withOpacity(0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD4AF37).withOpacity(0.15),
              ),
              child: const Center(child: Text('⚡', style: TextStyle(fontSize: 16))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                isMaxed ? 'AZM Legend — Max Tier!' : 'Next: ${next.label}',
                style: TextStyle(color: colors.textPrimary,
                  fontSize: 13, fontWeight: FontWeight.w800)),
              Text(
                isMaxed
                  ? '${total.toStringAsFixed(0)} AZM earned'
                  : '${remaining.toStringAsFixed(0)} AZM to go  ·  ${total.toStringAsFixed(0)} earned',
                style: TextStyle(color: colors.textSecondary, fontSize: 11)),
            ])),
            Icon(HugeIconsSolid.arrowRight01, size: 15, color: colors.textTertiary),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: colors.divider.withOpacity(0.4),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
              minHeight: 7,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${prevThreshold.toStringAsFixed(0)} AZM',
                style: TextStyle(color: colors.textTertiary, fontSize: 9)),
              Text('${next.threshold.toStringAsFixed(0)} AZM',
                style: TextStyle(color: colors.textTertiary, fontSize: 9)),
            ],
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2×2 feature grid — title + chevron, then an image-ready box.
// Drop a gradient image into each card by setting `imageAsset`.
// ─────────────────────────────────────────────────────────────────────────────
class _FeatureGrid extends StatelessWidget {
  final AzamanColors colors;

  const _FeatureGrid({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Explore',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _FeatureCard(
                title: 'Savings',
                imageAsset: 'assets/images/1.webp',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RoutedTabSurface(
                      title: 'Savings',
                      body: SavingsScreen(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FeatureCard(
                title: 'Buy USDC',
                imageAsset: 'assets/images/2.webp',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const P2PMarketListScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _FeatureCard(
                title: 'Susu',
                imageAsset: 'assets/images/3.webp',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SusuHubScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FeatureCard(
                title: 'Marketplace',
                imageAsset: 'assets/images/5.webp',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MarketplaceHomeScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 380.ms, delay: 80.ms, curve: Curves.easeOut);
  }
}

class _FeatureCard extends ConsumerWidget {
  final String title;
  final String? imageAsset;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.title,
    required this.imageAsset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: 172,
        decoration: BoxDecoration(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                Icon(HugeIconsSolid.arrowRight01,
                    size: 16, color: colors.textTertiary),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _ImageBox(imageAsset: imageAsset, colors: colors),
            ),
          ],
        ),
      ),
    );
  }
}

// Empty, image-ready box. Set `imageAsset` to a bundled asset path to fill it.
class _ImageBox extends StatelessWidget {
  final String? imageAsset;
  final AzamanColors colors;

  const _ImageBox({required this.imageAsset, required this.colors});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: colors.surface,
        child: imageAsset == null
            ? null
            : Image.asset(
                imageAsset!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
      ),
    );
  }
}

