// =============================================================================
// MARKETPLACE EXPERIENCE SCOPE — the blueprint, readable by every widget
// inside a vertical's stage.
//
// `MarketplaceVerticalExperienceStage` wraps its output in this InheritedWidget
// so any descendant (a product card, a tray, a commit overlay, a dossier
// sheet) can read the active blueprint, colours and tempo with:
//
//     final scope = MarketplaceExperienceScope.of(context);
//     final d = MarketplaceTempo.scaled(
//       context, scope.blueprint.motionTempo, MotionTokens.emphasized);
//
// without the stage prop-drilling blueprint fields through every constructor.
// This is the mechanism that turns the blueprint from a label into a law:
// every widget inside a vertical inherits its commit style, navigation mode,
// detail presentation and tempo by being inside the stage.
// =============================================================================

import 'package:flutter/widgets.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/providers/theme_provider.dart';

class MarketplaceExperienceScope extends InheritedWidget {
  /// The active blueprint (built from the business category + `experience`
  /// JSON exactly the way the stage builds it).
  final MarketplaceExperienceBlueprint blueprint;

  /// The active palette. Vertical widgets must read colours from here —
  /// never from `Theme.of(context).colorScheme` (see F-004).
  final AzamanColors colors;

  const MarketplaceExperienceScope({
    super.key,
    required this.blueprint,
    required this.colors,
    required super.child,
  });

  static MarketplaceExperienceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarketplaceExperienceScope>();

  static MarketplaceExperienceScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(
      scope != null,
      'MarketplaceExperienceScope.of() called with no scope in the tree. '
      'Wrap the widget in the output of MarketplaceVerticalExperienceStage '
      '(or in a MarketplaceExperienceScope).',
    );
    return scope!;
  }

  @override
  bool updateShouldNotify(MarketplaceExperienceScope oldWidget) =>
      oldWidget.blueprint != blueprint || oldWidget.colors != colors;
}
