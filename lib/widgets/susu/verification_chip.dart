// =============================================================================
// VERIFICATION CHIP — Phase 5 / Workstream D (2026-06-01)
//
// Small color-coded pill shown after a member's name during Susu
// initiation. Red = not started / rejected / expired, Yellow = in process
// (PENDING / PENDING_REVIEW), Green = verified. Used for both KYC and PoA.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class VerificationChip extends StatelessWidget {
  final String label; // 'KYC' | 'PoA'
  final String state; // 'red' | 'yellow' | 'green'
  final AzamanColors colors;

  const VerificationChip({
    super.key,
    required this.label,
    required this.state,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      'green' => colors.success,
      'yellow' => colors.warning,
      _ => colors.danger,
    };
    final icon = switch (state) {
      'green' => HugeIconsSolid.checkmarkCircle01,
      'yellow' => HugeIconsSolid.hourglass,
      _ => HugeIconsSolid.cancel01,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.40), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
