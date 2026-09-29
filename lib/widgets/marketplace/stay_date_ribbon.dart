// =============================================================================
// STAY DATE RIBBON — the hotel date scrubber (TASK-015)
//
// Check-in/check-out is the single most important decision in a hotel booking,
// so it gets the premium affordance: a horizontal ribbon of day cells that the
// finger scrubs. Drag right to extend the stay; the highlighted span, the
// price-per-night bars and the caller's live total all follow the finger.
// A modal picker is the fallback for precision — never the primary path.
//
// INTERACTION MODEL (one gesture, no ambiguity)
//   • The inner ListView is NeverScrollable — every horizontal drag over the
//     ribbon is a scrub gesture owned by the outer GestureDetector.
//   • Drag start sets check-in at the cell under the finger (1-night stay).
//   • Dragging right extends check-out one night per cell crossed; each added
//     night fires [onNightAdded] (the screen maps it to a threshold haptic).
//   • Dragging left of the start shrinks back to a 1-night stay.
//   • When the finger nears the right edge the window auto-advances one cell
//     (controller.jumpTo — instant, timer-free, test-safe).
//   • Tapping a cell sets a 1-night stay (or resets a completed stay) so the
//     ribbon is operable without dragging (accessibility path).
//   • The widget is CONTROLLED: the screen owns checkIn/checkOut; an external
//     change (e.g. the modal picker fallback) scrolls the ribbon to reveal it.
//
// PITCH INVARIANT (corrigendum §3A): a rendered cell is `_cellWidth` wide plus
// an `AzSpace.xs` right margin, so the sequence advances by `_cellPitch`
// (56 + 4 = 60dp at the current token value). Hit-testing (`_cellAt`), reveal
// positioning (`_reveal`) and the auto-advance scroll math all use the SAME
// `_cellPitch` — there is no separate 56dp geometry constant for the cell
// sequence. A permanent regression pins this alignment in
// stay_booking_test.dart.
//
// Bars: height encodes the per-night rate (weekend rate renders taller when
// the room has one). The caller's total uses its own rate math — the bars are
// informational, matching the shipped "date-specific rate calendar" caveat.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// Nights for a span expressed as day indices into the ribbon.
/// Always at least 1 while [endIndex] is ahead of [startIndex].
int ribbonNights(int startIndex, int endIndex) {
  final diff = endIndex - startIndex;
  return diff < 1 ? 1 : diff;
}

/// The date-only day at [index] cells after [firstDay].
DateTime ribbonDateAt(DateTime firstDay, int index) {
  final base = DateTime(firstDay.year, firstDay.month, firstDay.day);
  return base.add(Duration(days: index));
}

/// Nightly total for a stay.
double stayTotalFor(double nightlyRate, int nights) => nightlyRate * nights;

class StayDateRibbon extends StatefulWidget {
  final DateTime firstDay;
  final int dayCount;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final double? nightlyRate;
  final double? weekendRate;
  final ValueChanged<DateTimeRange> onRangeChanged;
  final VoidCallback? onNightAdded;
  final AzamanColors colors;

  const StayDateRibbon({
    super.key,
    required this.firstDay,
    required this.onRangeChanged,
    required this.colors,
    this.dayCount = 365,
    this.checkIn,
    this.checkOut,
    this.nightlyRate,
    this.weekendRate,
    this.onNightAdded,
  });

  @override
  State<StayDateRibbon> createState() => _StayDateRibbonState();
}

class _StayDateRibbonState extends State<StayDateRibbon> {
  /// Visible width of one date cell.
  static const double _cellWidth = 56.0;

  /// The authoritative rendered pitch of the date-cell sequence: one cell
  /// width plus the tokenized inter-cell gap. Every geometry that maps a
  /// horizontal position to a cell index — hit-testing, reveal/scroll
  /// positioning, and the auto-advance step — uses this single constant so
  /// interaction math can never drift from the rendered cells.
  static const double _cellPitch = _cellWidth + AzSpace.xs;

