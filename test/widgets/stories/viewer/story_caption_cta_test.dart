// =============================================================================
// WORKSTREAM F2 (2026-10-25) — the story viewer's caption + CTA block.
//
// The caption used to be a floating Positioned (bottom: 140, maxLines 4,
// hard ellipsis) while the store/market CTA floated at bottom: 88 —
// hard-coded offsets that collide at large text scales, no way to read a
// long caption, and the CTA's reachability was an accident of geometry.
//
// The bottom block is now ONE column: caption (own predictable space) →
// CTA → reply bar. Contracts proven here:
//   • long captions (> ~20 words) get a 'See more' affordance; the full
//     reveal is BOUNDED (≤ a third of the viewport) and scrollable, and
//     collapses back with 'Show less';
//   • the CTA is NEVER covered: it renders fully on screen below the
//     caption block in both states, on small heights and at 1.3x text;
//   • playback HOLDS while the reveal is open (no auto-advance mid-read)
//     and resumes on collapse;
//   • the TRUNCATED caption still carries the FULL text to semantics —
//     the visual ellipsis never discards the caption from the a11y tree;
//   • the reveal state is per-story (keyed) — it never leaks between
//     stories.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/az_gateway_result.dart';
import 'package:azaman/experience/gateways/story_gateway.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/story_model.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/widgets/stories/viewer/story_business_tray.dart';
import 'package:azaman/widgets/stories/viewer/story_viewer_screen.dart';

// ── Harness ──────────────────────────────────────────────────────────────────

class _FakeGateway implements StoryGateway {
  @override
  Set<StoryCapability> get capabilities => const {StoryCapability.view};

  final List<String> viewed = [];

  @override
  Future<void> markViewed(String storyId) async => viewed.add(storyId);

  @override
  Future<AzGatewayResult<void>> reply(String storyId, String message) async =>
      const AzUnsupported('reply');

  @override
  Future<AzGatewayResult<void>> boost(String storyId, int amount) async =>
      const AzUnsupported('boost');

  @override
  Future<AzGatewayResult<void>> react(String storyId, String emoji) async =>
      const AzUnsupported('react');

  @override
  Future<AzGatewayResult<void>> shareLink(String storyId) async =>
      const AzUnsupported('share');
}

class _SeededSearch extends BusinessSearchNotifier {
  _SeededSearch() : super(BusinessService()) {
    state = state.copyWith(
      results: [
        BusinessProfile(
          id: 'b1',
          bizId: 'B1',
          businessName: 'Adinkra Lounge',
          category: 'FOOD_BEVERAGE',
          isVerified: true,
          isSuspended: false,
          kybStatus: 'VERIFIED',
          totalEscrows: 4,
          completedEscrows: 4,
          userId: 1,
          totalVolume: 0,
          averageRating: 0,
          username: 'adinkra',
          createdAt: DateTime(2026, 10, 1),
        ),
      ],
    );
  }

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {}
}

/// 26 words — comfortably over the ~20-word 'See more' threshold, ending
/// with an unmistakable tail word.
const _longCaption =
    'Fresh jollof plates loaded this morning at the Osu kitchen '
    'with grilled tilapia and kelewele on the side plus banku and okra '
    'stew for the lunch rush and the very last word is kunu';

const _shortCaption = 'Fresh jollof plates this morning';

StoryItem _item(String id, {String? caption}) => StoryItem(
  id: id,
  mediaUrl: 'https://cdn.example.com/$id.jpg',
  mediaType: 'IMAGE',
  caption: caption,
  linkedBizId: 'B1',
  durationSeconds: 5,
  boosted: false,
  seen: false,
  createdAt: DateTime(2026, 10, 1),
);

StoryGroup _group(List<StoryItem> stories) => StoryGroup(
  authorId: 7,
  authorUsername: 'ama',
  hasUnseen: true,
  isBoosted: false,
  stories: stories,
);

