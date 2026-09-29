// =============================================================================
// AZAMAN — TRANSIT ROUTE RIBBON (TASK-014)
//
// The trip list reimagined as §7.3's "route ribbon": all trips sit as nodes
// on one curved path instead of a stack of near-identical cards. Tapping a
// node lifts it and expands a detail card inline with a spring; a sold-out
// trip is a dead, desaturated node.
//
// Motion discipline (per the Tier-0 brief): the dash flow along the path
// runs ONCE on entrance and settles — nothing here loops forever.
//
// Lifecycle (corrigendum 2.1): the reduced-motion lookup reads MediaQuery,
// so the entrance controller is created from didChangeDependencies(), never
// initState. Later dependency changes update the duration without
// replaying the entrance sweep.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// Node anchor points along the ribbon path, left→right, for [count] trips.
///
/// Pure and deterministic: the path is a single sine bow — `y = baseline +
/// amplitude * sin(π * t + phase)` with t in 0..1. The painter and the node
/// layout both consume this function, so they agree by construction. The
/// ends sit on the baseline, so the path starts and ends level.
List<Offset> transitRibbonNodePoints(Size size, int count) {
  if (count <= 0) return const [];
  if (count == 1) return [Offset(size.width / 2, size.height / 2)];

  final points = <Offset>[];
  for (int i = 0; i < count; i++) {
    final t = i / (count - 1);
    final x = 34 + t * (size.width - 68);
    final bow = math.sin(math.pi * t);
    final y = size.height / 2 - bow * (size.height * 0.30);
    points.add(Offset(x, y));
  }
  return points;
}

class TransitRouteRibbon extends StatefulWidget {
  final List<TransitTrip> trips;
  final AzamanColors colors;
  final void Function(TransitTrip trip) onTripTap;

  const TransitRouteRibbon({
    super.key,
    required this.trips,
    required this.colors,
    required this.onTripTap,
  });

  @override
  State<TransitRouteRibbon> createState() => _TransitRouteRibbonState();
}

class _TransitRouteRibbonState extends State<TransitRouteRibbon>
    with SingleTickerProviderStateMixin {
  // Nullable until didChangeDependencies resolves the accessibility-aware
  // duration (corrigendum 2.1 — never read MediaQuery from initState).
  AnimationController? _flowController;
  String? _expandedTripId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = MotionTokens.accessibleDuration(
      context,
      MotionTokens.ambient,
    );
    final existing = _flowController;
    if (existing == null) {
      // First (and only) initialisation: one-shot entrance sweep.
      final controller = AnimationController(duration: duration, vsync: this)
        ..forward();
      _flowController = controller;
    } else if (existing.duration != duration) {
      // Dependency changed: update the duration, do NOT replay the sweep.
      existing.duration = duration;
    }
  }

  @override
  void dispose() {
    _flowController?.dispose();
    super.dispose();
  }

  void _onNodeTap(TransitTrip trip) {
    if (trip.availableSeats == 0) return; // dead node
    AzamanHaptics.selection();
    setState(() {
      _expandedTripId = _expandedTripId == trip.id ? null : trip.id;
    });
  }

  TransitTrip? get _expandedTrip {
    for (final trip in widget.trips) {
      if (trip.id == _expandedTripId) return trip;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    const ribbonHeight = 216.0;

    final expanded = _expandedTrip;
    final flowController = _flowController;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'CHOOSE A DEPARTURE',
          style: AzText.eyebrow.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AzSpace.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final nodes = transitRibbonNodePoints(
              Size(constraints.maxWidth, ribbonHeight),
              widget.trips.length,
            );
            return SizedBox(
              height: ribbonHeight,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RibbonPathPainter(
                        nodes: nodes,
                        color: colors.accent,
                        dashFlow: flowController == null
                            ? 1.0
                            : CurvedAnimation(
                                parent: flowController,
                                curve: Curves.easeOut,
                              ).value,
                      ),
                    ),
                  ),
                  for (int i = 0; i < widget.trips.length; i++)
                    Positioned(
                      left: nodes[i].dx - 32,
                      top: nodes[i].dy - 24,
                      width: 64,
                      height: 76,
                      child: _RibbonNode(
                        trip: widget.trips[i],
                        colors: colors,
                        expanded: widget.trips[i].id == _expandedTripId,
                        onTap: () => _onNodeTap(widget.trips[i]),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        AnimatedSize(
          duration: MotionTokens.standard,
          curve: MotionTokens.spring,
          alignment: Alignment.topCenter,
          child: expanded == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: AzSpace.sm),
                  child: _ExpandedTripCard(
                    trip: expanded,
                    colors: colors,
                    onSelect: () => widget.onTripTap(expanded),
                  ),
                ),
        ),
      ],
    );
  }
}

class _RibbonPathPainter extends CustomPainter {
  final List<Offset> nodes;
  final Color color;
  final double dashFlow; // 0..1 entrance sweep

