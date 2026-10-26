// =============================================================================
// PROFILE JOYSTICK DELEGATES — the shared, REAL action implementations the
// listing avatar (BusinessResultCard) and the storefront hero
// (MarketStorefrontShell) both hand to ProfileJoystick (Workstream A,
// 2026-10-26).
//
// One implementation per concern — the hosts wire their own context
// (catalog callback, bookmark state label), but the story-open and
// show-less-confirm seams live HERE so the two joystick hosts can never
// grow two different behaviours for the same direction.
//
// Honesty is the contract: a story opens ONLY from the real stories
// fetch with at least one unexpired story (a failed request is never
// represented as "no story" — it simply opens nothing and invents no
// fallback), and show-less NEVER applies without an explicit confirm.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/story_model.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/screens/story_viewer_screen.dart';

import 'show_less_confirm_sheet.dart';

/// The joystick's DOWN direction: open the business's REAL story viewer,
/// only when a real active story exists.
///
/// Availability is judged by the caller from the AUTHORITATIVE story
/// state (BusinessStoryState.hasActiveStory — the same signal that
/// draws the ring); the open itself re-fetches the live stories
/// contract and keeps only unexpired stories. Empty or failed ->
/// nothing opens, nothing is faked, no fallback navigation.
Future<void> openJoystickStory(
  BuildContext context,
  WidgetRef ref,
  BusinessProfile business,
) async {
  try {
    final stories = await ref
        .read(marketplaceBookingServiceProvider)
        .getBusinessStories(business.bizId);
    if (!context.mounted) return;
    final now = DateTime.now();
    final active = stories
        .where((story) => story.expiresAt.isAfter(now))
        .toList(growable: false);
    if (active.isEmpty) return; // honest absence: no invented viewer
    await StoryViewerScreen.open(
      context,
      groups: [storyGroupFromBusinessStories(active)],
      initialGroupIndex: 0,
    );
  } catch (_) {
    // Fetch failure is not "no story" and is never faked as success —
    // the direction simply opens nothing.
  }
}

/// The joystick's LEFT direction: the MANDATORY explicit confirmation.
/// No recommendation-feedback request happens before the user confirms.
Future<void> openJoystickShowLessConfirm(
  BuildContext context,
  WidgetRef ref,
  BusinessProfile business,
) {
  return showJoystickShowLessConfirm(context, ref, business);
}
