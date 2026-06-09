import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/azm_rewards_screen.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class HologramBalanceCard extends ConsumerWidget {
  const HologramBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final balanceData = ref.watch(balanceDataProvider);
    final oracleRate = ref.watch(oracleRateProvider);
    final isVisible = ref.watch(balanceVisibleProvider);
    final user = ref.watch(authProvider).user;

    final totalUsdc = balanceData.totalBalance;
    final ghsEquivalent = totalUsdc * oracleRate;

    final uid = user?.id ?? '';
    final truncatedId = uid.length > 8
        ? '${uid.substring(0, 4)}...${uid.substring(uid.length - 4)}'
        : uid;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colors.divider,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
              child: Row(
                children: [
                  Text(
                    'Main account',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (truncatedId.isNotEmpty)
                    Text(
                      truncatedId,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Portfolio value',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref.read(balanceVisibleProvider.notifier).state =
                              !isVisible;
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              isVisible
                                  ? HugeIconsSolid.view
                                  : HugeIconsSolid.viewOff,
                              key: ValueKey(isVisible),
                              color: colors.textTertiary,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _CountUpNumber(
                    value: totalUsdc,
                    isVisible: isVisible,
                    colors: colors,
                    prefix: '\$',
                    suffix: ' USDC',
                    fontSize: 40,
                  ),
                  const SizedBox(height: 6),

                  _CountUpNumber(
                    value: ghsEquivalent,
                    isVisible: isVisible,
                    colors: colors,
                    prefix: 'GH\u20B5 ',
                    suffix: '',
                    fontSize: 14,
                  ),

                  const SizedBox(height: 20),

                  _BalanceChipsRow(
                    colors: colors,
                    isVisible: isVisible,
                    available: balanceData.availableBalance,
                    escrow: balanceData.escrowLockedBalance,
                    azm: balanceData.azmBalance,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 380.ms, curve: Curves.easeOut)
        .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
  }
}

class _CountUpNumber extends StatefulWidget {
  final double value;
  final bool isVisible;
  final AzamanColors colors;
  final String prefix;
  final String suffix;
  final double fontSize;

  const _CountUpNumber({
    required this.value,
    required this.isVisible,
    required this.colors,
    required this.prefix,
    required this.suffix,
    required this.fontSize,
  });

  @override
  State<_CountUpNumber> createState() => _CountUpNumberState();
}

class _CountUpNumberState extends State<_CountUpNumber>
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
  void didUpdateWidget(covariant _CountUpNumber oldWidget) {
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
            ? '${widget.prefix}${_formatNumber(v)}${widget.suffix}'
            : '${widget.prefix}\u2022\u2022\u2022\u2022\u2022\u2022${widget.suffix}';

        return Text(
          text,
          style: TextStyle(
            color: widget.colors.textPrimary,
            fontSize: widget.fontSize,
            fontWeight: widget.fontSize > 20 ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: widget.fontSize > 20 ? -0.8 : -0.2,
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

class _BalanceChipsRow extends StatelessWidget {
  final AzamanColors colors;
  final bool isVisible;
  final double available;
  final double escrow;
  final double azm;

  const _BalanceChipsRow({
    required this.colors,
    required this.isVisible,
    required this.available,
    required this.escrow,
    required this.azm,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _BalanceChip(
        colors: colors,
        label: 'Available',
        value: available,
        isVisible: isVisible,
        chipColor: colors.success,
      ),
      _BalanceChip(
        colors: colors,
        label: 'Escrow',
        value: escrow,
        isVisible: isVisible,
        chipColor: colors.warning,
      ),
      _BalanceChip(
        colors: colors,
        label: 'AZM',
        value: azm,
        isVisible: isVisible,
        chipColor: colors.accentSecondary,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AzmRewardsScreen(),
            ),
          );
        },
      ),
    ];

    return Row(
      children: [
        for (int i = 0; i < chips.length; i++) ...[
          Expanded(
            child: chips[i]
                .animate()
                .fadeIn(
                  delay: (180 + i * 80).ms,
                  duration: 320.ms,
                  curve: Curves.easeOut,
                )
                .slideY(begin: 0.25, end: 0, curve: Curves.easeOutCubic),
          ),
          if (i < chips.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _BalanceChip extends StatelessWidget {
  final AzamanColors colors;
  final String label;
  final double value;
  final bool isVisible;
  final Color chipColor;
  final VoidCallback? onTap;

  const _BalanceChip({
    required this.colors,
    required this.label,
    required this.value,
    required this.isVisible,
    required this.chipColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: chipColor.withValues(alpha: 0.06),
        border: Border.all(
          color: chipColor.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chipColor,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              if (onTap != null) ...[
                const Spacer(),
                Icon(
                  HugeIconsSolid.arrowRight01,
                  size: 11,
                  color: colors.textTertiary,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: Text(
              isVisible
                  ? (label == 'AZM'
                      ? value.toStringAsFixed(1)
                      : '\$${value.toStringAsFixed(2)}')
                  : '\u2022\u2022\u2022\u2022',
              key: ValueKey(isVisible ? value : 'hidden'),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );

    return onTap != null
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: child,
          )
        : child;
  }
}
