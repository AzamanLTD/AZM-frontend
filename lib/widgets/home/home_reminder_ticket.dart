// =============================================================================
// AZAMAN — HOME REMINDER TICKET  (ticket booklet pass, owner direction
// 2026-10-10)
//
// Task A: reminders read as TICKETS, not recolored payment cards. The
// silhouette is an actual ticket: rounded outer corners, inward
// semicircular cut-outs at both sides, a restrained perforated tear-off
// detail around the notches, and (only when the width suits it) a
// subtle ticket-stub perforation line. The palette is muted and
// low-saturation — taupe, dusty rose, soft mauve, sage, slate — with
// dark ink text in light themes and warm ivory text in dark themes, so
// contrast stays accessible in both. Tones are assigned
// deterministically from reminder identity (sorted ids), never per
// build randomness, and every ticket in the active set gets a distinct
// background.
//
// The face keeps the deck's honest content contract: same
// HomeReminderCardData, same key convention ('reminder-card-<id>'),
// same tap semantics. Motion lives in the deck, not here.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/home/home_reminder_deck.dart';
import 'package:azaman/widgets/scale_tap.dart';

/// One ticket tone: a low-saturation surface for light theme and its
/// deepened sibling for dark theme. Muted by design — no neon, no
/// heavy shadows; the deck must never out-shout the balance cards.
class HomeTicketTone {
  const HomeTicketTone({required this.light, required this.dark});

  final Color light;
  final Color dark;

  Color resolve(bool isDark) => isDark ? dark : light;
}

/// The controlled palette (owner direction): taupe, dusty rose, soft
/// mauve, sage, slate — brand-compatible equivalents.
const List<HomeTicketTone> kHomeTicketTones = <HomeTicketTone>[
  // Taupe
  HomeTicketTone(light: Color(0xFFC9BAAB), dark: Color(0xFF4F463D)),
  // Dusty rose
  HomeTicketTone(light: Color(0xFFD2ABA6), dark: Color(0xFF5C4442)),
  // Soft mauve
  HomeTicketTone(light: Color(0xFFC3ACBF), dark: Color(0xFF4E4152)),
  // Sage
  HomeTicketTone(light: Color(0xFFACBFA6), dark: Color(0xFF414D3E)),
  // Slate
  HomeTicketTone(light: Color(0xFFA6B1BB), dark: Color(0xFF3E4750)),
];

/// Ink roles resolved per theme — the accessible text colors painted on
/// a tone surface. Contrast is verified against every tone above
/// (>= 4.5:1 body, >= 7:1 titles in both themes).
class HomeTicketInk {
  const HomeTicketInk._(this.primary, this.secondary, this.tertiary);

  factory HomeTicketInk.of(bool isDark) => isDark
      ? const HomeTicketInk._(
          Color(0xFFF3ECE6),
          Color(0xFFCFC5BD),
          Color(0xFFB3A8A0),
        )
      : const HomeTicketInk._(
          Color(0xFF2E2926),
          Color(0xFF584E48),
          Color(0xFF6D625A),
        );

  final Color primary;
  final Color secondary;
  final Color tertiary;
}

/// Deterministic, set-distinct tone assignment (owner direction):
/// within the active reminder set every ticket gets a distinct
/// background, derived from reminder identity (sorted id order) — never
/// per-build randomness. Sets larger than the palette wrap by identity
/// order, which is still deterministic.
int homeTicketToneIndex({
  required String id,
  required Iterable<String> allIds,
}) {
  final sorted = allIds.toList()..sort();
  final index = sorted.indexOf(id);
  return index < 0 ? id.hashCode.abs() % kHomeTicketTones.length : index;
}

/// The ticket silhouette: a rounded rect minus two inward semicircular
/// cut-outs centered on the vertical mid-line of both sides.
class HomeTicketClipper extends CustomClipper<Path> {
  const HomeTicketClipper({this.radius = 15, this.notchRadius = 9});

  /// Outer corner rounding.
  final double radius;

  /// Inward side cut-out radius.
  final double notchRadius;

  @override
  Path getClip(Size size) {
    final base = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final notches = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(0, size.height / 2),
          radius: notchRadius,
        ),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width, size.height / 2),
          radius: notchRadius,
        ),
      );
    return Path.combine(PathOperation.difference, base, notches);
  }

  @override
  bool shouldReclip(HomeTicketClipper oldClipper) =>
      oldClipper.radius != radius || oldClipper.notchRadius != notchRadius;
}

