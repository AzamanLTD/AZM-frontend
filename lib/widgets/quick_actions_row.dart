import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';
import 'package:azaman/screens/withdrawal_screen.dart';

class QuickActionsRow extends ConsumerWidget {
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
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SoftActionButton(
            colors: colors,
            icon: Icons.call_received,
            label: 'Deposit',
            onTap: onDeposit ?? () => _defaultDeposit(context),
          ),
          _SoftActionButton(
            colors: colors,
            icon: Icons.call_made,
            label: 'Withdraw',
            onTap: onWithdraw ?? () => _defaultWithdraw(context),
          ),
          _SoftActionButton(
            colors: colors,
            icon: Icons.swap_horiz,
            label: 'Transfer',
            onTap: onTransfer ?? () => _defaultTransfer(context, ref),
          ),
        ],
      ),
    );
  }

  void _defaultDeposit(BuildContext ctx) {
    HapticFeedback.lightImpact();
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
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => const FriendsHubScreen()),
    );
  }
}

class _SoftActionButton extends StatefulWidget {
  final AzamanColors colors;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SoftActionButton({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_SoftActionButton> createState() => _SoftActionButtonState();
}

class _SoftActionButtonState extends State<_SoftActionButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

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
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.softSurface,
              ),
              child: Icon(widget.icon, color: colors.textPrimary, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              widget.label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
