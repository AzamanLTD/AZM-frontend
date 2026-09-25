import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';

class RiskTag extends ConsumerWidget {
  final String method;

  const RiskTag({super.key, required this.method});

  String get _riskLabel {
    final m = method.toLowerCase();
    if (m.contains('bank') || m.contains('wire')) return 'Low Risk';
    if (m.contains('momo') || m.contains('mtn') || m.contains('mobile') || m.contains('airtel')) {
      return 'Medium Risk';
    }
    return 'High Risk';
  }

  Color _riskColor(AzamanColors colors) {
    final m = method.toLowerCase();
    if (m.contains('bank') || m.contains('wire')) return colors.success;
    if (m.contains('momo') || m.contains('mtn') || m.contains('mobile') || m.contains('airtel')) {
      return colors.warning;
    }
    return colors.danger;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final Color rc = _riskColor(colors);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: rc.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: rc.withValues(alpha: 0.35),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: rc.withValues(alpha: 0.06),
            blurRadius: 6,
            spreadRadius: -1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(
              color: rc,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: rc.withValues(alpha: 0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _riskLabel,
            style: TextStyle(
              color: rc,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
