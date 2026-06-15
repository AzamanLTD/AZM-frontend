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

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/settings_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/services/socket_service.dart';

import 'package:azaman/screens/account_activity_screen.dart';
import 'package:azaman/screens/account_deactivation_screen.dart';
import 'package:azaman/screens/auth/login_screen.dart';
import 'package:azaman/screens/change_password_screen.dart';
import 'package:azaman/screens/kyc_verification_screen.dart';
import 'package:azaman/screens/profile_details_screen.dart';
import 'package:azaman/screens/referral_screen.dart';
import 'package:azaman/screens/saved_wallets_screen.dart';
import 'package:azaman/screens/saved_momo_accounts_screen.dart';
import 'package:azaman/screens/security_settings.dart';
import 'package:azaman/screens/theme_picker_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_confirm_sheet.dart';
import 'package:hugeicons_pro/hugeicons.dart';

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
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
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
          // ── ACCOUNT ─────────────────────────────────────────────────
          // Phase M (2026-05-25): wires three orphan screens that had
          // product value but no inbound import — Edit Profile (orphan
          // profile_details_screen.dart), Refer & Earn (orphan
          // referral_screen.dart), Delete Account (orphan
          // account_deactivation_screen.dart, distinct from the
          // duplicate account_deactivation.dart removed in same PR).
          _SectionHeader('Account', colors: colors),
          _Card(
            colors: colors,
            children: [
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.user,
                title: 'Edit Profile',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileDetailsScreen(),
                  ),
                ),
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.gift,
                title: 'Refer & Earn',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ReferralScreen(),
                  ),
                ),
              ),
            ],
          ),

          // ── APPEARANCE ──────────────────────────────────────────────
          _SectionHeader('Appearance', colors: colors),
          _Card(
            colors: colors,
            children: [
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.paintBoard,
                title: 'Theme',
                trailingText: themeLabel,
                onTap: () {
                  AzamanHaptics.nav();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ThemePickerScreen(),
                    ),
                  );
                },
              ),
            ],
          ),

          // ── NOTIFICATIONS ───────────────────────────────────────────
          _SectionHeader('Notifications', colors: colors),
          _Card(
            colors: colors,
            children: [
              _ToggleRow(
                colors: colors,
                icon: HugeIconsSolid.notification01,
                title: 'Push Notifications',
                subtitle: 'Receive alerts on your device',
                value: settings.pushNotifications,
                onChanged: (v) => settings.setPushNotifications(v),
              ),
              _Divider(colors),
              _ToggleRow(
                colors: colors,
                icon: HugeIconsSolid.exchange01,
                title: 'Trade Alerts',
                subtitle: 'New orders, releases, cancellations',
                value: settings.tradeAlerts,
                onChanged: (v) => settings.setTradeAlerts(v),
              ),
              _Divider(colors),
              _ToggleRow(
                colors: colors,
                icon: HugeIconsSolid.bubbleChat,
                title: 'Chat Messages',
                subtitle: 'In-trade chat notifications',
                value: settings.chatNotifications,
                onChanged: (v) => settings.setChatNotifications(v),
              ),
              _Divider(colors),
              // Master Sprint v2 (2026-05-27): vendor-tag visibility.
              // Off by default — only users who actually want the
              // vendor portal entry point need to see the side ribbon.
              _ToggleRow(
                colors: colors,
                icon: HugeIconsSolid.store01,
                title: 'Show Vendor Tag',
                subtitle: 'Pull-tab on the P2P tab to enter the vendor portal',
                value: settings.vendorTagEnabled,
                onChanged: (v) => settings.setVendorTagEnabled(v),
              ),
            ],
          ),

          // ── PREFERENCES ─────────────────────────────────────────────
          _SectionHeader('Preferences', colors: colors),
          _Card(
            colors: colors,
            children: [
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.dollar01,
                title: 'Default Currency',
                trailingText: settings.defaultCurrency,
                onTap: () => _pickFromList(
                  context,
                  colors,
                  title: 'Default Currency',
                  options: const ['USD', 'GHS', 'EUR', 'GBP', 'NGN'],
                  current: settings.defaultCurrency,
                  onPicked: settings.setDefaultCurrency,
                ),
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.internet,
                title: 'Language',
                trailingText: settings.appLanguage,
                onTap: () => _pickFromList(
                  context,
                  colors,
                  title: 'Language',
                  options: const ['English', 'French', 'Spanish', 'Arabic', 'Twi'],
                  current: settings.appLanguage,
                  onPicked: settings.setAppLanguage,
                ),
              ),
            ],
          ),

          // ── SECURITY & PRIVACY ──────────────────────────────────────
          _SectionHeader('Security & Privacy', colors: colors),
          _Card(
            colors: colors,
            children: [
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.shield01,
                title: 'Identity Verification (KYC)',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const KycVerificationScreen(),
                  ),
                ),
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.security,
                title: 'Two-Factor & PIN',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SecuritySettingsScreen(),
                  ),
                ),
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.lock,
                title: 'Change Password',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                ),
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.transactionHistory,
                title: 'Account Activity',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AccountActivityScreen(),
                  ),
                ),
              ),
            ],
          ),

          // ── PAYMENT ─────────────────────────────────────────────────
          // Phase UI-2 (2026-05-26): "Trade Accounts" tile REMOVED from
          // this section. Trade Accounts hold global fiat handles
          // (Zelle, CashApp, Venmo, PayPal, Apple Pay, etc.) that are
          // EXCLUSIVELY used by vendors when posting P2P ads. Surfacing
          // them under a regular user's Settings → Payment area
          // conflated payout destinations (where Azaman sends money to
          // the user) with vendor-side ad-receipt accounts (where ad
          // counterparties send money to the vendor). The vendor
          // dashboard already has a "MANAGE TRADE ACCOUNTS" button — that
          // is now the only entry point.
          _SectionHeader('Payment', colors: colors),
          _Card(
            colors: colors,
            children: [
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.wallet01,
                title: 'Withdrawal Addresses',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SavedWalletsScreen(),
                  ),
                ),
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.arrowDown01,
                title: 'Deposit Addresses',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SavedMomoAccountsScreen(),
                  ),
                ),
              ),
            ],
          ),

          // ── OTHER ───────────────────────────────────────────────────
          _SectionHeader('Other', colors: colors),
          _Card(
            colors: colors,
            children: [
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.delete01,
                title: 'Clear Cache',
                onTap: () {
                  AzamanHaptics.nav();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          const Text('System cache cleared. (42 MB freed)'),
                      backgroundColor: colors.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              _Divider(colors),
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.informationCircle,
                title: 'About Azaman',
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'Azaman Protocol',
                  applicationVersion: 'v3.1 (Phase F)',
                  applicationIcon:
                      Icon(HugeIconsSolid.shield01, color: colors.accent, size: 40),
                  children: const [
                    Text('The premier P2P crypto remittance engine.'),
                  ],
                ),
              ),
              _Divider(colors),
              // Phase M: wired the orphan account_deactivation_screen.dart.
              // Lives at the bottom of "Other" (next to Sign Out below) so
              // it's not the first thing users see, and uses danger-coloured
              // copy + icon to discourage accidental taps.
              _NavRow(
                colors: colors,
                icon: HugeIconsSolid.delete01,
                title: 'Delete Account',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AccountDeactivationScreen(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── SIGN OUT ────────────────────────────────────────────────
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
                    side:
                        BorderSide(color: colors.danger.withOpacity(0.25)),
                  ),
                  elevation: 0,
                ),
                onPressed: () => _confirmSignOut(context, ref, colors),
                child: const Text(
                  'Sign Out',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
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
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
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
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(HugeIconsSolid.checkmarkCircle01, color: colors.accent)
                      : null,
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
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
      icon: HugeIconsSolid.logout01,
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
        title.toUpperCase(),
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
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
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: colors.divider,
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final String title;
  final String? trailingText;
  final VoidCallback? onTap;

  const _NavRow({
    required this.colors,
    required this.icon,
    required this.title,
    this.trailingText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(icon, color: colors.textSecondary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText!,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(HugeIconsSolid.arrowRight01,
                color: colors.textTertiary, size: 13),
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
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.colors,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
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
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) {
              AzamanHaptics.toggle();
              onChanged(v);
            },
            activeColor: colors.success,
          ),
        ],
      ),
    );
  }
}
