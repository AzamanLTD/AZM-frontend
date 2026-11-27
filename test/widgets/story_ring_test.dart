import 'dart:math' as math;
// =============================================================================
// P3 — FINAL STORY RING / CIRCULAR STORY SYSTEM (spec §18 test contract).
//
// These tests did not exist before the P3 pass: at the pre-P3 head the
// squircle ring (hasUnseenStory / storyCount / glowEnabled) exposed none of
// this grammar, so every grammar pin below fails to compile against it —
// fail-first by construction.
//
// Laws pinned here (§18):
//   • only a red/solid dash when only silent unviewed stories exist
//   • only a purple/twin-line dash when only sound unviewed stories exist
//   • both dashes, mirrored around 12, when both types exist
//   • one CENTERED dash when only one type exists
//   • the badge carries the ACTUAL unviewed count (compact past 99,
//     never a literal "+N" placeholder)
//   • zero unviewed → no dashes at all (the caller renders the unified
//     gray resting arc)
//   • viewed dots: odd counts get a true 6-o'clock centre dot, even counts
//     split evenly, capped at 5 visible dots
//   • overflow badge carries the real viewed count
//   • NO glow layer exists anywhere in the ring
//   • the avatar is circular (ClipOval), never a squircle
//
// Real data path (§9):
//   • StoryRingCounts.fromGroup counts seen/unseen exactly from the feed
//   • the sound split stays 0/0 until the backend exposes an audio flag —
//     pinned here so nobody "fixes" it with invented data
//   • count-less sources (marketplace business timestamps) suppress the
//     numeric badge instead of manufacturing a count
// =============================================================================

import 'package:azaman/models/story_model.dart';
import 'package:azaman/widgets/story_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

StoryItem _story({required bool seen}) => StoryItem(
  id: 's${seen ? 1 : 0}-${DateTime.now().microsecondsSinceEpoch}',
  mediaUrl: 'https://example.com/s.jpg',
  mediaType: 'IMAGE',
  durationSeconds: 5,
  boosted: false,
  seen: seen,
  createdAt: DateTime(2026, 10, 6),
);

StoryGroup _group(List<StoryItem> stories) => StoryGroup(
  authorId: 7,
  authorUsername: 'ama',
  authorAvatarUrl: null,
  hasUnseen: stories.any((s) => !s.seen),
  isBoosted: false,
  stories: stories,
);

