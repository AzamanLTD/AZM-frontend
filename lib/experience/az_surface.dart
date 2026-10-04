// =============================================================================
// AZAMAN — EXPERIENCE VOCABULARY: SURFACE
//
// Surface taxonomy. A visual component declares exactly one kind; the kind
// pins its styling contract so two screens cannot restyle "a card".
// Values reference `AzRadius` tokens only — never raw numbers.
// =============================================================================

import 'package:azaman/theme/az_radius.dart';

/// The kinds of surface the product is built from.
enum AzSurfaceKind {
  hero,
  identity,
  contextRow,
  categoryRail,
  card,
  tray,
  sheet,
  inlineSearch,
  chip,
  noticeBoard,
  socialRail,
  statusRail,
  actionDock,
}

/// Styling contract for one [AzSurfaceKind].
class AzSurfaceSpec {
  final double radius;
  final bool hasBorder;
  final bool hasShadow;
  final bool hasBlur;

  const AzSurfaceSpec({
    required this.radius,
    this.hasBorder = false,
    this.hasShadow = false,
    this.hasBlur = false,
  });

  /// The single source of truth for how each kind is styled.
  static AzSurfaceSpec of(AzSurfaceKind kind) => switch (kind) {
        // Flat, rim-less cards (UI Correction §7.1): radius only.
        AzSurfaceKind.card => const AzSurfaceSpec(radius: AzRadius.lg),
        AzSurfaceKind.noticeBoard => const AzSurfaceSpec(radius: AzRadius.md),
        AzSurfaceKind.chip => const AzSurfaceSpec(radius: AzRadius.pill),
        AzSurfaceKind.sheet => const AzSurfaceSpec(radius: AzRadius.xxl),
        AzSurfaceKind.tray =>
          const AzSurfaceSpec(radius: AzRadius.xl, hasShadow: true),
        AzSurfaceKind.identity => const AzSurfaceSpec(radius: AzRadius.pill),
        AzSurfaceKind.inlineSearch =>
          const AzSurfaceSpec(radius: AzRadius.pill),
        AzSurfaceKind.actionDock =>
          const AzSurfaceSpec(radius: AzRadius.pill, hasBlur: true),
        AzSurfaceKind.hero ||
        AzSurfaceKind.contextRow ||
        AzSurfaceKind.categoryRail ||
        AzSurfaceKind.socialRail ||
        AzSurfaceKind.statusRail =>
          const AzSurfaceSpec(radius: AzRadius.lg),
      };
}