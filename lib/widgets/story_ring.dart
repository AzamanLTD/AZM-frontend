import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/story_model.dart';
import '../providers/theme_provider.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

// ── StoryRing ─────────────────────────────────────────────────────────────────
//
// FINAL STORY IDENTITY (P3, locked 2026-10-06): circular avatar + restrained
// Apple-like system-glyph ring + sound semantics. The old squircle ring
// (hasUnseenStory / storyCount segments / glowEnabled bloom) is GONE —
// circular, not squircle; no glow anywhere, on purpose; one canonical
// widget for every story surface.
//
//   TOP    (unviewed) — at most 2 dashes, one per sound state present,
//          mirrored around 12 o'clock. A numeric badge at 12 shows the REAL
//          total unviewed count. Zero unviewed collapses the top into one
//          unified gray arc (the settled "caught up" glyph).
//   BOTTOM (viewed)   — one gray dot per viewed story, mirrored around 6
//          o'clock, capped at [viewedDotCap]; past the cap a numeric badge
//          carries the real viewed count.
//
//   RED    = unviewed story with NO sound (solid stroke)
//   PURPLE = unviewed story WITH sound (twin fine lines)
// Colour is never the ONLY cue: the sound dash also gets a distinct stroke
// texture so the distinction survives colour-blind users.
//
// The ring is STATIC at rest (no breathing, no pulse) and renders through a
// single CustomPainter — no shaders, no blur, no glow layers; it stays
// cheap when dozens of rings are visible.
//
// ── USAGE ────────────────────────────────────────────────────────────────────
//   StoryRing(
//     counts: StoryRingCounts.fromGroup(group), // real data, see below
//     isBoosted: group.isBoosted,
//     size: 64,
//   )
//
// Zero stories at all (counts empty): plain dim border, same as always.
// =============================================================================

class StoryRing extends ConsumerWidget {
  final String? avatarUrl;

  /// The ring's real state, derived from the story feed. See
  /// [StoryRingCounts] — never hand-roll fake counts at a call site.
  final StoryRingCounts counts;

  /// A small independent accent dot at the bottom-right of the ring — for a
  /// boosted/verified account. Deliberately NOT a ring colour swap: ring
  /// colour is fully spoken for by the viewed/unviewed language, so
  /// "boosted" gets its own separate micro-indicator instead.
  final bool isBoosted;

  final double size;

  /// Above this many viewed stories, collapse to [viewedDotCap] dots plus a
  /// numeric badge instead of growing the dot row indefinitely. 5 gives a
  /// true centre dot (two mirrored pairs either side of 6 o'clock) and stays
  /// close to the dot count in the real Apple glyph.
  static const int viewedDotCap = 5;

  const StoryRing({
    super.key,
    this.avatarUrl,
    required this.counts,
    this.isBoosted = false,
    this.size = 64,
  });

