// =============================================================================
// AZAMAN — GATEWAYS: STORY CAPABILITY SURFACE
//
// Backend truth (routes/storyRoutes.js + routes/storyHighlightRoutes.js on
// AZM-backend main, verified 2026-10-04):
//   POST   /api/stories                create (multipart)
//   GET    /api/stories/feed           feed
//   POST   /api/stories/:id/view       mark viewed
//   POST   /api/stories/:id/boost      boost
//   DELETE /api/stories/:id            delete
//   GET    /api/stories/analytics/:storyId           per-story analytics
//   GET    /api/stories/analytics/business/:businessId  business totals
//
// NOT implemented by the server, so NOT capabilities:
//   • reply  — no POST /api/stories/:id/reply route exists (the legacy
//     StoryFeedNotifier.replyStory posted into a guaranteed 404); analytics
//     count storyRefId DMs but no route accepts storyRefId either.
//   • react  — no reaction endpoint (StoryReaction rows are counted by
//     analytics but cannot be created over HTTP).
//   • share link, viewers list, edit, privacy, lifespan, view-once — absent.
//
// UI consults `capabilities` and hides what is missing. No dead buttons, no
// fabricated success (brief §5 "No dead buttons. No fake success.").
// =============================================================================

import 'package:flutter/foundation.dart';

import 'package:azaman/experience/gateways/az_gateway_result.dart';
import 'package:azaman/providers/story_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the STORY backend can actually do today.
enum StoryCapability {
  /// POST /api/stories/:id/view
  view,

  /// POST /api/stories/:id/boost
  boost,

  /// No route — see file header.
  reply,

  /// No route — see file header.
  react,

  /// No share endpoint.
  share,

  /// No viewers-list endpoint (analytics exists but is author-scoped
  /// business analytics, not a per-story viewer roster the viewer can show).
  viewers,

  /// No story editing.
  edit,

  /// No privacy/close-friends enforcement on the viewer path.
  privacy,

  /// No expiry semantics surfaced by the feed.
  lifespan,

  /// No view-once semantics.
  viewOnce,
}

/// Narrow seam over the existing notifier so the gateway is unit-testable
/// without HTTP. The production implementation delegates to
/// [StoryFeedNotifier]; tests install a fake.
abstract interface class StoryFeedPort {
  /// POST /stories/:id/view (existing notifier already swallows errors).
  Future<void> markViewed(String storyId);

  /// POST /stories/:id/boost then refresh the feed.
  Future<void> boost(String storyId, int amount);
}

class RiverpodStoryFeedPort implements StoryFeedPort {
  RiverpodStoryFeedPort(this._notifier);
  final StoryFeedNotifier _notifier;

  @override
  Future<void> markViewed(String storyId) => _notifier.markViewed(storyId);

  @override
  Future<void> boost(String storyId, int amount) => _notifier.boost(storyId, amount);
}

/// Capability-aware story operations. UI must consult [capabilities] before
/// rendering an affordance; unsupported calls return [AzUnsupported] with the
/// exact missing route, never a fabricated success.
abstract interface class StoryGateway {
  Set<StoryCapability> get capabilities;

  /// Fire-and-forget view mark, deduped per story id per session.
  Future<void> markViewed(String storyId);

  Future<AzGatewayResult<void>> reply(String storyId, String message);

  Future<AzGatewayResult<void>> boost(String storyId, int amount);

  /// Unsupported today: no reaction endpoint exists (see file header).
  Future<AzGatewayResult<void>> react(String storyId, String emoji);

  Future<AzGatewayResult<void>> shareLink(String storyId);
}

class HttpStoryGateway implements StoryGateway {
  HttpStoryGateway({StoryFeedPort? feedPort})
      : _feed = feedPort ?? const _UnwiredStoryFeedPort();

  final StoryFeedPort _feed;
  final Set<String> _viewed = {};