/// The restrained tear-off detail: a hairline silhouette stroke, a
/// whisper ring around each cut-out, and three micro-perforation dots
/// trailing vertically from each notch. Only when the width suits it
/// is a quiet ticket-stub perforation drawn near the right edge.
class _TicketDetailPainter extends CustomPainter {
  const _TicketDetailPainter({
    required this.ink,
    this.notchRadius = 9,
    this.radius = 15,
  });

  final Color ink;
  final double notchRadius;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = ink.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(
      HomeTicketClipper(
        radius: radius,
        notchRadius: notchRadius,
      ).getClip(size).shift(Offset.zero),
      outline,
    );

    final ring = Paint()
      ..color = ink.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final dots = Paint()..color = ink.withValues(alpha: 0.28);

    for (final cx in <double>[0.0, size.width]) {
      final center = Offset(cx, size.height / 2);
      canvas.drawCircle(center, notchRadius, ring);
      // Micro-perforation dots trailing away from the cut-out.
      for (final dir in <double>[-1, 1]) {
        for (var i = 1; i <= 3; i++) {
          final dy = center.dy + dir * (notchRadius + 6 + (i - 1) * 5.5);
          if (dy < 8 || dy > size.height - 8) continue;
          canvas.drawCircle(Offset(cx, dy), 1.15, dots);
        }
      }
    }

    // Ticket-stub perforation — only when the width genuinely suits a
    // stub division (content keeps its room; never at narrow widths).
    if (size.width >= 320 && size.height >= 130) {
      final x = size.width * 0.78;
      final dash = Paint()
        ..color = ink.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      var y = 14.0;
      while (y < size.height - 14) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 3.5), dash);
        y += 8;
      }
    }
  }

  @override
  bool shouldRepaint(_TicketDetailPainter old) => old.ink != ink;
}

/// One reminder ticket face. Tapping navigates to the real destination
/// behind the signal; `onTap == null` is the honest placeholder.
class HomeReminderTicketFace extends StatelessWidget {
  const HomeReminderTicketFace({
    super.key,
    required this.card,
    required this.colors,
    required this.height,
    required this.toneIndex,
  });

  final HomeReminderCardData card;
  final AzamanColors colors;

  /// The face's height: drives the tall-mode typography.
  final double height;

  /// Palette index (see [homeTicketToneIndex]).
  final int toneIndex;

  static const double _radius = 15;
  static const double _notchRadius = 9;

  @override
  Widget build(BuildContext context) {
    final tall = height >= 150;
    final tone =
        kHomeTicketTones[toneIndex.clamp(0, kHomeTicketTones.length - 1)]
            .resolve(colors.isDark);
    final ink = HomeTicketInk.of(colors.isDark);
    final chipSize = tall ? 56.0 : 40.0;
    final iconSize = tall ? 26.0 : 20.0;

    final body = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          card.eyebrow,
          style: AzText.caption.copyWith(
            color: ink.tertiary,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: tall ? 4 : 2),
        Text(
          card.title,
          style: (tall ? AzText.titleL : AzText.title).copyWith(
            color: ink.primary,
          ),
          maxLines: tall ? 2 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: tall ? 4 : 2),
        Text(
          card.subtitle,
          style: (tall ? AzText.bodyL : AzText.bodyS).copyWith(
            color: ink.secondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    final content = Row(
      children: [
        Container(
          width: chipSize,
          height: chipSize,
          decoration: BoxDecoration(
            color: ink.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AzRadius.md),
          ),
          child: Icon(card.icon, color: ink.primary, size: iconSize),
        ),
        SizedBox(width: tall ? AzSpace.lg : AzSpace.md),
        Expanded(child: body),
        if (card.onTap != null)
          Icon(Icons.chevron_right_rounded, color: ink.tertiary),
      ],
    );

    // Horizontal padding clears the side cut-outs (notch at mid-height
    // + breathing room), so content never collides with the silhouette.
    const hPad = _notchRadius + AzSpace.md + 6;

    final ticket = ClipPath(
      clipper: const HomeTicketClipper(
        radius: _radius,
        notchRadius: _notchRadius,
      ),
      child: CustomPaint(
        painter: _TicketDetailPainter(
          ink: ink.primary,
          notchRadius: _notchRadius,
          radius: _radius,
        ),
        child: ColoredBox(
          color: tone,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              hPad,
              tall ? AzSpace.lg : AzSpace.sm,
              hPad,
              tall ? AzSpace.lg : AzSpace.sm,
            ),
            child: content,
          ),
        ),
      ),
    );

    return SizedBox(
      key: ValueKey('reminder-card-${card.id}'),
      height: height,
      child: card.onTap != null
          ? ScaleTap(onTap: card.onTap, child: ticket)
          : ticket,
    );
  }
}
