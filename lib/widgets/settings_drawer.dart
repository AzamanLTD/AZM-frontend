// lib/widgets/settings_drawer.dart
// =============================================================================
// AZAMAN — SETTINGS DRAWER (2026-11-27 redesign)
//
// Clean and premium, in the manner of the X side menu: a plain surface (no
// frosted glass, no glow), an identity header, then BIG destinations with
// outline icons, a hairline, quieter secondary rows, and a footer with the
// theme toggle. No staggered entrance and no shimmer: the drawer is revealed
// by the page sliding away (AzRevealDrawer), and that motion is enough.
//
//   [avatar]                          [QR]
//   Kofi ✓
//   @kofi   ·   AZM-8273941 ⧉
//
//   ○  Profile
//   ○  Accounts
//   ○  Verification            Verified
//   ○  Security & PIN      Biometrics on
//   ○  Azaman Store
//   ○  Refer & Earn
//   ○  Workplace               (employees only)
//   ─────────────────────────────
//   Currency                        GHS
//   All settings
//
//   ☾                          Azaman 3.1
//
// It works in two homes: inside AzRevealDrawer (the app shell) it is a bare
// panel and closes through AzRevealDrawerScope; mounted as a plain Scaffold
// endDrawer it wraps itself in a Drawer and closes by popping, as before.
// Every destination, the QR popup, the ID copy and the currency picker are
// unchanged; only the presentation moved.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/worker_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/screens/accounts_screen.dart';
import 'package:azaman/screens/azaman_store_screen.dart';
import 'package:azaman/screens/kyc_verification_screen.dart';
import 'package:azaman/screens/profile_details_screen.dart';
import 'package:azaman/screens/profile_screen.dart';
import 'package:azaman/screens/referral_screen.dart';
import 'package:azaman/screens/security_settings.dart';
import 'package:azaman/services/biometric_service.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/qr_profile_popup.dart';
import 'package:azaman/widgets/settings/az_reveal_drawer.dart';

class SettingsDrawer extends ConsumerStatefulWidget {
  const SettingsDrawer({super.key});

