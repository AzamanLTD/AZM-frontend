// =============================================================================
// AZAMAN — Susu Wheel (TASK-017, Tier 3 — Signature moments)
//
// The assessment's §4.2D call: the Susu dashboard should be organised
// around a wheel of members — current recipient highlighted, a progress
// arc sweeping toward the next turn — and position selection should be
// *that wheel*, draggable, spring-loaded, snapping into place.
//
// This file ships two widgets around one shared geometry vocabulary:
//
//   SusuWheel         — read-only wheel for the dashboard. Members sit at
//                       their cycleSlot; the upcoming cycle's slot is
//                       ringed; a progress arc fills across the window
//                       from the previous cycle's scheduledRunAt to the
//                       upcoming one. Honest: no arc when the window is
//                       missing, no countdown when no upcoming cycle.
//
//   SusuPositionWheel — draggable picker. The dots layer rotates with the
//                       drag; on release the wheel springs (kHouseSpring)
//                       to the nearest FREE slot under the 12-o'clock
//                       indicator. Tap-to-select is preserved; taken slots
//                       stay inert.
//
// Geometry rules (every position derives from the LayoutBuilder width):
//   * Slot 1 sits at 12 o'clock (angle −π/2); slots advance clockwise.
//   * The dots layer is rotated with Transform.rotate so Flutter's
//     hit-testing follows the rotation — painted dots would not.
//   * F-046: avatar hues are seeded from userId/displayName with a
//     codeUnits fold, never String.hashCode.
//   * F-049: one AnimationController per State → SingleTickerProviderStateMixin.
// =============================================================================
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/liquid/liquid_engine.dart';

// ── Pure helpers (unit-tested) ────────────────────────────────────────────────

/// Angle (radians) of [slot] (1-based) on a wheel of [total] slots.
/// Slot 1 is at 12 o'clock (−π/2); angles advance clockwise.
double susuSlotAngle(int slot, int total) {
  final safe = total <= 0 ? 1 : total;
  return -math.pi / 2 + 2 * math.pi * ((slot - 1) % safe) / safe;
}

/// The 1-based slot currently under the 12-o'clock indicator when the
/// dots layer has been rotated clockwise by [rotation] radians.
int susuRotationSlot(double rotation, int total) {
  final safe = total <= 0 ? 1 : total;
  final step = 2 * math.pi / safe;
  final idx = ((-rotation / step).round()) % safe;
  return idx + 1;
}

/// Shortest-path rotation (radians) that brings [slot] under the
/// 12-o'clock indicator, starting from [current].
double susuSnapRotation(double current, int slot, int total) {
  final target = -math.pi / 2 - susuSlotAngle(slot, total);
  var delta = (target - current) % (2 * math.pi);
  if (delta > math.pi) delta -= 2 * math.pi;
  if (delta < -math.pi) delta += 2 * math.pi;
  return current + delta;
}

/// Nearest free slot to the 12-o'clock position at [rotation], with the
/// angular distance to it. Null when no slot is free or [total] <= 0.
({int slot, double delta})? susuNearestFreeSlot(
    double rotation, int total, Set<int> taken) {
  if (total <= 0) return null;
  var bestSlot = -1;
  var bestDist = double.infinity;
  for (var s = 1; s <= total; s++) {
    if (taken.contains(s)) continue;
    final d = _circularDistance(rotation, _snapTargetFor(s, total));
    if (d < bestDist) {
      bestDist = d;
      bestSlot = s;
    }
  }
  if (bestSlot == -1) return null;
  return (slot: bestSlot, delta: bestDist);
}

double _snapTargetFor(int slot, int total) =>
    -math.pi / 2 - susuSlotAngle(slot, total);

double _circularDistance(double a, double b) {
  var d = (a - b) % (2 * math.pi);
  if (d > math.pi) d -= 2 * math.pi;
  if (d < -math.pi) d += 2 * math.pi;
  return d.abs();
}

