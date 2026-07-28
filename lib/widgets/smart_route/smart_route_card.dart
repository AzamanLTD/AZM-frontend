// =============================================================================
// SMART ROUTE CARD  (Master Sprint, 2026-05-27)
//
// Slender route summary with:
//   • action icon plate
//   • route name
//   • amount + frequency
//   • next-run countdown
//   • status pill (LIVE | PAUSED | CANCELLED | COMPLETED)
// =============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:azaman/providers/smart_route_provider.dart';
import 'package:azaman/providers/theme_provider.dart';


class SmartRouteCard extends StatelessWidget {
  final SmartRoute route;
  final AzamanColors colors;
  const SmartRouteCard({super.key, required this.route, required this.colors});

  IconData get _icon => switch (route.action) {
        'WITHDRAW_MOMO' => Icons.smartphone_outlined,
        'INTERNAL_TRANSFER' => Icons.swap_horiz,
        'SAVINGS_DEPOSIT' => Icons.savings_outlined,
        'VAULT_DEPOSIT' => Icons.lock_outline,
        _ => Icons.turn_left,
      };

  Color _accent() => switch (route.action) {
        'WITHDRAW_MOMO' => colors.warning,
        'INTERNAL_TRANSFER' => colors.success,
        'SAVINGS_DEPOSIT' => colors.accent,
        'VAULT_DEPOSIT' => colors.accentSecondary,
        _ => colors.textSecondary,
      };

  String _short(DateTime t) {
    final diff = t.difference(DateTime.now());
    if (diff.isNegative) return 'now';
    if (diff.inHours < 24) return 'in ${diff.inHours}h';
    return 'in ${diff.inDays}d';
  }

  String _destLabel() {
    switch (route.action) {
      case 'WITHDRAW_MOMO':
        return route.destMomoNumber ?? 'MoMo';
      case 'INTERNAL_TRANSFER':
        return 'Friend #${route.destFriendUserId ?? '—'}';
      case 'SAVINGS_DEPOSIT':
        return 'Savings goal';
      case 'VAULT_DEPOSIT':
        return 'Vault';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: colors.card.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accent.withValues(alpha: 0.20),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon, color: accent, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      route.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '\$${route.amountUsdc.toStringAsFixed(2)} · ${route.frequency.toLowerCase()} → ${_destLabel()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusPill(status: route.status, colors: colors),
                  const SizedBox(height: 4),
                  Text(
                    _short(route.nextRunAt),
                    style: TextStyle(color: colors.textTertiary, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  final AzamanColors colors;
  const _StatusPill({required this.status, required this.colors});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'ACTIVE' => ('LIVE', colors.success),
      'PAUSED' => ('PAUSED', colors.warning),
      'CANCELLED' => ('OFF', colors.textTertiary),
      'COMPLETED' => ('DONE', colors.accent),
      _ => ('—', colors.textTertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 0.7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
