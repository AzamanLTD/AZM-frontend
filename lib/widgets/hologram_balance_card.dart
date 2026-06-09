import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class HologramBalanceCard extends ConsumerWidget {
  const HologramBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final balanceData = ref.watch(balanceDataProvider);
    final isVisible = ref.watch(balanceVisibleProvider);
    final user = ref.watch(authProvider).user;

    final totalUsdc = balanceData.totalBalance;
    final uid = user?.id ?? '';
    final truncatedId = uid.length > 6
        ? '\u00b7\u00b7 ${uid.substring(uid.length - 4)}'
        : uid;

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.divider, width: 1),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accent.withValues(alpha: 0.12),
                  border: Border.all(color: colors.divider, width: 1),
                ),
                child: Text(
                  '\$',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'USDC',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (truncatedId.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  HugeIconsSolid.wallet01,
                  size: 14,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  truncatedId,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          _BalanceNumber(
            value: totalUsdc,
            isVisible: isVisible,
            colors: colors,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 380.ms, curve: Curves.easeOut).slideY(
          begin: 0.04,
          end: 0,
          curve: Curves.easeOutCubic,
        );
  }
}

class _BalanceNumber extends StatefulWidget {
  final double value;
  final bool isVisible;
  final AzamanColors colors;

  const _BalanceNumber({
    required this.value,
    required this.isVisible,
    required this.colors,
  });

  @override
  State<_BalanceNumber> createState() => _BalanceNumberState();
}

class _BalanceNumberState extends State<_BalanceNumber>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _from = 0;
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _from = 0;
    _to = widget.value;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _anim = Tween<double>(begin: _from, end: _to)
        .chain(CurveTween(curve: Curves.easeOutQuint))
        .animate(_ctrl);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _BalanceNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _from = _anim.value;
      _to = widget.value;
      _anim = Tween<double>(begin: _from, end: _to)
          .chain(CurveTween(curve: Curves.easeOutQuint))
          .animate(_ctrl);
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final v = _anim.value;
        final text = widget.isVisible
            ? _formatNumber(v)
            : '\u2022\u2022\u2022\u2022\u2022\u2022';

        return Text(
          text,
          style: TextStyle(
            color: widget.colors.textPrimary,
            fontSize: 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }

  String _formatNumber(double value) {
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
