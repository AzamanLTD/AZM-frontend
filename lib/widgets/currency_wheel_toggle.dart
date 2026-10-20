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
    this.enabled = true,
    this.semanticLabelPrefix = 'Input currency',
  }) : assert(options.length >= 1);

  final List<AzCurrency> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
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
  double _dragDx = 0;
  int _animFrom = 0;
  int _animTo = 0;

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
        _dragDx == 0 &&
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
    if (index == _animTo && _dragDx == 0) {
      if (widget.selectedIndex != index) widget.onChanged(index);
      return;
    }
    setState(() {
      _animFrom = _animTo;
      _animTo = index.clamp(0, widget.options.length - 1);
      _dragDx = 0;
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
    final dx = _dragDx;
    final velocity = details.primaryVelocity ?? 0;
    // A deliberate roll needs either a real drag past the threshold or a
    // decisive fling velocity — an accidental graze never changes money
    // denominations.
    final decisive =
        dx.abs() >= _dragThreshold || velocity.abs() >= 200;
    if (!decisive) {
      setState(() => _dragDx = 0);
      return;
    }
    _rollTo((dx < 0 ? _animTo + 1 : _animTo - 1)
        .clamp(0, widget.options.length - 1));
  }

  void _openPicker() {
    final colors = ref.read(themeProvider).colors;
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final position = box.localToGlobal(Offset.zero);
    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx,
          position.dy + _chipHeight, position.dx + 200, 0),
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

    const slot = _chipWidth + 2 * _peek;
    final rollT = Curves.easeOutCubic.transform(_controller.value);
    final base = _animFrom + (_animTo - _animFrom) * rollT;
    final offset = -base * slot + _dragDx;

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

    final roller = SizedBox(
      width: _chipWidth + 2 * _peek,
      height: _chipHeight,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          alignment: Alignment.center,
          child: Transform.translate(
            offset: Offset(offset, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.options.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2 * _peek),
                  chip(widget.options[i], i == widget.selectedIndex),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    final fader = ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0x00000000),
          Color(0xFF000000),
          Color(0xFF000000),
          Color(0x00000000),
        ],
        stops: [0.0, 0.16, 0.84, 1.0],
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
        onHorizontalDragUpdate: widget.enabled
            ? (d) => setState(() => _dragDx += d.delta.dx)
            : null,
        onHorizontalDragEnd: widget.enabled ? _onDragEnd : null,
        onHorizontalDragCancel: widget.enabled
            ? () => setState(() => _dragDx = 0)
            : null,
        child: fader,
      ),
    );
  }
}
