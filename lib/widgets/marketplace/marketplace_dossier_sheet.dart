// =============================================================================
// MARKETPLACE DOSSIER SHEET — the shared detail surface for every vertical.
//
// The blueprint's `detailPresentation` axis decides HOW a product / dish /
// room / seat detail is presented. `morph` means the vertical's existing
// detail surface. Every other presentation renders through this one scaffold,
// so all four verticals share a single detail grammar:
//
//   - a drag handle + glass substrate (PremiumGlassContainer v2),
//   - a presentation eyebrow with glyph,
//   - the title in titleXl display type,
//   - the caller's content, entering as one composed block,
//   - an optional footer (the dossier's primary action),
//   - tempo-aware duration and curve (MarketplaceTempo).
//
// TASK-011 ships the scaffold and adopts it for retail's productDossier.
// TASK-012..015 adopt it for their verticals and extend the CONTENT — the
// scaffold itself does not change.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/marketplace/experiences/marketplace_tempo.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/azaman_sheet.dart';

/// Opens the shared dossier sheet. Returns when the sheet is dismissed.
///
/// [content] is the vertical's dossier body. It should be a `Column` with
/// `mainAxisSize: MainAxisSize.min` — the scaffold provides scrolling for tall
/// content and does NOT clip it.
///
/// [footer] is the dossier's primary action row (full-width button).
/// [eyebrow] overrides the presentation label; omit to use the presentation's
/// own name.
Future<void> showMarketplaceDossierSheet(
  BuildContext context, {
  required MarketplaceDetailPresentation presentation,
  required String title,
  required AzamanColors colors,
  required WidgetBuilder content,
  String? eyebrow,
  Widget? footer,
  MarketplaceMotionTempo tempo = MarketplaceMotionTempo.balanced,
}) {
  // NEW-B (Stage): the dossier is a full-bleed place, not a layer — it owns
  // the whole screen height and its own scrolling. The weight supplies the
  // surface, radius and safe-area, so the body's own glass chrome and drag
  // handle are deleted (rule: a migrated body must not keep its own chrome).
  return AzamanSheet.showStage<void>(
    context,
    builder: (_) => MarketplaceDossierSheet(
      presentation: presentation,
      title: title,
      eyebrow: eyebrow,
      colors: colors,
      content: content,
      footer: footer,
      tempo: tempo,
    ),
  );
}

/// The dossier sheet body. Prefer [showMarketplaceDossierSheet]; this widget
/// is public for verticals that want to embed the dossier inside their own
/// surface instead of a bottom sheet.
class MarketplaceDossierSheet extends StatelessWidget {
  final MarketplaceDetailPresentation presentation;
  final String title;
  final String? eyebrow;
  final AzamanColors colors;
  final WidgetBuilder content;
  final Widget? footer;
  final MarketplaceMotionTempo tempo;

  const MarketplaceDossierSheet({
    super.key,
    required this.presentation,
    required this.title,
    this.eyebrow,
    required this.colors,
    required this.content,
    this.footer,
    this.tempo = MarketplaceMotionTempo.balanced,
  });

  String get _presentationLabel => switch (presentation) {
        MarketplaceDetailPresentation.morph => 'Details',
        MarketplaceDetailPresentation.dishDossier => 'Dish dossier',
        MarketplaceDetailPresentation.productDossier => 'Product dossier',
        MarketplaceDetailPresentation.roomDossier => 'Room dossier',
        MarketplaceDetailPresentation.seatDossier => 'Seat dossier',
        MarketplaceDetailPresentation.serviceDossier => 'Service dossier',
      };

  // Only in-repo-verified Hugeicons names are used (F-035). `shoppingBag01`
  // from the spec is NOT present in the local package, so the product dossier
  // borrows the store glyph family rather than guessing a name.
  IconData get _presentationGlyph => switch (presentation) {
        MarketplaceDetailPresentation.dishDossier => HugeIconsStroke.store01,
        MarketplaceDetailPresentation.productDossier => HugeIconsSolid.store01,
        MarketplaceDetailPresentation.roomDossier => HugeIconsSolid.bank,
        MarketplaceDetailPresentation.seatDossier =>
          HugeIconsSolid.arrowDataTransferHorizontal,
        MarketplaceDetailPresentation.serviceDossier => HugeIconsSolid.note01,
        MarketplaceDetailPresentation.morph =>
          HugeIconsSolid.informationCircle,
      };

  @override
  Widget build(BuildContext context) {
    final duration = MarketplaceTempo.standard(context, tempo);
    final curve = MarketplaceTempo.enterCurve(tempo);
    final contentWidget = content(context);
    // The Stage weight supplies surface, radius, safe-area AND the grab
    // handle, so the body's own glass container, outer padding and inline
    // handle are deleted (I.8.1 — a migrated body must not keep its own
    // chrome). Only the inner content padding remains.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AzSpace.lg, AzSpace.sm, AzSpace.lg, AzSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DossierEntrance(
            duration: duration,
            curve: curve,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_presentationGlyph,
                        size: 14, color: colors.accent),
                    const SizedBox(width: AzSpace.xs),
                    Flexible(
                      child: Text(
                        (eyebrow ?? _presentationLabel).toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AzText.eyebrow.copyWith(color: colors.accent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AzSpace.sm),
                Text(title, style: AzText.titleXl.copyWith(color: colors.textPrimary)),
                const SizedBox(height: AzSpace.lg),
                contentWidget,
              ],
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: AzSpace.lg),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// One composed entrance for the dossier content: a single fade + 12px rise,
/// duration and curve from the vertical's tempo. Under reduced motion the
/// duration is already zero, so the content appears instantly — there is no
/// separate reduced-motion branch to maintain.
class _DossierEntrance extends StatelessWidget {
  final Duration duration;
  final Curve curve;
  final Widget child;

  const _DossierEntrance({
    required this.duration,
    required this.curve,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: duration,
      curve: curve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
