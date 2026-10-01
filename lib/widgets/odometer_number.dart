// lib/widgets/odometer_number.dart
// =============================================================================
// ODOMETER NUMBER — per-digit roll
//
// ── WHY ──────────────────────────────────────────────────────────────────────
// A plain cross-fade replaces the WHOLE figure to change part of it. Going from
// "GH₵ 1,240.42" to "GH₵ 1,240.85" fades eight unchanged characters so that two
// can change, which means the eye cannot see which digits moved and the change
// carries no weight.
//
// An odometer rolls ONLY the digits that changed — upward when the digit
// increased, downward when it decreased. Non-digit characters (the currency
// symbol, thousands separators, the decimal point) stay perfectly still, which
// is what makes the movement legible: only the part of the number that is
// telling you something new is allowed to move.
//
// ── HOW ──────────────────────────────────────────────────────────────────────
// The string is split into one cell per character. Each DIGIT cell that differs
// from its previous value gets its own `AnimatedSwitcher`, which slides the old
// character out and the new one in from the opposite direction. Because every
// cell is a single character rendered in a TABULAR-figure style, all digit cells
// are the same width, so nothing reflows while the number rolls.
//
// ── REQUIREMENT ──────────────────────────────────────────────────────────────
// [style] MUST have tabular figures (`AzText.money(...)` provides them). Without
// tabular figures, a digit changing from "1" to "8" changes the cell width and
// the whole number shifts sideways — which looks broken.
//
// ── USAGE ────────────────────────────────────────────────────────────────────
//   OdometerNumber(
//     value: AzMoney.ghs(balance),
//     style: AzText.money(colors.textPrimary, size: AzText.sizeHero),
//   )
//
// When the parent rebuilds with a new [value], only the changed digits roll.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/theme/motion_tokens.dart';

class OdometerNumber extends StatefulWidget {
  const OdometerNumber({
    super.key,
    required this.value,
    required this.style,
    this.duration = MotionTokens.emphasized,
    this.curve = MotionTokens.enter,
    this.textAlign = TextAlign.start,
    this.semanticsLabel,
  });

  /// The fully formatted string to display, e.g. `"GH₵ 1,240.42"`.
  /// Digits that differ from the previous value roll into place.
  final String value;

  /// MUST use tabular figures — see the file header.
  final TextStyle style;

  /// How long a single digit takes to roll.
  final Duration duration;

  /// Curve for the roll.
  final Curve curve;

  /// Horizontal alignment of the rendered run.
  final TextAlign textAlign;

  /// Optional accessibility label. If null, the raw [value] is announced, which
  /// is usually correct for a currency figure.
  final String? semanticsLabel;

  @override
  State<OdometerNumber> createState() => _OdometerNumberState();
}

class _OdometerNumberState extends State<OdometerNumber> {
  /// The value as it was on the previous build. Compared character-by-character
  /// against `widget.value` to decide which cells roll.
  late String _previous;

  @override
  void initState() {
    super.initState();
    // On first build there is nothing to roll FROM, so every cell renders
    // statically. This is deliberate: the mount animation belongs to the
    // screen's entrance choreography, not to this widget.
    _previous = widget.value;
  }

