// =============================================================================
// AZAMAN — ACCOUNTS  (the single home for saved money endpoints)
//
// The settings IA keeps ONE entry: "Accounts". Deposit sources (MoMo
// STK-push) and payout destinations live together here as two clean
// rows, exactly as the approved mockup drew it — no split entries in
// the settings IA, no icon boxes.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/saved_momo_accounts_screen.dart';
import 'package:azaman/screens/saved_wallets_screen.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/nav_transitions.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Accounts',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _AccountsRow(
            colors: colors,
            icon: Icons.arrow_downward,
            iconColor: colors.accent,
            title: 'Deposit accounts',
            subtitle: 'MoMo numbers saved for STK-push',
            onTap: () => pushWithVerticalTransition(
              context,
              const SavedMomoAccountsScreen(),
            ),
          ),
          const SizedBox(height: 10),
          _AccountsRow(
            colors: colors,
            icon: Icons.arrow_upward,
            iconColor: colors.accent,
            title: 'Payout destinations',
            subtitle: 'Where withdrawals land',
            onTap: () => pushWithVerticalTransition(
              context,
              const SavedWalletsScreen(),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountsRow extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AccountsRow({
    required this.colors,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = colors.isDark;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        AzamanHaptics.nav();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(18),
          border: isDark
              ? Border.all(color: colors.divider.withValues(alpha: 0.45))
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: const Color(0x0A000000).withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11.5,
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
}
