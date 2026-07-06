// =============================================================================
// SETTINGS DRAWER — "ECLIPSE GLOW"  (Polish Sprint)
//
// Aesthetic directive (strict):
//   • FORBIDDEN: grid lines, box patterns, horizontal scanning beams,
//     CustomPainter chrome of any kind. The previous _TechBackground +
//     _HQScannerEffect have been removed in their entirety.
//   • REQUIRED: an "Eclipse Glow" backdrop — pure dark scaffold with a
//     single soft RadialGradient halo radiating from the top-center.
//     One static gradient. No animation. No texture. Lets foreground
//     buttons / typography pop without any visual noise.
//
// Profile section is now a Riverpod ConsumerWidget that reads:
//   • user.username           → headline
//   • '@UID-${user.id}'       → secondary line
//   • user.kycStatus enum     → dynamic Verified / Pending / Unverified
//                                badge (green / yellow / red)
//
// All hard-coded "Azaman_Official" / "8273941" / "VERIFIED PRO" copy
// has been removed.
// =============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/worker_provider.dart';
import 'package:azaman/screens/account_activity_screen.dart';
import 'package:azaman/screens/admin/admin_dashboard.dart';
import 'package:azaman/screens/azm_auction/azm_auction_screen.dart';
import 'package:azaman/screens/azm_rewards_screen.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/screens/leaderboard_screen.dart';
import 'package:azaman/screens/profile_screen.dart';
import 'package:azaman/screens/referral_screen.dart';
import 'package:azaman/screens/saved_momo_accounts_screen.dart';
import 'package:azaman/screens/saved_wallets_screen.dart';
import 'package:azaman/screens/security_settings.dart';
import 'package:azaman/screens/settings_screen.dart';
import 'package:azaman/screens/share_profile_screen.dart';
import 'package:azaman/screens/theme_picker_screen.dart';
import 'package:azaman/screens/vault/vault_list_screen.dart';
import 'package:azaman/screens/vendor_dashboard.dart';
import 'package:azaman/screens/withdrawal_screen.dart';
import 'package:azaman/screens/azaman_store_screen.dart';
import 'package:azaman/screens/marketplace/business_dashboard_screen.dart';
import 'package:azaman/screens/marketplace/business_register_screen.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';


