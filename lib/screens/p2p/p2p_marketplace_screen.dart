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
    // FIX (2026-07-06): pull-to-refresh on the P2P page never actually
    // refreshed the AZM rewards bar's data -- AzmRewardNotifier.refresh()
    // existed for exactly this but nothing here called it, so the bar could
    // go stale even though the pull-to-refresh spinner ran. Also feeds the
    // progress-bar fill-up animation via ref.listen in _AzmProgressBar.
    // ignore: discarded_futures
    ref.read(azmRewardProvider.notifier).refresh();
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

  // FIX (2026-07-06): this card must look identical no matter which app
  // theme (Light / Dark / Midnight) is active — it's a "physical bank
  // card" metaphor, like the plastic card in your wallet doesn't change
  // color when your phone switches to dark mode. Previously it read
  // colors.accent + colors.isDark from the live theme, which meant the
  // Midnight theme's violet accent (0xFFBB86FC) bled into what's supposed
  // to be a fixed gold-on-carbon card, and the Light theme softened the
  // sheen/gradient. Fixed by hardcoding a permanent brand palette here
  // instead of reading from ref.watch(themeProvider) for anything visual.
  static const Color _cardAccent = Color(0xFFD4AF37); // permanent card gold — not the theme accent
  static const Color _gradTopBase = Color(0xFF0E1116);
  static const Color _gradBottom = Color(0xFF05070A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(hologramBalanceProvider);
    final visible = ref.watch(balanceVisibleProvider);

    // Premium "bank card" treatment — deep carbon-to-black gradient with a
    // fixed gold sheen (never the app's switchable theme accent), a faint
    // chip glyph, a brand wordmark, and a slow diagonal glass sheen so it
    // reads as a real card in the wallet, unaffected by theme switching.
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          // FIX (2026-07-08): this was a bare non-positioned Container with
          // no width/height/child. This Stack sits inside a
          // SingleChildScrollView -> Column, which gives it UNBOUNDED
          // height -- and a childless Container with no explicit size
          // collapses to ~zero size under unbounded constraints (it only
          // "expands to fill" when the incoming constraints are bounded).
          // So this background gradient/border/shadow layer was never
          // actually painting across the card's real area at all -- the
          // visible card size came entirely from the content Padding below
          // (which has real intrinsic height), while this decorative layer
          // rendered as a sliver nobody could see. It happened to be masked
          // in Dark/Midnight themes because the Scaffold surface behind it
          // is already near-black, coincidentally similar to the intended
          // card gradient -- but in Light theme the Scaffold surface is
          // cream/white, so the card looked washed-out/blank with only the
          // gold accents (chip, AZAMAN wordmark, ring) still visible and
          // the white balance text unreadable against the light backdrop.
          // Wrapping in Positioned.fill (matching the ring/sheen layers
          // below, which were already correctly positioned) makes this
          // layer explicitly stretch to the Stack's real resolved size.
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(_cardAccent.withOpacity(0.16), _gradTopBase),
                    _gradBottom,
                  ],
                ),
                border: Border.all(color: _cardAccent.withOpacity(0.22), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: _cardAccent.withOpacity(0.14),
                    blurRadius: 28,
                    spreadRadius: -6,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
            ),
          ),
          // Faint decorative card texture — soft ring, top-right.
          Positioned(
            right: -40,
            top: -50,
            child: IgnorePointer(
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _cardAccent.withOpacity(0.10), width: 22),
                ),
              ),
            ),
          ),
          // Slow diagonal glass sheen sweep — the one "subtle animation" cue.
          // Fixed opacity — the card is permanently dark, so this no longer
          // needs to soften for the Light theme.
          Positioned.fill(
            child: IgnorePointer(
              child: _CardSheen(color: Colors.white.withOpacity(0.05)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _cardAccent.withOpacity(0.85),
                            _cardAccent.withOpacity(0.45),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Cash Balance',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'AZAMAN',
                      style: TextStyle(
                        color: _cardAccent.withOpacity(0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'GH₵',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
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
                          style: const TextStyle(
                            color: Colors.white,
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
                        colors: ref.watch(themeProvider).colors,
                        label: 'Add money',
                        onDarkCard: true,
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
                        colors: ref.watch(themeProvider).colors,
                        label: 'Withdraw',
                        onDarkCard: true,
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
  // True when this pill sits on the dark _CashBalanceCard gradient — needs
  // a light/translucent treatment instead of the theme's default surface
  // color so it stays legible in both light and dark app themes.
  final bool onDarkCard;

  const _BalancePill({
    required this.colors,
    required this.label,
    required this.onTap,
    this.onDarkCard = false,
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
    final bgColor = widget.onDarkCard ? Colors.white.withOpacity(0.14) : c.surface;
    final textColor = widget.onDarkCard ? Colors.white : c.textPrimary;

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
            color: bgColor,
            borderRadius: BorderRadius.circular(26),
            border: widget.onDarkCard
                ? Border.all(color: Colors.white.withOpacity(0.16))
                : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: textColor,
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
// Card sheen — a slow diagonal glass highlight band that sweeps across the
// balance card on a loop, giving it the subtle "premium card" shimmer.
// ─────────────────────────────────────────────────────────────────────────────
class _CardSheen extends StatefulWidget {
  final Color color;
  const _CardSheen({required this.color});

  @override
  State<_CardSheen> createState() => _CardSheenState();
}

class _CardSheenState extends State<_CardSheen> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w <= 0 || !w.isFinite) return const SizedBox.shrink();
        return ClipRect(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              // Slow diagonal band sweeps left-to-right and loops.
              final t = Curves.easeInOutSine.transform(_ctrl.value);
              final dx = -w * 0.7 + t * w * 1.9;
              return Transform.translate(
                offset: Offset(dx, 0),
                child: Transform.rotate(
                  angle: -0.4,
                  child: Container(
                    width: w * 0.30,
                    height: w * 2.4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          widget.color,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AzmProgressBar extends ConsumerStatefulWidget {
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
  ConsumerState<_AzmProgressBar> createState() => _AzmProgressBarState();
}

class _AzmProgressBarState extends ConsumerState<_AzmProgressBar>
    with SingleTickerProviderStateMixin {
  // FIX (2026-07-06): the fill bar used to jump straight to its value with
  // no animation at all. Now it always animates FROM its current on-screen
  // value TO the freshly computed target -- 0 -> X the first time the P2P
  // page mounts, and old -> new every time pull-to-refresh (or a realtime
  // AZM credit) changes the underlying total, so progress genuinely reads
  // as "gaining ground" rather than a static bar.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late Animation<double> _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  double _lastTarget = 0.0;
  bool _primed = false;

  ({double threshold, String label}) _nextMilestone(double total) {
    return _AzmProgressBar._milestones.firstWhere(
      (m) => m.threshold > total,
      orElse: () => (threshold: _AzmProgressBar._milestones.last.threshold, label: 'AZM Legend'),
    );
  }

  double _computeProgress(double total) {
    final next = _nextMilestone(total);
    final prevIdx = _AzmProgressBar._milestones.indexWhere((m) => m.threshold == next.threshold) - 1;
    final prevThreshold = prevIdx >= 0 ? _AzmProgressBar._milestones[prevIdx].threshold : 0.0;
    final band = next.threshold - prevThreshold;
    final earned = (total - prevThreshold).clamp(0.0, band);
    return band > 0 ? earned / band : 1.0;
  }

  void _animateTo(double target) {
    if ((target - _lastTarget).abs() < 0.0001) return;
    _lastTarget = target;
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl
      ..value = _primed ? _ctrl.value : 0.0
      ..animateTo(target.clamp(0.0, 1.0), curve: Curves.easeOutCubic);
    _primed = true;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors   = ref.watch(themeProvider).colors;
    final azmBal   = ref.watch(azmBalanceProvider);

    // Re-run the fill-up animation whenever the reward summary changes --
    // covers both the initial page-open load and every pull-to-refresh.
    ref.listen(azmRewardProvider, (prev, next) {
      final total = next.summary?.totalEarned ?? azmBal;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animateTo(_computeProgress(total));
      });
    });

    final stateVal = ref.watch(azmRewardProvider);
    final summary  = stateVal.summary;
    final total    = summary?.totalEarned ?? azmBal;

    final next = _nextMilestone(total);
    final prevIdx = _AzmProgressBar._milestones.indexWhere((m) => m.threshold == next.threshold) - 1;
    final prevThreshold = prevIdx >= 0 ? _AzmProgressBar._milestones[prevIdx].threshold : 0.0;
    final remaining = (next.threshold - total).clamp(0.0, double.infinity);
    final isMaxed = total >= _AzmProgressBar._milestones.last.threshold;

    final targetProgress = _computeProgress(total);
    if (!_primed) {
      // First frame: kick off the 0 -> target fill on page open.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animateTo(targetProgress);
      });
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AzmRewardsScreen()));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        // Slimmer, more restrained padding than before.
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.accent.withOpacity(0.13),
              const Color(0xFFD4AF37).withOpacity(0.07),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.accent.withOpacity(0.22)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD4AF37).withOpacity(0.16),
              ),
              child: const Center(
                child: Icon(HugeIconsSolid.flash, size: 13, color: Color(0xFFD4AF37)),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                isMaxed ? 'AZM Legend — Max Tier!' : 'Next: ${next.label}',
                style: TextStyle(color: colors.textPrimary,
                  fontSize: 12.5, fontWeight: FontWeight.w800)),
              Text(
                isMaxed
                  ? '${total.toStringAsFixed(0)} AZM earned'
                  : '${remaining.toStringAsFixed(0)} AZM to go  ·  ${total.toStringAsFixed(0)} earned',
                style: TextStyle(color: colors.textSecondary, fontSize: 10.5)),
            ])),
            Icon(HugeIconsSolid.arrowRight01, size: 14, color: colors.textTertiary),
          ]),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: _anim,
            builder: (context, _) => ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _anim.value.clamp(0.0, 1.0),
                backgroundColor: colors.divider.withOpacity(0.4),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                minHeight: 5,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${prevThreshold.toStringAsFixed(0)} AZM',
                style: TextStyle(color: colors.textTertiary, fontSize: 8.5)),
              Text('${next.threshold.toStringAsFixed(0)} AZM',
                style: TextStyle(color: colors.textTertiary, fontSize: 8.5)),
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