  @override
  ConsumerState<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends ConsumerState<SettingsDrawer> {
  // Real state for the Security chip — the same store the Security Center
  // reads. No fake badges: biometrics off renders no chip.
  bool _biometricsOn = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
    // The business profile is prefetched here (consumed by the
    // Marketplace), once, not on every build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final biz = ref.read(myBusinessProvider);
      if (!biz.hasLoaded && !biz.isLoading) {
        ref.read(myBusinessProvider.notifier).load();
      }
    });
  }

  Future<void> _loadBiometricState() async {
    final enabled = await BiometricService().isEnabled;
    if (mounted) setState(() => _biometricsOn = enabled);
  }

  // ── closing and navigating ────────────────────────────────────────────

  /// Close the drawer in whichever home it lives in.
  void _close() {
    final scope = AzRevealDrawerScope.maybeOf(context);
    if (scope != null) {
      scope.close();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Close, then open [destination] (a screen without a canonical route)
  /// or [route] (authoritative when the screen has one).
  void _go({Widget? destination, String? route}) {
    HapticFeedback.lightImpact();
    final navigator = Navigator.of(context);
    final router = GoRouter.maybeOf(context);
    _close();
    if (route != null && router != null) {
      router.push(route);
    } else if (destination != null) {
      navigator.push(MaterialPageRoute(builder: (_) => destination));
    }
  }

  // ── build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final user = ref.watch(currentUserProvider).value;
    final username = (user?.username.isNotEmpty ?? false) ? user!.username : 'Guest';

    // Material (not a bare ColoredBox): outside the Scaffold the rows'
    // ink still needs a sheet to print on.
    final panel = Material(
      color: colors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // A short, fixed list: built eagerly (a lazy list would leave
              // the secondary rows unbuilt on short screens).
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    colors: colors,
                    user: user,
                    username: username,
                    onOpenProfile: () => _go(destination: const ProfileScreen()),
                  ),
                  const SizedBox(height: 22),
                  _Row(
                    colors: colors,
                    icon: Icons.person_outline_rounded,
                    label: 'Profile',
                    onTap: () => _go(destination: const ProfileDetailsScreen()),
                  ),
                  _Row(
                    colors: colors,
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Accounts',
                    // Deposits and payout destinations: one concept.
                    onTap: () => _go(destination: const AccountsScreen()),
                  ),
                  _Row(
                    colors: colors,
                    icon: Icons.verified_outlined,
                    label: 'Verification',
                    status: _kycStatus(user?.kycStatus, colors),
                    onTap: () => _go(destination: const KycVerificationScreen()),
                  ),
                  _Row(
                    colors: colors,
                    icon: Icons.lock_outline_rounded,
                    label: 'Security & PIN',
                    status: _biometricsOn
                        ? _Status('Biometrics on', colors.textSecondary)
                        : null,
                    onTap: () => _go(destination: const SecuritySettingsScreen()),
                  ),
                  _Row(
                    colors: colors,
                    icon: Icons.storefront_outlined,
                    label: 'Azaman Store',
                    onTap: () => _go(destination: const AzamanStoreScreen()),
                  ),
                  _Row(
                    colors: colors,
                    icon: Icons.card_giftcard_outlined,
                    label: 'Refer & Earn',
                    onTap: () => _go(destination: const ReferralScreen()),
                  ),
                  // Employees only; renders nothing otherwise.
                  _WorkplaceRow(colors: colors, onOpen: () => _go(route: AzRoutes.workerHub)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 14, 8, 14),
                    child: Divider(height: 1, thickness: 0.6, color: colors.divider),
                  ),
                  _Row(
                    colors: colors,
                    secondary: true,
                    icon: Icons.payments_outlined,
                    label: 'Currency',
                    status: _Status(
                      ref.watch(currencyProvider).name.toUpperCase(),
                      colors.textSecondary,
                    ),
                    onTap: () => _pickCurrency(colors),
                  ),
                  _Row(
                    colors: colors,
                    secondary: true,
                    icon: Icons.tune_rounded,
                    label: 'All settings',
                    onTap: () => _go(route: AzRoutes.settings),
                  ),
                ],
              ),
              ),
            ),
            _Footer(colors: colors),
          ],
        ),
      ),
    );

    if (AzRevealDrawerScope.maybeOf(context) != null) return panel;
    // Plain endDrawer home: the inner edge (LEFT, for a right drawer) is the
    // one that rounds.
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.86,
      backgroundColor: colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(28)),
      ),
      child: panel,
    );
  }

  _Status? _kycStatus(KycStatus? status, AzamanColors colors) {
    switch (status) {
      case KycStatus.verified:
        return _Status('Verified', colors.success);
      case KycStatus.pending:
        return _Status('Pending', colors.warning);
      case KycStatus.rejected:
        return _Status('Action needed', colors.danger);
      default:
        return null;
    }
  }

  Future<void> _pickCurrency(AzamanColors colors) async {
    HapticFeedback.lightImpact();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            for (final option in const ['USDC', 'GHS'])
              ListTile(
                title: Text(option, style: TextStyle(color: colors.textPrimary)),
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
}

// ── header ───────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.colors,
    required this.user,
    required this.username,
    required this.onOpenProfile,
  });

  final AzamanColors colors;
  final User? user;
  final String username;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final azamanId = user?.azamanId;
    final verified = user?.kycStatus == KycStatus.verified;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: 'Open your profile',
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('profile_hero_avatar'),
                onTap: onOpenProfile,
                child: _Avatar(colors: colors, user: user, username: username, size: 52),
              ),
            ),
            const Spacer(),
            Semantics(
              button: true,
              label: 'Show my Azaman QR code',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => showQrProfilePopup(context, username),
                child: QrProfileThumbnail(
                  key: const ValueKey('profile_hero_qr'),
                  username: username,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Flexible(
              child: Text(
                username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            if (verified) ...[
              const SizedBox(width: 6),
              Icon(Icons.verified_rounded, size: 18, color: colors.accent),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              '@$username',
              style: TextStyle(color: colors.textSecondary, fontSize: 15),
            ),
            if (azamanId != null && azamanId.isNotEmpty) ...[
              Text('·', style: TextStyle(color: colors.textTertiary, fontSize: 15)),
              GestureDetector(
                key: const ValueKey('profile_hero_azm'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: azamanId));
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(
                      content: Text('Copied $azamanId'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      azamanId,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13.5,
                        fontFamily: AzText.numericFamily,
                        fontFeatures: AzText.tabular,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.copy_rounded, size: 13, color: colors.textTertiary),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.colors, required this.user, required this.username, required this.size});

  final AzamanColors colors;
  final User? user;
  final String username;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = user?.profilePictureUrl;
    final initial = username.trim().isEmpty ? 'A' : username.trim()[0].toUpperCase();
    final monogram = Center(
      child: Text(
        initial,
        style: TextStyle(color: colors.textPrimary, fontSize: size * 0.4, fontWeight: FontWeight.w800),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: colors.softSurface),
      clipBehavior: Clip.antiAlias,
      child: (url != null && url.isNotEmpty)
          ? AzamanNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => monogram,
            )
          : monogram,
    );
  }
}

// ── rows ─────────────────────────────────────────────────────────────────

class _Status {
  const _Status(this.label, this.color);
  final String label;
  final Color color;
}

/// A destination. Primary rows are big (the X rhythm: 22px type, 26px outline
/// icon, generous height); secondary rows are quieter.
class _Row extends StatelessWidget {
  const _Row({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onTap,
    this.status,
    this.secondary = false,
  });

  final AzamanColors colors;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final _Status? status;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: status == null ? label : '$label, ${status!.label}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        highlightColor: colors.textPrimary.withValues(alpha: 0.06),
        splashColor: colors.textPrimary.withValues(alpha: 0.04),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: secondary ? 12 : 14, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: secondary ? 22 : 26, color: colors.textPrimary),
              SizedBox(width: secondary ? 16 : 20),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: secondary ? 16 : 21,
                    fontWeight: secondary ? FontWeight.w600 : FontWeight.w700,
                    letterSpacing: secondary ? 0 : -0.2,
                  ),
                ),
              ),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    status!.label,
                    style: TextStyle(
                      color: status!.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The workplace entry, for active employees only.
class _WorkplaceRow extends ConsumerWidget {
  const _WorkplaceRow({required this.colors, required this.onOpen});

  final AzamanColors colors;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(myEmployeeProvider).maybeWhen(
          data: (employee) => employee == null
              ? const SizedBox.shrink()
              : _Row(
                  colors: colors,
                  icon: Icons.badge_outlined,
                  label: 'Workplace',
                  onTap: onOpen,
                ),
          orElse: () => const SizedBox.shrink(),
        );
  }
}

// ── footer ───────────────────────────────────────────────────────────────

class _Footer extends ConsumerWidget {
  const _Footer({required this.colors});

  final AzamanColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final dark = theme.currentTheme == AzamanTheme.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 24, 16),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: dark ? 'Switch to light theme' : 'Switch to dark theme',
            excludeSemantics: true,
            child: IconButton(
              key: const ValueKey('drawer-theme-toggle'),
              onPressed: () {
                HapticFeedback.selectionClick();
                theme.setTheme(dark ? AzamanTheme.light : AzamanTheme.dark);
              },
              icon: Icon(
                dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                color: colors.textPrimary,
                size: 24,
              ),
            ),
          ),
          const Spacer(),
          Text(
            'Azaman 3.1',
            style: TextStyle(color: colors.textTertiary, fontSize: 11, letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}
