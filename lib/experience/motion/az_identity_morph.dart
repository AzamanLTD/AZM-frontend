// =============================================================================
// AZAMAN — MOTION CONTRACT: IDENTITY MORPH
//
// "Same object, different form." A business keeps the same Hero tag from a
// marketplace card to the storefront identity to the compact pill; a story
// ring carries into the viewer header; a group avatar into the group profile.
//
// Rule: apply to exactly ONE element per transition (the logo/avatar).
// Names cross-fade; never Hero text.
// =============================================================================

import 'package:flutter/widgets.dart';

/// Hero tags are the identity carrier. One function builds them so that a
/// business keeps the same tag from a marketplace card to the store pill.
abstract final class AzIdentityTag {
  static String business(String bizId) => 'az-identity-biz-$bizId';
  static String user(int userId) => 'az-identity-user-$userId';
  static String group(String groupId) => 'az-identity-group-$groupId';
  static String story(int authorId) => 'az-identity-story-$authorId';
}

/// Wraps an avatar/logo in a [Hero] only when motion travel is allowed; with
/// reduced motion the Hero is skipped so the route change is a plain cut.
class AzIdentityMorph extends StatelessWidget {
  final String tag;
  final Widget child;

  /// `AzMotion.of(context).travel`.
  final bool travel;

  const AzIdentityMorph({
    super.key,
    required this.tag,
    required this.child,
    required this.travel,
  });

  @override
  Widget build(BuildContext context) {
    if (!travel) return child;
    return Hero(
      tag: tag,
      // Fly the destination's form so the identity "becomes" its new shape
      // rather than stretching the launcher.
      flightShuttleBuilder: (ctx, anim, dir, from, to) => to.widget,
      child: child,
    );
  }
}