/// Fraction of the window [start]→[end] elapsed at [now].
/// 0 on any missing or degenerate window; clamped to 1.0.
double susuArcSweep(DateTime? start, DateTime? end, DateTime now) {
  if (start == null || end == null) return 0.0;
  final totalMs = end.difference(start).inMilliseconds;
  if (totalMs <= 0) return 0.0;
  final elapsedMs = now.difference(start).inMilliseconds;
  return (elapsedMs / totalMs).clamp(0.0, 1.0).toDouble();
}

/// F-046: String.hashCode is not stable across Dart runs; deterministic
/// visuals derived from ids use this codeUnits fold instead.
int susuStableSeed(String id) =>
    id.codeUnits.fold<int>(7, (sum, u) => sum * 31 + u);

/// Stable hue (0..360) for an avatar placeholder.
double susuAvatarHue(String id) => (susuStableSeed(id) % 360).toDouble();

/// Compact countdown for the upcoming payout moment. '' when [at] is
/// null; 'Due now' once the moment has passed.
String susuCountdownLabel(DateTime? at, DateTime now) {
  if (at == null) return '';
  final diff = at.difference(now);
  if (diff.inSeconds <= 0) return 'Due now';
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  final minutes = diff.inMinutes % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m';
  return '<1m';
}

// ── Shared geometry and chrome ────────────────────────────────────────────────

const double _kWheelMaxDiameter = 280.0;
const double _kDotSize = 44.0;
const double _kDotPad = 5.0;

Widget _twelveOClockIndicator(AzamanColors colors) {
  return Align(
    alignment: Alignment.topCenter,
    // TASK-017: keyed so the acceptance test can MEASURE (not assume) that
    // the indicator sits at the wheel's top edge, horizontally centred.
    // The key sits on the Icon, not the Align: the Align expands to fill
    // the wheel, so its rect is the wheel's rect and cannot prove
    // placement — the indicator element itself is what must be measured.
    child: Icon(Icons.arrow_drop_down,
        key: const ValueKey('susu-12-oclock-indicator'),
        color: colors.accent,
        size: 22),
  );
}

// ── SusuWheel — read-only dashboard wheel ─────────────────────────────────────

class SusuWheel extends ConsumerStatefulWidget {
  final List<SusuMemberView> members;
  final List<SusuCycleView> cycles;
  final int totalSlots;
  final dynamic meUserId;

  const SusuWheel({
    super.key,
    required this.members,
    required this.cycles,
    required this.totalSlots,
    required this.meUserId,
  });

  @override
  ConsumerState<SusuWheel> createState() => _SusuWheelState();
}

