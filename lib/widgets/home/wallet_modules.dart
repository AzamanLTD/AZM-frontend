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
// Material language (owner, 2026-10-30): DIMENSIONAL. The circle is a sphere,
// not a disc — a light-facing tint falling to almost nothing at the bottom
// right, a shaded lower edge, a rim, a specular highlight and a short shadow to
// lift it off the row. Everything stays measured: no blur, no glow bloom, no
// particles. The quiet-depth cycle still animates the rim alone, which is why
// the content subtree is never inside the backdrop.
//
// FEEL: press and pop are one gesture, not two (lib/widgets/home/bubble_press
// .dart). The bubble compresses under the finger, rebounds past its own size,
// and the navigation fires as it leaves — the Hero carries it from there. A
// second tap during that window is swallowed so one gesture cannot queue two
// pushes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/widgets/navigation/bubble_morph.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/quiet_depth.dart';
import 'package:azaman/widgets/home/bubble_press.dart';

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
            child: BubbleMorphSource(
              tag: BubbleMorphTag.save,
              child: HomeActionBubble(
                key: const ValueKey('wallet-module-save'),
                icon: HugeIconsSolid.piggyBank,
                label: 'Save',
                onTap: () {
                  AzamanHaptics.nav();
                  if (!BubbleNavigation.allow(AzRoutes.savings)) return;
                  context.push(AzRoutes.savings);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: BubbleMorphSource(
              tag: BubbleMorphTag.p2p,
              child: HomeActionBubble(
                key: const ValueKey('wallet-module-p2p'),
                icon: HugeIconsSolid.creditCard,
                label: 'P2P',
                onTap: () {
                  AzamanHaptics.nav();
                  // UX-CORRECTION §10 — the CANONICAL USDC/P2P market page
                  // (/marketplace → P2PMarketListScreen), not the legacy
                  // P2PMarketplaceScreen. No second P2P page.
                  if (!BubbleNavigation.allow(AzRoutes.marketplace)) return;
                  context.push(AzRoutes.marketplace);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: _SusuBubble()),
          const SizedBox(width: 8),
          Expanded(
            child: BubbleMorphSource(
              tag: BubbleMorphTag.bills,
              child: HomeActionBubble(
                key: const ValueKey('wallet-module-bills'),
                icon: HugeIconsSolid.invoice01,
                label: 'Bills',
                onTap: () {
                  AzamanHaptics.nav();
                  if (!BubbleNavigation.allow(AzRoutes.bills)) return;
                  context.push(AzRoutes.bills);
                },
              ),
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
    final destination = active != null ? '/susu/${active.id}' : '/susu';
    return BubbleMorphSource(
      tag: BubbleMorphTag.susu,
      child: HomeActionBubble(
        key: const ValueKey('wallet-module-susu'),
        icon: HugeIconsSolid.userGroup,
        label: 'Susu',
        onTap: () {
          AzamanHaptics.nav();
          if (!BubbleNavigation.allow(destination)) return;
          context.push(destination);
        },
      ),
    );
  }
}

/// One circular control: symbol AND caption inside a single dimensional
/// bubble.
///
/// Sizing is derived from the width the row actually gives each item, so four
/// bubbles fit 320dp without a second row and without clipping a word:
///   • the visual circle is clamped to [52, 60] logical px;
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

    // THE BUBBLE (owner, 2026-10-30): a genuinely ROUND bubble carrying a soft
    // light, not a tall capsule. Owner direction supersedes the earlier
    // flat-only treatment: a restrained glassy sheen and a gentle lift are
    // wanted, still nothing loud — no blur, no big glow, no particles.
    //
    // Volume is three layers on one circle: the body gradient (light top-left,
    // nothing bottom-right), a lower-edge shade so the underside turns away,
    // and the specular highlight below.
    Widget bubble(bool recessed) {
      final accent = colors.accent;
      final rim = colors.textTertiary.withValues(alpha: recessed ? 0.42 : 0.78);
      return DecoratedBox(
        key: ValueKey<bool>(recessed),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Reads as a sphere: light-facing tint at the top-left falling away
          // to almost nothing at the bottom-right.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: recessed ? 0.09 : 0.17),
              accent.withValues(alpha: recessed ? 0.03 : 0.06),
              accent.withValues(alpha: recessed ? 0.01 : 0.02),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
          border: Border.all(color: rim, width: 1),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: recessed ? 0.06 : 0.11),
              blurRadius: 12,
              spreadRadius: -2,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const SizedBox.expand(),
      );
    }

    // The underside turning away from the light. A tint at the bottom-right is
    // what makes the circle read as a sphere rather than a filled disc; it is
    // deliberately weak, because a strong one turns into a drop shadow inside
    // the bubble.
    Widget underside(bool recessed) => IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(0.55, 0.75),
            radius: 0.95,
            colors: [
              Colors.black.withValues(alpha: recessed ? 0.10 : 0.16),
              Colors.black.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.72],
          ),
        ),
      ),
    );

    Widget specular(bool recessed) => Align(
      alignment: const Alignment(-0.42, -0.55),
      child: FractionallySizedBox(
        widthFactor: 0.42,
        heightFactor: 0.26,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.white.withValues(alpha: recessed ? 0.16 : 0.26),
                Colors.white.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // A circle, always. The diameter is CAPPED so a wide slot cannot
        // stretch it, and the box is SQUARE and fixed so nothing below can
        // inflate it vertically (that is what made them look tall).
        final diameter = constraints.maxWidth.clamp(52.0, 60.0);

        final content = Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: diameter * 0.14),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: diameter * 0.30, color: colors.mutedAccent),
                  SizedBox(height: diameter * 0.04),
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
        );

        // The widget must CLAIM only the circle's height. A bare Center
        // fills its slot (a Column gives it the viewport height), which is
        // exactly what made the row tall and the bubbles look stretched.
        return SizedBox(
          height: diameter,
          child: Center(
            child: SizedBox(
              width: diameter,
              height: diameter,
              child: BubblePress(
                onTap: () {
                  QuietDepthScope.maybeOf(context)?.wake();
                  onTap();
                },
                child: QuietDepthSurface(
                  content: content,
                  backdrop: (context, recessed) => Stack(
                    fit: StackFit.expand,
                    children: [
                      bubble(recessed),
                      underside(recessed),
                      specular(recessed),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
