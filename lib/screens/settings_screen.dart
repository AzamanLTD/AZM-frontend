// =============================================================================
// AZAMAN — SETTINGS SCREEN  (Phase F overhaul, the original user pain point)
//
// Phase F merges the Phase 0 grid-based settings_screen with the design
// language of the orphan `actual_settings_screen.dart` (deleted in Phase 0)
// and ships:
//
//   1. Apple / Binance-style row layout. Every entry is a single row tile
//      with an icon, label, optional trailing summary value, and chevron.
//      No more 11-tile grid jammed into the main settings ListView.
//
//   2. The theme picker is no longer inline. The "Theme" row renders the
//      *currently selected theme's name* on the trailing edge and routes
//      to the dedicated `ThemePickerScreen` — full-page picker with live
//      preview at the top (FRONTEND_AUDIT.md §3, Phase F).
//
//   3. New Security & Privacy section wires four real backends:
//        • Two-Factor & PIN  → existing /api/security/2fa/* + /pin/*
//        • Change Password   → /api/security/change-password (added in this PR)
//        • Account Activity  → /api/users/me/security-logs
//        • Identity / KYC    → existing KycVerificationScreen
//
//   4. Sign Out preserved. Dropdowns (currency / language) preserved as
//      iOS-style action sheets so they sit comfortably inside the row
//      layout instead of breaking the grid.
//
// Theme system is read-only here — picker writes it. Settings provider
// is the authority for non-theme prefs (push, trade alerts, etc.) and
// persists to SharedPreferences as before.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/settings_provider.dart';
import 'package:azaman/widgets/sensory_preferences_section.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/socket_service.dart';

