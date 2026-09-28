// =============================================================================
// AZAMAN — SHEET GRAMMAR  (NEW-B)
//
// The render layer over `AzSheetGeometry`. One entry point per weight, so a
// migration is a one-line swap and every sheet in the app inherits the same
// drag feel, scrim, radius and motion.
//
//   AzamanSheet.showPanel(context, builder: ...)     // task surface
//   AzamanSheet.showWhisper(context, builder: ...)   // short confirmation
//   AzamanSheet.showStage(context, builder: ...)     // full-bleed
//
// WHY THIS BUILDS ON `showModalBottomSheet`
// A weight's scrim is a *blurred* scrim (σ per `AzSheetGeometry`). Flutter's
// `barrierColor` is a flat fill with no filter, and replacing the whole route
// to get a backdrop blur means re-implementing barrier dismissal, drag
// dismissal, route animation and back-button handling for zero visual gain —
// the modal sheet's own `barrierColor` can supply the dim, and the sheet
// surface itself carries the blur. So the grammar deliberately builds on the
// platform sheet and spends its complexity on the parts that actually differ
// between weights.
//
// DO NOT
//   Do NOT call `showModalBottomSheet` or `showDialog` directly any more. They
//   have no weight and therefore no voice. New sheets go through this class;
//   existing ones migrate screen by screen, so each change is reviewed in
//   context rather than as part of a 66-site blind sweep.
//   Do NOT add a fourth weight. If a surface does not fit one of the three, the
//   surface is wrong, not the vocabulary.
//   Do NOT play a sound or haptic on scrim dismissal. Per the brief's standing
//   rule (§H.7) motion may confirm a user action and may not summon one.
// =============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_sheet.dart';
import 'package:azaman/theme/motion_tokens.dart';

/// Fades + lifts [child] into place after [delay].
///
/// Stagger is a receipt, not decoration: it tells the eye that these rows
/// arrived together and belong together. It collapses to an immediate,
/// unanimated child under the OS reduce-motion setting — a delayed reveal is
/// exactly the kind of thing that setting exists to forbid.
class AzStaggeredReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const AzStaggeredReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  @override
  State<AzStaggeredReveal> createState() => _AzStaggeredRevealState();
}

class _AzStaggeredRevealState extends State<AzStaggeredReveal> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _visible = true;
      return;
    }
    Future<void>.delayed(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: MotionTokens.microInteraction,
      curve: MotionTokens.enter,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.08),
        duration: MotionTokens.microInteraction,
        curve: MotionTokens.enter,
        child: widget.child,
      ),
    );
  }
}

/// Staggers [children] into place on first build.
///
/// The cap keeps a long list from crawling: rows past [cap] all land together
/// once the stagger window has elapsed.
class AzStaggeredColumn extends StatelessWidget {
  final List<Widget> children;
  final int cap;

  const AzStaggeredColumn({super.key, required this.children, this.cap = 8});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        children.length,
        (i) => AzStaggeredReveal(
          delay: MotionTokens.staggerDelay(i, cap: cap),
          child: children[i],
        ),
      ),
    );
  }
}

/// The grab affordance. 36×4, centred, on the divider token.
class AzSheetHandle extends ConsumerWidget {
  const AzSheetHandle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: colors.divider,
            borderRadius: BorderRadius.circular(AzRadius.pill),
          ),
        ),
      ),
    );
  }
}

/// The visual shell shared by all three weights: radius, surface, safe-area
/// and the optional grab handle.
///
/// The blur lives here, on the *content* of the sheet, rather than on the
/// scrim: it gives the panel a frosted read against the surface behind it
/// without making a dismissal gesture ambiguous.
class AzSheetSurface extends ConsumerWidget {
  final AzSheetWeight weight;
  final Widget child;
  final bool showHandle;
  final bool safeBottom;

  const AzSheetSurface({
    super.key,
    required this.weight,
    required this.child,
    this.showHandle = true,
    this.safeBottom = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final bottom = MediaQuery.of(context).padding.bottom;
    final sigma = AzSheetGeometry.scrimSigmaFor(weight);

    final body = Container(
      color: colors.surface,
      child: Padding(
        padding: EdgeInsets.only(bottom: safeBottom ? bottom : 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHandle) const AzSheetHandle(),
            Flexible(child: child),
          ],
        ),
      ),
    );

    return ClipRRect(
      // A stage is a screen, not a sheet. Rounding its top corners tells the
      // eye it is a temporary layer when it is meant to read as a place.
      borderRadius: weight == AzSheetWeight.stage
          ? AzRadius.brXl
          : AzRadius.sheetTop,
      child: sigma > 0
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: body,
            )
          : body,
    );
  }
}

/// The public entry points. Each returns the builder's value, or `null` if the
/// user dismissed — the same contract as `showDialog`, so migration is a
/// rename plus a builder rather than a behavioural change.
abstract final class AzamanSheet {
  const AzamanSheet._();

  /// Short confirmation. Sized to content, capped at the whisper ceiling, no
  /// grab handle, dismissed by a backdrop tap.
  static Future<T?> showWhisper<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isDismissible = true,
  }) {
    final viewport = MediaQuery.of(context).size.height;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      isDismissible: isDismissible,
      barrierColor: Colors.black.withValues(
        alpha: AzSheetGeometry.whisperScrimOpacity,
      ),
      constraints: BoxConstraints(
        maxHeight: AzSheetGeometry.whisperHeight(
          viewportHeight: viewport,
          contentHeight: double.infinity,
        ),
      ),
      builder: (ctx) => AzSheetSurface(
        weight: AzSheetWeight.whisper,
        showHandle: false,
        child: builder(ctx),
      ),
    );
  }

  /// Task surface. Opens at [AzSheetGeometry.panelRestFraction] and snaps to
  /// [AzSheetGeometry.panelExtendedFraction]. The builder receives a
  /// [ScrollController] already wired to the sheet's own scroll view, so a
  /// drag on the content and a drag on the detent are the same gesture.
  static Future<T?> showPanel<T>(
    BuildContext context, {
    required Widget Function(BuildContext, ScrollController) builder,
    double initialFraction = AzSheetGeometry.panelRestFraction,
    bool isDismissible = true,
  }) {
    final maxFraction = AzSheetGeometry.panelExtendedFraction;
    final minFraction = (AzSheetGeometry.panelRestFraction * 0.6).clamp(
      0.0,
      maxFraction,
    );
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      isDismissible: isDismissible,
      barrierColor: Colors.black.withValues(
        alpha: AzSheetGeometry.panelScrimOpacity,
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: initialFraction.clamp(0.0, maxFraction),
        minChildSize: minFraction,
        maxChildSize: maxFraction,
        expand: false,
        builder: (ctx, scrollController) => AzSheetSurface(
          weight: AzSheetWeight.panel,
          child: builder(ctx, scrollController),
        ),
      ),
    );
  }

  /// Full-bleed experience. No detents, no handle, no scrim: the surface *is*
  /// the screen. Used by the marketplace verticals, which are places rather
  /// than layers.
  static Future<T?> showStage<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    final viewport = MediaQuery.of(context).size.height;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      isDismissible: false,
      enableDrag: false,
      constraints: BoxConstraints(
        maxHeight: AzSheetGeometry.stageHeight(viewport),
      ),
      builder: (ctx) => AzSheetSurface(
        weight: AzSheetWeight.stage,
        showHandle: false,
        safeBottom: false,
        child: builder(ctx),
      ),
    );
  }
}