  @override
  void didUpdateWidget(covariant OdometerNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      // Capture the outgoing string BEFORE the rebuild so each cell can compare
      // its old character with its new one.
      _previous = oldWidget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reduced-motion: render the new value instantly. The information is
    // preserved; only the roll is suppressed.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : widget.duration;

    final current = widget.value;
    final previous = _previous;

    final cells = <Widget>[];
    for (var i = 0; i < current.length; i++) {
      final ch = current[i];
      final prevCh = i < previous.length ? previous[i] : null;

      // Under reduced motion a digit renders as PLAIN TEXT, not a switcher with
      // a zero duration. AnimatedSwitcher keeps the controller it built for each
      // entry and reverses that controller to play the exit, so a switcher that
      // was mounted while animations were enabled would still slide its outgoing
      // digit out over the full duration — the value would arrive half-faded
      // instead of appearing whole on the first frame. Dropping the switcher
      // means there is no outgoing child to animate at all.
      if (!_isDigit(ch) || prevCh == null || reduceMotion) {
        cells.add(_staticCell(ch));
      } else {
        // Rolling UP means the new digit is numerically larger.
        final rollsUp = ch != prevCh && ch.codeUnitAt(0) > prevCh.codeUnitAt(0);
        // EVERY digit cell is an AnimatedSwitcher, even when unchanged. If an
        // unchanged digit were rendered as a plain Text, that cell's element
        // would change TYPE on the rebuild and be destroyed — so the very
        // moment it starts to change, the switcher would be mounted fresh with
        // no outgoing child and the digit would snap instead of roll.
        cells.add(
          _digitCell(
            index: i,
            ch: ch,
            prevCh: prevCh,
            rollsUp: rollsUp,
            duration: duration,
          ),
        );
      }
    }

    return Semantics(
      label: widget.semanticsLabel ?? current,
      // The per-cell text below would otherwise be announced digit by digit.
      excludeSemantics: true,
      // A boundary of its own: without this the label merges with whatever
      // is announced next to the figure (the currency symbol, tab labels…)
      // and the value stops being one coherent string.
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // `Flexible` + `FittedBox` guards against a longer value (e.g.
          // 999.00 → 1,000.00) overflowing a constrained parent. It scales down
          // rather than clipping, so a balance is never truncated.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: _alignmentFor(widget.textAlign),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: cells,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A character that does not change: the currency symbol, a separator, the
  /// decimal point. Rendered as plain text and never animated.
  Widget _staticCell(String ch) => Text(ch, style: widget.style);

  /// A digit that changed. Slides the old character out and the new one in.
  Widget _digitCell({
    required int index,
    required String ch,
    required String prevCh,
    required bool rollsUp,
    required Duration duration,
  }) {
    // The incoming child key encodes BOTH the cell index and the character, so
    // two cells showing the same digit never collide and an unchanged digit
    // keeps the same key (no transition, no wasted animation).
    final key = ValueKey<String>('digit-$index-$ch');

    // `duration` is passed UNCHANGED, never shortened to zero for a cell that
    // currently matches its predecessor. AnimatedSwitcher builds the outgoing
    // child's AnimationController when that entry is first created, and it
    // reverses THAT controller later to play the exit. A cell that mounted while
    // its digit was unchanged was created with a zero duration, so reversing it
    // would dismiss the outgoing digit on the very same frame and the roll would
    // never be seen — the value would just snap. Because a cell whose key did not
    // change never gets a new entry at all (AnimatedSwitcher updates it in place
    // and starts no animation), passing the real duration here costs nothing on
    // an unchanged digit and is what makes a changed one actually roll.
    final effective = duration;
    // `rollsUp == true`  → the new digit arrives from BELOW and the old one
    //                      leaves upward (like a real odometer increasing).
    // `rollsUp == false` → the new digit arrives from ABOVE and the old one
    //                      leaves downward.
    final sign = rollsUp ? 1.0 : -1.0;

    return AnimatedSwitcher(
      duration: effective,
      switchInCurve: widget.curve,
      switchOutCurve: widget.curve,
      // A Stack keeps the outgoing and incoming characters on top of each other
      // so the cell never changes width mid-roll.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == key;
        // Incoming runs 0 → 1, so (begin, end) is (from, to).
        // Outgoing runs 1 → 0, so (begin, end) is (to, from).
        final tween = isIncoming
            ? Tween<Offset>(begin: Offset(0, sign), end: Offset.zero)
            : Tween<Offset>(begin: Offset(0, -sign), end: Offset.zero);
        return ClipRect(
          child: SlideTransition(
            position: tween.animate(animation),
            child: child,
          ),
        );
      },
      child: Text(ch, key: key, style: widget.style),
    );
  }

  static bool _isDigit(String ch) {
    final code = ch.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39; // '0'..'9'
  }

  static Alignment _alignmentFor(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      case TextAlign.left:
      case TextAlign.start:
      default:
        return Alignment.centerLeft;
    }
  }
}
