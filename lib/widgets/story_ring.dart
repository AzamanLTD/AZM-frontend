// lib/widgets/story_ring.dart
// =============================================================================
// THE STORY RING (2026-11-27 redesign)
//
// One unbroken circle around the photo, in two colours that meet:
//
//   • the UNVIEWED share is a vivid arc in the user's accent family,
//     starting at 12 o'clock and running clockwise;
//   • the VIEWED share continues in grey until it meets the start again;
//   • arc lengths follow the real counts, so three new stories out of four
//     read as three-quarters colour;
//   • all viewed: a thin, quiet grey ring; nothing at all: no ring.
//
// Red is retired (in a money app red means an error), the viewed dots and
// count badge of the earlier status-glyph design are gone, and the photo
// fills about 86% of the ring (it was about 62%).
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/story_model.dart';
import '../providers/theme_provider.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

class StoryRing extends ConsumerWidget {
  final String? avatarUrl;

  /// The ring's real state, derived from the story feed. See
  /// [StoryRingCounts]; never hand-roll fake counts at a call site.
  final StoryRingCounts counts;

  /// A small independent accent dot at the bottom-right of the ring, for a
  /// boosted/verified account. Ring colour is spoken for by viewed/unviewed,
  /// so "boosted" keeps its own micro-indicator.
  final bool isBoosted;

  final double size;

  const StoryRing({
    super.key,
    this.avatarUrl,
    required this.counts,
    this.isBoosted = false,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final split = storyRingSplit(counts);
    final stroke = storyRingStroke(size, split);
    // Ring, then a thin gap, then the photo: the photo is the subject.
    final avatarInset = split.hasRing ? stroke + size * 0.035 : 0.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            key: const ValueKey('story-ring-paint'),
            size: Size(size, size),
            painter: _StoryRingPainter(
              split: split,
              stroke: stroke,
              unviewedFrom: colors.accent,
              unviewedTo: colors.accentSecondary,
              viewed: colors.textTertiary.withValues(alpha: 0.38),
            ),
          ),
          Positioned(
            key: const ValueKey('story-ring-avatar'),
            left: avatarInset,
            top: avatarInset,
            right: avatarInset,
            bottom: avatarInset,
            child: ClipOval(
              child: avatarUrl != null && avatarUrl!.isNotEmpty
                  ? AzamanNetworkImage(
                      imageUrl: avatarUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _placeholder(colors),
                    )
                  : _placeholder(colors),
            ),
          ),
          if (isBoosted)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.22,
                height: size * 0.22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accent,
                  border: Border.all(color: colors.surface, width: 2),
                ),
                child: Icon(Icons.check, size: size * 0.13, color: colors.surface),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(AzamanColors colors) => Container(
        color: colors.softSurface,
        child: Icon(Icons.person, color: colors.textTertiary, size: size * 0.42),
      );
}

// ── Real-data adapter ────────────────────────────────────────────────────────
//
// §9: the ring is driven by REAL story data. Never manufacture sound state,
// never derive viewed counts from totals, never reuse a boolean "has unseen"
// flag as a fake count.
//
// CONTRACT AUDIT (2026-10-06, backend services/storyService.js feed map +
// prisma Story):
//   • viewed state      — REAL. The feed marks each story seen via StoryView
//     records, and returns the group's full active story list, so counting
//     stories[].seen is exact.
//   • unviewed counts   — REAL and exact (stories.length − seen).
//   • sound/audio state  — DOES NOT EXIST in the contract. Prisma Story has
//     mediaUrl/caption only; the feed map sends no audio flag. Per §9 we do
//     NOT invent it — no inference from media type, file extension or URL.
//     The red no-sound dash is therefore a DOCUMENTED FALLBACK for missing
//     audio metadata, NOT a confirmed "this story has no sound"
//     classification. It must never be described or reported as real
//     sound data. The purple twin-line dash is fully implemented and goes
//     live the moment the backend exposes a hasAudio flag.
class StoryRingCounts {
  /// Unviewed stories in the NO-SOUND (red) bucket. For a per-story feed
  /// this is the exact count of stories not yet seen. The bucket itself
  /// is the documented FALLBACK for missing audio metadata (audit note
  /// above): a story in it is NOT confirmed to be silent — the client
  /// simply has no audio data for it yet.
  final int unviewedSilentCount;

  /// Unviewed stories in the SOUND (purple) bucket. Currently always 0 —
  /// the feed contract exposes no audio flag, so no story may be placed
  /// in this bucket (the purple branch stays dormant by contract, not by
  /// styling). Wire it when the backend adds hasAudio.
  final int unviewedSoundCount;

  /// Already-viewed stories. Rendered as gray dots at the bottom.
  final int viewedCount;

  /// Whether the numeric unviewed badge may render. Sources that know an
  /// unviewed story EXISTS but not HOW MANY (the marketplace business feed
  /// only carries lastStoryAt/lastViewedAt timestamps) pass false — the
  /// badge must only ever show a real count, so a count-less source shows
  /// the dash alone.
  final bool unviewedBadgeVisible;

  /// COUNT-LESS STATE — an unviewed story is KNOWN to exist even though
  /// the source carries no per-story records to count it. Drives the
  /// unviewed dash WITHOUT any numeric claim: it never adds to
  /// [unviewedTotal] and never enables the badge.
  final bool hasUnviewed;

