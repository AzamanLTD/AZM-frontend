// =============================================================================
// VAULT PROGRESS CARD  (Master Sprint, 2026-05-27)
//
// Slender vault row matching the new aesthetic:
//   • 32×32 lock icon plate (gradient ring when ACTIVE)
//   • Title + maturity countdown
//   • Slim linear progress + percent label
//   • Streak chip + AZM-earned chip
// =============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/vault_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class VaultProgressCard extends StatelessWidget {
  final Vault vault;
  final AzamanColors colors;
  final VoidCallback onTap;

  const VaultProgressCard({
    super.key,
    required this.vault,
    required this.colors,
    required this.onTap,
  });

  String _shortDuration(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d';
    if (d.inHours >= 1) return '${d.inHours}h';
    return '${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final progress = vault.progressFraction;
    final isActive = vault.status == 'ACTIVE';
    final remaining = vault.maturityDate.difference(DateTime.now());
    final accent = isActive ? colors.accent : colors.textTertiary;
    final rate = 0.08;
    final daysTotal = vault.maturityDate.difference(vault.startDate).inDays;
    final projected = vault.targetAmountUsdc * rate * (daysTotal / 365);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: colors.card.withOpacity(0.55),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accent.withOpacity(0.20),
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accent.withOpacity(0.25),
                            accent.withOpacity(0.10),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: accent.withOpacity(0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(
                        isActive ? HugeIconsSolid.lock : HugeIconsSolid.lockKey,
                        color: accent,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            vault.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _statusLine(remaining),
                            style: TextStyle(
                              color: colors.textTertiary,
                              fontSize: 11,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusBadge(status: vault.status, colors: colors),
                  ],
                ),
                const SizedBox(height: 12),
                // Progress ring + details
                Row(children: [
                  SizedBox(
                    width: 56, height: 56,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox(
                        width: 56, height: 56,
                        child: CircularProgressIndicator(
                          value: progress.toDouble(),
                          strokeWidth: 4,
                          color: accent,
                          backgroundColor: colors.softSurface,
                        ),
                      ),
                      Text("${(progress * 100).toInt()}%",
                        style: TextStyle(
                          color: accent,
                          fontSize: 11, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      '\$${vault.currentAmountUsdc.toStringAsFixed(2)} / \$${vault.targetAmountUsdc.toStringAsFixed(2)} USDC',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Projected: +${projected.toStringAsFixed(2)} USDC by ${_shortDate(vault.maturityDate)}",
                      style: TextStyle(color: colors.success, fontSize: 11,
                        fontWeight: FontWeight.w600),
                    ),
                  ])),
                ]),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Chip(
                      icon: HugeIconsSolid.fire,
                      label: '${vault.streakCount}',
                      color: colors.warning,
                    ),
                    const SizedBox(width: 6),
                    _Chip(
                      icon: HugeIconsSolid.flash,
                      label: vault.totalAzmEarned.toStringAsFixed(0),
                      color: colors.accentSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _shortDate(DateTime dt) {
    final months = ["Jan","Feb","Mar","Apr","May","Jun",
                    "Jul","Aug","Sep","Oct","Nov","Dec"];
    return "${dt.day} ${months[dt.month-1]} ${dt.year}";
  }

  String _statusLine(Duration remaining) {
    if (vault.status == 'COMPLETED') return 'Completed · receipt ready';
    if (vault.status == 'BROKEN_EARLY') return 'Broken early';
    if (vault.status == 'CANCELLED') return 'Cancelled';
    if (remaining.isNegative) return 'Maturing soon';
    return 'Matures in ${_shortDuration(remaining)}';
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final AzamanColors colors;
  const _StatusBadge({required this.status, required this.colors});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'ACTIVE' => ('LIVE', colors.success),
      'COMPLETED' => ('DONE', colors.accent),
      'BROKEN_EARLY' => ('BROKEN', colors.danger),
      _ => ('—', colors.textTertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: color.withOpacity(0.10),
        border: Border.all(color: color.withOpacity(0.30), width: 0.7),
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

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color.withOpacity(0.10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
