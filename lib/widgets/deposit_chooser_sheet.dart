// =============================================================================
// AZAMAN — DEPOSIT CHOOSER SHEET
//
// Bottom sheet that presents the two ways a user can fund their account:
//
//   1. Crypto Deposit — Polygon USDC, instant once on-chain. Routes to
//      CryptoDepositScreen which fetches the user's HD wallet address from
//      GET /api/wallet/deposit-address/polygon and renders it as QR + copy.
//
//   2. Fiat Deposit   — MTN MoMo / Vodafone / AirtelTigo / bank. Routes to
//      FiatDepositFlowScreen which posts to /api/deposit/fiat/initiate and
//      shows the user the payment instructions + reference code.
//
// Phase C addition (2026-05): the home Quick Action for "Deposit" used to
// route directly to the fiat flow, leaving CryptoDepositScreen orphan and
// users with no way to deposit USDC on Polygon. This sheet is the entry
// point that resolves that.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/crypto_deposit_screen.dart';
import 'package:azaman/screens/fiat_deposit_flow_screen.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class DepositChooserSheet extends ConsumerWidget {
  const DepositChooserSheet({super.key});

  /// Convenience opener — `await DepositChooserSheet.show(context)` from
  /// any callsite. Returns whatever the chooser pushed (or null if dismissed).
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DepositChooserSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          Text(
            'Deposit Funds',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Choose how you want to fund your account.',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),

          _DepositOption(
            icon: HugeIconsSolid.bitcoin,
            iconColor: colors.success,
            title: 'Crypto (Polygon USDC)',
            subtitle:
                'Instant on-chain credit. Use your unique deposit address. '
                'Network: Polygon. Token: USDC only.',
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CryptoDepositScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _DepositOption(
            icon: HugeIconsSolid.wallet01,
            iconColor: colors.accent,
            title: 'Fiat (Mobile Money)',
            subtitle:
                'MTN, Vodafone, AirtelTigo or bank transfer. We re-quote at '
                'the live rate when your payment lands.',
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FiatDepositFlowScreen(),
                ),
              );
            },
          ),

          const SizedBox(height: 14),
          Text(
            'Crypto deposits land instantly once confirmed on-chain. '
            'Fiat deposits clear in 1–5 minutes after the gateway confirms payment.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Single option tile ──────────────────────────────────────────────────────

class _DepositOption extends ConsumerWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DepositOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: iconColor.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
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
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              HugeIconsSolid.arrowRight01,
              color: colors.textTertiary,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