class SettingsDrawer extends ConsumerWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final user = ref.watch(currentUserProvider).value;
    final bizState = ref.watch(myBusinessProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.read(myBusinessProvider).hasLoaded && !ref.read(myBusinessProvider).isLoading) {
        ref.read(myBusinessProvider.notifier).load();
      }
    });

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.88,
      backgroundColor: Colors.transparent,
      // Master Sprint v2 (2026-05-27): true frosted-glass drawer.
      // The whole drawer surface is wrapped in a BackdropFilter that
      // blurs *only* the area the drawer occupies. The screen below
      // is dimmed by the standard Drawer scrim. The inner column sits
      // on a tinted glass card so foreground content reads cleanly
      // without losing the underlying scenery.
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Stack(
            children: [
              // Tinted glass card — semi-opaque so the blur still reads
              // but contrast stays AA-compliant against the foreground.
              Positioned.fill(
                child: ColoredBox(
                  color: colors.background.withOpacity(0.72),
                ),
              ),
              const Positioned.fill(child: _EclipseGlow()),

              SafeArea(
            child: Column(
              children: [
                _buildTopActionBar(context, colors),

                // ── Profile card (live from Riverpod) ───────────────────
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProfileScreen(),
                      ),
                    );
                  },
                  child: _animatedWrapper(
                    delay: 1,
                    child: _buildPremiumProfileCard(colors, user),
                  ),
                ),

                const SizedBox(height: 10),
                Divider(
                  color: colors.divider.withOpacity(0.4),
                  thickness: 1,
                  indent: 24,
                  endIndent: 24,
                ),

                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 15),
                    children: [
                      // ROOT ACCESS — restricted to the platform admin account only.
                      // The backend already hard-gates every /api/admin route behind
                      // `adminOnly` middleware; this UI gate just keeps the entry point
                      // from cluttering the drawer for every other user.
                      if ((user?.email ?? '').toLowerCase() == 'admin@azaman.test') ...[
                        _animatedWrapper(
                          delay: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(
                                'ROOT ACCESS',
                                colors: colors,
                                headerColor: colors.danger,
                              ),
                              const SizedBox(height: 12),
                              _buildGodModeTile(context, colors),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25),
                      ],

                      // PAYMENT ADDRESSES (Phase UI-2, 2026-05-26)
                      // Both deposit destinations (where users send funds
                      // INTO Azaman from external accounts/wallets) and
                      // withdrawal destinations (where Azaman sends funds
                      // OUT to the user) live side-by-side here. Phase UI-1
                      // shipped the Withdrawal tile in this slot; UI-2
                      // mirrors the Deposit Addresses entry alongside it
                      // using the same slender-tile pattern. The pair gives
                      // the user a single coherent surface for managing
                      // every external account they use to fund their
                      // platform operations.
                      _animatedWrapper(
                        delay: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('PAYMENT ADDRESSES',
                                colors: colors),
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.025),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colors.divider),
                              ),
                              child: Column(
                                children: [
                                  _buildSlenderTile(
                                    context,
                                    colors,
                                    title: 'Deposit Addresses',
                                    subtitle:
                                        'Saved MoMo accounts for STK-push deposits',
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
                                    title: 'Withdrawal Addresses',
                                    subtitle:
                                        'MoMo & crypto payout destinations',
                                    icon: Icons.arrow_upward,
                                    iconColor: colors.warning,
                                    destination: const SavedWalletsScreen(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 25),

                      // SHORTCUTS
                      _animatedWrapper(
                        delay: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('HQ SHORTCUTS',
                                colors: colors, showEdit: true),
                            const SizedBox(height: 15),
                            _buildShortcutsGrid(context, colors),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      _animatedWrapper(
                        delay: 7,
                        child: _buildSectionHeader('RECOMMENDED',
                            colors: colors),
                      ),
                      const SizedBox(height: 10),

                      // The Recommended section is the place for high-value
                      // user destinations. Each tile routes to a real screen
                      // (was previously a dead link with a static tag).
                      // Phase UI-2 (2026-05-26): "Withdrawal Addresses" tile
                      // removed from this section — the dedicated PAYMENT
                      // ADDRESSES block above (Deposit + Withdrawal) is the
                      // canonical home for it now and a duplicate here would
                      // produce two doors into the same screen.
                      // P2P Trading was previously here too but routed to a
                      // tab-root screen (`P2PMarketplaceScreen`) with no
                      // AppBar / back button. Pushing it left the user
                      // stranded with no way home. Removed because the P2P
                      // tab in the bottom nav is the canonical entry point.
                      //
                      // 2026-05-27: filled out with two more standalone
                      // destinations (Theme + AZM Rewards) so the section
                      // is more than two tiles. Both screens have proper
                      // AppBars with back arrows so the user can return.
                      _buildMenuItem(
                        context,
                        Icons.security,
                        'Security Center',
                        'High',
                        colors,
                        destination: const SecuritySettingsScreen(),
                      ),
                      // Master Sprint (2026-05-27)
                      _buildMenuItem(
                        context,
                        Icons.lock_outline,
                        'Vaults',
                        'New',
                        colors,
                        destination: const VaultListScreen(),
                      ),
                      // Master Sprint v2 (2026-05-27): Smart Routes
                      // moved to the Withdrawal screen (where users
                      // configure recurring outbound payments). Susu /
                      // Groups live under the Savings tab. Rewards
                      // (Auction + AZM + Referrals) collapse into a
                      // single expandable tile below.
                      _buildRewardsExpansion(context, colors),
                      _buildMenuItem(
                        context,
                        Icons.palette_outlined,
                        'Theme',
                        'Style',
                        colors,
                        destination: const ThemePickerScreen(),
                      ),
                      _buildMenuItem(
                        context,
                        Icons.storefront_outlined,
                        'Azaman Store',
                        'New',
                        colors,
                        destination: const AzamanStoreScreen(),
                      ),
                      if (bizState.isLoading && !bizState.hasLoaded)
                        const SizedBox(
                          height: 80,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (bizState.profile == null)
                        _buildMenuItem(
                          context,
                          Icons.add_business,
                          'Register Your Business',
                          'Start',
                          colors,
                          destination: const BusinessRegisterScreen(),
                        )
                      else
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [colors.accent.withOpacity(0.08), colors.accent.withOpacity(0.02)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: colors.accent.withOpacity(0.15), width: 1),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.of(context).pop();
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const BusinessDashboardScreen(),
                              ));
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: bizState.profile!.logoUrl != null && bizState.profile!.logoUrl!.isNotEmpty
                                        ? CachedNetworkImage(imageUrl: bizState.profile!.logoUrl!, width: 48, height: 48, fit: BoxFit.cover)
                                        : Container(width: 48, height: 48, color: colors.accent.withOpacity(0.1),
                                            child: Icon(Icons.store, color: colors.accent, size: 24)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(bizState.profile!.businessName, style: TextStyle(
                                                fontSize: 15, fontWeight: FontWeight.w700, color: colors.textPrimary,
                                              ), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            ),
                                            if (bizState.profile!.isVerified)
                                              Icon(Icons.verified, size: 14, color: colors.accent),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: bizState.profile!.kybStatus == 'VERIFIED'
                                                    ? Colors.green.withOpacity(0.1)
                                                    : Colors.orange.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                bizState.profile!.kybStatus == 'VERIFIED' ? 'Verified' : 'Pending KYB',
                                                style: TextStyle(
                                                  fontSize: 10, fontWeight: FontWeight.w500,
                                                  color: bizState.profile!.kybStatus == 'VERIFIED' ? Colors.green : Colors.orange,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (bizState.profile!.averageRating > 0) ...[
                                              Icon(Icons.star, size: 12, color: Colors.amber),
                                              const SizedBox(width: 2),
                                              Text(bizState.profile!.averageRating.toStringAsFixed(1),
                                                style: TextStyle(fontSize: 11, color: colors.textSecondary)),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right, color: colors.textTertiary, size: 20),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // ── Worker Sub-Portal Card ────────────────────────────
                      _WorkerCard(colors: colors),

                      const SizedBox(height: 40),
                      Center(
                        child: Text(
                          'AZAMAN PROTOCOL V3.0 — THEMED',
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 8,
                            letterSpacing: 2,
                          ),
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
  // PROFILE CARD — fully wired to Riverpod auth state
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildPremiumProfileCard(AzamanColors colors, User? user) {
    final username = (user?.username.isNotEmpty ?? false)
        ? user!.username
        : 'Guest';
    final uidLine = (user?.azamanId != null && user!.azamanId!.isNotEmpty)
        ? user.azamanId!
        : (user != null ? 'AZM-—' : 'AZM-—');
    final badge = _kycBadgeFor(user?.kycStatus, colors);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.06),
            Colors.white.withOpacity(0.015),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar — initial-letter monogram derived from username.
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.accent.withOpacity(0.35),
                      colors.accent.withOpacity(0.10),
                    ],
                  ),
                  border: Border.all(
                    color: colors.accent.withOpacity(0.45),
                    width: 1.0,
                  ),
                ),
                alignment: Alignment.center,
                child: (user?.profilePictureUrl != null &&
                        user!.profilePictureUrl!.isNotEmpty)
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: user.profilePictureUrl!,
                          width: 64, height: 64,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Text(
                            _initial(username),
                            style: TextStyle(
                              color: colors.accent,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      )
                    : Text(
                        _initial(username),
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
              // Verification ring overlay only when fully verified.
              if (user?.kycStatus == KycStatus.verified)
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.background,
                    border: Border.all(
                      color: colors.background,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF22C55E),
                    size: 18,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  uidLine,
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 8),
                badge,
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward,
            color: colors.textTertiary,
            size: 14,
          ),
        ],
      ),
    );
  }

  /// Build the dynamic KYC badge. Colors are sourced once and reused
  /// so the badge stays consistent across light/dark themes.
  Widget _kycBadgeFor(KycStatus? status, AzamanColors colors) {
    final s = status ?? KycStatus.unverified;

    late final Color tint;
    late final String label;
    late final IconData icon;

    switch (s) {
      case KycStatus.verified:
        tint = const Color(0xFF22C55E); // green
        label = 'Verified';
        icon = Icons.check_circle_outline;
        break;
      case KycStatus.pending:
        tint = const Color(0xFFF59E0B); // amber/yellow
        label = 'Pending';
        icon = Icons.hourglass_empty;
        break;
      case KycStatus.rejected:
        tint = const Color(0xFFEF4444); // red
        label = 'Rejected';
        icon = Icons.shield_outlined;
        break;
      case KycStatus.unverified:
        tint = const Color(0xFFEF4444); // red
        label = 'Unverified';
        icon = Icons.shield_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withOpacity(0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: tint.withOpacity(0.55),
          width: 0.8,
        ),
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

  String _initial(String name) {
    final t = name.trim();
    if (t.isEmpty) return 'A';
    return t.substring(0, 1).toUpperCase();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // OTHER UI COMPONENTS — preserved from previous drawer
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildGodModeTile(BuildContext context, AzamanColors colors) {
    return InkWell(
      onTap: () {
        HapticFeedback.heavyImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboard()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.danger.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.danger.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: colors.danger.withOpacity(0.08),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.danger.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.danger.withOpacity(0.5)),
              ),
              child: Icon(Icons.shield_outlined, color: colors.danger, size: 24),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin War Room',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    'System overrides & resolutions',
                    style: TextStyle(
                      color: colors.danger.withOpacity(0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.error_outline, color: colors.danger, size: 18),
          ],
        ),
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
    VoidCallback? onTapOverride,
  }) {
    // Phase UI-1 (2026-05-26): slender list-tile pattern that replaces the
    // chunky `_buildPortalTile`. Same hit target, ~40% less vertical chrome.
    // The icon plate dropped from 40×40 to 32×32, the subtitle is single-line
    // with ellipsis, the trailing chevron is hairline-weight. This pattern
    // is reused by the Deposit Addresses / Withdrawal Addresses entries
    // (Phase UI-2 will mirror Deposit Addresses into the same section).
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (onTapOverride != null) {
          HapticFeedback.lightImpact();
          onTapOverride();
          return;
        }
        if (destination != null) {
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
                color: iconColor.withOpacity(0.10),
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
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward,
              color: colors.textTertiary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // Phase UI-1 (2026-05-26): `_buildPortalTile` was retired. All payment-
  // section tiles use the new `_buildSlenderTile` helper above. The chunky
  // portal pattern is preserved in git history if a future surface (e.g.
  // a hero "Vendor Portal" entry) wants to opt back into it.

  Widget _buildTopActionBar(BuildContext context, AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: Icon(Icons.qr_code_outlined, color: colors.textSecondary),
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ShareProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, color: colors.accent),
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title, {
    required AzamanColors colors,
    bool showEdit = false,
    Color? headerColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: headerColor ?? colors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        if (showEdit)
          Text(
            'Edit',
            style: TextStyle(color: colors.accent, fontSize: 12),
          ),
      ],
    );
  }

  Widget _buildShortcutsGrid(BuildContext context, AzamanColors colors) {
    final List<Map<String, dynamic>> items = [
      {
        'icon': Icons.account_balance_wallet_outlined,
        'label': 'Deposit',
        'destination': const DepositScreen(),
      },
      {
        'icon': Icons.send_outlined,
        'label': 'Withdraw',
        'destination': const WithdrawalScreen(),
      },
      {
        'icon': Icons.history,
        'label': 'History',
        'destination': const AccountActivityScreen(),
      },
      {
        'icon': Icons.analytics_outlined,
        'label': 'Leaderboard',
        'destination': const LeaderboardScreen(),
      },
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.lightImpact();
          // Close the drawer first so the destination screen is the visible
          // top-of-stack route. Without this the drawer briefly overlays
          // the pushed page.
          Navigator.of(context).pop();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => items[i]['destination'] as Widget,
          ));
        },
        child: Column(
          children: [
            Icon(items[i]['icon'] as IconData,
                color: colors.accent, size: 24),
            const SizedBox(height: 6),
            Text(
              items[i]['label'] as String,
              style: TextStyle(color: colors.textTertiary, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String title,
    String tag,
    AzamanColors colors, {
    Widget? destination,
  }) {
    // Sprint UI-OVERHAUL (2026-05-27): replaced the bulky ListTile with a
    // slender shimmer-on-tap row. Same hit area, ~30% less vertical chrome,
    // monochrome iconography, hairline trailing chevron. The shimmer fires
    // via flutter_animate when the tile mounts so the user gets a subtle
    // "live" cue without manual AnimationController plumbing.
    return _SlenderMenuTile(
      colors: colors,
      icon: icon,
      title: title,
      tag: tag,
      onTap: destination == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => destination,
              ));
            },
    );
  }

  /// Master Sprint v2 (2026-05-27) — collapsible "Rewards" section that
  /// folds AZM Auction + AZM Rewards + Referral Rewards under one entry
  /// in the drawer's Recommended block. Reduces visible noise: most users
  /// don't tap any of those daily, so they hide behind a single chevron
  /// until expanded.
  Widget _buildRewardsExpansion(BuildContext context, AzamanColors colors) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        // ExpansionTile inherits the parent ListTile theme; force the
        // padding back to the tight inset our slender pattern uses so it
        // visually matches the surrounding rows.
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.zero,
          horizontalTitleGap: 12,
          minVerticalPadding: 4,
        ),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 36),
        leading: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: colors.textSecondary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.card_giftcard_outlined,
            color: colors.textSecondary,
            size: 15,
          ),
        ),
        title: Text(
          'Rewards',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
        trailing: Icon(
          Icons.arrow_downward,
          color: colors.divider,
          size: 18,
        ),
        children: [
          _buildMenuItem(
            context,
            Icons.local_fire_department_outlined,
            'AZM Auction',
            'Vendor',
            colors,
            destination: const AzmAuctionScreen(),
          ),
          _buildMenuItem(
            context,
            Icons.diamond_outlined,
            'AZM Rewards',
            'Earn',
            colors,
            destination: const AzmRewardsScreen(),
          ),
          _buildMenuItem(
            context,
            Icons.card_giftcard_outlined,
            'Referral Rewards',
            '10%',
            colors,
            destination: const ReferralScreen(),
          ),
        ],
      ),
    );
  }

  Widget _animatedWrapper({required int delay, required Widget child}) {
    return TweenAnimationBuilder(
      tween: Tween<Offset>(begin: const Offset(40, 0), end: Offset.zero),
      duration: Duration(milliseconds: 500 + (delay * 100)),
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
// Pure gradient: a single soft RadialGradient halo radiating from
// roughly the top-center of the drawer over a pitch-dark base. No
// painters, no animation, no scan lines, no grids. The opacity is
// kept low so foreground content remains the focal point.
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
            Colors.black.withOpacity(0.18),
            colors.background,
          ),
          gradient: RadialGradient(
            // Halo origin sits slightly above-and-left of center so the
            // glow falls naturally onto the profile card area.
            center: const Alignment(-0.15, -0.85),
            radius: 1.15,
            colors: [
              colors.accent.withOpacity(0.14),
              colors.accent.withOpacity(0.04),
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
// SLENDER MENU TILE — Sprint UI-OVERHAUL
//
// Replaces the chunky default ListTile inside the drawer's "Recommended"
// section. Anatomy:
//
//   [icon plate 28×28]   Title              Tag · ›
//
// Press feedback: a quick scale-down + a flutter_animate shimmer chained
// onto the row so each press feels alive without any manual
// AnimationController. The tile also shimmers once on mount as the drawer
// opens (subtle "draw the user's eye" cue).
// =============================================================================
class _SlenderMenuTile extends StatefulWidget {
  final AzamanColors colors;
  final IconData icon;
  final String title;
  final String tag;
  final VoidCallback? onTap;

  const _SlenderMenuTile({
    required this.colors,
    required this.icon,
    required this.title,
    required this.tag,
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
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withOpacity(0.06),
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
              Text(
                widget.tag,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
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
              color: colors.accent.withOpacity(0.18),
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
              colors: [colors.accentSecondary.withOpacity(0.08), colors.accentSecondary.withOpacity(0.02)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.accentSecondary.withOpacity(0.15), width: 1),
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
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: colors.accentSecondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.badge, color: colors.accentSecondary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Workplace', style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                        Text('${employee.title ?? employee.role.name} @ ${employee.businessName ?? "Business"}',
                            style: TextStyle(fontSize: 11, color: colors.textSecondary),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.textTertiary, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
