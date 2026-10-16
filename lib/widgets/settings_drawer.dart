// =============================================================================
// SETTINGS DRAWER — PROFILE HERO, QR & REGROUPED DESTINATIONS
//
// PR-B of the Home/Settings refresh (spec 2026-10-12, §1.4):
//
//   • PROFILE HERO — pinned SliverPersistentHeader at the drawer top. The
//     real profile picture is horizontally centred relative to the DRAWER's
//     own width and protrudes from the hero surface; @username sits below
//     the avatar; the KYC badge and public Azaman ID stay visible; a real
//     scannable QR preview rides beside the identity row and opens a
//     larger scan-ready popup (payload `azaman://user/$username`,
//     end-to-end with the add-friend scanner contract in
//     qr_scanner_screen.dart).
//
//   • SCROLL-DRIVEN AVATAR (Telegram-inspired) — the hero collapses under
//     the content as it scrolls: the avatar sinks toward the collapsed bar
//     purely by interpolating the delegate's own minExtent/maxExtent with
//     shrinkOffset. No scroll listeners, no whole-drawer rebuilds per tick,
//     no idle animation loop. Dimensions derive from the drawer's own
//     constraints; the SafeArea above absorbs the top inset so nothing
//     hardcodes a notch. The morph is position-proportional (no springs),
//     which keeps it reduced-motion safe; the section entrance wraps use
//     MotionTokens.accessibleDuration to collapse travel when the OS asks
//     for reduced motion.
//
//   • HERO TAP opens the genuine profile edit flow. Audited 2026-10-13:
//     ProfileDetailsScreen is a read-only display (avatar, legal name,
//     UID, KYC, account info — no editing), so the genuine edit surface
//     (photo pick, name, bio, phone) is ProfileScreen. The hero therefore
//     routes there; ProfileDetailsScreen remains one tap away in the
//     PROFILE & IDENTITY group.
//
//   • REDESIGNED (Phantom-inspired, 2026-10-16) — the drawer is now
//     identity + destinations, not a second settings hub:
//     • QUICK ACTIONS — Withdraw / Deposit / QR / Refer as icon-first
//       glass pills; management rows live below.
//     • Sentence-case groups: Account (Profile, Verification with the
//       REAL KYC chip), Money (merged saved-accounts card, Currency with
//       the live value, Azaman Store), Security (Security & PIN with the
//       REAL biometric chip from BiometricService).
//     • Decorative one-word badges, the gear shortcut and the ALL-CAPS
//       enterprise labels are GONE; state chips show real values only
//       (empty state renders no chip at all).
//     • One 'All settings' row routes to the canonical /settings page
//       (AzRoutes.settings); the footer reads 'Azaman 3.1'.
//     • _WorkerCard (role-valid only) and the pinned scroll-driven
//       hero survive untouched.
//
// The "Eclipse Glow" backdrop (single static RadialGradient halo, no
// painters/scan-lines) and the frosted-glass shell are preserved.
// =============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/models/currency_model.dart';
import 'package:azaman/screens/kyc_verification_screen.dart';
import 'package:azaman/screens/referral_screen.dart';
import 'package:azaman/services/biometric_service.dart';
import 'package:azaman/providers/worker_provider.dart';
import 'package:azaman/screens/profile_details_screen.dart';
import 'package:azaman/screens/profile_screen.dart';
import 'package:azaman/screens/saved_momo_accounts_screen.dart';
import 'package:azaman/screens/saved_wallets_screen.dart';
import 'package:azaman/screens/security_settings.dart';
import 'package:azaman/screens/share_profile_screen.dart';
import 'package:azaman/screens/withdrawal_screen.dart';
import 'package:azaman/screens/azaman_store_screen.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/qr_profile_popup.dart';

class SettingsDrawer extends ConsumerStatefulWidget {
  const SettingsDrawer({super.key});

