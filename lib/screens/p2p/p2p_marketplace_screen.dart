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
import 'package:hugeicons_pro/hugeicons.dart';

class P2PMarketplaceScreen extends ConsumerStatefulWidget {
  const P2PMarketplaceScreen({super.key});

  @override
  ConsumerState<P2PMarketplaceScreen> createState() =>
      _P2PMarketplaceScreenState();
}

class _P2PMarketplaceScreenState extends ConsumerState<P2PMarketplaceScreen> {
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
          child: const SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.only(bottom: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 8),
                _MoneyHeader(),
                SizedBox(height: 20),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: _CashBalanceCard(),
                ),
                SizedBox(height: 24),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: _FeatureGrid(),
                ),
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

// ─────────────────────────────────────────────────────────────────────────────
// 2×2 feature grid — title + chevron, then an image-ready box.
// Drop a gradient image into each card by setting `imageAsset`.
// ─────────────────────────────────────────────────────────────────────────────
class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
                      builder: (_) => const P2PMarketListScreen()),
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
                  MaterialPageRoute(builder: (_) => const SusuHubScreen()),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FeatureCard(
                title: 'Rewards',
                imageAsset: 'assets/images/4.webp',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AzmRewardsScreen()),
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