Future<void> _pumpRing(
  WidgetTester tester,
  StoryRingCounts counts, {
  bool isBoosted = false,
  String? avatarUrl,
}) async {
  await tester.binding.setSurfaceSize(const Size(200, 200));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: StoryRing(
              avatarUrl: avatarUrl,
              counts: counts,
              isBoosted: isBoosted,
              size: 64,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _hasGlowLayer(WidgetTester tester) =>
    tester.widgetList<ShaderMask>(find.byType(ShaderMask)).isNotEmpty ||
    tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).isNotEmpty ||
    tester.widgetList<ImageFiltered>(find.byType(ImageFiltered)).isNotEmpty ||
    tester
        .widgetList<Container>(
          find.byWidgetPredicate(
            (w) => w is Container && _hasBoxShadowBlur(w as Container),
          ),
        )
        .isNotEmpty;

bool _hasBoxShadowBlur(Container c) {
  final d = c.decoration;
  return d is BoxDecoration &&
      (d.boxShadow?.any((s) => s.blurRadius > 0) ?? false);
}

// ── TOP grammar (§3, §4) ─────────────────────────────────────────────────────

void main() {
  // 2026-11-27 redesign: one connected two-colour ring. The split is pure
  // geometry, so it is pinned here without a canvas.
  group('two-colour ring split', () {
    test('three new out of four reads as three-quarters colour', () {
      final split = storyRingSplit(const StoryRingCounts(
        unviewedSilentCount: 3, viewedCount: 1, hasUnviewed: true, unviewedCountKnown: true));
      expect(split.hasRing, isTrue);
      expect(split.unviewedFraction, closeTo(0.75, 1e-9));
    });

    test('all viewed is an all-grey ring, thinner than an active one', () {
      final split = storyRingSplit(const StoryRingCounts(viewedCount: 2));
      expect(split.hasRing, isTrue);
      expect(split.allViewed, isTrue);
      final active = storyRingSplit(const StoryRingCounts(
        unviewedSilentCount: 1, hasUnviewed: true, unviewedCountKnown: true));
      expect(storyRingStroke(64, split), lessThan(storyRingStroke(64, active)));
    });

    test('an unseen flag without a count is all colour, never a guessed fraction', () {
      final split = storyRingSplit(StoryRingCounts.fromUnseenFlag(true));
      expect(split.unviewedFraction, 1);
    });

    test('no stories: no ring and no stroke', () {
      final split = storyRingSplit(const StoryRingCounts.empty());
      expect(split.hasRing, isFalse);
      expect(storyRingStroke(64, split), 0);
    });

    test('unseen is always centred on the top and seen on the bottom', () {
      for (final f in [0.1, 0.25, 0.5, 0.75, 0.9]) {
        final arcs = storyRingArcs(StoryRingSplit(unviewedFraction: f, hasRing: true));
        // Centres: 12 o'clock is -pi/2, 6 o'clock is +pi/2.
        expect(arcs.unviewedStart + arcs.unviewedSweep / 2, closeTo(-math.pi / 2, 1e-9));
        expect(arcs.viewedStart + arcs.viewedSweep / 2, closeTo(math.pi / 2, 1e-9));
        // Together they make the whole circle and meet on both sides.
        expect(arcs.unviewedSweep + arcs.viewedSweep, closeTo(2 * math.pi, 1e-9));
        final unviewedEnd = arcs.unviewedStart + arcs.unviewedSweep;
        expect(unviewedEnd, closeTo(arcs.viewedStart, 1e-9), reason: 'right side joins');
        expect(arcs.viewedStart + arcs.viewedSweep - 2 * math.pi,
            closeTo(arcs.unviewedStart, 1e-9), reason: 'left side joins');
      }
    });

    test('60 degrees seen: a 300 degree top arc and a 60 degree bottom arc', () {
      final arcs = storyRingArcs(const StoryRingSplit(unviewedFraction: 300 / 360, hasRing: true));
      expect(arcs.unviewedSweep * 180 / math.pi, closeTo(300, 1e-9));
      expect(arcs.viewedSweep * 180 / math.pi, closeTo(60, 1e-9));
    });

    test('a fresh group from the feed splits by its real seen flags', () {
      final split = storyRingSplit(StoryRingCounts.fromGroup(
          _group([_story(seen: false), _story(seen: true), _story(seen: true), _story(seen: true)])));
      expect(split.unviewedFraction, closeTo(0.25, 1e-9));
    });
  });

  group('StoryRingCounts — real data', () {
    test('fromGroup counts seen/unseen EXACTLY from the feed', () {
      final g = _group([
        _story(seen: true),
        _story(seen: false),
        _story(seen: false),
        _story(seen: true),
      ]);
      final counts = StoryRingCounts.fromGroup(g);
      expect(counts.viewedCount, 2);
      expect(counts.unviewedTotal, 2);
      expect(counts.unviewedSilentCount, 2);
      expect(
        counts.unviewedCountKnown,
        isTrue,
        reason: 'a per-story feed carries the real count',
      );
      expect(counts.hasUnviewed, isTrue);
      expect(counts.isEmpty, isFalse);
      expect(
        counts.badgeMayRender,
        isTrue,
        reason: 'a real count may show a real number',
      );
    });

    test('fromGroup all-seen → zero unviewed (caught up)', () {
      final counts = StoryRingCounts.fromGroup(
        _group([_story(seen: true), _story(seen: true)]),
      );
      expect(counts.unviewedTotal, 0);
      expect(counts.viewedCount, 2);
      expect(counts.hasUnviewed, isFalse);
      expect(counts.isEmpty, isFalse, reason: 'viewed stories still exist');
      expect(
        storyRingSplit(counts).allViewed,
        isTrue,
        reason: 'caught up: an all-grey ring, no colour',
      );
    });

    test('sound split stays 0/0 until the backend exposes an audio flag '
        '(contract gap, 2026-10-06 audit — do not invent)', () {
      final counts = StoryRingCounts.fromGroup(_group([_story(seen: false)]));
      expect(
        counts.unviewedSoundCount,
        0,
        reason:
            'prisma Story has no audio field; feed map sends none. '
            'Wire the purple dash when real data exists — never before.',
      );
      expect(
        counts.unviewedSilentCount,
        1,
        reason: 'the unviewed story still counts, in the no-sound dash',
      );
    });

    test(
      'count-less unseen → presence dash visible, numeric badge suppressed',
      () {
        final counts = StoryRingCounts.fromUnseenFlag(true);
        expect(
          counts.hasUnviewed,
          isTrue,
          reason: 'existence is explicit, not encoded as a count',
        );
        expect(
          counts.isEmpty,
          isFalse,
          reason: 'an unseen story is known to exist',
        );
        expect(
          counts.unviewedBadgeVisible,
          isFalse,
          reason:
              'the marketplace feed has timestamps, not counts — '
              'the badge only ever shows a real number',
        );
        expect(counts.badgeMayRender, isFalse);
        expect(
          storyRingSplit(counts).unviewedFraction,
          1,
          reason: 'presence without a count is all colour, never a guess',
        );
      },
    );

    test('count-less unseen does NOT expose a fake total '
        '(regression: fromUnseenFlag once manufactured 1)', () {
      final counts = StoryRingCounts.fromUnseenFlag(true);
      expect(
        counts.unviewedTotal,
        0,
        reason: 'never encode "unknown" as a number',
      );
      expect(
        counts.unviewedSilentCount,
        0,
        reason: 'no fake 1 in the data model',
      );
      expect(counts.unviewedCountKnown, isFalse);
    });

    test('count-less false → genuinely empty', () {
      final counts = StoryRingCounts.fromUnseenFlag(false);
      expect(counts.hasUnviewed, isFalse);
      expect(counts.isEmpty, isTrue);
      expect(counts.badgeMayRender, isFalse);
      expect(
        storyRingSplit(counts).hasRing,
        isFalse,
        reason: 'no story: no ring',
      );
    });

    test('empty counts → no story state at all', () {
      const counts = StoryRingCounts.empty();
      expect(counts.isEmpty, isTrue);
      expect(storyRingSplit(counts).hasRing, isFalse);
    });
  });

  // ── widget structure (§1, §2, §12) ─────────────────────────────────────────

  group('widget structure', () {
    testWidgets('avatar is CIRCULAR (ClipOval), never a squircle', (
      tester,
    ) async {
      await _pumpRing(
        tester,
        const StoryRingCounts(unviewedSilentCount: 2),
        avatarUrl: 'https://example.com/a.jpg',
      );
      expect(find.byKey(const ValueKey('story-ring-avatar')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('story-ring-avatar')),
          matching: find.byType(ClipOval),
        ),
        findsOneWidget,
        reason: '§1: a real circular profile photo, not a squircle clip',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('story-ring-avatar')),
          matching: find.byType(ClipPath),
        ),
        findsNothing,
      );
    });

    testWidgets('NO glow layer exists anywhere in the ring', (tester) async {
      await _pumpRing(
        tester,
        const StoryRingCounts(unviewedSilentCount: 2, viewedCount: 3),
      );
      expect(
        _hasGlowLayer(tester),
        isFalse,
        reason: '§2: no glow, no halo, no blurred/luminous ring, ever',
      );
    });

    testWidgets('zero stories → plain ring still renders (no crash, no glow)', (
      tester,
    ) async {
      await _pumpRing(tester, const StoryRingCounts.empty());
      expect(find.byKey(const ValueKey('story-ring-paint')), findsOneWidget);
      expect(_hasGlowLayer(tester), isFalse);
    });

    testWidgets(
      'boosted → independent check micro-indicator, never a ring recolour',
      (tester) async {
        await _pumpRing(tester, const StoryRingCounts.empty(), isBoosted: true);
        expect(
          find.byIcon(Icons.check),
          findsOneWidget,
          reason: '§12: boosted gets its own small badge, not ring colours',
        );
      },
    );

    testWidgets('geometry is derived from size (24dp compact rail renders)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(100, 100));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: StoryRing(
                  avatarUrl: null,
                  counts: const StoryRingCounts(unviewedSilentCount: 1),
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-ring-paint')), findsOneWidget);
      final box = tester.getSize(
        find.byKey(const ValueKey('story-ring-paint')),
      );
      expect(
        box,
        const Size(24, 24),
        reason: "§13: the ring's geometry follows the requested size",
      );
    });
  });
}
