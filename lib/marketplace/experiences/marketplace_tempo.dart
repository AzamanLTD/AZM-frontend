// =============================================================================
// MARKETPLACE TEMPO — per-vertical motion tempo, applied to MotionTokens
//
// The marketplace blueprint assigns every vertical a motion tempo
// (`relaxed` / `balanced` / `quick`). This file is the single source of truth
// for what a tempo means in milliseconds, so "a hotel browse feels relaxed and
// a transit booking feels quick" is one enum — not hand-picked durations
// scattered across screens.
//
// ── THE TWO PRESERVED LADDERS ───────────────────────────────────────────────
// Two per-tempo progressions already exist in shipped code. They are PRESERVED
// EXACTLY here (this file centralises them; it does not retune):
//
//   standard(context, tempo) — the stage switcher duration:
//       relaxed 450ms (spatial) · balanced 220ms (standard) · quick 180ms
//       (control). Identical to `blueprint.motionDuration(...)`.
//   commit(tempo)            — the restaurant commit ritual:
//       relaxed 820ms · balanced 720ms · quick 560ms.
//       Identical to the values hardcoded in `RestaurantCommitSurface`.
//
// ── THE MULTIPLIER ───────────────────────────────────────────────────────────
// Everything else derives from `multiplierOf` so future motion inside a
// vertical inherits tempo automatically: relaxed ×1.25 · balanced ×1.0 ·
// quick ×0.72. Use `scaled(...)` for any NEW duration inside a vertical.
//
// Every duration routes through `MotionTokens.accessibleDuration` (except the
// pure `commit` ladder, whose consumer — the commit surface — already gates
// reduced motion itself), so reduced motion collapses motion to zero exactly
// like the rest of the app.
// =============================================================================

import 'package:flutter/widgets.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/theme/motion_tokens.dart';

abstract class MarketplaceTempo {
  /// Multiplier applied to any `MotionTokens` duration so it inherits tempo.
  static double multiplierOf(MarketplaceMotionTempo tempo) {
    switch (tempo) {
      case MarketplaceMotionTempo.relaxed:
        return 1.25;
      case MarketplaceMotionTempo.balanced:
        return 1.0;
      case MarketplaceMotionTempo.quick:
        return 0.72;
    }
  }

  /// Canonical per-tempo duration for a vertical's primary transition (stage
  /// switcher, dossier sheet). Values are IDENTICAL to the shipped
  /// `blueprint.motionDuration` mapping — this ladder replaces that mapping
  /// with byte-identical rendering.
  static Duration standard(BuildContext context, MarketplaceMotionTempo tempo) {
    final base = switch (tempo) {
      MarketplaceMotionTempo.relaxed => MotionTokens.spatial,
      MarketplaceMotionTempo.balanced => MotionTokens.standard,
      MarketplaceMotionTempo.quick => MotionTokens.control,
    };
    return MotionTokens.accessibleDuration(context, base);
  }

  /// The commit-ritual ladder (paper rip / lift / drop choreography).
  /// Values are IDENTICAL to the shipped `RestaurantCommitSurface` durations.
  static Duration commit(MarketplaceMotionTempo tempo) {
    switch (tempo) {
      case MarketplaceMotionTempo.relaxed:
        return const Duration(milliseconds: 820);
      case MarketplaceMotionTempo.balanced:
        return const Duration(milliseconds: 720);
      case MarketplaceMotionTempo.quick:
        return const Duration(milliseconds: 560);
    }
  }

  /// A `MotionTokens` duration scaled by the tempo multiplier and collapsed to
  /// zero under reduced motion. Use for any NEW motion inside a vertical.
  static Duration scaled(
    BuildContext context,
    MarketplaceMotionTempo tempo,
    Duration base,
  ) {
    return MotionTokens.accessibleDuration(context, base * multiplierOf(tempo));
  }

  /// Tempo-aware stagger: quick verticals snap items in faster.
  static Duration stagger(
    BuildContext context,
    MarketplaceMotionTempo tempo,
    int index, {
    int cap = 8,
  }) {
    return scaled(context, tempo, MotionTokens.staggerDelay(index, cap: cap));
  }

  /// Entering curve per tempo. Relaxed moves evenly (symmetric), balanced
  /// arrives with the app's standard ease-out, quick snaps off the line.
  static Curve enterCurve(MarketplaceMotionTempo tempo) {
    switch (tempo) {
      case MarketplaceMotionTempo.relaxed:
        return MotionTokens.symmetric;
      case MarketplaceMotionTempo.balanced:
        return MotionTokens.enter;
      case MarketplaceMotionTempo.quick:
        return MotionTokens.decelerate;
    }
  }

  /// Leaving curve per tempo — the fast-out/slow-in partner of [enterCurve].
  static Curve exitCurve(MarketplaceMotionTempo tempo) {
    switch (tempo) {
      case MarketplaceMotionTempo.relaxed:
        return MotionTokens.symmetric;
      case MarketplaceMotionTempo.balanced:
        return MotionTokens.exit;
      case MarketplaceMotionTempo.quick:
        return MotionTokens.exit;
    }
  }
}
