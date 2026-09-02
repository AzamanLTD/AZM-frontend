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
        return _slideFromBottom(context, child: _dossierCard(), distanceFactor: 1);
      case MarketplaceDetailPresentation.productDossier:
        return _slideFromRight(context, child: _dossierCard(), scale: 0.98);
      case MarketplaceDetailPresentation.roomDossier:
        return _slideFromBottomRight(context, child: _dossierCard(), scale: 0.985);
      case MarketplaceDetailPresentation.seatDossier:
        return _slideFromRight(context, child: _dossierCard(), scale: 0.975);
      case MarketplaceDetailPresentation.serviceDossier:
        return Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: 1),
            duration: duration,
            curve: MotionTokens.enter,
            builder: (_, value, child) => Opacity(
              opacity: value,
              child: Transform.scale(scale: value, child: child),
            ),
            child: _card(maxHeight: 680),
          ),
        );
    }
  }

  Widget _slideFromBottom(
    BuildContext context, {
    required Widget child,
    required double distanceFactor,
  }) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.06, end: 1),
        duration: duration,
        curve: MotionTokens.enter,
        builder: (_, value, child) => Transform.translate(
          offset: Offset(0, MediaQuery.sizeOf(context).height * distanceFactor * (1 - value)),
          child: child,
        ),
        child: child,
      ),
    );
  }

  Widget _slideFromRight(
    BuildContext context, {
    required Widget child,
    required double scale,
  }) {
    return Align(
      alignment: Alignment.centerRight,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: duration,
        curve: MotionTokens.enter,
        builder: (_, value, child) => Transform.translate(
          offset: Offset(MediaQuery.sizeOf(context).width * (1 - value), 0),
          child: Transform.scale(
            scale: scale + ((1 - scale) * value),
            child: child,
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _slideFromBottomRight(
    BuildContext context, {
    required Widget child,
    required double scale,
  }) {
    return Align(
      alignment: Alignment.bottomRight,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: duration,
        curve: MotionTokens.enter,
        builder: (_, value, child) {
          final size = MediaQuery.sizeOf(context);
          return Transform.translate(
            offset: Offset(
              size.width * 0.18 * (1 - value),
              size.height * 0.18 * (1 - value),
            ),
            child: Transform.scale(
              scale: scale + ((1 - scale) * value),
              child: child,
            ),
          );
        },
        child: child,
      ),
    );
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