class _SusuWheelState extends ConsumerState<SusuWheel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;

  SusuCycleView? get _upcoming {
    for (final c in widget.cycles) {
      if (c.status == SusuCycleStatus.pending ||
          c.status == SusuCycleStatus.collecting ||
          c.status == SusuCycleStatus.collectingGrace) {
        return c;
      }
    }
    return null;
  }

  SusuCycleView? get _previous {
    SusuCycleView? prev;
    for (final c in widget.cycles) {
      if (c.status == SusuCycleStatus.paidOut ||
          c.status == SusuCycleStatus.defaulted) {
        prev = c;
      }
    }
    return prev;
  }

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  /// The ticker decision reads `MediaQuery` (via `liquidReducedMotion`), and an
  /// inherited widget may not be read from `initState`. It is also the right hook
  /// regardless: it re-runs when the user flips the OS reduced-motion switch, so
  /// the wheel starts and stops its idle animation without a rebuild from outside.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(SusuWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  /// Runs the 1s idle pulse only when there is something to count toward and the
  /// user has not asked for reduced motion. A never-settling ticker is exactly
  /// what would make `pumpAndSettle` hang, so both conditions are hard gates.
  void _syncTicker() {
    final shouldRun = !liquidReducedMotion(context) && _upcoming != null;
    if (shouldRun) {
      if (!_clock.isAnimating) _clock.repeat();
    } else {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  SusuCycleView? _cycleForSlot(int slot) {
    for (final c in widget.cycles) {
      if (c.cycleNumber == slot) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final now = DateTime.now();
    final meId = widget.meUserId?.toString();

    final membersBySlot = <int, SusuMemberView>{};
    for (final m in widget.members) {
      final slot = m.cycleSlot;
      if (slot != null && slot >= 1) membersBySlot[slot] = m;
    }

    double arcPrevAngle = 0;
    double arcNextAngle = 0;
    double sweep = 0;
    final prev = _previous;
    final next = _upcoming;
    if (prev != null &&
        next != null &&
        prev.id != next.id &&
        prev.scheduledRunAt.isBefore(next.scheduledRunAt)) {
      arcPrevAngle = susuSlotAngle(prev.cycleNumber, widget.totalSlots);
      arcNextAngle = susuSlotAngle(next.cycleNumber, widget.totalSlots);
      sweep = susuArcSweep(prev.scheduledRunAt, next.scheduledRunAt, now);
    }

    final allTerminal = widget.cycles.isNotEmpty &&
        widget.cycles.every((c) =>
            c.status == SusuCycleStatus.paidOut ||
            c.status == SusuCycleStatus.defaulted);

    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) =>
          LayoutBuilder(builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, _kWheelMaxDiameter);
        final center = Offset(size / 2, size / 2);
        final radius = size / 2 - _kDotSize / 2 - _kDotPad - 2;

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                key: const ValueKey('susu-wheel-canvas'),
                size: Size.square(size),
                painter: _WheelArcPainter(
                  colors: colors,
                  center: center,
                  radius: radius,
                  previousAngle: arcPrevAngle,
                  nextAngle: arcNextAngle,
                  sweep: sweep,
                ),
              ),
              ..._slotDots(center, radius, membersBySlot, meId, colors),
              _twelveOClockIndicator(colors),
              _centerLabel(next, allTerminal, now, meId, colors),
            ],
          ),
        );
      }),
    );
  }

  List<Widget> _slotDots(
    Offset center,
    double radius,
    Map<int, SusuMemberView> membersBySlot,
    String? meId,
    AzamanColors colors,
  ) {
    final upcoming = _upcoming;
    final dots = <Widget>[];

    for (var slot = 1; slot <= widget.totalSlots; slot++) {
      final angle = susuSlotAngle(slot, widget.totalSlots);
      final pos = center +
          Offset(radius * math.cos(angle), radius * math.sin(angle));
      final member = membersBySlot[slot];
      final cycle = _cycleForSlot(slot);
      final isNext = upcoming != null && upcoming.cycleNumber == slot;
      final isMe = member != null && member.userId.toString() == meId;

      dots.add(Positioned(
        left: pos.dx - _kDotSize / 2,
        top: pos.dy - _kDotSize / 2,
        child: _ReadOnlySlotDot(
          key: isNext ? const ValueKey('susu-wheel-next-dot') : null,
          slot: slot,
          member: member,
          isNext: isNext,
          isDone: cycle != null &&
              (cycle.status == SusuCycleStatus.paidOut ||
                  cycle.status == SusuCycleStatus.defaulted),
          defaulted: cycle?.status == SusuCycleStatus.defaulted,
          isMe: isMe,
          colors: colors,
        ),
      ));
    }
    return dots;
  }

  Widget _centerLabel(
    SusuCycleView? upcoming,
    bool allTerminal,
    DateTime now,
    String? meId,
    AzamanColors colors,
  ) {
    final String title;
    final String? subtitle;

    if (upcoming != null) {
      title = susuCountdownLabel(upcoming.scheduledRunAt, now);
      subtitle = upcoming.payoutUserId.toString() == meId
          ? 'your payout!'
          : 'to payout · slot ${upcoming.cycleNumber}';
    } else if (allTerminal) {
      title = 'Done';
      subtitle = null;
    } else {
      title = '';
      subtitle = null;
    }

    return Center(
      child: Column(
        key: const ValueKey('susu-wheel-center-label'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900)),
          if (subtitle != null)
            Text(subtitle,
                style: TextStyle(color: colors.textTertiary, fontSize: 10)),
        ],
      ),
    );
  }
}

class _ReadOnlySlotDot extends StatelessWidget {
  final int slot;
  final SusuMemberView? member;
  final bool isNext;
  final bool isDone;
  final bool defaulted;
  final bool isMe;
  final AzamanColors colors;

