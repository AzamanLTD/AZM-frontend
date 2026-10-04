// Azaman trust language (brief §7.5): exactly one TrustMark per surface.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';

enum TrustLevel { verified, kybPending, none }

TrustLevel trustLevelOf(BusinessProfile business) => business.isVerified
    ? TrustLevel.verified
    : (business.kybStatus == 'PENDING' ? TrustLevel.kybPending : TrustLevel.none);

class TrustMark extends ConsumerWidget {
  final BusinessProfile business;
  final bool compact;
  const TrustMark({super.key, required this.business, this.compact = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = trustLevelOf(business);
    if (level == TrustLevel.none) return const SizedBox.shrink();
    final colors = ref.watch(themeProvider).colors;
    final verified = level == TrustLevel.verified;
    final icon = verified ? HugeIconsSolid.checkmarkBadge01 : HugeIconsSolid.clock01;
    final label = verified ? 'Verified' : 'Verification pending';
    final color = verified ? colors.accent : colors.textTertiary;
    return Semantics(
      label: '$label business',
      child: compact
          ? Icon(icon, key: ValueKey('trust_mark_${level.name}'), size: 16, color: color)
          : Row(
              key: ValueKey('trust_mark_${level.name}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: AzSpace.xs),
                Text(label, style: AzText.caption.copyWith(color: color)),
              ],
            ),
    );
  }
}