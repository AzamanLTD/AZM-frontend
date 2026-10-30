// AZAMAN — SAVE / P2P / SUSU / BILLS BUBBLES
//
// Home block 3. Four circular controls, one row, at every supported width:
//
//   SAVE  → /savings                          (unchanged destination)
//   P2P   → the canonical /marketplace screen (unchanged destination)
//   SUSU  → the deterministic active group, else the susu hub (unchanged)
//   BILLS → the canonical /bills destination  (new)
//
// OWNER DECISION (2026-10-30): the caption lives INSIDE the bubble, not under
// it. So the circle carries BOTH the symbol and the word — icon above, label
// below it, the pair centred inside one rim. An earlier brief asked for the
// label below the circle; the owner overrode that while sending the brief, and
// this file implements the override.
//
// Material language is unchanged from the pills these replace (PR #184):
// FLAT, border-only, no fill, no glass, no gradient, no glow, no shadow. The
// quiet-depth cycle still animates the RIM ALONE, which is why the content
// subtree is never inside the backdrop.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/quiet_depth.dart';
import 'package:azaman/widgets/scale_tap.dart';

/// Deterministic active-group selection, unchanged: the first active group in
/// the server's own order wins.
SusuSummary? chooseMostRelevantSusu(List<SusuSummary> groups) {
  SusuSummary? best;
  DateTime? bestRunAt;
  for (final g in groups) {
    if (g.status != SusuStatus.active) continue;
    final runAt = g.nextCycle?.scheduledRunAt;
    if (best == null) {
      best = g;
      bestRunAt = runAt;
      continue;
    }
    if (runAt == null) continue; // best already chosen; unscheduled loses
    if (bestRunAt == null || runAt.isBefore(bestRunAt)) {
      best = g;
      bestRunAt = runAt;
    }
  }
  return best;
}

/// The Home resting row: four circular controls, no descriptions.
class WalletModulesRow extends ConsumerWidget {
  const WalletModulesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
      child: Row(
        children: [
          Expanded(
            child: HomeActionBubble(
              key: const ValueKey('wallet-module-save'),
              icon: HugeIconsSolid.piggyBank,
              label: 'Save',
              onTap: () {
                AzamanHaptics.nav();
                context.push(AzRoutes.savings);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: HomeActionBubble(
              key: const ValueKey('wallet-module-p2p'),
              icon: HugeIconsSolid.creditCard,
              label: 'P2P',
              onTap: () {
                AzamanHaptics.nav();
                // UX-CORRECTION §10 — the CANONICAL USDC/P2P market page
                // (/marketplace → P2PMarketListScreen), not the legacy
                // P2PMarketplaceScreen. No second P2P page.
                context.push(AzRoutes.marketplace);
              },
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: _SusuBubble()),
          const SizedBox(width: 8),
          Expanded(
            child: HomeActionBubble(
              key: const ValueKey('wallet-module-bills'),
              icon: HugeIconsSolid.invoice01,
              label: 'Bills',
              onTap: () {
                AzamanHaptics.nav();
                context.push(AzRoutes.bills);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Susu bubble — the destination stays data-aware: the deterministic active
/// group's detail when one exists, the susu hub otherwise.
class _SusuBubble extends ConsumerWidget {
  const _SusuBubble();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups =
        ref.watch(susuListProvider).valueOrNull ?? const <SusuSummary>[];
    final active = chooseMostRelevantSusu(groups);
    return HomeActionBubble(
      key: const ValueKey('wallet-module-susu'),
      icon: HugeIconsSolid.userGroup,
      label: 'Susu',
      onTap: () {
        AzamanHaptics.nav();
        context.push(active != null ? '/susu/${active.id}' : '/susu');
      },
    );
  }
}

/// One circular control: symbol AND caption inside a single flat rim.
///
/// Sizing is derived from the width the row actually gives each item, so four
/// bubbles fit 320dp without a second row and without clipping a word:
///   • the visual circle is clamped to [56, 72] logical px;
///   • the tap target is never smaller than 48dp (the circle already is);
///   • label type scales down with the circle instead of being ellipsised, so
///     a 1.6x text scale shrinks the pair rather than losing the word.
class HomeActionBubble extends ConsumerWidget {
  const HomeActionBubble({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    Widget backdrop(bool recessed) {
      // Same rim vocabulary as the pills: tertiary ink, softened for the
      // settled state. The CIRCLE is the only container treatment.
      final ink = colors.textTertiary;
      final rim = recessed ? ink.withValues(alpha: ink.a * 0.55) : ink;
      return DecoratedBox(
        key: ValueKey<bool>(recessed),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: rim, width: 1),
        ),
        child: const SizedBox.expand(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final diameter = width.clamp(56.0, 72.0);

        final content = SizedBox(
          width: diameter,
          height: diameter,
          child: Center(
            child: Padding(
              // Keeps the pair off the rim at 1.6x text.
              padding: EdgeInsets.symmetric(horizontal: diameter * 0.13),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: diameter * 0.30,
                      color: colors.mutedAccent,
                    ),
                    SizedBox(height: diameter * 0.045),
                    Text(
                      label,
                      maxLines: 1,
                      style: AzText.caption.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        return ScaleTap(
          onTap: () {
            QuietDepthScope.maybeOf(context)?.wake();
            onTap();
          },
          child: QuietDepthSurface(
            content: Center(
              // Guarantees the 48dp floor even if a future circle shrinks.
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: content,
              ),
            ),
            backdrop: (context, recessed) => backdrop(recessed),
          ),
        );
      },
    );
  }
}
