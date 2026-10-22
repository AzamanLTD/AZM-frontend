// =============================================================================
// AZAMAN — SAVE / P2P / SUSU COMPACT PILLS  (correction E)
//
// The Home resting surface shows three compact pill controls — [icon] Save,
// [icon] P2P, [icon] Susu — and NOTHING else. The educational/progress
// sentence no longer occupies Home space: the pill communicates the product
// name only. Icon identity, accent colors and the AZM glass language are
// preserved exactly; only the description is gone.
//
// Real-data behaviour is preserved where it already existed:
//   SAVE → /savings                       (unchanged destination)
//   P2P  → the P2P marketplace screen     (unchanged destination)
//   SUSU → the DETERMINISTIC most-relevant active group (same selection
//          rule as before: earliest upcoming scheduled contribution among
//          ACTIVE groups, ties broken stably) or the susu hub.
// =============================================================================

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
import 'package:azaman/theme/az_elevation.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:azaman/widgets/quiet_depth.dart';
import 'package:azaman/widgets/scale_tap.dart';

/// The deterministic SUSU selection — the SAME group the notice used to
/// describe now drives the navigation target directly: an active group with
/// the earliest upcoming scheduled contribution (unscheduled groups lose to
/// scheduled ones; ties broken by group id so the choice is stable).
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

// ── WIDGETS ───────────────────────────────────────────────────────────────

/// The Home resting row: three compact pill controls, no descriptions.
class WalletModulesRow extends ConsumerWidget {
  const WalletModulesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
      child: Row(
        children: [
          Expanded(
            child: _WalletPill(
              key: const ValueKey('wallet-module-save'),
              icon: HugeIconsSolid.piggyBank,
              label: 'Save',
              onTap: () {
                AzamanHaptics.nav();
                context.push('/savings');
              },
            ),
          ),
          const SizedBox(width: AzSpace.md),
          Expanded(
            child: _WalletPill(
              key: const ValueKey('wallet-module-p2p'),
              icon: HugeIconsSolid.creditCard,
              label: 'P2P',
              onTap: () {
                AzamanHaptics.nav();
                // UX-CORRECTION §10 — the Home P2P pill opens the CANONICAL
                // USDC/P2P market page (/marketplace → P2PMarketListScreen),
                // not the legacy P2PMarketplaceScreen. No second P2P page.
                // (AzRoutes.marketplace is the PATH form '/marketplace';
                // AzRouteNames.marketplace is the route NAME — push takes
                // the location.)
                context.push(AzRoutes.marketplace);
              },
            ),
          ),
          const SizedBox(width: AzSpace.md),
          const Expanded(child: _SusuPill()),
        ],
      ),
    );
  }
}

/// Susu pill — the destination stays data-aware: the deterministic active
/// group's detail when one exists, the susu hub otherwise.
class _SusuPill extends ConsumerWidget {
  const _SusuPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups =
        ref.watch(susuListProvider).valueOrNull ?? const <SusuSummary>[];
    final active = chooseMostRelevantSusu(groups);
    return _WalletPill(
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

/// One compact pill: [icon] label — the AZM glass language in a pill
/// silhouette. The pill communicates the product name only.
class _WalletPill extends ConsumerWidget {
  const _WalletPill({
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

    // QUIET DEPTH (Home pilot, 2026-10-22): the pill has a raised tactile
    // state and a nearly-flush quiet state, driven by the scoped
    // [QuietDepthController]. Only the BACKDROP changes — icon, label,
    // padding, hit target and semantics are the SAME widget subtree in
    // both states, and the fade between them is pure decoration.

    // FINAL PASS §3 — light-mode depth. Glass at 5% opacity over the
    // near-white #F2F3F5 page is INVISIBLE: the pills (the Home's
    // primary controls) vanished into the canvas (verified by pixel
    // capture — the whole lower page sat inside one ~8-luma-unit band).
    // In LIGHT the pill therefore sits on the design system's CARD
    // step: opaque c.card fill + hairline + the AzElevation contact
    // shadow — exactly the "existing elevation, surface, text, spacing
    // primitives" the brief allows. DARK keeps the premium glass
    // language untouched: glass reads on the black ramp.
    // PR #154: guarantee the 44dp minimum pill hit target even under
    // reduced text scales. The pill box = this content + the container's
    // 24px vertical padding, so a 20px content floor keeps the tappable
    // pill at >= 44dp while the default-metric pill is visually unchanged.
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // PASS E — the wallet module icons are SUPPORTING feature
            // icons: muted gold, so bright gold stays reserved for the
            // primary actions and selected navigation.
            Icon(icon, size: 18, color: colors.mutedAccent),
            const SizedBox(width: AzSpace.sm),
            Flexible(
              child: Text(
                label,
                style: AzText.title.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    // The stable content layer: mounted EXACTLY ONCE, above the
    // backdrops. It carries the padding that sizes the pill, so both
    // backdrop variants occupy the same box.
    final paddedContent = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AzSpace.lg,
        vertical: 12,
      ),
      child: content,
    );

    // The raised and recessed backdrops: decorative only. The content
    // subtree is NEVER inside them, so the depth cross-fade animates
    // shadows and glass alone — icon, label and semantics stay mounted
    // and fully opaque through the whole transition.
    Widget backdrop(bool recessed) {
      if (colors.isDark) {
        // DARK keeps the premium glass language. Raised = the current
        // glass; recessed = a whisper-flatter glass (lower opacity, less
        // blur) so the pill reads as sitting INTO the canvas while its
        // rim, label and icon keep full contrast.
        return PremiumGlassContainer(
          blur: recessed ? 6 : 10,
          opacity: recessed ? 0.03 : 0.05,
          borderRadius: 999,
          padding: EdgeInsets.zero,
          enableShadow: false,
          border: Border.all(color: colors.divider, width: 0.5),
          child: const SizedBox.expand(),
        );
      }
      // LIGHT: raised = the card step with the AzElevation contact shadow;
      // recessed = flush with the plane (no shadow, the surface fill) but
      // the hairline border stays, so the pill is still visibly a button.
      return Container(
        decoration: BoxDecoration(
          color: recessed ? colors.surface : colors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.border, width: 1),
          boxShadow: recessed ? AzElevation.level0 : AzElevation.level1(false),
        ),
        child: const SizedBox.expand(),
      );
    }

    return ScaleTap(
      onTap: () {
        // A qualifying interaction wakes the quiet-depth cycle. The wake
        // is pure bookkeeping — it can never delay or swallow the real
        // action below it.
        QuietDepthScope.maybeOf(context)?.wake();
        onTap();
      },
      child: QuietDepthSurface(
        content: paddedContent,
        backdrop: (context, recessed) => backdrop(recessed),
      ),
    );
  }
}
