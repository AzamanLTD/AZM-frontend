// =============================================================================
// AZAMAN — CURRENCY WHEEL TOGGLE (GHS-first, 2026-10-20)
//
// THE shared inline currency wheel/roller. Placed immediately before a
// numeric amount, it identifies (and — on amount-entry surfaces — chooses)
// the denomination that amount is expressed in. Every surface uses THIS
// component; no screen builds its own currency switch.
//
// • Genuine roller, not a relabelled dropdown: the selected chip sits in
//   a horizontally draggable strip; the neighbouring supported currency
//   peeks through on both sides so the affordance is obvious.
// • Swipe horizontally to roll; tap to open a real picker menu (a gesture
//   is never the only way); screen readers get onIncrease/onDecrease
//   actions plus a live announcement of the selected currency.
// • ~180ms roll (MotionTokens.control), zero-duration under reduced
//   motion, NO idle animation ever.
// • Options are passed IN by the caller from [CurrencyCatalog] — the
//   wheel renders exactly the currencies that surface's contract
//   supports, never a speculative list.
// • Touch target ≥ 44dp. Contrast follows the theme palette.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;

import 'package:azaman/models/currency_catalog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// Which direction the roller strips along. Horizontal is the default and
/// stays the presentation for existing callers (display surfaces, Card
/// Transfer); Send opts into the vertical roller so the selected chip is
/// never cropped by the surrounding page row.
enum CurrencyWheelAxis { horizontal, vertical }

/// A swipeable inline currency wheel. [options] is the surface's real
/// supported set; [selected] is the current index; [onChanged] fires with
/// the new index whenever the user rolls, taps-picks or semantically
/// changes it. The callback is the caller's contract: a Send composer
/// converts its amount; a display surface updates the global preference.
class CurrencyWheelToggle extends ConsumerStatefulWidget {
  const CurrencyWheelToggle({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
    this.axis = CurrencyWheelAxis.horizontal,
    this.enabled = true,
    this.semanticLabelPrefix = 'Input currency',
  }) : assert(options.length >= 1);

  final List<AzCurrency> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// The roll direction of the roller. Same chips, same semantics, same
  /// deliberate-gesture threshold; only the strip's orientation differs.
  /// Horizontal stays the default so existing callers are unchanged.
  final CurrencyWheelAxis axis;
  final bool enabled;

  /// What the control chooses on this surface ('Input currency' on amount
  /// entry, 'Display currency' on Home).
  final String semanticLabelPrefix;

  @override
  ConsumerState<CurrencyWheelToggle> createState() => _CurrencyWheelToggleState();
}