  const _RibbonPathPainter({
    required this.nodes,
    required this.color,
    required this.dashFlow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.length < 2) return;

    // Smooth quadratic curve through the nodes: control point = previous
    // node, end point = midpoint of previous and current.
    final path = Path()..moveTo(nodes.first.dx, nodes.first.dy);
    for (int i = 1; i < nodes.length; i++) {
      final prev = nodes[i - 1];
      final curr = nodes[i];
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    path.lineTo(nodes.last.dx, nodes.last.dy);

    // Base track
    final track = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, track);

    // Flowing dashes — the "headlight" sweep, once on entrance
    final dashPaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dashLength = 6.0;
    const gapLength = 10.0;
    for (final metric in path.computeMetrics()) {
      final phase = -dashFlow * (dashLength + gapLength);
      var d = phase;
      while (d < metric.length) {
        final start = math.max(d, 0.0);
        final end = math.min(d + dashLength, metric.length);
        if (end > start) {
          canvas.drawPath(metric.extractPath(start, end), dashPaint);
        }
        d += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_RibbonPathPainter oldDelegate) {
    return oldDelegate.dashFlow != dashFlow ||
        oldDelegate.nodes != nodes ||
        oldDelegate.color != color;
  }
}

class _RibbonNode extends StatelessWidget {
  final TransitTrip trip;
  final AzamanColors colors;
  final bool expanded;
  final VoidCallback onTap;

  const _RibbonNode({
    required this.trip,
    required this.colors,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final soldOut = trip.availableSeats == 0;
    final statusColor = soldOut
        ? colors.danger
        : trip.availableSeats > 10
        ? colors.success
        : colors.warning;
    final icon = (trip.vehicleType ?? '').toLowerCase() == 'bus'
        ? Icons.directions_bus_rounded
        : Icons.directions_car_rounded;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: expanded ? 1.16 : 1.0,
        duration: MotionTokens.control,
        curve: MotionTokens.spring,
        child: Opacity(
          opacity: soldOut ? 0.45 : 1.0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: expanded ? colors.accent : colors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: statusColor, width: 2),
                  boxShadow: expanded
                      ? [
                          BoxShadow(
                            color: colors.accent.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  soldOut ? Icons.block_rounded : icon,
                  size: 16,
                  color: expanded ? colors.background : statusColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '\$${trip.fareUsdc.toStringAsFixed(0)}',
                style: AzText.label.copyWith(
                  color: soldOut ? colors.textTertiary : colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (soldOut)
                Text(
                  'FULL',
                  style: AzText.caption.copyWith(color: colors.danger),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandedTripCard extends StatelessWidget {
  final TransitTrip trip;
  final AzamanColors colors;
  final VoidCallback onSelect;

  const _ExpandedTripCard({
    required this.trip,
    required this.colors,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final dep = TimeOfDay.fromDateTime(trip.departureAt);
    final depStr =
        '${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')}';

    var arrStr = '--:--';
    var durationStr = '--';
    if (trip.arrivalAt != null) {
      final arr = TimeOfDay.fromDateTime(trip.arrivalAt!);
      arrStr =
          '${arr.hour.toString().padLeft(2, '0')}:${arr.minute.toString().padLeft(2, '0')}';
      final diff = trip.arrivalAt!.difference(trip.departureAt);
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      durationStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';
    }

    final seatStatus = trip.availableSeats > 10
        ? colors.success
        : trip.availableSeats > 0
        ? colors.warning
        : colors.danger;

    return Container(
      padding: AzSpace.cardInset,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: AzRadius.brLg,
        border: Border.all(color: colors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  trip.origin,
                  style: AzText.label.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AzSpace.sm),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: colors.accent,
                ),
              ),
              Expanded(
                child: Text(
                  trip.destination,
                  textAlign: TextAlign.right,
                  style: AzText.label.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AzSpace.md),
          Row(
            children: [
              _statCell('DEPART', depStr),
              _statCell('DURATION', durationStr, center: true),
              _statCell('ARRIVE', arrStr, end: true),
            ],
          ),
          const SizedBox(height: AzSpace.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AzSpace.md,
              vertical: AzSpace.sm,
            ),
            decoration: BoxDecoration(
              color: colors.softSurface,
              borderRadius: AzRadius.brMd,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${trip.vehicleLabel} · ${_formatDate(trip.departureAt)}',
                    style: AzText.bodyS.copyWith(color: colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.event_seat_rounded, size: 14, color: seatStatus),
                    const SizedBox(width: 4),
                    Text(
                      '${trip.availableSeats} seats left',
                      style: AzText.label.copyWith(
                        color: seatStatus,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AzSpace.md),
          Row(
            children: [
              Text(
                '\$${trip.fareUsdc.toStringAsFixed(2)}',
                style: AzText.money(colors.accent, size: 20),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  AzamanHaptics.navigation();
                  onSelect();
                },
                icon: const Icon(Icons.event_seat_outlined, size: 18),
                label: const Text('Select seats'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCell(
    String label,
    String value, {
    bool center = false,
    bool end = false,
  }) {
    final alignment = center
        ? CrossAxisAlignment.center
        : end
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    return Expanded(
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Text(
            label,
            style: AzText.caption.copyWith(
              color: colors.textTertiary,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: AzSpace.xs),
          Text(
            value,
            style: AzText.titleL.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}