  /// Whether [unviewedSilentCount] + [unviewedSoundCount] is the REAL,
  /// exact unviewed count (a per-story feed). False for count-less
  /// sources, where the exact number is unknown — never encoded as a
  /// fake count.
  final bool unviewedCountKnown;

  const StoryRingCounts({
    this.unviewedSilentCount = 0,
    this.unviewedSoundCount = 0,
    this.viewedCount = 0,
    this.unviewedBadgeVisible = true,
    this.hasUnviewed = false,
    this.unviewedCountKnown = false,
  });

  const StoryRingCounts.empty()
    : this(unviewedSilentCount: 0, unviewedSoundCount: 0, viewedCount: 0);

  /// No stories at all — and no known-to-exist unviewed story either.
  bool get isEmpty => unviewedTotal == 0 && viewedCount == 0 && !hasUnviewed;

  int get unviewedTotal => unviewedSilentCount + unviewedSoundCount;

  /// Whether the numeric unviewed badge may actually paint: only with a
  /// REAL count. A count-less source never renders a number — there is
  /// no number.
  bool get badgeMayRender => unviewedBadgeVisible && unviewedCountKnown;

  /// The REAL data path: exact counts from a story feed group. The group's
  /// stories list is authoritative — the backend returns every active story
  /// with its real seen flag.
  factory StoryRingCounts.fromGroup(StoryGroup group) {
    final viewed = group.stories.where((s) => s.seen).length;
    final unviewed = group.stories.length - viewed;
    return StoryRingCounts(
      // Sound split stays all-fallback here: no audio flag in the
      // contract (audit note above), so every unseen story lands in the
      // no-metadata bucket. unviewedTotal stays EXACT — a real count
      // from real per-story records.
      unviewedSilentCount: unviewed,
      unviewedSoundCount: 0,
      viewedCount: viewed,
      hasUnviewed: unviewed > 0,
      unviewedCountKnown: true,
    );
  }

  /// Count-less source: an unseen story is KNOWN to exist, but the feed
  /// carries no per-story seen records to count it. Encoded as the
  /// explicit [hasUnviewed] state — NEVER as a manufactured numeric count:
  /// [unviewedTotal] stays 0 and the numeric badge stays suppressed.
  /// The unviewed dash still renders (one presence dash), driven by the
  /// flag, not by a fake number.
  factory StoryRingCounts.fromUnseenFlag(bool hasUnseen) => StoryRingCounts(
    hasUnviewed: hasUnseen,
    unviewedCountKnown: false,
    unviewedBadgeVisible: false,
  );
}


// ── Pure geometry (unit-tested) ──────────────────────────────────────────────

/// How the ring is split. [unviewedFraction] is the coloured share of the
/// circle (0..1); the rest is grey. [hasRing] is false when there is no
/// story at all.
@immutable
class StoryRingSplit {
  const StoryRingSplit({required this.unviewedFraction, required this.hasRing});

  final double unviewedFraction;
  final bool hasRing;

  bool get allViewed => hasRing && unviewedFraction == 0;

  @override
  bool operator ==(Object other) =>
      other is StoryRingSplit &&
      other.unviewedFraction == unviewedFraction &&
      other.hasRing == hasRing;

  @override
  int get hashCode => Object.hash(unviewedFraction, hasRing);
}

/// The split from REAL counts:
///   • counted stories: unviewed / (unviewed + viewed);
///   • an unseen flag with no count (marketplace feed): all colour, never a
///     guessed fraction;
///   • only viewed: all grey; nothing: no ring.
StoryRingSplit storyRingSplit(StoryRingCounts c) {
  final unviewed = c.unviewedTotal;
  final total = unviewed + c.viewedCount;
  if (total > 0) {
    return StoryRingSplit(unviewedFraction: unviewed / total, hasRing: true);
  }
  if (c.hasUnviewed) {
    return const StoryRingSplit(unviewedFraction: 1, hasRing: true);
  }
  return const StoryRingSplit(unviewedFraction: 0, hasRing: false);
}

/// Stroke width: confident when something is new, quieter when all viewed.
double storyRingStroke(double size, StoryRingSplit split) {
  if (!split.hasRing) return 0;
  return split.allViewed ? size * 0.03 : size * 0.047;
}

class _StoryRingPainter extends CustomPainter {
  _StoryRingPainter({
    required this.split,
    required this.stroke,
    required this.unviewedFrom,
    required this.unviewedTo,
    required this.viewed,
  });

  final StoryRingSplit split;
  final double stroke;
  final Color unviewedFrom;
  final Color unviewedTo;
  final Color viewed;

  static const double _start = -math.pi / 2; // 12 o'clock

  @override
  void paint(Canvas canvas, Size size) {
    if (!split.hasRing) return;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - stroke / 2,
    );
    final coloured = split.unviewedFraction * 2 * math.pi;

    // Grey for the viewed share. Butt caps on both arcs, so the two colours
    // meet edge to edge with no gap and no overlap.
    if (split.unviewedFraction < 1) {
      canvas.drawArc(
        rect,
        _start + coloured,
        2 * math.pi - coloured,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = viewed,
      );
    }
    if (coloured > 0) {
      canvas.drawArc(
        rect,
        _start,
        coloured,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: math.max(coloured, 0.01),
            colors: [unviewedFrom, unviewedTo],
            transform: const GradientRotation(_start),
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_StoryRingPainter old) =>
      old.split != split ||
      old.stroke != stroke ||
      old.unviewedFrom != unviewedFrom ||
      old.unviewedTo != unviewedTo ||
      old.viewed != viewed;
}
