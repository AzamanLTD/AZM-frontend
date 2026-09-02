import 'package:flutter/material.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';

/// Shared presentation shell for focused marketplace item details.
///
/// The domain widget remains responsible for the contents; this surface only
/// owns how the focused object enters/leaves the user's attention.
class MarketplaceDetailSurface extends StatelessWidget {
  final MarketplaceDetailPresentation presentation;
  final AzamanColors colors;
  final Duration duration;
  final VoidCallback onDismiss;
  final Widget child;

  const MarketplaceDetailSurface({
    super.key,
    required this.presentation,
    required this.colors,
    required this.duration,
    required this.onDismiss,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.58),
          child: _content(context),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    switch (presentation) {
      case MarketplaceDetailPresentation.morph:
        return Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.94, end: 1),
            duration: duration,
            curve: MotionTokens.enter,
            builder: (_, value, child) => Transform.scale(scale: value, child: child),
            child: _card(maxHeight: 680),
          ),
        );
      case MarketplaceDetailPresentation.dishDossier:
        return Align(
          alignment: Alignment.bottomCenter,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.08, end: 1),
            duration: duration,
            curve: MotionTokens.enter,
            builder: (_, value, child) => Transform.translate(
              offset: Offset(0, MediaQuery.sizeOf(context).height * (1 - value)),
              child: child,
            ),
            child: _dossierCard(),
          ),
        );
      default:
        return Align(
          alignment: Alignment.bottomCenter,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.96, end: 1),
            duration: duration,
            curve: MotionTokens.enter,
            builder: (_, value, child) => Opacity(opacity: value, child: Transform.translate(offset: Offset(0, 28 * (1 - value)), child: child)),
            child: _dossierCard(),
          ),
        );
    }
  }

  Widget _dossierCard() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 28, 8, 8),
        child: _card(maxHeight: 720),
      ),
    );
  }

  Widget _card({required double maxHeight}) {
    return GestureDetector(
      onTap: () {},
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 430, maxHeight: maxHeight),
        child: Material(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28), bottom: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          color: colors.card,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: colors.textTertiary.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(999)),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
