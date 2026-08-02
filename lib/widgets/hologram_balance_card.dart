import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/animated_number.dart';


class HologramBalanceCard extends ConsumerWidget {
  const HologramBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final balanceData = ref.watch(balanceDataProvider);
    final user = ref.watch(authProvider).user;

    final totalUsdc = balanceData.totalBalance;
    final uid = user?.id ?? '';
    final truncatedId = uid.length > 6
        ? '\u00b7\u00b7 ${uid.substring(uid.length - 4)}'
        : uid;

    return Container(
      constraints: const BoxConstraints(minHeight: 158),
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accent.withValues(alpha: 0.14),
                ),
                child: Text(
                  '\$',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Text(
                'USDC',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (truncatedId.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
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
            const SizedBox(height: 4),
          ],
          Consumer(
            builder: (context, ref, _) {
              final isVisible = ref.watch(balanceVisibleProvider);
              final rate = ref.watch(oracleRateProvider);
              final ghsVal = totalUsdc * rate;
              final currency = ref.watch(currencyProvider);
              final ghsFirst = currency == DisplayCurrency.ghs;
              String fmtGhs(double v) {
                final parts = v.toStringAsFixed(2).split('.');
                final intPart = parts[0];
                final buf = StringBuffer();
                for (int i = 0; i < intPart.length; i++) {
                  if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
                  buf.write(intPart[i]);
                }
                return '$buf.${parts[1]}';
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                isVisible
                    ? AnimatedNumber(
                        value: ghsFirst ? ghsVal : totalUsdc,
                        formatter: (v) => ghsFirst
                            ? 'GH₵ ${fmtGhs(v)}'
                            : '${v.toStringAsFixed(2)} USDC',
                        duration: const Duration(milliseconds: 600),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      )
                    : Text('••••••',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                const SizedBox(height: 2),
                if (isVisible)
                  Text(
                    ghsFirst ? '${totalUsdc.toStringAsFixed(2)} USDC' : 'GH₵ ${fmtGhs(ghsVal)}',
                    style: TextStyle(
                      color: colors.textSecondary.withValues(alpha: 0.75),
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(children: [
                  Container(width: 6, height: 6,
                    decoration: BoxDecoration(color: colors.success, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.3),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Text(
                      "1 USDC = GH₵ ${rate.toStringAsFixed(2)}",
                      key: ValueKey(rate.toStringAsFixed(2)),
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ]),
              ]);
            },
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

        return SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: TextStyle(
                color: widget.colors.textPrimary,
                fontSize: 33,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
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