  static const List<String> _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  late final ScrollController _scroll;
  int? _dragStart;
  int? _dragEnd;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(StayDateRibbon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragging) return;
    if (widget.checkIn != oldWidget.checkIn && widget.checkIn != null) {
      _reveal(_indexForDay(widget.checkIn!));
    }
  }

  int _indexForDay(DateTime day) {
    final base = ribbonDateAt(widget.firstDay, 0);
    final days = day.difference(base).inDays;
    return days < 0 ? 0 : days;
  }

  int? get _startIndex =>
      widget.checkIn == null ? null : _indexForDay(widget.checkIn!);

  int? get _endIndex =>
      widget.checkOut == null ? null : _indexForDay(widget.checkOut!);

  int _cellAt(double localDx) {
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    return ((offset + localDx) / _cellPitch)
        .floor()
        .clamp(0, widget.dayCount - 1)
        .toInt();
  }

  void _onDragStart(DragStartDetails details) {
    final start = _cellAt(details.localPosition.dx);
    _dragging = true;
    _dragStart = start;
    _dragEnd = start + 1;
    _emit();
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    final start = _dragStart;
    if (start == null) return;
    final cell = _cellAt(details.localPosition.dx);
    final newEnd = cell > start ? cell + 1 : start + 1;
    final oldEnd = _dragEnd ?? start + 1;
    _dragEnd = newEnd;
    if (newEnd > oldEnd) widget.onNightAdded?.call();
    _emit();
    // Auto-advance the window when the finger nears the right edge.
    if (_scroll.hasClients && details.localPosition.dx > width - 48) {
      final target = (_scroll.offset + _cellPitch)
          .clamp(0.0, _scroll.position.maxScrollExtent)
          .toDouble();
      if (target > _scroll.offset) _scroll.jumpTo(target);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    _dragStart = null;
    _dragEnd = null;
  }

  void _onTapUp(TapUpDetails details) {
    final cell = _cellAt(details.localPosition.dx);
    AzamanHaptics.selection();
    if (widget.checkIn == null || widget.checkOut != null) {
      widget.onRangeChanged(DateTimeRange(
        start: ribbonDateAt(widget.firstDay, cell),
        end: ribbonDateAt(widget.firstDay, cell + 1),
      ));
      return;
    }
    final startIdx = _indexForDay(widget.checkIn!);
    if (cell > startIdx) {
      widget.onRangeChanged(DateTimeRange(
        start: widget.checkIn!,
        end: ribbonDateAt(widget.firstDay, cell + 1),
      ));
    } else if (cell < startIdx) {
      widget.onRangeChanged(DateTimeRange(
        start: ribbonDateAt(widget.firstDay, cell),
        end: ribbonDateAt(widget.firstDay, cell + 1),
      ));
    } else {
      widget.onRangeChanged(DateTimeRange(
        start: widget.checkIn!,
        end: ribbonDateAt(widget.firstDay, startIdx + 1),
      ));
    }
  }

  void _emit() {
    final start = _dragStart;
    if (start == null) return;
    final end = _dragEnd ?? start + 1;
    widget.onRangeChanged(DateTimeRange(
      start: ribbonDateAt(widget.firstDay, start),
      end: ribbonDateAt(widget.firstDay, end < start ? start + 1 : end),
    ));
  }

  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final target =
        (index * _cellPitch - _cellPitch * 2).clamp(0.0, max).toDouble();
    _scroll.jumpTo(target);
  }

  String _formatDay(DateTime day) => '${_months[day.month - 1]} ${day.day}';

  Widget _cell(int index) {
    final day = ribbonDateAt(widget.firstDay, index);
    final startIdx = _startIndex;
    final endIdx = _endIndex;
    final inSpan = startIdx != null &&
        endIdx != null &&
        index >= startIdx &&
        index < endIdx;
    final isCheckIn = index == startIdx;
    final weekend = day.weekday == DateTime.friday ||
        day.weekday == DateTime.saturday;
    final rate =
        weekend ? (widget.weekendRate ?? widget.nightlyRate) : widget.nightlyRate;
    final maxRate = widget.nightlyRate != null && widget.weekendRate != null
        ? (widget.nightlyRate! > widget.weekendRate!
            ? widget.nightlyRate!
            : widget.weekendRate!)
        : (widget.nightlyRate ?? 0);
    final barHeight =
        rate == null || maxRate <= 0 ? 4.0 : 6.0 + 22.0 * (rate / maxRate);
    final radius = BorderRadius.horizontal(
      left: Radius.circular(isCheckIn ? AzRadius.md : 0),
      right: Radius.circular(index == (endIdx ?? 0) - 1 ? AzRadius.md : 0),
    );
    return Container(
      width: _cellWidth,
      margin: const EdgeInsets.only(right: AzSpace.xs),
      padding: const EdgeInsets.symmetric(vertical: AzSpace.sm),
      decoration: BoxDecoration(
        color: inSpan
            ? widget.colors.accent.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: radius,
      ),
      child: Column(
        children: [
          Text(
            day.day == 1 ? _months[day.month - 1] : _weekdays[day.weekday - 1],
            style: AzText.caption.copyWith(
              color: inSpan
                  ? widget.colors.accent
                  : widget.colors.textTertiary,
            ),
          ),
          const SizedBox(height: AzSpace.xs),
          Text(
            '${day.day}',
            style: AzText.bodyS.copyWith(
              color: inSpan
                  ? widget.colors.textPrimary
                  : widget.colors.textSecondary,
              fontWeight: inSpan ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          const Spacer(),
          const SizedBox(height: AzSpace.xs),
          Container(
            width: 14,
            height: barHeight,
            decoration: BoxDecoration(
              color: inSpan ? widget.colors.accent : widget.colors.divider,
              borderRadius: AzRadius.brXs,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final startIdx = _startIndex;
    final endIdx = _endIndex;
    final nights =
        startIdx == null || endIdx == null ? 0 : ribbonNights(startIdx, endIdx);
    final summary = startIdx == null || endIdx == null
        ? 'Drag to choose your dates'
        : '${_formatDay(widget.checkIn!)} → ${_formatDay(widget.checkOut!)} · '
            '$nights night${nights == 1 ? '' : 's'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          label: 'Stay: $summary',
          child: Text(
            summary,
            style: AzText.bodyS.copyWith(
              color: startIdx == null
                  ? widget.colors.textTertiary
                  : widget.colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: AzSpace.sm),
        SizedBox(
          height: 96,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapUp,
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: (details) =>
                    _onDragUpdate(details, width),
                onHorizontalDragEnd: _onDragEnd,
                child: ListView.builder(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.dayCount,
                  itemBuilder: (context, index) => _cell(index),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