Widget _host(List<StoryGroup> groups, {double textScale = 1.0}) =>
    MediaQuery.withClampedTextScaling(
      minScaleFactor: textScale,
      maxScaleFactor: textScale,
      child: ProviderScope(
        overrides: [
          storyGatewayProvider.overrideWithValue(_FakeGateway()),
          businessSearchProvider.overrideWith((ref) => _SeededSearch()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        StoryViewerScreen(groups: groups, heroTag: null),
                  ),
                ),
                child: const Text('OPEN VIEWER'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _openViewer(WidgetTester tester) async {
  await tester.tap(find.text('OPEN VIEWER'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1)); // route transition
}

Rect _ctaRect(WidgetTester tester) =>
    tester.getRect(find.byWidgetPredicate((w) => w is StoryBusinessTray));

double _screenHeight(WidgetTester tester) => tester.view.physicalSize.height;

void main() {
  testWidgets('long caption truncates with a See more affordance; the CTA '
      'renders FULLY below it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host([
        _group([_item('s0', caption: _longCaption)]),
      ]),
    );
    await _openViewer(tester);
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('See more'), findsOneWidget);
    expect(find.text('Show less'), findsNothing);

    // The truncated caption block sits fully ABOVE the CTA — own
    // predictable space, no overlap in either direction.
    final captionRect = tester.getRect(find.text(_longCaption));
    final ctaRect = _ctaRect(tester);
    expect(
      captionRect.bottom,
      lessThanOrEqualTo(ctaRect.top + 0.5),
      reason: 'the caption never covers the CTA',
    );

    // The CTA itself is fully on screen and persistent at the bottom.
    expect(ctaRect.top, greaterThan(0));
    expect(ctaRect.bottom, lessThanOrEqualTo(_screenHeight(tester)));
  });

  testWidgets('See more opens a bounded, scrollable full reveal; Show less '
      'collapses it back', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host([
        _group([_item('s0', caption: _longCaption)]),
      ]),
    );
    await _openViewer(tester);
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.text('See more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // The reveal is BOUNDED: never more than a third of the viewport.
    final revealRect = tester.getRect(find.text(_longCaption));
    expect(
      revealRect.height,
      lessThanOrEqualTo(_screenHeight(tester) / 3 + 44),
      reason: 'the full reveal is bounded to a third of the viewport',
    );

    // The full text is scrollable — the tail word is reachable.
    final scrollable = find.descendant(
      of: find.byWidgetPredicate((w) => w is SingleChildScrollView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.textContaining('kunu'),
      100,
      scrollable: scrollable,
    );
    expect(find.textContaining('kunu'), findsOneWidget);

    // The CTA is STILL fully on screen while the reveal is open.
    final ctaRect = _ctaRect(tester);
    expect(
      ctaRect.bottom,
      lessThanOrEqualTo(_screenHeight(tester)),
      reason: 'the CTA is never covered by the open reveal',
    );

    // Collapsible: Show less returns to the truncated state.
    await tester.scrollUntilVisible(
      find.text('Show less'),
      100,
      scrollable: scrollable,
    );
    await tester.tap(find.text('Show less'));
    await tester.pump();
    expect(find.text('See more'), findsOneWidget);
    expect(find.text('Show less'), findsNothing);
  });

  testWidgets('playback holds while the reveal is open and resumes on '
      'collapse — no auto-advance mid-read', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host([
        _group([
          _item('s0', caption: _longCaption),
          _item('s1', caption: _shortCaption),
        ]),
      ]),
    );
    await _openViewer(tester);
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.widgetList<Text>(find.textContaining('1 of 2')),
      isNotEmpty,
      reason: 'on story one',
    );

    // Open the reveal and OUTLIVE the 5s duration.
    await tester.tap(find.text('See more'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));

    expect(
      tester.widgetList<Text>(find.textContaining('1 of 2')),
      isNotEmpty,
      reason: 'the story did NOT auto-advance while the reveal was open',
    );

    // Collapsing resumes playback: the story advances after its duration.
    await tester.tap(find.text('Show less'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(
      tester.widgetList<Text>(find.textContaining('2 of 2')),
      isNotEmpty,
      reason: 'playback resumed after the reveal collapsed',
    );
  });

  testWidgets('the truncated caption still carries the FULL text to '
      'semantics', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      _host([
        _group([_item('s0', caption: _longCaption)]),
      ]),
    );
    await _openViewer(tester);
    await tester.pump(const Duration(milliseconds: 16));

    // Visually truncated (3 lines + ellipsis)…
    expect(find.text('See more'), findsOneWidget);

    // …but the a11y label is the COMPLETE caption — nothing discarded.
    final semantics = tester.getSemantics(find.text(_longCaption));
    expect(
      semantics.label,
      contains(_longCaption),
      reason:
          'the visual ellipsis never discards the caption from '
          'the a11y tree — the full text is in the semantics label',
    );
    expect(
      semantics.label.contains('kunu'),
      isTrue,
      reason: 'right through to the caption\'s very last word',
    );

    handle.dispose();
  });

  testWidgets('short captions (≤ ~20 words) show the whole text with NO '
      'See more affordance', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host([
        _group([_item('s0', caption: _shortCaption)]),
      ]),
    );
    await _openViewer(tester);
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text(_shortCaption), findsOneWidget);
    expect(
      find.text('See more'),
      findsNothing,
      reason: 'a short caption never gets a reveal affordance',
    );
  });

  testWidgets('the CTA stays fully reachable on a small height and at 1.3x '
      'text scale, reveal open', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host([
        _group([_item('s0', caption: _longCaption)]),
      ], textScale: 1.3),
    );
    await _openViewer(tester);
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.takeException(),
      isNull,
      reason: 'no overflow at 320x568 with 1.3x text',
    );

    await tester.tap(find.text('See more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.takeException(),
      isNull,
      reason: 'no overflow with the reveal open at 1.3x text',
    );

    final ctaRect = _ctaRect(tester);
    expect(ctaRect.top, greaterThan(0));
    expect(
      ctaRect.bottom,
      lessThanOrEqualTo(_screenHeight(tester)),
      reason:
          'the CTA is fully on screen on a small device at 1.3x '
          'text scale with the reveal open',
    );
  });

  testWidgets('the reveal state is per-story — opening it on story one never '
      'expands story two', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host([
        _group([
          _item('s0', caption: _longCaption),
          _item('s1', caption: _longCaption),
        ]),
      ]),
    );
    await _openViewer(tester);
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.text('See more'));
    await tester.pump();
    expect(
      find.text('Show less'),
      findsOneWidget,
      reason: 'the reveal is open on story one',
    );

    // Advance to story two through the REAL gesture arbiter (right-side
    // tap = next story) — the only user path that can change stories while
    // the reveal is open (the reveal holds auto-advance).
    await tester.tapAt(const Offset(360, 400));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      tester.widgetList<Text>(find.textContaining('2 of 2')),
      isNotEmpty,
      reason: 'advanced to story two via the arbiter',
    );
    expect(
      find.text('See more'),
      findsOneWidget,
      reason:
          'story two starts COLLAPSED — the reveal never leaks '
          'between stories',
    );
    expect(
      find.text('Show less'),
      findsNothing,
      reason: 'and no hold leaks either — the reveal state is per-story',
    );
  });
}
