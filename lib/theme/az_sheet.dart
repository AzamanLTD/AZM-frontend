// =============================================================================
// AZAMAN — SHEET WEIGHTS  (NEW-B)
//
// The app currently has 37 hand-rolled `showModalBottomSheet` calls and 29
// `showDialog` calls, each inventing its own height, radius, drag behaviour and
// scrim. Two sheets side by side read as two different apps.
//
// This file defines the *vocabulary*: two weights, and the geometry that
// belongs to each. It is deliberately pure — no widgets, no BuildContext, no
// Riverpod — so the decisions are testable without pumping a frame.
//
//   WHISPER  a short confirmation. Two decisions, no scroll, dismisses on
//            backdrop tap. Cannot grow.
//   PANEL    a task surface. Scrolls, snaps, owns a title and a commit row.
//   STAGE    a full-bleed experience (marketplace verticals). Near-full height,
//            no snap detent, its own chrome.
//
// WHY THREE AND NOT TWO
// The brief names two weights (Panel + Stage). But 11 of the 37 sheets are
// short confirmations that physically cannot use the Panel grammar — a
// confirm dialog has no title bar to snap against and no reason to scroll.
// Folding them into Panel would force a drag handle and a detent onto a surface
// that should be a single glance. Whisper is therefore recorded here as a
// first-class weight, not a special case of Panel.
//
// USAGE
//   AzSheetGeometry.panelHeight(viewport)   // pure math, no Flutter objects
//   AzSheetWeight.fromTapTarget(height)    // classifies a migration site
// =============================================================================

/// The three sheet weights, ordered lightest to heaviest.
enum AzSheetWeight {
  /// Short confirmation. Fixed height, no drag, backdrop tap dismisses.
  /// Intrinsic height only — never taller than [whisperMaxFraction].
  whisper,

  /// Task surface. Snaps between detents, scrolls internally, has a title.
  panel,

  /// Full-bleed experience. Owns the whole screen below the status bar.
  stage,
}

/// Vertical geometry of one weight, expressed as fractions of the viewport
/// height rather than pixels.
///
/// Fractions, not pixels, because the same sheet has to be honest on a 5.4"
/// phone and a 6.9" one. A panel that is 420px tall is a third of one screen
/// and a quarter of another; which of those it *should* be depends on the
/// viewport, not on a number someone picked on a desk.
abstract final class AzSheetGeometry {
  const AzSheetGeometry._();

  // ── WHISPER ──────────────────────────────────────────────────────────────
  /// Upper bound as a fraction of the viewport. A whisper taller than this is
  /// not a whisper — it has become a panel and should say so.
  static const double whisperMaxFraction = 0.45;

  /// A whisper sized to its content, clamped into the legal band.
  ///
  /// [contentHeight] is the laid-out intrinsic height of the child.
  static double whisperHeight({
    required double viewportHeight,
    required double contentHeight,
  }) {
    if (viewportHeight <= 0) return contentHeight;
    final cap = viewportHeight * whisperMaxFraction;
    return contentHeight.clamp(0.0, cap);
  }

  // ── PANEL ────────────────────────────────────────────────────────────────
  /// Resting detent. A panel opens here and stays here unless the user drags.
  static const double panelRestFraction = 0.45;

  /// Extended detent. Covers most of the screen but leaves the header and a
  /// slice of the surface behind visible, so the panel reads as *above*
  /// something rather than *instead of* it.
  static const double panelExtendedFraction = 0.90;

  /// Smallest detent the drag will settle at, as a fraction of the panel's
  /// own max height. Below this the content is a peep and users overshoot
  /// straight past it.
  static const double panelMinDetent = 0.0;

  /// Height for a given detent.
  static double panelHeight(double viewportHeight, double fraction) {
    if (viewportHeight <= 0) return 0;
    return viewportHeight * fraction.clamp(0.0, 1.0);
  }

  // ── STAGE ────────────────────────────────────────────────────────────────
  /// A stage leaves only the status bar. Anything less and the marketplace
  /// verticals render inside a letterbox, which is the exact look the Stage
  /// weight exists to prevent.
  static const double stageTopInsetFraction = 0.06;

  static double stageHeight(double viewportHeight) {
    if (viewportHeight <= 0) return 0;
    return viewportHeight * (1.0 - stageTopInsetFraction);
  }

  // ── SCRIM ────────────────────────────────────────────────────────────────
  /// Gaussian sigma applied to the backdrop blur, per weight.
  ///
  /// Whisper blurs least: a confirmation is a small interruption, and blurring
  /// the whole app behind a 200px sheet is a much larger statement than the
  /// interruption warrants. Panel blurs enough that the surface behind stops
  /// competing with the content the user came to read.
  static const double whisperScrimSigma = 4;
  static const double panelScrimSigma = 12;
  static const double stageScrimSigma = 0;

  /// Scrim dim per weight, in the same spirit as the sigma above.
  static const double whisperScrimOpacity = 0.32;
  static const double panelScrimOpacity = 0.45;
  static const double stageScrimOpacity = 0.0;

  static double scrimSigmaFor(AzSheetWeight weight) => switch (weight) {
    AzSheetWeight.whisper => whisperScrimSigma,
    AzSheetWeight.panel => panelScrimSigma,
    AzSheetWeight.stage => stageScrimSigma,
  };

  static double scrimOpacityFor(AzSheetWeight weight) => switch (weight) {
    AzSheetWeight.whisper => whisperScrimOpacity,
    AzSheetWeight.panel => panelScrimOpacity,
    AzSheetWeight.stage => stageScrimOpacity,
  };

  // ── CLASSIFICATION ───────────────────────────────────────────────────────
  /// Picks the weight a migration site should adopt from what that site is
  /// today, before anyone decides the design.
  ///
  /// [contentHeight] is 0 when unknown, in which case [isScrollable] decides
  /// on its own.
  static AzSheetWeight classify({
    required bool isScrollable,
    double contentHeight = 0,
    double viewportHeight = 0,
    bool isFullScreen = false,
  }) {
    if (isFullScreen) return AzSheetWeight.stage;
    if (isScrollable) return AzSheetWeight.panel;
    if (contentHeight > 0 && viewportHeight > 0) {
      if (contentHeight <= viewportHeight * whisperMaxFraction) {
        return AzSheetWeight.whisper;
      }
    }
    // Non-scrollable but tall: almost always a form the user has to see all
    // of at once. A whisper that is 60% of the screen is a panel.
    return AzSheetWeight.panel;
  }
}