  bool get _hasAnyStory =>
      counts.unviewedTotal > 0 || counts.viewedCount > 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    // Breathing room between the avatar and the ring elements, so dashes and
    // dots never read as flush against the photo. Bigger than the old
    // squircle ring's padding on purpose — real geometry lives in that gap.
    // Scales with size (§13 responsive geometry), zero at 64dp.
    final ringGap = _hasAnyStory ? size * 0.14 : size * 0.05;
    final avatarInset = ringGap + (size * 0.05); // + stroke clearance

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
              counts: counts,
              silentColor: colors.danger,
              soundColor: colors.accentSecondary,
              dimColor: colors.divider,
              badgeBg: colors.textPrimary,
              badgeFg: colors.surface,
              scale: size / 64,
            ),
          ),
          // The avatar is a real circular profile photo (§1) — ClipOval,
          // never a squircle.
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
                child: Icon(Icons.check,
                    size: size * 0.13, color: colors.surface),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(AzamanColors colors) => Container(
        color: colors.softSurface,
        child:
            Icon(Icons.person, color: colors.textTertiary, size: size * 0.42),
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
//     NOT invent it: all unviewed stories render in the NO-SOUND dash until
//     the backend exposes a hasAudio flag. The purple twin-line dash is
//     fully implemented and goes live the moment real data arrives.
class StoryRingCounts {
  /// Unviewed stories with no audio. Rendered as a red solid dash.
  final int unviewedSilentCount;

  /// Unviewed stories with audio. Rendered as a purple twin-line dash.
  /// Currently always 0 — the feed contract exposes no audio flag (see the
  /// audit note above); wire it when the backend adds one.
  final int unviewedSoundCount;

  /// Already-viewed stories. Rendered as gray dots at the bottom.
  final int viewedCount;

  /// Whether the numeric unviewed badge may render. Sources that know an
  /// unviewed story EXISTS but not HOW MANY (the marketplace business feed
  /// only carries lastStoryAt/lastViewedAt timestamps) pass false — the
  /// badge must only ever show a real count, so a count-less source shows
  /// the dash alone.
  final bool unviewedBadgeVisible;

  const StoryRingCounts({
    this.unviewedSilentCount = 0,
    this.unviewedSoundCount = 0,
    this.viewedCount = 0,
    this.unviewedBadgeVisible = true,
  });

  const StoryRingCounts.empty()
      : this(unviewedSilentCount: 0, unviewedSoundCount: 0, viewedCount: 0);

  /// No stories at all.
  bool get isEmpty =>
      unviewedTotal == 0 && viewedCount == 0;

  int get unviewedTotal => unviewedSilentCount + unviewedSoundCount;

  /// The REAL data path: exact counts from a story feed group. The group's
  /// stories list is authoritative — the backend returns every active story
  /// with its real seen flag.
  factory StoryRingCounts.fromGroup(StoryGroup group) {
    final viewed = group.stories.where((s) => s.seen).length;
    final unviewed = group.stories.length - viewed;
    return StoryRingCounts(
      // Sound split stays 0/0 here: no audio flag in the contract (audit
      // note above). unviewedTotal stays exact.
      unviewedSilentCount: unviewed,
      unviewedSoundCount: 0,
      viewedCount: viewed,
    );
  }

  /// Count-less source: an unseen story is KNOWN to exist, but the feed
  /// carries no per-story seen records to count. Renders the unviewed dash
  /// with NO numeric badge — never a manufactured count.
  factory StoryRingCounts.fromUnseenFlag(bool hasUnseen) =>
      StoryRingCounts(
        unviewedSilentCount: hasUnseen ? 1 : 0,
        unviewedBadgeVisible: false,
      );
}

// ── Pure layout grammar (testable without a canvas) ──────────────────────────
//
// Exposed so the §18 test contract can pin the exact ring grammar as pure
// functions: which dashes exist, where the dots sit, what the badges say.

enum StoryDashTexture { solid, twinLine }

class StoryDashSpec {
  final double centerHour; // 12 = top of the ring
  final double sweepHours;
  final StoryDashTexture texture;
  final bool isSound;

  const StoryDashSpec(this.centerHour, this.sweepHours, this.texture,
      {required this.isSound});
}

/// TOP grammar: at most one dash per sound state present.
///   both states    → mirrored pair straddling 12 (silent left, sound right)
///   one state only → a single dash centred on 12 (ring stays symmetric)
///   zero unviewed  → no dashes at all (caller renders the resting arc)
List<StoryDashSpec> storyRingTopDashes(int silent, int sound) {
  if (silent > 0 && sound > 0) {
    return const [
      StoryDashSpec(12 - 0.85, 1.3, StoryDashTexture.solid, isSound: false),
      StoryDashSpec(12 + 0.85, 1.3, StoryDashTexture.twinLine, isSound: true),
    ];
  }
  if (sound > 0) {
    return const [
      StoryDashSpec(12, 1.7, StoryDashTexture.twinLine, isSound: true),
    ];
  }
  if (silent > 0) {
    return const [
      StoryDashSpec(12, 1.7, StoryDashTexture.solid, isSound: false),
    ];
  }
  return const [];
}

/// Badge label for a count: the actual number, compacted only past 99
/// (never a literal "+N" placeholder).
String storyRingBadgeLabel(int count) => count > 99 ? '99+' : '$count';

/// BOTTOM grammar: viewed dots mirrored around 6 o'clock. Odd counts get a
/// true centre dot; even counts split evenly. Capped at
/// [StoryRing.viewedDotCap] visible dots — past the cap the badge carries
/// the real count instead.
List<double> storyRingViewedDotHours(int viewedCount) {
  final shown = math.min(viewedCount, StoryRing.viewedDotCap);
  const dotSpacingHours = 0.62;
  final hours = <double>[];
  if (shown.isOdd) {
    hours.add(6);
    for (int i = 1; i <= (shown - 1) ~/ 2; i++) {
      hours.add(6 - i * dotSpacingHours);
      hours.add(6 + i * dotSpacingHours);
    }
  } else {
    for (int i = 0; i < shown ~/ 2; i++) {
      final offset = (i + 0.5) * dotSpacingHours;
      hours.add(6 - offset);
      hours.add(6 + offset);
    }
  }
  return hours;
}

// ── Custom painter ──────────────────────────────────────────────────────────
//
// Angle convention: Flutter's drawArc takes 0 = 3 o'clock, angles increasing
// CLOCKWISE. _clock lets the rest of the file say "12 o'clock" / "6 o'clock".

double _clock(double hours) => (hours / 12.0) * 2 * math.pi - (math.pi / 2);

class _StoryRingPainter extends CustomPainter {
  final StoryRingCounts counts;
  final Color silentColor;
  final Color soundColor;
  final Color dimColor;
  final Color badgeBg;
  final Color badgeFg;

  /// All fixed geometry scales with the ring's actual size (§13): 1.0 at the
  /// 64dp baseline, smaller on the 24dp compact rail, larger on big
  /// surfaces. Never hard-coded pixels that only work at 64dp.
  final double scale;

  _StoryRingPainter({
    required this.counts,
    required this.silentColor,
    required this.soundColor,
    required this.dimColor,
    required this.badgeBg,
    required this.badgeFg,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 3.0 * scale;

    if (counts.isEmpty) {
      // No stories at all — plain dim border, same as the old widget.
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = dimColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * scale,
      );
      return;
    }

    _paintTop(canvas, center, radius);
    _paintBottom(canvas, center, radius);
  }

  // ── TOP: unviewed ──────────────────────────────────────────────────────
  void _paintTop(Canvas canvas, Offset center, double radius) {
    if (counts.unviewedTotal == 0) {
      // Fully caught up — one unified resting arc, the Apple "idle" glyph.
      final paint = Paint()
        ..color = dimColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * scale
        ..strokeCap = StrokeCap.round;
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(rect, _clock(10.3), _sweepFor(3.4), false, paint);
      return;
    }

    final rect = Rect.fromCircle(center: center, radius: radius);
    for (final dash in storyRingTopDashes(
        counts.unviewedSilentCount, counts.unviewedSoundCount)) {
      _drawDash(canvas, rect, dash);
    }

    if (counts.unviewedBadgeVisible) {
      _drawBadge(
        canvas,
        center,
        radius,
        hour: 12,
        label: storyRingBadgeLabel(counts.unviewedTotal),
        bg: badgeBg,
        fg: badgeFg,
      );
    }
  }

  // ── BOTTOM: viewed ─────────────────────────────────────────────────────
  void _paintBottom(Canvas canvas, Offset center, double radius) {
    if (counts.viewedCount == 0) return;

    final dotPaint = Paint()..color = dimColor;
    final dotRadius = 2.6 * scale;

    for (final h in storyRingViewedDotHours(counts.viewedCount)) {
      canvas.drawCircle(
          _pointOnCircle(center, radius, h), dotRadius, dotPaint);
    }

    if (counts.viewedCount > StoryRing.viewedDotCap) {
      _drawBadge(
        canvas,
        center,
        radius,
        hour: 6,
        label: storyRingBadgeLabel(counts.viewedCount),
        bg: dimColor,
        fg: badgeFg,
      );
    }
  }

  // ── shared drawing helpers ─────────────────────────────────────────────

  double _sweepFor(double hours) => (hours / 12.0) * 2 * math.pi;

  Offset _pointOnCircle(Offset center, double radius, double hour) {
    final a = _clock(hour);
    return Offset(
        center.dx + radius * math.cos(a), center.dy + radius * math.sin(a));
  }

  void _drawDash(Canvas canvas, Rect rect, StoryDashSpec dash) {
    final startHour = dash.centerHour - dash.sweepHours / 2;
    final sweep = _sweepFor(dash.sweepHours);
    final color = dash.isSound ? soundColor : silentColor;

    if (dash.texture == StoryDashTexture.solid) {
      // Silent (red): a single solid stroke.
      canvas.drawArc(
        rect,
        _clock(startHour),
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6 * scale
          ..strokeCap = StrokeCap.round,
      );
    } else {
      // Sound (purple): twin fine lines instead of one thick line — the
      // colour-independent cue. Same angular footprint as the solid dash so
      // the two read as the same "size" of element.
      final radius = rect.width / 2;
      final inner =
          Rect.fromCircle(center: rect.center, radius: radius - 1.6 * scale);
      final outer =
          Rect.fromCircle(center: rect.center, radius: radius + 1.6 * scale);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * scale
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(inner, _clock(startHour), sweep, false, paint);
      canvas.drawArc(outer, _clock(startHour), sweep, false, paint);
    }
  }

  void _drawBadge(
    Canvas canvas,
    Offset center,
    double radius, {
    required double hour,
    required String label,
    required Color bg,
    required Color fg,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: fg,
          fontSize: 8.5 * scale,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeW = math.max(14.0 * scale, textPainter.width + 7 * scale);
    final badgeH = 13.0 * scale;
    final pos = _pointOnCircle(center, radius + 7 * scale, hour);

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos, width: badgeW, height: badgeH),
      Radius.circular(badgeH / 2),
    );
    canvas.drawRRect(badgeRect, Paint()..color = bg);
    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _StoryRingPainter old) =>
      old.counts.unviewedSilentCount != counts.unviewedSilentCount ||
      old.counts.unviewedSoundCount != counts.unviewedSoundCount ||
      old.counts.viewedCount != counts.viewedCount ||
      old.silentColor != silentColor ||
      old.soundColor != soundColor ||
      old.dimColor != dimColor ||
      old.scale != scale;
}