  const _ReadOnlySlotDot({
    super.key,
    required this.slot,
    required this.member,
    required this.isNext,
    required this.isDone,
    required this.defaulted,
    required this.isMe,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final Color fill;
    if (defaulted) {
      fill = colors.danger.withValues(alpha: 0.20);
    } else if (isDone) {
      fill = colors.success.withValues(alpha: 0.20);
    } else if (member != null) {
      fill = colors.softSurface;
    } else {
      fill = colors.textTertiary.withValues(alpha: 0.08);
    }

    final dot = Container(
      width: _kDotSize,
      height: _kDotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(
          color: isNext ? colors.accent : colors.border,
          width: isNext ? 2.5 : 1,
        ),
        boxShadow: isNext
            ? [
                BoxShadow(
                    color: colors.accent.withValues(alpha: 0.35),
                    blurRadius: 10)
              ]
            : null,
      ),
      child: Center(
        child: member == null
            ? Text('$slot',
                style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700))
            : _MemberAvatar(
                displayName: member!.displayName,
                avatarUrl: member!.avatar,
                seedId: member!.userId.toString(),
                colors: colors,
                size: _kDotSize - 8,
              ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        if (isMe)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('YOU',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900)),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('$slot',
                style: TextStyle(
                    color: isNext ? colors.accent : colors.textTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  final String displayName;
  final String? avatarUrl;
  final String seedId;
  final AzamanColors colors;
  final double size;

  const _MemberAvatar({
    required this.displayName,
    required this.avatarUrl,
    required this.seedId,
    required this.colors,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final fallback =
        HSLColor.fromAHSL(1, susuAvatarHue(seedId), 0.45, 0.52).toColor();
    final fallbackChild = Center(
      child: Text(
        displayName.isEmpty ? '?' : displayName[0].toUpperCase(),
        style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w800),
      ),
    );

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: avatarUrl == null || avatarUrl!.isEmpty
            ? ColoredBox(color: fallback, child: fallbackChild)
            : AzamanNetworkImage(
                imageUrl: avatarUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    ColoredBox(color: fallback, child: fallbackChild),
              ),
      ),
    );
  }
}

class _WheelArcPainter extends CustomPainter {
  final AzamanColors colors;
  final Offset center;
  final double radius;
  final double previousAngle;
  final double nextAngle;
  final double sweep;

  const _WheelArcPainter({
    required this.colors,
    required this.center,
    required this.radius,
    required this.previousAngle,
    required this.nextAngle,
    required this.sweep,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = colors.divider;
    canvas.drawCircle(center, radius, track);

    if (sweep <= 0) return;

    final span = _positiveSpan(previousAngle, nextAngle);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = colors.accent.withValues(alpha: 0.85);

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
        rect, previousAngle, span * sweep.clamp(0.0, 1.0).toDouble(), false, arc);

    // Glow tip at the arc's leading edge (where the sweep currently is).
    if (sweep > 0.02) {
      final tipAngle = previousAngle + span * sweep.clamp(0.0, 1.0).toDouble();
      final tip = center +
          Offset(radius * math.cos(tipAngle), radius * math.sin(tipAngle));
      canvas.drawCircle(
          tip,
          5,
          Paint()
            ..style = PaintingStyle.fill
            ..color = colors.accent.withValues(alpha: 0.30));
    }
  }

  double _positiveSpan(double from, double to) {
    var span = (to - from) % (2 * math.pi);
    if (span < 0) span += 2 * math.pi;
    return span;
  }

  @override
  bool shouldRepaint(_WheelArcPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.center != center ||
      oldDelegate.radius != radius ||
      oldDelegate.previousAngle != previousAngle ||
      oldDelegate.nextAngle != nextAngle ||
      oldDelegate.sweep != sweep;
}

// ── SusuPositionWheel — draggable picker ──────────────────────────────────────

class SusuPositionWheel extends ConsumerStatefulWidget {
  final int totalPositions;
  final int? selectedPosition;
  final List<Map<String, dynamic>> members; // [{position, username, avatarUrl, paid}]
  final ValueChanged<int> onPositionSelected;

  const SusuPositionWheel({
    super.key,
    required this.totalPositions,
    this.selectedPosition,
    required this.members,
    required this.onPositionSelected,
  });

  @override
  ConsumerState<SusuPositionWheel> createState() => _SusuPositionWheelState();
}

class _SusuPositionWheelState extends ConsumerState<SusuPositionWheel>
    with SingleTickerProviderStateMixin {
  // The controller's value IS the wheel rotation (radians, clockwise).
  late final AnimationController _rot;
  double _dragStartRotation = 0.0;
  Offset? _dragStartPoint;
  double _wheelRadius = 100.0;

  // TASK-017 selection-commit contract: the last slot committed by ONE user
  // selection flow. A duplicate gesture resolving to the SAME already-
  // committed slot (re-tap, or the hub naming the slot just committed) is a
  // no-op: no callback, no haptic, no spring re-run. The guard is per-slot,
  // not a one-shot latch — committing a DIFFERENT free slot afterwards is a
  // new selection and fires once. Resynced when the externally supplied
  // selectedPosition changes so the contract never contradicts the host.
  int? _lastCommittedSlot;

  Set<int> get _taken => widget.members
      .map((m) => m['position'] as int?)
      .whereType<int>()
      .toSet();

  @override
  void initState() {
    super.initState();
    _rot = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      lowerBound: -1000.0,
      upperBound: 1000.0,
      value: 0.0,
    );
  }

  @override
  void didUpdateWidget(SusuPositionWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Resync the exactly-once guard when the host supplies a new external
    // selection: that change is authoritative, not a duplicate gesture.
    if (widget.selectedPosition != oldWidget.selectedPosition) {
      _lastCommittedSlot = widget.selectedPosition;
    }
  }

  @override
  void dispose() {
    _rot.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails d) {
    _rot.stop();
    _dragStartRotation = _rot.value;
    _dragStartPoint = d.localPosition;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final start = _dragStartPoint;
    if (start == null || _wheelRadius <= 0) return;
    final delta = d.localPosition - start;
    _rot.value =
        (_dragStartRotation + delta.dx / _wheelRadius).clamp(-1000.0, 1000.0);
  }

  void _onDragEnd(DragEndDetails d) {
    _dragStartPoint = null;
    _snapToNearest();
  }

  void _snapToNearest() {
    final nearest =
        susuNearestFreeSlot(_rot.value, widget.totalPositions, _taken);
    if (nearest == null) return;
    final target =
        susuSnapRotation(_rot.value, nearest.slot, widget.totalPositions);
    if (liquidReducedMotion(context)) {
      _rot.value = target;
      return;
    }
    _rot.stop();
    _rot.animateTo(target, curve: kHouseSpring).then((_) {
      if (mounted) AzamanHaptics.selection();
    });
  }

  void _selectSlot(int slot) {
    if (_taken.contains(slot)) return;
    if (_lastCommittedSlot == slot) return; // exactly-once: already committed
    _lastCommittedSlot = slot;
    AzamanHaptics.confirm();
    widget.onPositionSelected(slot);
    final target = susuSnapRotation(_rot.value, slot, widget.totalPositions);
    if (liquidReducedMotion(context)) {
      _rot.value = target;
      return;
    }
    _rot.stop();
    _rot.animateTo(target, curve: kHouseSpring);
  }

  void _confirmHub(int? hubSlot) {
    if (hubSlot == null) return;
    _selectSlot(hubSlot);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final taken = _taken;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, _kWheelMaxDiameter);
        _wheelRadius = size / 2 - _kDotSize / 2 - _kDotPad - 2;
        final center = Offset(size / 2, size / 2);

        return SizedBox(
          key: const ValueKey('susu-position-wheel'),
          width: size,
          height: size,
          child: AnimatedBuilder(
            animation: _rot,
            builder: (context, _) {
              final nearest = susuNearestFreeSlot(
                  _rot.value, widget.totalPositions, taken);
              final step = widget.totalPositions > 0
                  ? 2 * math.pi / widget.totalPositions
                  : double.infinity;
              final hubSlot = (nearest != null && nearest.delta <= step / 2 + 0.01)
                  ? nearest.slot
                  : null;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size.square(size),
                      painter: _WheelArcPainter(
                        colors: colors,
                        center: center,
                        radius: _wheelRadius,
                        previousAngle: 0,
                        nextAngle: 0,
                        sweep: 0,
                      ),
                    ),
                    Transform.rotate(
                      angle: _rot.value,
                      child:
                          Stack(children: _slotDots(center, _wheelRadius, taken, colors)),
                    ),
                    _twelveOClockIndicator(colors),
                    _hub(hubSlot, colors),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  List<Widget> _slotDots(
    Offset center,
    double radius,
    Set<int> taken,
    AzamanColors colors,
  ) {
    return List<Widget>.generate(widget.totalPositions, (i) {
      final slot = i + 1;
      final angle = susuSlotAngle(slot, widget.totalPositions);
      final pos =
          center + Offset(radius * math.cos(angle), radius * math.sin(angle));
      final member = widget.members
          .cast<Map<String, dynamic>?>()
          .firstWhere((m) => (m?['position'] as int?) == slot,
              orElse: () => null);
      final isTaken = taken.contains(slot);
      final isSelected = widget.selectedPosition == slot;

      return Positioned(
        left: pos.dx - _kDotSize / 2,
        top: pos.dy - _kDotSize / 2,
        child: GestureDetector(
          key: ValueKey('susu-position-slot-$slot'),
          onTap: isTaken ? null : () => _selectSlot(slot),
          child: _PickerSlotDot(
            slot: slot,
            isTaken: isTaken,
            isSelected: isSelected,
            member: member,
            colors: colors,
          ),
        ),
      );
    });
  }

  Widget _hub(int? hubSlot, AzamanColors colors) {
    final enabled = hubSlot != null;
    return Center(
      child: GestureDetector(
        key: const ValueKey('susu-position-hub'),
        onTap: enabled ? () => _confirmHub(hubSlot) : null,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surface,
            border: Border.all(
              color: enabled ? colors.accent : colors.border,
              width: 2,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  enabled ? Icons.check_circle : Icons.touch_app,
                  color: enabled ? colors.accent : colors.textTertiary,
                  size: 22,
                ),
                const SizedBox(height: 2),
                Text(
                  enabled ? 'Pick slot $hubSlot' : 'Spin',
                  style: TextStyle(
                    color: enabled ? colors.accent : colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerSlotDot extends StatelessWidget {
  final int slot;
  final bool isTaken;
  final bool isSelected;
  final Map<String, dynamic>? member;
  final AzamanColors colors;

  const _PickerSlotDot({
    required this.slot,
    required this.isTaken,
    required this.isSelected,
    required this.member,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final Color dotColor;
    if (isSelected) {
      dotColor = colors.accent;
    } else if (isTaken) {
      dotColor = colors.success;
    } else {
      dotColor = colors.textTertiary.withValues(alpha: 0.4);
    }

    return Container(
      width: _kDotSize,
      height: _kDotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dotColor,
        border: Border.all(
          color: isSelected ? colors.accent : colors.border,
          width: isSelected ? 3 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                    color: colors.accent.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 2)
              ]
            : null,
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              '$slot',
              style: TextStyle(
                color:
                    isTaken || isSelected ? Colors.white : colors.textTertiary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (isTaken && member != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surface,
                  border: Border.all(color: colors.border, width: 1.5),
                ),
                child: member!['avatarUrl'] != null
                    ? ClipOval(
                        child: AzamanNetworkImage(
                            imageUrl: member!['avatarUrl'],
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink()))
                    : _initials(member!, colors),
              ),
            ),
          if (slot == 1)
            const Positioned(
              top: -8,
              left: 0,
              right: 0,
              child: Icon(Icons.workspace_premium,
                  size: 16, color: Color(0xFFFFD700)),
            ),
        ],
      ),
    );
  }

  Widget _initials(Map<String, dynamic> member, AzamanColors colors) {
    final name = member['username']?.toString() ?? '?';
    return Center(
      child: Text(name[0].toUpperCase(),
          style: TextStyle(
              color: colors.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.w600)),
    );
  }
}