  /// The exact server surface today (see file header). `view` and `boost`
  /// map to real routes; everything else is unsupported.
  @override
  Set<StoryCapability> get capabilities => const {
        StoryCapability.view,
        StoryCapability.boost,
      };

  @override
  Future<void> markViewed(String storyId) async {
    if (!_viewed.add(storyId)) return;
    await _feed.markViewed(storyId);
  }

  @override
  Future<AzGatewayResult<void>> reply(String storyId, String message) async =>
      const AzUnsupported(
          'Story replies need POST /api/stories/:id/reply, which does not exist on the backend');

  @override
  Future<AzGatewayResult<void>> boost(String storyId, int amount) async {
    if (amount <= 0) {
      return const AzFailed('Boost amount must be positive');
    }
    try {
      await _feed.boost(storyId, amount);
      return const AzOk(null);
    } catch (e) {
      return AzFailed('Boost failed', cause: e);
    }
  }

  @override
  Future<AzGatewayResult<void>> react(String storyId, String emoji) async =>
      const AzUnsupported(
          'Story reactions need POST /api/stories/:id/react, which does not exist on the backend');

  @override
  Future<AzGatewayResult<void>> shareLink(String storyId) async =>
      const AzUnsupported('No story share endpoint exists on the backend');
}

// autoDispose: storyFeedProvider is autoDispose on purpose (the feed reloads
// on each hub entry; stories expire server-side after 24h). A NON-autoDispose
// gateway watching its notifier would pin the feed for the whole app run after
// the first viewer open — stale stories, no reload ever again. The gateway
// lives exactly as long as the viewer subtree that reads it; the markViewed
// dedupe set is then per viewer session, which is all it needs to be (it
// guards POST spam while paging back and forth; the server is the authority).
final storyGatewayProvider = Provider.autoDispose<StoryGateway>(
  (ref) => HttpStoryGateway(
    feedPort: RiverpodStoryFeedPort(ref.watch(storyFeedProvider.notifier)),
  ),
);

/// Never constructed in production code paths that never talk to the feed.
class _UnwiredStoryFeedPort implements StoryFeedPort {
  const _UnwiredStoryFeedPort();

  @override
  Future<void> markViewed(String storyId) async {}

  @override
  Future<void> boost(String storyId, int amount) async {}
}

@visibleForTesting
class FakeStoryGateway implements StoryGateway {
  FakeStoryGateway(this._capabilities);
  final Set<StoryCapability> _capabilities;

  final List<String> viewed = [];
  final List<(String, String)> replies = [];
  final List<(String, int)> boosts = [];
  final List<(String, String)> reactions = [];
  final Set<String> failBoostFor = {};

  @override
  Set<StoryCapability> get capabilities => _capabilities;

  @override
  Future<void> markViewed(String storyId) async => viewed.add(storyId);

  @override
  Future<AzGatewayResult<void>> reply(String storyId, String message) async {
    if (!_capabilities.contains(StoryCapability.reply)) {
      return const AzUnsupported('reply unsupported (fake)');
    }
    replies.add((storyId, message));
    return const AzOk(null);
  }

  @override
  Future<AzGatewayResult<void>> boost(String storyId, int amount) async {
    if (!_capabilities.contains(StoryCapability.boost)) {
      return const AzUnsupported('boost unsupported (fake)');
    }
    if (failBoostFor.contains(storyId)) {
      return const AzFailed('boost exploded');
    }
    boosts.add((storyId, amount));
    return const AzOk(null);
  }

  @override
  Future<AzGatewayResult<void>> react(String storyId, String emoji) async {
    if (!_capabilities.contains(StoryCapability.react)) {
      return const AzUnsupported('react unsupported (fake)');
    }
    reactions.add((storyId, emoji));
    return const AzOk(null);
  }

  @override
  Future<AzGatewayResult<void>> shareLink(String storyId) async =>
      const AzUnsupported('share unsupported (fake)');
}