  @override
  ConsumerState<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends ConsumerState<SettingsDrawer> {
  // Real state for the Security chip — loaded from the same store the
  // Security Center screen reads (BiometricService.isEnabled). No fake
  // badges: if biometrics are off the chip simply doesn't render.
  bool _biometricsOn = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final enabled = await BiometricService().isEnabled;
    if (mounted) setState(() => _biometricsOn = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final colors = ref.watch(themeProvider).colors;
    final user = ref.watch(currentUserProvider).value;
    // Business profile state is prefetched below and consumed by the
    // Marketplace floating action button, not rendered in this drawer.

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.read(myBusinessProvider).hasLoaded &&
          !ref.read(myBusinessProvider).isLoading) {
        ref.read(myBusinessProvider.notifier).load();
      }
    });

    final username = (user?.username.isNotEmpty ?? false)
        ? user!.username
        : 'Guest';

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.88,
      backgroundColor: Colors.transparent,
      // Frosted-glass drawer: BackdropFilter blurs only the drawer area;
      // the inner content sits on a tinted glass card so foreground copy
      // reads cleanly without losing the underlying scenery.
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Stack(
            children: [
              // Tinted glass card — 92% in light mode for a readable
              // frosted surface, 72% in dark/midnight where the dark
              // background already provides contrast.
              Positioned.fill(
                child: ColoredBox(
                  color: colors.background.withValues(
                    alpha: colors.isDark ? 0.72 : 0.92,
                  ),
                ),
              ),
              const Positioned.fill(child: _EclipseGlow()),

              SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                          // ── PROFILE HERO (pinned, scroll-driven) ──────
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _ProfileHeroDelegate(
                              username: username,
                              user: user,
                            ),
                          ),

                          // ── QUICK ACTIONS ──────────────────────────────
                          // Actions live here; management lives in the
                          // groups below and everything else in Settings.
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate([
                                _animatedWrapper(
                                  context,
                                  delay: 3,
                                  child: _buildQuickActions(context, colors),
                                ),
                              ]),
                            ),
                          ),

                          // ── GROUPS ─────────────────────────────────────
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate([
                                _animatedWrapper(
                                  context,
                                  delay: 4,
                                  child: _buildGroup(
                                    context,
                                    colors,
                                    label: 'Account',
                                    rows: [
                                      _buildMenuItem(
                                        context,
                                        Icons.person_outline,
                                        'Profile',
                                        colors,
                                        destination:
                                            const ProfileDetailsScreen(),
                                      ),
                                      _buildMenuItem(
                                        context,
                                        Icons.verified_user_outlined,
                                        'Verification',
                                        colors,
                                        chip: _kycChip(ref),
                                        destination:
                                            const KycVerificationScreen(),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _animatedWrapper(
                                  context,
                                  delay: 5,
                                  child: _buildGroup(
                                    context,
                                    colors,
                                    label: 'Money',
                                    rows: [
                                      _savedAccountsCard(context, colors),
                                      const SizedBox(height: 4),
                                      _buildMenuItem(
                                        context,
                                        Icons.attach_money,
                                        'Currency',
                                        colors,
                                        chip: ref
                                            .watch(currencyProvider)
                                            .name
                                            .toUpperCase(),
                                        onTapOverride: () =>
                                            _pickCurrency(context, colors),
                                      ),
                                      _buildMenuItem(
                                        context,
                                        Icons.storefront_outlined,
                                        'Azaman Store',
                                        colors,
                                        destination:
                                            const AzamanStoreScreen(),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _animatedWrapper(
                                  context,
                                  delay: 6,
                                  child: _buildGroup(
                                    context,
                                    colors,
                                    label: 'Security',
                                    rows: [
                                      _buildMenuItem(
                                        context,
                                        Icons.lock_outline,
                                        'Security & PIN',
                                        colors,
                                        chip: _biometricsOn
                                            ? 'Biometrics on'
                                            : null,
                                        destination:
                                            const SecuritySettingsScreen(),
                                      ),
                                    ],
                                  ),
                                ),

                                // ── BUSINESS TOOLS (role-valid only) ────
                                // _WorkerCard renders nothing unless the
                                // signed-in user is an active employee.
                                _animatedWrapper(
                                  context,
                                  delay: 7,
                                  child: _WorkerCard(colors: colors),
                                ),

                                const SizedBox(height: 14),

                                // ── CANONICAL SETTINGS ──────────────────
                                // The drawer is identity + destinations;
                                // every preference control lives once, in
                                // the Settings page.
                                _animatedWrapper(
                                  context,
                                  delay: 8,
                                  child: _buildAllSettingsRow(
                                    context,
                                    colors,
                                  ),
                                ),

                                const SizedBox(height: 24),
                                Center(
                                  child: Text(
                                    'Azaman 3.1',
                                    style: TextStyle(
                                      color: colors.textTertiary,
                                      fontSize: 9,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
]),
                            ),
                          ),
                        ],
                      ),
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

  // ──────────────────────────────────────────────────────────────────────────
  // QUICK ACTIONS — the four things people actually open the drawer for.
  // Circular glass buttons, icon-first, labels underneath. These are
  // ACTIONS; management rows live in the groups below.
  Widget _buildQuickActions(BuildContext context, AzamanColors colors) {
    Widget action(
      IconData icon,
      String label,
      VoidCallback onTap,
    ) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
            onTap();
          },
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : colors.softSurface,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: colors.divider),
                ),
                child: Icon(icon, color: colors.accent, size: 21),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        action(
          Icons.arrow_outward,
          'Withdraw',
          () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const WithdrawalScreen()),
          ),
        ),
        action(
          Icons.arrow_downward,
          'Deposit',
          () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const SavedMomoAccountsScreen()),
          ),
        ),
        action(
          Icons.qr_code_2,
          'QR',
          () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ShareProfileScreen()),
          ),
        ),
        action(
          Icons.card_giftcard_outlined,
          'Refer',
          () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ReferralScreen()),
          ),
        ),
      ],
    );
  }

  /// Sentence-case group: a small muted label above the rows. No caps, no
  /// enterprise shouting — the rows are the hierarchy.
  Widget _buildGroup(
    BuildContext context,
    AzamanColors colors, {
    required String label,
    required List<Widget> rows,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(label, colors: colors),
        const SizedBox(height: 6),
        ...rows,
      ],
    );
  }

  /// The merged saved-accounts card: deposit (MoMo) and payout
  /// destinations sit side by side as ONE physical concept.
  Widget _savedAccountsCard(BuildContext context, AzamanColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.isDark
            ? Colors.white.withValues(alpha: 0.025)
            : colors.softSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          _buildSlenderTile(
            context,
            colors,
            title: 'MoMo deposits',
            subtitle: 'Saved accounts for STK-push',
            icon: Icons.arrow_downward,
            iconColor: colors.success,
            destination: const SavedMomoAccountsScreen(),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: colors.divider,
            indent: 56,
          ),
          _buildSlenderTile(
            context,
            colors,
            title: 'Payout destinations',
            subtitle: 'Where withdrawals land',
            icon: Icons.arrow_upward,
            iconColor: colors.warning,
            destination: const SavedWalletsScreen(),
          ),
        ],
      ),
    );
  }

  /// The single drawer affordance for the canonical Settings page.
  Widget _buildAllSettingsRow(BuildContext context, AzamanColors colors) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).pop();
        context.push(AzRoutes.settings);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colors.accent.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.tune, color: colors.accent, size: 17),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'All settings',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.arrow_forward, color: colors.accent, size: 16),
          ],
        ),
      ),
    );
  }

  /// Real KYC state chip — the same KycStatus the backend returns. No
  /// decoration: unverified renders no chip at all.
  String? _kycChip(WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    switch (user?.kycStatus) {
      case KycStatus.verified:
        return 'Verified';
      case KycStatus.pending:
        return 'Pending';
      case KycStatus.rejected:
        return 'Action needed';
      default:
        return null;
    }
  }

  Future<void> _pickCurrency(BuildContext context, AzamanColors colors) async {
    HapticFeedback.lightImpact();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            for (final option in const ['USDC', 'GHS'])
              ListTile(
                title: Text(
                  option,
                  style: TextStyle(color: colors.textPrimary),
                ),
                onTap: () => Navigator.pop(sheet, option),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) {
      await ref
          .read(currencyProvider.notifier)
          .set(picked == 'GHS' ? DisplayCurrency.ghs : DisplayCurrency.usdc);
    }
  }

  Widget _buildSectionHeader(String title, {required AzamanColors colors}) {
    return Text(
      title,
      style: TextStyle(
        color: colors.textTertiary,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildSlenderTile(
    BuildContext context,
    AzamanColors colors, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    Widget? destination,
    String? route,
    VoidCallback? onTapOverride,
  }) {
    // Slender list-tile pattern: same hit target, ~40% less vertical chrome
    // than the retired chunky tile — icon plate 32×32, single-line
    // subtitle, hairline chevron.
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (onTapOverride != null) {
          HapticFeedback.lightImpact();
          onTapOverride();
          return;
        }
        if (route != null) {
          // NEW-A: canonical route is authoritative.
          HapticFeedback.lightImpact();
          Navigator.of(context).pop();
          context.push(route);
        } else if (destination != null) {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => destination),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textTertiary, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, color: colors.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String title,
    AzamanColors colors, {
    String? chip,
    Widget? destination,
    String? route,
    VoidCallback? onTapOverride,
  }) {
    return _SlenderMenuTile(
      colors: colors,
      icon: icon,
      title: title,
      chip: chip,
      // NEW-A: when the destination has a canonical route, the route is
      // authoritative; the widget push remains only for screens without a
      // GoRoute yet.
      onTap: onTapOverride ??
          ((destination == null && route == null)
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop();
                  if (route != null) {
                    context.push(route);
                  } else {
                    Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (_) => destination!));
                  }
                }),
    );
  }

  Widget _animatedWrapper(
    BuildContext context, {
    required int delay,
    required Widget child,
  }) {
    // Reduced motion: the OS-level disableAnimations flag collapses the
    // entrance duration to zero so sections simply appear.
    final duration = MotionTokens.accessibleDuration(
      context,
      Duration(milliseconds: 500 + (delay * 100)),
    );
    return TweenAnimationBuilder<Offset>(
      tween: Tween(begin: const Offset(40, 0), end: Offset.zero),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, Offset offset, child) => Transform.translate(
        offset: offset,
        child: Opacity(
          opacity: (1.0 - (offset.dx / 40)).clamp(0.0, 1.0),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

// =============================================================================
// ECLIPSE GLOW BACKDROP
//
// Pure gradient: a single soft RadialGradient halo radiating from roughly
// the top-center of the drawer over a pitch-dark base. No painters, no
// animation, no scan lines, no grids. Kept low-opacity so foreground
// content remains the focal point.
// =============================================================================
class _EclipseGlow extends ConsumerWidget {
  const _EclipseGlow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Base is the scaffold background with a touch deeper to read
          // as a true "eclipse" silhouette behind the soft halo.
          color: Color.alphaBlend(
            Colors.black.withValues(alpha: 0.18),
            colors.background,
          ),
          gradient: RadialGradient(
            // Halo origin sits slightly above-and-left of center so the
            // glow falls naturally onto the profile hero area.
            center: const Alignment(-0.15, -0.85),
            radius: 1.15,
            colors: [
              colors.accent.withValues(alpha: 0.14),
              colors.accent.withValues(alpha: 0.04),
              Colors.transparent,
            ],
            stops: const [0.0, 0.35, 1.0],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SLENDER MENU TILE
//
//   [icon plate 28×28]   Title              Tag · ›
//
// Press feedback: a quick scale-down + a flutter_animate shimmer chained
// onto the row so each press feels alive without manual
// AnimationController plumbing.
// =============================================================================
class _SlenderMenuTile extends StatefulWidget {
  final AzamanColors colors;
  final IconData icon;
  final String title;
  final String? chip;
  final VoidCallback? onTap;

  const _SlenderMenuTile({
    required this.colors,
    required this.icon,
    required this.title,
    required this.chip,
    required this.onTap,
  });

  @override
  State<_SlenderMenuTile> createState() => _SlenderMenuTileState();
}

class _SlenderMenuTileState extends State<_SlenderMenuTile> {
  bool _pressed = false;
  Key _shimmerKey = UniqueKey();

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  void _onTap() {
    if (widget.onTap == null) return;
    setState(() => _shimmerKey = UniqueKey()); // re-trigger shimmer
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final disabled = widget.onTap == null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: disabled ? null : _onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: MotionTokens.accessibleDuration(
          context,
          const Duration(milliseconds: 110),
        ),
        curve: Curves.easeOut,
        child:
            Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colors.textSecondary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          widget.icon,
                          color: colors.textSecondary,
                          size: 15,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                      if (widget.chip != null &&
                          widget.chip!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            widget.chip!,
                            style: TextStyle(
                              color: colors.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Icon(
                        Icons.arrow_forward,
                        color: colors.divider,
                        size: 16,
                      ),
                    ],
                  ),
                )
                .animate(key: _shimmerKey)
                .fadeIn(duration: 220.ms)
                .shimmer(
                  delay: 80.ms,
                  duration: 900.ms,
                  color: colors.accent.withValues(alpha: 0.18),
                ),
      ),
    );
  }
}

// =============================================================================
// WORKER SUB-PORTAL CARD — Shows in settings drawer when user is an employee
// =============================================================================
class _WorkerCard extends ConsumerWidget {
  final dynamic colors;
  const _WorkerCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empAsync = ref.watch(myEmployeeProvider);

    return empAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (employee) {
        if (employee == null) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colors.accentSecondary.withValues(alpha: 0.08),
                colors.accentSecondary.withValues(alpha: 0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colors.accentSecondary.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
              context.push('/worker');
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.accentSecondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.badge,
                      color: colors.accentSecondary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Workplace',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          '${employee.title ?? employee.role.name} @ ${employee.businessName ?? "Business"}',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: colors.textTertiary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// PROFILE HERO — pinned sliver header with the scroll-driven avatar.
//
// Geometry (all values derive from the delegate's own extents; the SafeArea
// above absorbs the OS top inset, so nothing hardcodes a notch):
//
//   EXPANDED (maxExtent 224)            COLLAPSED (minExtent 64)
//   ┌───────────────────────────┐       ┌──────────────────────────┐
//   │      ╭──────╮              │       │ (avatar sinks into bar) │
//   │      │avatar│ 88px, top 16 │  ──►  │ ● @username   [verified]│
//   │      ╰──────╯              │       └──────────────────────────┘
//   │ ┌─────────────────────────┴─┐
//   │ │ hero surface (protrudes)  │
//   │ │      @username (centred)  │
//   │ │ AZM-ID · badge      [QR] │
//   │ └───────────────────────────┘
//   └──────────────────────────────┘
//
// The morph is a pure interpolation of shrinkOffset between the two
// geometries — no controllers, no listeners, no idle loop. The username /
// identity / QR crossfade with t; conditional inclusion (t bands) keeps
// the two presentations from fighting each other mid-transition. Under
// reduced motion the position-proportional morph is inherently safe
// (nothing springs or overshoots).
// =============================================================================
class _ProfileHeroDelegate extends SliverPersistentHeaderDelegate {
  final String username;
  final User? user;

  static const double _minExtent = 64;
  static const double _maxExtent = 224;

  _ProfileHeroDelegate({required this.username, this.user});

  @override
  double get minExtent => _minExtent;

  @override
  double get maxExtent => _maxExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final t = (shrinkOffset / (_maxExtent - _minExtent)).clamp(0.0, 1.0);
    return _ProfileHeroBody(username: username, user: user, t: t);
  }

  @override
  bool shouldRebuild(_ProfileHeroDelegate oldDelegate) =>
      oldDelegate.username != username || oldDelegate.user != user;
}

class _ProfileHeroBody extends ConsumerWidget {
  final String username;
  final User? user;

  /// 0 = fully expanded, 1 = fully collapsed. Scroll-linked, not animated.
  final double t;

  const _ProfileHeroBody({
    required this.username,
    required this.user,
    required this.t,
  });

  static const double _avatarExpanded = 88;
  static const double _avatarCollapsed = 40;
  static const double _surfaceExpanded = 128;
  static const double _surfaceCollapsed = 64;

  void _openProfileEditor(BuildContext context) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final badgeColor = _kycTint(user?.kycStatus);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // Interpolated geometry.
        final avatarSize = lerpDouble(_avatarExpanded, _avatarCollapsed, t)!;
        final avatarTop = lerpDouble(16, (h - _avatarCollapsed) / 2, t)!;
        final avatarLeft = lerpDouble((w - _avatarExpanded) / 2, 18, t)!;
        final surfaceHeight = lerpDouble(
          _surfaceExpanded,
          _surfaceCollapsed,
          t,
        )!;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // ── HERO SURFACE ──────────────────────────────────────────
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              height: surfaceHeight,
              child: _HeroSurface(
                colors: colors,
                username: username,
                user: user,
                t: t,
                badgeColor: badgeColor,
              ),
            ),

            // ── AVATAR (scroll-driven morph, protrudes over surface) ──
            Positioned(
              left: avatarLeft,
              top: avatarTop,
              child: Semantics(
                button: true,
                label: 'Open profile editor',
                child: GestureDetector(
                  key: const ValueKey('profile_hero_avatar'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openProfileEditor(context),
                  child: _buildAvatar(colors, avatarSize),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAvatar(AzamanColors colors, double size) {
    final hasPhoto =
        (user?.profilePictureUrl != null &&
        user!.profilePictureUrl!.isNotEmpty);
    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.accent.withValues(alpha: 0.35),
            colors.accent.withValues(alpha: 0.10),
          ],
        ),
        border: Border.all(
          color: colors.accent.withValues(alpha: 0.45),
          width: 1.0,
        ),
      ),
      alignment: Alignment.center,
      child: hasPhoto
          ? ClipOval(
              child: AzamanNetworkImage(
                imageUrl: user!.profilePictureUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _monogram(colors, size),
              ),
            )
          : _monogram(colors, size),
    );

    // Verification ring only when fully verified (preserved affordance).
    if (user?.kycStatus == KycStatus.verified) {
      avatar = Stack(
        alignment: Alignment.bottomRight,
        children: [
          avatar,
          Container(
            width: size * 0.26,
            height: size * 0.26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.background,
              border: Border.all(color: colors.background, width: 2),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.check_circle_outline,
              color: const Color(0xFF22C55E),
              size: size * 0.21,
            ),
          ),
        ],
      );
    }
    return avatar;
  }

  Widget _monogram(AzamanColors colors, double size) {
    final c = username.trim();
    final initial = c.isEmpty ? 'A' : c.substring(0, 1).toUpperCase();
    return Text(
      initial,
      style: TextStyle(
        color: colors.accent,
        fontSize: size * 0.34,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// The glass surface under the avatar: expanded state carries @username
/// centred under the avatar, the public Azaman ID row + KYC badge, and
/// the QR thumbnail; collapsed state is the compact bar with the username
/// and a small QR affordance. The two presentations crossfade with [t]
/// and are included in the tree only within their active bands so neither
/// over-constrains the other's geometry mid-morph.
class _HeroSurface extends StatelessWidget {
  final AzamanColors colors;
  final String username;
  final User? user;
  final double t;
  final Color badgeColor;

  const _HeroSurface({
    required this.colors,
    required this.username,
    required this.user,
    required this.t,
    required this.badgeColor,
  });

  void _openProfileEditor(BuildContext context) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expandedOpacity = (1.0 - t * 1.6).clamp(0.0, 1.0);
    final collapsedOpacity = (t * 1.6 - 0.6).clamp(0.0, 1.0);

    final uidLine = (user?.azamanId != null && user!.azamanId!.isNotEmpty)
        ? user!.azamanId!
        : 'AZM-—';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Empty area of the surface opens the profile editor — the QR and
      // identity affordances below win the arena in their own regions.
      onTap: () => _openProfileEditor(context),
      child: Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                Colors.white.withValues(alpha: colors.isDark ? 0.06 : 0.03),
                colors.card,
              ),
              Color.alphaBlend(
                Colors.white.withValues(alpha: colors.isDark ? 0.015 : 0.0),
                colors.card,
              ),
            ],
          ),
          border: Border.all(
            color: colors.isDark
                ? Colors.white.withValues(alpha: 0.08)
                : colors.border,
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: colors.isDark ? 0.35 : 0.08,
              ),
              blurRadius: 18,
              spreadRadius: -4,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── EXPANDED presentation ────────────────────────────────
            if (expandedOpacity > 0.02)
              Positioned.fill(
                child: Opacity(
                  opacity: expandedOpacity,
                  child: IgnorePointer(
                    ignoring: expandedOpacity < 0.5,
                    child: Stack(
                      children: [
                        // @username centred under the avatar.
                        Positioned(
                          top: 34,
                          left: 12,
                          right: 12,
                          child: Center(
                            child: Text(
                              '@$username',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ),
                        // Identity row: public Azaman ID + copy + KYC badge.
                        Positioned(
                          left: 16,
                          right: 76,
                          bottom: 30,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      uidLine,
                                      maxLines: 1,
                                      overflow: TextOverflow.visible,
                                      softWrap: false,
                                      style: TextStyle(
                                        color: colors.textTertiary,
                                        fontSize: 11,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                  if (user?.azamanId != null &&
                                      user!.azamanId!.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _copyAzamanId(
                                        context,
                                        user!.azamanId!,
                                      ),
                                      child: Icon(
                                        Icons.copy_rounded,
                                        size: 13,
                                        color: colors.textTertiary.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              _kycBadge(user?.kycStatus, colors),
                            ],
                          ),
                        ),
                        // QR preview beside the identity row.
                        Positioned(
                          right: 14,
                          bottom: 14,
                          child: Semantics(
                            button: true,
                            label: 'Show my QR',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  showQrProfilePopup(context, username),
                              child: QrProfileThumbnail(
                                key: const ValueKey('profile_hero_qr'),
                                username: username,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── COLLAPSED presentation (compact bar) ─────────────────
            if (collapsedOpacity > 0.02)
              Positioned.fill(
                child: Opacity(
                  opacity: collapsedOpacity,
                  child: IgnorePointer(
                    ignoring: collapsedOpacity < 0.5,
                    child: Padding(
                      // 54 clears the avatar that overlaps the bar's
                      // left edge (avatar left 18 + 40 + 12 gap, minus
                      // the surface's own 16px left inset).
                      padding: const EdgeInsets.only(left: 54, right: 10),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              '@$username',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.shield_outlined,
                            color: badgeColor,
                            size: 13,
                          ),
                          const Spacer(),
                          GestureDetector(
                            key: const ValueKey('profile_hero_qr_icon'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => showQrProfilePopup(context, username),
                            child: Icon(
                              Icons.qr_code,
                              color: colors.textSecondary,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _copyAzamanId(BuildContext context, String azamanId) {
    Clipboard.setData(ClipboardData(text: azamanId));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $azamanId'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

Color _kycTint(KycStatus? status) {
  switch (status ?? KycStatus.unverified) {
    case KycStatus.verified:
      return const Color(0xFF22C55E);
    case KycStatus.pending:
      return const Color(0xFFF59E0B);
    case KycStatus.rejected:
    case KycStatus.unverified:
      return const Color(0xFFEF4444);
  }
}

Widget _kycBadge(KycStatus? status, AzamanColors colors) {
  final s = status ?? KycStatus.unverified;
  final tint = _kycTint(s);

  late final String label;
  late final IconData icon;
  switch (s) {
    case KycStatus.verified:
      label = 'Verified';
      icon = Icons.check_circle_outline;
    case KycStatus.pending:
      label = 'Pending';
      icon = Icons.hourglass_empty;
    case KycStatus.rejected:
      label = 'Rejected';
      icon = Icons.shield_outlined;
    case KycStatus.unverified:
      label = 'Unverified';
      icon = Icons.shield_outlined;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: tint.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: tint.withValues(alpha: 0.55), width: 0.8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: tint, size: 11),
        const SizedBox(width: 5),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: tint,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      ],
    ),
  );
}
