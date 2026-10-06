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

Future<void> _pumpRing(WidgetTester tester, StoryRingCounts counts,
    {bool isBoosted = false, String? avatarUrl}) async {
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
            find.byWidgetPredicate((w) => w is Container && _hasBoxShadowBlur(w as Container)))
        .isNotEmpty;

bool _hasBoxShadowBlur(Container c) {
  final d = c.decoration;
  return d is BoxDecoration &&
      (d.boxShadow?.any((s) => s.blurRadius > 0) ?? false);
}

// ── TOP grammar (§3, §4) ─────────────────────────────────────────────────────

void main() {
  group('top dash grammar', () {
    test('only silent unviewed → ONE solid dash, centred on 12', () {
      final dashes = storyRingTopDashes(3, 0);
      expect(dashes, hasLength(1));
      expect(dashes.single.isSound, isFalse,
          reason: 'silent stories must render the no-sound (red) dash');
      expect(dashes.single.texture, StoryDashTexture.solid);
      expect(dashes.single.centerHour, 12,
          reason: 'single-type state stays symmetric: centred on 12');
    });

    test('only sound unviewed → ONE twin-line dash, centred on 12', () {
      final dashes = storyRingTopDashes(0, 2);
      expect(dashes, hasLength(1));
      expect(dashes.single.isSound, isTrue,
          reason: 'sound stories render the has-sound (purple) dash');
      expect(dashes.single.texture, StoryDashTexture.twinLine,
          reason: 'the colour-independent cue must survive colour-blindness');
      expect(dashes.single.centerHour, 12);
    });

    test('both sound states → mirrored pair straddling 12, never more', () {
      final dashes = storyRingTopDashes(80, 20);
      expect(dashes, hasLength(2),
          reason: '§4: at most two dashes, however many stories exist');
      expect(dashes[0].centerHour, lessThan(12),
          reason: 'silent dash sits left of 12');
      expect(dashes[1].centerHour, greaterThan(12),
          reason: 'sound dash sits right of 12');
      expect(12 - dashes[0].centerHour,
          closeTo(dashes[1].centerHour - 12, 0.0001),
          reason: 'the pair is MIRRORED around 12');
      expect(dashes[0].texture, StoryDashTexture.solid);
      expect(dashes[1].texture, StoryDashTexture.twinLine);
    });

    test('zero unviewed → no dashes at all (resting arc territory)', () {
      expect(storyRingTopDashes(0, 0), isEmpty,
          reason: 'the caught-up state must not leave stale colored dashes');
    });
  });

  // ── badge (§5) ─────────────────────────────────────────────────────────────

  group('unviewed badge', () {
    test('shows the ACTUAL count', () {
      expect(storyRingBadgeLabel(7), '7');
      expect(storyRingBadgeLabel(1), '1');
    });

    test('compacts only past 99 — never a literal +N placeholder', () {
      expect(storyRingBadgeLabel(99), '99');
      expect(storyRingBadgeLabel(100), '99+');
      expect(storyRingBadgeLabel(120), '99+');
      expect(storyRingBadgeLabel(3).contains('+'), isFalse);
    });
  });

  // ── BOTTOM grammar (§7, §8) ─────────────────────────────────────────────────

  group('viewed dot grammar', () {
    test('odd counts get a true centre dot at exactly 6 o\'clock', () {
      expect(storyRingViewedDotHours(1), [6]);
      expect(storyRingViewedDotHours(3), contains(6));
      expect(storyRingViewedDotHours(3), hasLength(3));
    });

    test('even counts split evenly around 6, no centre dot', () {
      final hours = storyRingViewedDotHours(2);
      expect(hours, hasLength(2));
      expect(hours, isNot(contains(6)));
      expect(hours.where((h) => h < 6).length, 1);
      expect(hours.where((h) => h > 6).length, 1);
    });

    test('caps at 5 visible dots — no bead chain', () {
      expect(storyRingViewedDotHours(5), hasLength(5));
      expect(storyRingViewedDotHours(6), hasLength(5),
          reason: '§8: past the cap the badge carries the count instead');
      expect(storyRingViewedDotHours(50), hasLength(5));
    });

    test('dots are mirror-symmetric around 6', () {
      final hours = storyRingViewedDotHours(4);
      hours.sort();
      for (var i = 0; i < hours.length; i++) {
        expect(hours[i], closeTo(12 - hours[hours.length - 1 - i], 0.0001));
      }
    });
  });

  // ── real data path (§9) ─────────────────────────────────────────────────────

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
      expect(counts.unviewedCountKnown, isTrue,
          reason: 'a per-story feed carries the real count');
      expect(counts.hasUnviewed, isTrue);
      expect(counts.isEmpty, isFalse);
      expect(counts.badgeMayRender, isTrue,
          reason: 'a real count may show a real number');
    });

    test('fromGroup all-seen → zero unviewed (caught up)', () {
      final counts =
          StoryRingCounts.fromGroup(_group([_story(seen: true), _story(seen: true)]));
      expect(counts.unviewedTotal, 0);
      expect(counts.viewedCount, 2);
      expect(counts.hasUnviewed, isFalse);
      expect(counts.isEmpty, isFalse, reason: 'viewed stories still exist');
      expect(storyRingTopDashSpecs(counts), isEmpty,
          reason: 'caught up — the resting arc, no dash');
    });

    test(
        'sound split stays 0/0 until the backend exposes an audio flag '
        '(contract gap, 2026-10-06 audit — do not invent)',
        () {
      final counts = StoryRingCounts.fromGroup(_group([_story(seen: false)]));
      expect(counts.unviewedSoundCount, 0,
          reason: 'prisma Story has no audio field; feed map sends none. '
              'Wire the purple dash when real data exists — never before.');
      expect(counts.unviewedSilentCount, 1,
          reason: 'the unviewed story still counts, in the no-sound dash');
    });

    test(
        'count-less unseen → presence dash visible, numeric badge suppressed',
        () {
      final counts = StoryRingCounts.fromUnseenFlag(true);
      expect(counts.hasUnviewed, isTrue,
          reason: 'existence is explicit, not encoded as a count');
      expect(counts.isEmpty, isFalse,
          reason: 'an unseen story is known to exist');
      expect(counts.unviewedBadgeVisible, isFalse,
          reason: 'the marketplace feed has timestamps, not counts — '
              'the badge only ever shows a real number');
      expect(counts.badgeMayRender, isFalse);
      final dashes = storyRingTopDashSpecs(counts);
      expect(dashes, hasLength(1), reason: 'exactly one presence dash');
      expect(dashes.single.texture, StoryDashTexture.solid,
          reason: 'the no-sound dash — the documented fallback for '
              'missing audio metadata, not a sound classification');
      expect(dashes.single.isSound, isFalse,
          reason: 'the purple branch stays dormant without real data');
    });

    test(
        'count-less unseen does NOT expose a fake total '
        '(regression: fromUnseenFlag once manufactured 1)',
        () {
      final counts = StoryRingCounts.fromUnseenFlag(true);
      expect(counts.unviewedTotal, 0,
          reason: 'never encode "unknown" as a number');
      expect(counts.unviewedSilentCount, 0,
          reason: 'no fake 1 in the data model');
      expect(counts.unviewedCountKnown, isFalse);
    });

    test('count-less false → genuinely empty', () {
      final counts = StoryRingCounts.fromUnseenFlag(false);
      expect(counts.hasUnviewed, isFalse);
      expect(counts.isEmpty, isTrue);
      expect(counts.badgeMayRender, isFalse);
      expect(storyRingTopDashSpecs(counts), isEmpty,
          reason: 'no dash, no badge — the plain resting ring');
    });

    test('empty counts → no story state at all', () {
      const counts = StoryRingCounts.empty();
      expect(counts.isEmpty, isTrue);
      expect(storyRingTopDashes(counts.unviewedSilentCount, counts.unviewedSoundCount),
          isEmpty);
      expect(storyRingViewedDotHours(counts.viewedCount), isEmpty);
    });
  });

  // ── widget structure (§1, §2, §12) ─────────────────────────────────────────

  group('widget structure', () {
    testWidgets('avatar is CIRCULAR (ClipOval), never a squircle',
        (tester) async {
      await _pumpRing(tester, const StoryRingCounts(unviewedSilentCount: 2),
          avatarUrl: 'https://example.com/a.jpg');
      expect(find.byKey(const ValueKey('story-ring-avatar')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('story-ring-avatar')),
              matching: find.byType(ClipOval)),
          findsOneWidget,
          reason: '§1: a real circular profile photo, not a squircle clip');
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('story-ring-avatar')),
              matching: find.byType(ClipPath)),
          findsNothing);
    });

    testWidgets('NO glow layer exists anywhere in the ring', (tester) async {
      await _pumpRing(tester, const StoryRingCounts(unviewedSilentCount: 2, viewedCount: 3));
      expect(_hasGlowLayer(tester), isFalse,
          reason: '§2: no glow, no halo, no blurred/luminous ring, ever');
    });

    testWidgets('zero stories → plain ring still renders (no crash, no glow)',
        (tester) async {
      await _pumpRing(tester, const StoryRingCounts.empty());
      expect(find.byKey(const ValueKey('story-ring-paint')), findsOneWidget);
      expect(_hasGlowLayer(tester), isFalse);
    });

    testWidgets('boosted → independent check micro-indicator, never a ring recolour',
        (tester) async {
      await _pumpRing(tester, const StoryRingCounts.empty(), isBoosted: true);
      expect(find.byIcon(Icons.check), findsOneWidget,
          reason: '§12: boosted gets its own small badge, not ring colours');
    });

    testWidgets('geometry is derived from size (24dp compact rail renders)',
        (tester) async {
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
      final box = tester.getSize(find.byKey(const ValueKey('story-ring-paint')));
      expect(box, const Size(24, 24),
          reason: "§13: the ring's geometry follows the requested size");
    });
  });
}
