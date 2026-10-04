// "Pick up where you left off" — rendered only when a real intent exists.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/marketplace_resume_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/scale_tap.dart';

/// Bubbled up to the hosting screen for intents it must handle itself
/// (world search → `_enterExplore(wire)`).
class ResumeIntentNotification extends Notification {
  final ResumeIntent intent;
  const ResumeIntentNotification(this.intent);
}

class ResumeCard extends ConsumerWidget {
  const ResumeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intent = ref.watch(marketplaceResumeProvider);
    if (intent == null) return const SizedBox.shrink();
    final colors = ref.watch(themeProvider).colors;
    final icon = intent.kind == ResumeKind.cart
        ? HugeIconsSolid.shoppingCart01
        : HugeIconsSolid.search01;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AzSpace.lg, 0, AzSpace.lg, AzSpace.lg),
      child: ScaleTap(
        onTap: () => _resume(context, intent),
        child: Container(
          key: const ValueKey('marketplace_resume_card'),
          padding: const EdgeInsets.all(AzSpace.lg),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AzRadius.lg),
          ),
          child: Row(children: [
            Icon(icon, color: colors.accent),
            const SizedBox(width: AzSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pick up where you left off',
                      style: AzText.caption.copyWith(color: colors.textTertiary)),
                  Text(intent.title,
                      style: AzText.title.copyWith(color: colors.textPrimary), maxLines: 2),
                  Text(intent.subtitle,
                      style: AzText.bodyS.copyWith(color: colors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
          ]),
        ),
      ),
    );
  }

  void _resume(BuildContext context, ResumeIntent intent) {
    switch (intent.kind) {
      case ResumeKind.cart:
        context.push(AzRoutes.cart);
      case ResumeKind.worldSearch:
        ResumeIntentNotification(intent).dispatch(context);
    }
  }
}