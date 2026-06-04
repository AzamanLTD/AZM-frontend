// =============================================================================
// QUICK ACTIONS ROW  (Polish Sprint)
//
// Three circular glassmorphism buttons placed *below* the slender Black
// Card on the main feed: Deposit · Withdraw · Transfer. Designed to pop
// against the deep scaffold background — frosted disc with 10% white
// border, soft drop-shadow, springy press animation.
//
// History is intentionally absent (per Polish Sprint spec).
// =============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';
import 'package:azaman/screens/withdrawal_screen.dart';

/// Three-button quick-action row. Place directly below DashboardBalanceCard.
class QuickActionsRow extends ConsumerWidget {
  /// Optional overrides — each defaults to a sensible navigation target
  /// (Deposit → DepositScreen with crypto+fiat tabs,
  /// Withdraw → WithdrawalScreen,
  /// Transfer → FriendsHubScreen for internal user→user transfers).
  final VoidCallback? onDeposit;
  final VoidCallback? onWithdraw;
  final VoidCallback? onTransfer;

  const QuickActionsRow({
    super.key,
    this.onDeposit,
    this.onWithdraw,
    this.onTransfer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _GlassActionButton(
            colors: colors,
            icon: Icons.south_rounded,
            label: 'Deposit',
            onTap: onDeposit ?? () => _defaultDeposit(context),
          ),
          _GlassActionButton(
            colors: colors,
            icon: Icons.north_rounded,
            label: 'Withdraw',
            onTap: onWithdraw ?? () => _defaultWithdraw(context),
          ),
          _GlassActionButton(
            colors: colors,
            icon: Icons.sync_alt_rounded,
            label: 'Transfer',
            onTap: onTransfer ?? () => _defaultTransfer(context, ref),
          ),
        ],
      ),
    );
  }

  // ── Default handlers ────────────────────────────────────────────────────
  void _defaultDeposit(BuildContext ctx) {
    HapticFeedback.lightImpact();
    // Both the Home dashboard and the P2P market feed route Deposit to the
    // SAME unified screen so users get one consistent surface with crypto
    // and mobile-money tabs side-by-side.
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => const DepositScreen()),
    );
  }

  void _defaultWithdraw(BuildContext ctx) {
    HapticFeedback.lightImpact();
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => const WithdrawalScreen()),
    );
  }

  void _defaultTransfer(BuildContext ctx, WidgetRef ref) {
    HapticFeedback.selectionClick();
    // Internal transfers are friend-scoped — the TransferModal needs a
    // friendshipId + username, so the entry point is the Friends Hub.
    // Once on the hub, the user picks a friend and uses the chat
    // transfer affordance (the "+" / send-crypto button on the chat).
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => const FriendsHubScreen()),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One glass circular button + label.
// ─────────────────────────────────────────────────────────────────────────────
class _GlassActionButton extends StatefulWidget {
  final AzamanColors colors;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GlassActionButton({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_GlassActionButton> createState() => _GlassActionButtonState();
}

class _GlassActionButtonState extends State<_GlassActionButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    // Theme-aware tints so light themes don't render invisible buttons.
    // On dark themes we still want the frosted "lifted" feel — a soft
    // white bloom on the disc. On light themes that bloom is *inverted*
    // to a dark tint so the disc reads as a tactile shadow against the
    // bright background. Same logic for the label.
    final discTint = colors.isDark
        ? Colors.white.withOpacity(_pressed ? 0.14 : 0.10)
        : colors.accent.withOpacity(_pressed ? 0.16 : 0.10);
    final discTintEnd = colors.isDark
        ? Colors.white.withOpacity(0.025)
        : colors.accent.withOpacity(0.04);
    final discBorder = colors.isDark
        ? Colors.white.withOpacity(0.12)
        : colors.accent.withOpacity(0.30);
    final discIcon = colors.isDark ? Colors.white : colors.accent;
    final labelColor = colors.textSecondary;
    final shadowColor = colors.isDark
        ? Colors.black.withOpacity(0.45)
        : colors.accent.withOpacity(0.22);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Frosted glass disc
            ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [discTint, discTintEnd],
                    ),
                    border: Border.all(color: discBorder, width: 0.8),
                    boxShadow: [
                      BoxShadow(
                        color: shadowColor,
                        blurRadius: 12,
                        spreadRadius: -2,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(widget.icon, color: discIcon, size: 22),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.label,
              style: TextStyle(
                color: labelColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