class _CurrencyWheelToggleState extends ConsumerState<CurrencyWheelToggle>
    with SingleTickerProviderStateMixin {
  static const _chipWidth = 74.0;
  static const _chipHeight = 44.0; // ≥44dp touch target
  static const _peek = 14.0; // neighbour visibility per side
  static const _dragThreshold = 24.0;

  late final AnimationController _controller;

  /// Primary-axis drag offset (dx horizontal, dy vertical). Reset to 0
  /// by a cancelled gesture — a graze or a lost arena battle never
  /// changes money denominations.
  double _drag = 0;
  int _animFrom = 0;
  int _animTo = 0;

  // ── Axis-aware geometry ──────────────────────────────────────────────
  //
  // The wheel's box spans the selected chip plus a [peek] gutter on each
  // side. The selected chip must sit EXACTLY CENTRED in that box — never
  // cropped by the wheel's own peek geometry — with the neighbour chips
  // peeking precisely `peek` into each gutter, fading under the shader.
  //
  // ONE geometry, both axes: chips are ADJACENT (the pitch IS the chip
  // extent), the strip's origin is pinned to the box's roll-axis edge,
  // and [_originShift] seats the selected chip's leading edge exactly one
  // [peek] into the box — so its centre is the box centreline. The
  // neighbour peeks precisely [peek] through the trailing gutter, under
  // the fade. Chip visibility is pinned in the box's OWN coordinates, so
  // it holds for ANY option count — one chip, two, or more.
  //
  // VERTICAL (Send) is byte-identical to the pre-fix rendering at two
  // options (verified: the send goldens do not move). HORIZONTAL (Card
  // Transfer, the home balance card) previously centred the whole strip
  // in the box with a chip+2*peek pitch — the selected chip sat on the
  // box EDGE, half-cropped. It now rides the same centred geometry the
  // vertical axis proved. Verified geometrically by
  // currency_wheel_alignment_test.dart (both axes).
  double get _chipExtent =>
      widget.axis == CurrencyWheelAxis.vertical ? _chipHeight : _chipWidth;

  double get _pitch => _chipExtent;

  double get _slotTotal => _chipExtent + 2 * _peek;

  /// Where the strip sits along the roll axis: the strip's leading edge
  /// is pinned at the box's roll-axis edge, and this shift seats the
  /// SELECTED chip exactly one [peek] in — dead-centred on the box
  /// centreline, gutter for gutter. (The pre-fix vertical shift of half
  /// a chip height produced the same box coordinates at two options and
  /// is superseded by this n-independent form.)
  double get _originShift => _peek;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: MotionTokens.control, // 180ms, collapses to 0 on reduced motion
    )..addListener(() {
        if (mounted) setState(() {});
      });
    _animTo = widget.selectedIndex;
    _animFrom = widget.selectedIndex;
  }

  @override
  void didUpdateWidget(covariant CurrencyWheelToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // External selection change (e.g. a11y action elsewhere, or the caller
    // resetting the surface): roll to it unless we're mid-drag.
    if (oldWidget.selectedIndex != widget.selectedIndex &&
        _drag == 0 &&
        _animTo != widget.selectedIndex) {
      _rollTo(widget.selectedIndex, haptic: false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _rollTo(int index, {bool haptic = true}) {
    if (index == _animTo && _drag == 0) {
      if (widget.selectedIndex != index) widget.onChanged(index);
      return;
    }
    setState(() {
      _animFrom = _animTo;
      _animTo = index.clamp(0, widget.options.length - 1);
      _drag = 0;
    });
    if (haptic) AzamanHaptics.toggle();
    final duration = MotionTokens.accessibleDuration(
        context, MotionTokens.control);
    _controller.duration = duration;
    _controller.forward(from: 0);
    widget.onChanged(_animTo);
    _announce(_animTo);
  }

  void _announce(int index) {
    final c = widget.options[index];
    SemanticsService.announce('${c.label} (${c.code}) selected', TextDirection.ltr); // ignore: deprecated_member_use
  }

  void _onDragEnd(DragEndDetails details) {
    final delta = _drag;
    final velocity = details.primaryVelocity ?? 0;
    // A deliberate roll needs either a real drag past the threshold or a
    // decisive fling velocity — an accidental graze never changes money
    // denominations. (Vertical mirrors horizontal: rolling against the
    // reading direction — up — advances; either way the gesture must be
    // DELIBERATE, and a cancelled gesture resets to 0 without a change.)
    final decisive =
        delta.abs() >= _dragThreshold || velocity.abs() >= 200;
    if (!decisive) {
      setState(() => _drag = 0);
      return;
    }
    _rollTo((delta < 0 ? _animTo + 1 : _animTo - 1)
        .clamp(0, widget.options.length - 1));
  }

  void _openPicker() {
    final colors = ref.read(themeProvider).colors;
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final position = box.localToGlobal(Offset.zero);
    // Horizontal: menu drops below the chip. Vertical: menu opens to the
    // wheel's right so it never covers the roller itself.
    final left = widget.axis == CurrencyWheelAxis.vertical
        ? position.dx + _chipWidth
        : position.dx;
    final top = widget.axis == CurrencyWheelAxis.vertical
        ? position.dy
        : position.dy + _chipHeight;
    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(left, top, left + 200, 0),
      items: [
        for (var i = 0; i < widget.options.length; i++)
          PopupMenuItem(
            value: i,
            child: Row(
              children: [
                if (i == widget.selectedIndex)
                  Icon(Icons.check, size: 18, color: colors.accent)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 10),
                Text('${widget.options[i].symbol} — ${widget.options[i].label}'),
              ],
            ),
          ),
      ],
    ).then((picked) {
      if (picked != null && picked != widget.selectedIndex) {
        _rollTo(picked);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final selected = widget.options[widget.selectedIndex.clamp(
        0, widget.options.length - 1)];

    final pitch = _pitch;
    final rollT = Curves.easeOutCubic.transform(_controller.value);
    final base = _animFrom + (_animTo - _animFrom) * rollT;
    final offset = -base * pitch + _originShift + _drag;
    final vertical = widget.axis == CurrencyWheelAxis.vertical;

    final chipRadius = BorderRadius.circular(AzRadius.sm + 2);

    Widget chip(AzCurrency c, bool isSel) {
      return Container(
        width: _chipWidth,
        height: _chipHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: chipRadius,
          border: Border.all(
            color: isSel ? colors.accent : colors.divider,
            width: isSel ? 1.4 : 1,
          ),
        ),
        child: Text(
          c.symbol,
          maxLines: 1,
          style: TextStyle(
            color: isSel ? colors.textPrimary : colors.textTertiary,
            fontSize: isSel ? 15 : 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      );
    }

    // The strip's box spans exactly the selected chip plus the two peek
    // gutters along the roll axis; across the axis it is exactly the
    // chip — so the SELECTED chip is never cropped by the wheel's own
    // geometry, only the neighbours fade at the gutters.
    final roller = SizedBox(
      width: vertical ? _chipWidth : _chipWidth + 2 * _peek,
      height: vertical ? _chipHeight + 2 * _peek : _chipHeight,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: vertical ? _chipWidth : double.infinity,
          maxHeight: vertical ? double.infinity : _chipHeight,
          // The strip's leading edge is pinned at the box's roll-axis
          // edge so [_originShift] alone seats the selected chip dead
          // centre — independent of how many chips the strip carries
          // (centre-aligning the whole strip made visibility depend on
          // the option count). The cross axis is exactly the chip, so
          // topLeft positions it identically to center.
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset:
                vertical ? Offset(0, offset) : Offset(offset, 0),
            child: vertical
                ? Column(
                    // Adjacent chips: the pitch IS the chip extent, so
                    // the neighbour peeks exactly [peek] into each
                    // gutter, under the fade. Same on both axes.
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.options.length; i++)
                        chip(widget.options[i], i == widget.selectedIndex),
                    ],
                  )
                : Row(
                    // Adjacent chips — the pre-fix chip+2*peek gap pushed
                    // the neighbour clear past the gutter, so nothing
                    // ever peeked; the strip is now the vertical's twin.
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.options.length; i++)
                        chip(widget.options[i], i == widget.selectedIndex),
                    ],
                  ),
          ),
        ),
      ),
    );

    // §6 — the fade lives ONLY inside the peek gutters: the selected
    // chip (always centered, spanning the full slot minus the peeks) is
    // rendered at FULL opacity — the shader never touches its label or
    // accent border — while the neighbours genuinely peek through the
    // fading edges. Computed from the geometry constants, not eyeballed.
    final edgeFade = _peek / _slotTotal;
    final shaderColors = vertical
        ? const [Color(0x00000000), Color(0xFF000000),
            Color(0xFF000000), Color(0x00000000)]
        : const [Color(0x00000000), Color(0xFF000000),
            Color(0xFF000000), Color(0x00000000)];
    final fader = ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
        end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
        colors: shaderColors,
        stops: [0.0, edgeFade, 1.0 - edgeFade, 1.0],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: roller,
    );

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label:
          '${widget.semanticLabelPrefix}: ${selected.label} (${selected.code})',
      value: selected.code,
      hint: widget.options.length > 1
          ? 'Swipe, tap to open the picker, or use increase and decrease '
              'actions to change the currency'
          : 'Fixed at ${selected.label}',
      increasedValue: widget.options.length > 1
          ? widget.options[(widget.selectedIndex + 1) % widget.options.length]
              .code
          : null,
      decreasedValue: widget.options.length > 1
          ? widget.options[(widget.selectedIndex - 1)
                  .clamp(0, widget.options.length - 1)]
              .code
          : null,
      onIncrease: widget.enabled && widget.options.length > 1
          ? () => _rollTo(
              (widget.selectedIndex + 1).clamp(0, widget.options.length - 1))
          : null,
      onDecrease: widget.enabled && widget.options.length > 1
          ? () => _rollTo((widget.selectedIndex - 1)
              .clamp(0, widget.options.length - 1))
          : null,
      onTap: widget.enabled && widget.options.length > 1 ? _openPicker : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap:
            widget.enabled && widget.options.length > 1 ? _openPicker : null,
        // Only the roll axis is draggable: on Send (vertical) the wheel
        // claims vertical gestures within its own bounds and CANCELS
        // cleanly if the surrounding scrollable wins the arena — a
        // scroll that happens to start on the wheel never changes the
        // currency.
        onHorizontalDragUpdate: widget.enabled && !vertical
            ? (d) => setState(() => _drag += d.delta.dx)
            : null,
        onHorizontalDragEnd: widget.enabled && !vertical ? _onDragEnd : null,
        onHorizontalDragCancel: widget.enabled && !vertical
            ? () => setState(() => _drag = 0)
            : null,
        onVerticalDragUpdate: widget.enabled && vertical
            ? (d) => setState(() => _drag += d.delta.dy)
            : null,
        onVerticalDragEnd: widget.enabled && vertical ? _onDragEnd : null,
        onVerticalDragCancel: widget.enabled && vertical
            ? () => setState(() => _drag = 0)
            : null,
        child: fader,
      ),
    );
  }
}
