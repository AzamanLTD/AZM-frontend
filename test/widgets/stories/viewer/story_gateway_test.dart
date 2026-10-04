// Story gateway: capability truth + view-mark dedupe (Overhaul 05 §6.1).
//
// The capability set is the CONTRACT: UI hides anything not in it. These
// tests fail if someone adds a capability without its backend route.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/az_gateway_result.dart';
import 'package:azaman/experience/gateways/story_gateway.dart';
import 'package:azaman/providers/story_provider.dart';

class _RecordingFeedPort implements StoryFeedPort {
  _RecordingFeedPort({this.failBoost = false});
  final bool failBoost;
  final List<String> viewed = [];
  final List<(String, int)> boosted = [];

  @override
  Future<void> markViewed(String storyId) async => viewed.add(storyId);

  @override
  Future<void> boost(String storyId, int amount) async {
    if (failBoost) throw Exception('network down');
    boosted.add((storyId, amount));
  }
}

void main() {
  group('capability truth', () {
    test('exactly view + boost map to real backend routes', () {
      // routes/storyRoutes.js has POST /:id/view and POST /:id/boost only.
      expect(
        HttpStoryGateway().capabilities,
        const {
          StoryCapability.view,
          StoryCapability.boost,
        },
      );
    });

    test('reply, react, share, viewers are NOT capabilities', () {
      final caps = HttpStoryGateway().capabilities;
      expect(caps.contains(StoryCapability.reply), isFalse);
      expect(caps.contains(StoryCapability.react), isFalse);
      expect(caps.contains(StoryCapability.share), isFalse);
      expect(caps.contains(StoryCapability.viewers), isFalse);
    });
  });

  group('unsupported operations name the exact missing route', () {
    test('reply', () async {
      final result = await HttpStoryGateway().reply('s1', 'hi');
      expect(result, isA<AzUnsupported<void>>());
      expect(
        (result as AzUnsupported<void>).reason,
        contains('/api/stories/:id/reply'),
      );
    });

    test('react', () async {
      final result = await HttpStoryGateway().react('s1', '❤️');
      expect(result, isA<AzUnsupported<void>>());
      expect(
        (result as AzUnsupported<void>).reason,
        contains('/api/stories/:id/react'),
      );
    });

    test('shareLink', () async {
      final result = await HttpStoryGateway().shareLink('s1');
      expect(result, isA<AzUnsupported<void>>());
    });
  });

  group('markViewed', () {
    test('posts once per story id per session, regardless of repeats', () async {
      final port = _RecordingFeedPort();
      final gateway = HttpStoryGateway(feedPort: port);
      await gateway.markViewed('a');
      await gateway.markViewed('a');
      await gateway.markViewed('b');
      await gateway.markViewed('a');
      expect(port.viewed, ['a', 'b']);
    });
  });

  group('boost', () {
    test('forwards to the feed port on success', () async {
      final port = _RecordingFeedPort();
      final gateway = HttpStoryGateway(feedPort: port);
      final result = await gateway.boost('s1', 10);
      expect(result, isA<AzOk<void>>());
      expect(port.boosted, [('s1', 10)]);
    });

    test('rejects non-positive amounts before any wire', () async {
      final port = _RecordingFeedPort();
      final gateway = HttpStoryGateway(feedPort: port);
      final result = await gateway.boost('s1', 0);
      expect(result, isA<AzFailed<void>>());
      expect(port.boosted, isEmpty);
    });

    test('runtime failure is AzFailed, not fabricated success', () async {
      final gateway =
          HttpStoryGateway(feedPort: _RecordingFeedPort(failBoost: true));
      final result = await gateway.boost('s1', 10);
      expect(result, isA<AzFailed<void>>());
      expect((result as AzFailed<void>).message, contains('Boost failed'));
    });
  });

  test('the gateway never pins the autoDispose story feed', () async {
    // storyFeedProvider is autoDispose on purpose: the feed reloads on each
    // hub entry and stories expire server-side (24h). A NON-autoDispose
    // gateway watching its notifier pins the feed for the whole app run
    // after the first viewer open — stale stories, no reload. The gateway
    // must die with its last listener so the feed can dispose too.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.exists(storyFeedProvider), isFalse,
        reason: 'nobody reads the feed until a gateway or hub listens');
    final sub = container.listen(storyGatewayProvider, (_, __) {});
    expect(container.exists(storyFeedProvider), isTrue,
        reason: 'the gateway watches the feed notifier');
    sub.close();
    // Let Riverpod flush autoDispose disposals.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.exists(storyFeedProvider), isFalse,
        reason: 'the gateway died with its listener; the feed is not '
            'pinned for the rest of the app run');
  });
}