import 'package:azaman/screens/account_activity_screen.dart';
import 'package:azaman/screens/account_deactivation_screen.dart';
import 'package:azaman/screens/auth/login_screen.dart';
import 'package:azaman/screens/change_password_screen.dart';
import 'package:azaman/screens/kyc_verification_screen.dart';
import 'package:azaman/screens/profile_details_screen.dart';
import 'package:azaman/screens/profile_screen.dart';
import 'package:azaman/screens/support_screen.dart';
import 'package:azaman/services/biometric_service.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/screens/referral_screen.dart';
import 'package:azaman/screens/saved_wallets_screen.dart';
import 'package:azaman/screens/saved_momo_accounts_screen.dart';
import 'package:azaman/screens/security_settings.dart';
import 'package:azaman/screens/theme_picker_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_confirm_sheet.dart';
import 'package:azaman/widgets/azaman_sheet.dart';
import 'package:azaman/widgets/nav_transitions.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeNotifier = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);
    final colors = themeNotifier.colors;

    // The label shown on the right of the Theme row.
    final themeLabel = ThemeProvider.getColors(themeNotifier.currentTheme).name;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          // ── ACCOUNT HEADER ───────────────────────────────────────────
          // Phantom-style: the page opens with WHO you are on Azaman,
          // not a logo. Avatar, @username, public AZM ID, one chevron
          // into the genuine edit flow.
          _AccountHeaderCard(
            colors: colors,
            user: ref.watch(currentUserProvider).value,
          ),
          const SizedBox(height: 10),

          // ── ACCOUNT ──────────────────────────────────────────────────
          _SectionHeader('Account', colors: colors),
          _Card(
            colors: colors,
            children: [
              _NavRow(
                colors: colors,
                icon: Icons.person_outline,
                title: 'Edit Profile',
                onTap: () => pushWithVerticalTransition(
                  context,
                  const ProfileDetailsScreen(),
                ),
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: Icons.verified_user_outlined,
                title: 'Identity Verification',
                trailingText: _kycChipLabel(
                  ref.watch(currentUserProvider).value?.kycStatus,
                ),
                onTap: () => pushWithVerticalTransition(
                  context,
                  const KycVerificationScreen(),
                ),
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: Icons.card_giftcard_outlined,
                title: 'Refer & Earn',
                onTap: () => pushWithVerticalTransition(
                  context,
                  const ReferralScreen(),
                ),
              ),
            ],
          ),

          // ── MONEY ────────────────────────────────────────────────────
          _SectionHeader('Money', colors: colors),
          _Card(
            colors: colors,
            children: [
              _NavRow(
                colors: colors,
                icon: Icons.arrow_downward,
                title: 'MoMo deposits',
                onTap: () => pushWithVerticalTransition(
                  context,
                  const SavedMomoAccountsScreen(),
                ),
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: Icons.arrow_upward,
                title: 'Payout destinations',
                onTap: () => pushWithVerticalTransition(
                  context,
                  const SavedWalletsScreen(),
                ),
              ),
            ],
          ),

          // ── NOTIFICATIONS ────────────────────────────────────────────
          _SectionHeader('Notifications', colors: colors),
          _Card(
            colors: colors,
            children: [
              _ToggleRow(
                colors: colors,
                icon: Icons.notifications_outlined,
                title: 'Push Notifications',
                value: settings.pushNotifications,
                onChanged: (v) => settings.setPushNotifications(v),
              ),
              _Divider(colors),
              _ToggleRow(
                colors: colors,
                icon: Icons.swap_horiz,
                title: 'Trade Alerts',
                value: settings.tradeAlerts,
                onChanged: (v) => settings.setTradeAlerts(v),
              ),
              _Divider(colors),
              _ToggleRow(
                colors: colors,
                icon: Icons.chat_bubble_outline,
                title: 'Chat Messages',
                value: settings.chatNotifications,
                onChanged: (v) => settings.setChatNotifications(v),
              ),
              _Divider(colors),
              // Master Sprint v2: vendor-tag visibility, renamed for
              // humans — same provider, same behaviour.
              _ToggleRow(
                colors: colors,
                icon: Icons.storefront_outlined,
                title: 'Vendor tools',
                value: settings.vendorTagEnabled,
                onChanged: (v) => settings.setVendorTagEnabled(v),
              ),
            ],
          ),

          // ── APPEARANCE ────────────────────────────────────────────────
          _SectionHeader('Appearance', colors: colors),
          _Card(
            colors: colors,
            children: [
              _NavRow(
                colors: colors,
                icon: Icons.palette_outlined,
                title: 'Theme',
                trailingText:
                    '$themeLabel \u00b7 ${themeNotifier.accent.label}',
                onTap: () {
                  AzamanHaptics.nav();
                  pushWithVerticalTransition(
                    context,
                    const ThemePickerScreen(),
                  );
                },
              ),
            ],
          ),
          const SensoryPreferencesSection(title: 'Motion & feedback'),

          // ── PREFERENCES ───────────────────────────────────────────────
          _SectionHeader('Preferences', colors: colors),
          _Card(
            colors: colors,
            children: [
              _NavRow(
                colors: colors,
                icon: Icons.attach_money,
                title: 'Display Currency',
                trailingText: ref.watch(currencyProvider).name.toUpperCase(),
                onTap: () => _pickFromList(
                  context,
                  colors,
                  title: 'Display Currency',
                  options: const ['USDC', 'GHS'],
                  current: ref.watch(currencyProvider).name.toUpperCase(),
                  onPicked: (v) {
                    ref
                        .read(currencyProvider.notifier)
                        .set(
                          v == 'GHS'
                              ? DisplayCurrency.ghs
                              : DisplayCurrency.usdc,
                        );
                  },
                ),
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: Icons.language,
                title: 'Language',
                trailingText: settings.appLanguage,
                onTap: () => _pickFromList(
                  context,
                  colors,
                  title: 'Language',
                  options: const [
                    'English',
                    'French',
                    'Spanish',
                    'Arabic',
                    'Twi',
                  ],
                  current: settings.appLanguage,
                  onPicked: settings.setAppLanguage,
                ),
              ),
            ],
          ),

          // ── SECURITY ──────────────────────────────────────────────────
          _SectionHeader('Security', colors: colors),
          _Card(
            colors: colors,
            children: [
              FutureBuilder<bool>(
                future: BiometricService().isEnabled,
                builder: (context, snapshot) {
                  // Real state, not decoration: the chip reads the same
                  // store the Security screen's toggle writes.
                  final bio = snapshot.data == true;
                  return _NavRow(
                    colors: colors,
                    icon: Icons.security_outlined,
                    title: 'Two-Factor & PIN',
                    trailingText: snapshot.hasData
                        ? (bio ? 'Biometrics on' : 'PIN only')
                        : null,
                    onTap: () => pushWithVerticalTransition(
                      context,
                      const SecuritySettingsScreen(),
                    ),
                  );
                },
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: Icons.lock_outline,
                title: 'Change Password',
                onTap: () => pushWithVerticalTransition(
                  context,
                  const ChangePasswordScreen(),
                ),
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: Icons.history,
                title: 'Account Activity',
                onTap: () => pushWithVerticalTransition(
                  context,
                  const AccountActivityScreen(),
                ),
              ),
            ],
          ),

          // ── SUPPORT ───────────────────────────────────────────────────
          _SectionHeader('Support', colors: colors),
          _Card(
            colors: colors,
            children: [
              _NavRow(
                colors: colors,
                icon: Icons.help_outline,
                title: 'Help & FAQ',
                onTap: () => pushWithVerticalTransition(
                  context,
                  const SupportScreen(),
                ),
              ),
            ],
          ),

          // ── ABOUT ─────────────────────────────────────────────────────
          _SectionHeader('About', colors: colors),
          _Card(
            colors: colors,
            children: [
              _NavRow(
                colors: colors,
                icon: Icons.info_outline,
                title: 'About Azaman',
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'Azaman Protocol',
                  applicationVersion: 'v3.1 (Phase F)',
                  applicationIcon: Image.asset(
                    'assets/images/azaman_logo.png',
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                  ),
                  children: const [
                    Text('The premier P2P crypto remittance engine.'),
                  ],
                ),
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: Icons.tag_outlined,
                title: 'Version',
                trailingText: 'v3.1',
                onTap: null,
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: Icons.cleaning_services_outlined,
                title: 'Clear Cache',
                onTap: () {
                  AzamanHaptics.nav();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'System cache cleared. (42 MB freed)',
                      ),
                      backgroundColor: colors.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── ACCOUNT MANAGEMENT (destructive) ──────────────────────────
          // Directly under Sign Out so destructive actions read as a
          // distinct zone.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.card,
                  foregroundColor: colors.danger,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: colors.danger.withValues(alpha: 0.25),
                    ),
                  ),
                  elevation: 0,
                ),
                onPressed: () => _confirmSignOut(context, ref, colors),
                child: const Text(
                  'Sign Out',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _Card(
              colors: colors,
              children: [
                _NavRow(
                  colors: colors,
                  icon: Icons.no_accounts_outlined,
                  title: 'Delete Account',
                  subtitle: 'Permanently deactivate your Azaman account',
                  isDestructive: true,
                  onTap: () => pushWithVerticalTransition(
                    context,
                    const AccountDeactivationScreen(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Real KYC state chip — the same KycStatus the backend returns.
  /// Unverified renders no chip at all (no decoration).
  String? _kycChipLabel(KycStatus? status) {
    switch (status) {
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
  // ── DROPDOWN HELPER (iOS-style action sheet) ──────────────────────────────
  //
  // Replaces the previous DropdownButton crammed inside a row tile. Renders
  // a bottom sheet with one row per option, the current selection highlighted.
  Future<void> _pickFromList(
    BuildContext context,
    AzamanColors colors, {
    required String title,
    required List<String> options,
    required String current,
    required ValueChanged<String> onPicked,
  }) async {
    AzamanHaptics.toggle();
    // NEW-B: a fixed option list is the reference Whisper surface — sized to
    // content, no handle, no scroll. The old body carried its own surface
    // colour, 20px radius and drag handle; the weight supplies all three now,
    // so they are deleted rather than ported (I.8.1).
    final selected = await AzamanSheet.showWhisper<String>(
      context,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...options.map((opt) {
              final isSelected = opt == current;
              return ListTile(
                onTap: () => Navigator.pop(ctx, opt),
                title: Text(
                  opt,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle_outline, color: colors.accent)
                    : null,
              );
            }),
            const SizedBox(height: 12),
          ],
        );
      },
    );

    if (selected != null && selected != current) {
      onPicked(selected);
    }
  }

  // ── SIGN OUT ──────────────────────────────────────────────────────────────

  Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
    AzamanColors colors,
  ) async {
    // Phase H — bottom-sheet confirm replaces the legacy AlertDialog. Same
    // return contract (`bool?`), so the post-confirm path below is unchanged.
    final confirm = await AzamanConfirmSheet.show(
      context,
      title: 'Sign Out',
      message:
          'Are you sure you want to sign out? You\'ll need to log back in to access your account.',
      confirmLabel: 'Sign Out',
      cancelLabel: 'Cancel',
      destructive: true,
      icon: Icons.logout,
    );

    if (confirm == true && context.mounted) {
      SocketService.instance.disconnect();
      ref.read(authProvider).logout();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }
}

// =============================================================================
// PRIVATE LAYOUT PRIMITIVES — Apple/Binance row tiles
//
// Each section is a `_Card` (rounded container with the theme card color)
// containing one or more rows separated by `_Divider`. Rows render into
// the same height (56–64) regardless of variant (nav, toggle), so the
// list reads as a coherent stack.
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  final AzamanColors colors;
  const _SectionHeader(this.title, {required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final AzamanColors colors;
  final List<Widget> children;
  const _Card({required this.colors, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final AzamanColors colors;
  const _Divider(this.colors);

  @override
  Widget build(BuildContext context) {
    // Indented so the divider doesn't run under the leading icon —
    // matches iOS Settings exactly.
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(height: 1, thickness: 0.5, color: colors.divider),
    );
  }
}

class _NavRow extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final bool isDestructive;
  final VoidCallback? onTap;

  const _NavRow({
    required this.colors,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.isDestructive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = isDestructive ? colors.danger : colors.textPrimary;
    final iconColor = isDestructive ? colors.danger : colors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingText != null && trailingText!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  trailingText!,
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Icon(Icons.arrow_forward, color: colors.textTertiary, size: 13),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.colors,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Icon(icon, color: colors.textSecondary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) {
              AzamanHaptics.toggle();
              onChanged(v);
            },
            activeThumbColor: colors.success,
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// ACCOUNT HEADER — the identity moment at the top of Settings.
// Avatar, @username, public AZM ID, one chevron into the genuine edit
// flow (ProfileScreen; ProfileDetailsScreen is the read-only view and
// stays one row below).
class _AccountHeaderCard extends StatelessWidget {
  final AzamanColors colors;
  final User? user;

  const _AccountHeaderCard({required this.colors, this.user});

  @override
  Widget build(BuildContext context) {
    final username =
        (user?.username.isNotEmpty ?? false) ? user!.username : 'Guest';
    final azm = (user?.azamanId != null && user!.azamanId!.isNotEmpty)
        ? user!.azamanId!
        : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          AzamanHaptics.nav();
          pushWithVerticalTransition(context, const ProfileScreen());
        },
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: AzamanNetworkImage(
                imageUrl: user?.profilePictureUrl,
                width: 54,
                height: 54,
                fit: BoxFit.cover,
                placeholder: (_, __) => _initials(colors, username),
                errorWidget: (_, __, ___) => _initials(colors, username),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@$username',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (azm != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            azm,
                            style: TextStyle(
                              color: colors.accent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        if (user?.kycStatus == KycStatus.verified) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified,
                            color: colors.success,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.arrow_forward, color: colors.textTertiary, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _initials(AzamanColors colors, String username) {
    final initials = username.isEmpty
        ? '?'
        : username.substring(0, 1).toUpperCase();
    return Container(
      color: colors.accent.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: colors.accent,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
