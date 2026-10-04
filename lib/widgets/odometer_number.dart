// lib/widgets/odometer_number.dart
// =============================================================================
// ODOMETER NUMBER — per-digit roll, keyed by SLOT FROM THE RIGHT
//
// ── WHY ──────────────────────────────────────────────────────────────────────
// A plain cross-fade replaces the WHOLE figure to change part of it. Going from
// "GH₵ 1,240.42" to "GH₵ 1,240.85" fades eight unchanged characters so that two
// can change, which means the eye cannot see which digits moved and the change
// carries no weight.
//
// An odometer rolls ONLY the digits that changed. Non-digit characters (the
// currency symbol, thousands separators, the decimal point) stay perfectly
// still, which is what makes the movement legible: only the part of the number
// that is telling you something new is allowed to move.
//
// ── IDENTITY: SLOTS FROM THE RIGHT (UI-correction Phase A, 2026-10-03) ────────
// The earlier implementation compared characters by LEFT index. That is wrong
// for an amount: typing changes the string on the RIGHT, and the grouping
// comma sits at a position counted from the RIGHT, so a left-index identity
// re-rolls digits that did not change whenever the comma shifts indices.
//
// The correct rule: characters are SLOTS counted from the RIGHT. Slot 0 is
// always the last character of the string; slot 1 the second-to-last; and so
// on. Comparing slot N of the previous value with slot N of the current value
// keeps unchanged characters still no matter what the rest of the string did:
//
//   '999'  → '9,990'   slots 1–2 (the two '9's) are UNCHANGED and stay still;
//                      only the typed '0' rolls in, the comma fades in, and
//                      the new leftmost '9' rolls in from below.
//   '1,000'→ '10,000'  the three zeros and the comma stay still; only the
//                      shifting '1' and the new digit move.
//   backspace          the emptied slot's outgoing digit rolls out downward.
//
// Per-slot behaviour:
//   • unchanged digit      → remains still (same child key, no animation);
//   • changed existing     → rolls (up if the digit increased);
//   • new slot             → rolls in from below;
//   • deleted slot         → the outgoing digit rolls out downward;
//   • comma/decimal point  → static cell that FADES when appearing or
//                            disappearing — separators never slide.
//
// When a slot changes BETWEEN a digit and a separator, the incoming character
// follows its own grammar: a separator fades in where a digit was; a digit
// rolls in from below where a separator was.
//
// ── ELEMENT STABILITY (why EVERY cell is an AnimatedSwitcher) ─────────────────
// Every slot renders as an AnimatedSwitcher keyed by its slot number — even a
// slot whose character is unchanged. An unchanged slot keeps the same child
// key, so the switcher updates in place and starts NO animation (it is
// visually a static cell). But the element TYPE never changes across
// rebuilds, which is what makes every other transition possible: a slot that
// later changes/deletes has a LIVE switcher whose outgoing child (built with
// its entry transition) is reversed on exit — the digit rolls out downward.
// Rendering an unchanged slot as plain Text instead would change the element
// type the moment it starts moving, remount the switcher with no outgoing
// child, and the digit would snap instead of roll.
//
// ── REQUIREMENT ──────────────────────────────────────────────────────────────
// [style] MUST have tabular figures (`AzText.money(...)` provides them — and
// pins Inter, which ships them). Without tabular figures, a digit changing
// from "1" to "8" changes the cell width and the whole number shifts
// sideways — which looks broken.
//
// ── USAGE ────────────────────────────────────────────────────────────────────
//   OdometerNumber(
//     value: AzMoney.ghs(balance),
//     style: AzText.money(colors.textPrimary, size: AzText.sizeHero),
//   )
//
// When the parent rebuilds with a new [value], only the changed slots roll.
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
  /// Slots that differ from the previous value roll into place.
  final String value;

  /// MUST use tabular figures — see the file header.
  final TextStyle style;

  /// How long a single slot takes to roll or fade.
  final Duration duration;

  /// Curve for the roll/fade.
  final Curve curve;

  /// Horizontal alignment of the rendered run.
  final TextAlign textAlign;

  /// Optional accessibility label. If null, the raw [value] is announced, which
  /// is usually correct for a currency figure.
  final String? semanticsLabel;

  @override
  State<OdometerNumber> createState() => _OdometerNumberState();
}

/// What one right-keyed slot has to do on this rebuild. Pure data, computed
/// before any widget is built, so the slot logic is unit-testable in
/// isolation (see test/widgets/odometer_slot_identity_test.dart).
enum OdometerSlotKind {
  /// Same character as the previous value — still, no motion.
  unchanged,

  /// Digit present before and after but different — rolls up or down.
  changedDigit,

  /// No character before, digit now — rolls in from below.
  newDigit,

  /// Digit before, no character now — rolls out downward.
  deletedDigit,

  /// A separator is appearing (or, when [OdometerSlotPlan.currentChar] is
  /// null, disappearing) — separators fade, never slide.
  separatorFade,
}

/// The plan for one slot: what the slot shows now, what it showed before, and
/// what kind of motion (if any) it needs.
@visibleForTesting
class OdometerSlotPlan {
  const OdometerSlotPlan({
    required this.slot,
    required this.currentChar,
    required this.previousChar,
    required this.kind,
  });

  /// Identity: 0 = last character of the string, 1 = second-to-last, …
  final int slot;

  /// The character the slot shows on this build; null when the slot was
  /// deleted (the previous character still renders, rolling out).
  final String? currentChar;

  /// The character the slot showed on the previous build; null when the slot
  /// is new.
  final String? previousChar;

  final OdometerSlotKind kind;

  @override
  bool operator ==(Object other) =>
      other is OdometerSlotPlan &&
      other.slot == slot &&
      other.currentChar == currentChar &&
      other.previousChar == previousChar &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(slot, currentChar, previousChar, kind);

  @override
  String toString() =>
      'OdometerSlotPlan(slot: $slot, cur: $currentChar, prev: '
      '$previousChar, kind: $kind)';
}

/// The pure slot planner: [plan] computes what every right-keyed slot must
/// do when the odometer moves from [previous] to [current].
@visibleForTesting
abstract final class OdometerSlots {
  const OdometerSlots._();

  static bool _isDigit(String ch) =>
      ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;

  static List<OdometerSlotPlan> plan(String current, String previous) {
    final slotCount =
        current.length > previous.length ? current.length : previous.length;
    final plans = <OdometerSlotPlan>[];
    for (var slot = 0; slot < slotCount; slot++) {
      final curIndex = current.length - 1 - slot;
      final prevIndex = previous.length - 1 - slot;
      final cur = curIndex >= 0 ? current[curIndex] : null;
      final prev = prevIndex >= 0 ? previous[prevIndex] : null;

      OdometerSlotKind kind;
      if (cur != null && prev == cur) {
        kind = OdometerSlotKind.unchanged;
      } else if (cur == null && prev != null) {
        // Deleted slot: a digit rolls out downward; a separator (which
        // never slides) fades out.
        kind = _isDigit(prev)
            ? OdometerSlotKind.deletedDigit
            : OdometerSlotKind.separatorFade;
      } else if (prev == null && cur != null) {
        // New slot: a digit rolls in from below; a separator fades in.
        kind = _isDigit(cur)
            ? OdometerSlotKind.newDigit
            : OdometerSlotKind.separatorFade;
      } else if (!_isDigit(cur!) || !_isDigit(prev!)) {
        // A separator is involved on one side of a changed slot — the
        // incoming character follows the separator grammar: fade, never
        // slide.
        kind = OdometerSlotKind.separatorFade;
      } else {
        // Both digits, different values — a real roll.
        kind = OdometerSlotKind.changedDigit;
      }
      plans.add(
        OdometerSlotPlan(
          slot: slot,
          currentChar: cur,
          previousChar: prev,
          kind: kind,
        ),
      );
    }
    return plans;
  }
}

class _OdometerNumberState extends State<OdometerNumber> {
  /// The slot kinds of the CURRENT build, by slot. Drives the per-slot
  /// transitionBuilder selection in [_slotCell].
  Map<int, OdometerSlotKind> _kindsBySlot = const {};

  /// The slot kinds of the PREVIOUS build, by slot. Read by the
  /// continuity guard in [_slotTransition].
  Map<int, OdometerSlotKind> _previousKindsBySlot = const {};

  /// The value as it was on the previous build. Compared slot-by-slot
  /// (from the right) against `widget.value` to decide which cells roll.
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
      // Capture the outgoing string BEFORE the rebuild so each slot can
      // compare its old character with its new one.
      _previous = oldWidget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reduced-motion: render the new value instantly. The information is
    // preserved; only the roll is suppressed.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : widget.duration;

    final plans = OdometerSlots.plan(widget.value, _previous);

    // The builder selection (see [_slotTransition]) reads these: the slot
    // kinds of the PREVIOUS build let the continuity guard recognise a
    // deletion exit that is still in flight after the slot's plan has
    // already moved on; the current kinds drive the builder selection in
    // [_slotCell]. Both are pure functions of the value pair, so an
    // unrelated rebuild recomputes identical maps and nothing flips.
    _previousKindsBySlot = _kindsBySlot;
    _kindsBySlot = {for (final plan in plans) plan.slot: plan.kind};

    // Slot 0 is the RIGHTMOST character, so the cell list is reversed to
    // render left → right.
    final cells = <Widget>[];
    for (final plan in plans.reversed) {
      cells.add(
        reduceMotion ? _reducedMotionCell(plan) : _slotCell(plan, duration),
      );
    }

    // The cells run, mounted either bare (reduced motion) or inside the
    // width-animated wrapper below.
    final cellsRow = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: cells,
    );

    return Semantics(
      label: widget.semanticsLabel ?? widget.value,
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
          // 999.00 → 1,000.00) overflowing a constrained parent. It scales
          // down rather than clipping, so a balance is never truncated.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: _alignmentFor(widget.textAlign),
              // UI-correction Phase A: the amount WIDTH animates as digits
              // arrive and leave, instead of snapping once the roll ends.
              // Review patch (2026-10-04): the width animation must ALSO
              // honour reduced motion. The equivalent-zero-duration
              // behaviour is achieved by NOT MOUNTING the AnimatedSize at
              // all under `disableAnimations`, for the same reason the
              // per-cell switchers are dropped (see
              // [_reducedMotionCell]): RenderAnimatedSize drives its own
              // controller from inside performLayout, and a zero-duration
              // controller completes synchronously during layout and
              // re-dirties the render object mid-layout — a framework
              // assertion. Dropping the wrapper makes the geometry snap to
              // its final value in one frame with no layout mutation.
              child: reduceMotion
                  ? cellsRow
                  : AnimatedSize(
                      duration: MotionTokens.control,
                      curve: MotionTokens.enter,
                      child: cellsRow,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// The per-slot identity key. Two odometers on one screen (e.g. primary and
  /// secondary balances) each own their own element tree, so the slot number
  /// alone is unique within this widget.
  Key _cellKey(int slot) => ValueKey<String>('odometer-slot-$slot');

  /// Reduced motion: the new value renders as PLAIN TEXT, not switchers with
  /// a zero duration. AnimatedSwitcher keeps the controller it built for each
  /// entry and reverses that controller to play the exit, so a switcher that
  /// was mounted while animations were enabled would still slide its outgoing
  /// digit out over the full duration — the value would arrive half-faded
  /// instead of appearing whole on the first frame. Dropping the switcher
  /// means there is no outgoing child to animate at all.
  Widget _reducedMotionCell(OdometerSlotPlan plan) {
    if (plan.currentChar == null) {
      return SizedBox.shrink(key: _cellKey(plan.slot));
    }
    return Text(plan.currentChar!, key: _cellKey(plan.slot), style: widget.style);
  }

  /// One slot, one AnimatedSwitcher — see the element-stability header.
  Widget _slotCell(OdometerSlotPlan plan, Duration duration) {
    return AnimatedSwitcher(
      key: _cellKey(plan.slot),
      duration: duration,
      switchInCurve: widget.curve,
      switchOutCurve: widget.curve,
      // A Stack keeps the outgoing and incoming characters on top of each
      // other so the cell never changes width mid-roll.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      // Review patch (2026-10-04): the builder is STABLE — a State
      // method tear-off, never a fresh closure. Dart guarantees that two
      // tear-offs of the same method of the same object are equal, so
      // AnimatedSwitcher sees an UNCHANGED builder on every rebuild and
      // never re-wraps live entries. The builder property changes exactly
      // when a slot's plan kind flips — and the ONE deliberate re-wrap
      // that fires there is where the deletion exit is applied (and
      // protected). See [_slotTransition] and [_deletedSlotTransition].
      transitionBuilder: plan.kind == OdometerSlotKind.deletedDigit
          ? _deletedSlotTransition
          : _slotTransition,
      // A deleted slot mounts a zero-size child so the switcher animates the
      // outgoing digit out; every other slot mounts its current character.
      // The incoming child key encodes the SLOT and the character, so two
      // slots showing the same digit never collide and a slot holding its
      // value keeps the same key (no transition, no wasted animation).
      child: _OdometerCell(
        key: ValueKey<String>(
            'slot-${plan.slot}-${plan.currentChar ?? 'empty'}'),
        slot: plan.slot,
        char: plan.currentChar,
        motion: _OdometerCell.motionFor(plan),
        style: widget.style,
      ),
    );
  }

  // ── TRANSITION IDENTITY (review patches 2026-10-04) ─────────────────────
  // AnimatedSwitcher bakes each entry's transition ONCE — when the entry
  // is created, by calling the transitionBuilder — and replays it in
  // REVERSE to retire the entry. It re-wraps live entries ONLY when the
  // builder property itself changes between builds (didUpdateWidget).
  // Two consequences drive this design:
  //
  //   1. PER-BUILD CLOSURES ARE THE DEFECT (first review patch): a fresh
  //      closure every build makes the property change on EVERY rebuild,
  //      so a rapid second update — or any unrelated parent rebuild —
  //      could re-wrap a digit mid-roll with the CURRENT plan's
  //      semantics: a digit that entered from below would exit upward,
  //      or turn into a fade mid-flight.
  //
  //   2. THE DELETION EXIT NEEDS THE ONE RE-WRAP (second review patch):
  //      an exit replays the digit's own baked entry transition in
  //      reverse, so a deleted digit would always leave by reversing
  //      the direction it happened to enter with — mount-created digits
  //      (fade-wrapped, they never slid) would simply vanish, and
  //      above-entered digits would roll OUT upward. The design
  //      requires a deleted digit to roll DOWN out of the slot.
  //
  // Both are solved with STABLE STATE TEAR-OFFS as the builder. Dart
  // guarantees that two tear-offs of the same method of the same object
  // are equal, so a slot whose plan kind has not changed presents the
  // IDENTICAL builder on every rebuild: no re-wraps, and each entry's
  // semantics stay frozen at entry time (see [_OdometerCell.motionFor]).
  // The builder property changes exactly when a slot's kind flips, and
  // that one deliberate re-wrap is where the deletion exit is applied —
  // and where it must be protected:
  //
  //   * [_deletedSlotTransition] is mounted while the plan says
  //     deletedDigit. The flip re-wraps the slot's live entries; the
  //     SETTLED digit (its animation is completed) is re-wrapped to
  //     slide DOWN — the deletion exit — while anything still in flight
  //     keeps its own frozen semantics (an interrupted arrival backs
  //     out the way it came in, a mid-flight change exit keeps its
  //     own direction).
  //   * [_slotTransition] is mounted otherwise. Its continuity guard
  //     recognises a deletion exit that is still in flight when the
  //     slot's kind flips back (a rapid retype) and keeps it sliding
  //     DOWN, instead of letting the re-wrap restore the digit's
  //     original entry motion mid-flight.
  //
  // Invariant: slot identity stays stable; unchanged slots stay still;
  // changed/new digits roll in their own direction and exit reversing
  // the direction they entered with; DELETED digits always roll
  // downward; no rebuild can mutate an in-flight transition's
  // direction.
  // ─────────────────────────────────────────────────────────────────────────

  /// The stable transitionBuilder for every slot whose plan is not
  /// deletedDigit.
  ///
  /// The child of an entry is always an [_OdometerCell] here, but the
  /// fade fallback keeps the builder total (and safe) for any child.
  Widget _slotTransition(Widget child, Animation<double> animation) {
    if (child is! _OdometerCell) {
      return FadeTransition(opacity: animation, child: child);
    }
    // Continuity guard: this exit was STARTED by a deletion (the slot's
    // kind was deletedDigit on the previous build), and the kind has
    // since flipped back — e.g. the user retyped into the slot before
    // the exit finished. Keep it rolling downward; re-deriving the
    // digit's original entry motion here would mutate the in-flight
    // exit's direction.
    if (animation.status == AnimationStatus.reverse &&
        _previousKindsBySlot[child.slot] == OdometerSlotKind.deletedDigit) {
      return _OdometerCell.slide(child, animation, 1.0);
    }
    return child.buildTransition(animation);
  }

  /// The stable transitionBuilder mounted while the slot's plan is
  /// deletedDigit — the one build where the outgoing digit's exit must
  /// be pinned to the deletion semantics.
  Widget _deletedSlotTransition(Widget child, Animation<double> animation) {
    if (child is! _OdometerCell) {
      return FadeTransition(opacity: animation, child: child);
    }
    // The settled digit of a deleted slot rolls DOWN out of the slot —
    // deterministically, regardless of the direction it entered with
    // (a mount-created digit never slid, an above-entered digit would
    // otherwise reverse upward). In-flight entries are untouched: they
    // keep their own frozen semantics.
    if (animation.status == AnimationStatus.completed) {
      return _OdometerCell.slide(child, animation, 1.0);
    }
    return child.buildTransition(animation);
  }

  AlignmentGeometry _alignmentFor(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      case TextAlign.left:
      case TextAlign.start:
      case TextAlign.justify:
        return Alignment.centerLeft;
    }
  }
}



/// How one cell's entry transition moves.
enum _OdometerCellMotion {
  /// Fades in (separators; also unchanged/deleted cells, where the wrap is
  /// a visual no-op).
  fade,

  /// Rolls up — enters sliding from below (begin offset +1).
  slideFromBelow,

  /// Rolls down — enters sliding from above (begin offset -1).
  slideFromAbove,
}

/// One slot's content plus the transition metadata frozen at entry time.
///
/// This widget is the child handed to [AnimatedSwitcher]. AnimatedSwitcher
/// keeps the exact child widget an entry was created with, so the metadata
/// here survives any later build — the entry's transition always rebuilds
/// (if it ever does) with ITS OWN semantics, never the current plan's.
class _OdometerCell extends StatelessWidget {
  const _OdometerCell({
    super.key,
    required this.slot,
    required this.char,
    required this.motion,
    required this.style,
  });

  /// The right-keyed slot this cell lives in (0 = last character).
  final int slot;

  /// The character the cell renders; null for a deleted slot's empty child.
  final String? char;

  /// How the cell enters (and, reversed, how it exits).
  final _OdometerCellMotion motion;

  final TextStyle style;

  /// Derives the entry motion from the slot's plan. This runs ONCE, when
  /// the child is created — the plan of a LATER build can never reach it.
  static _OdometerCellMotion motionFor(OdometerSlotPlan plan) {
    switch (plan.kind) {
      case OdometerSlotKind.unchanged:
      case OdometerSlotKind.deletedDigit:
        // Unchanged: the child key did not move, this wrap only applies to
        // a re-mounted cell and the value is already identical — fade is a
        // no-op visually. Deleted: the incoming child is zero-size, so the
        // wrap is invisible either way.
        return _OdometerCellMotion.fade;
      case OdometerSlotKind.separatorFade:
        // Separators never slide — they fade in.
        return _OdometerCellMotion.fade;
      case OdometerSlotKind.changedDigit:
        final rollsUp = plan.currentChar!.codeUnitAt(0) >
            plan.previousChar!.codeUnitAt(0);
        return rollsUp
            ? _OdometerCellMotion.slideFromBelow
            : _OdometerCellMotion.slideFromAbove;
      case OdometerSlotKind.newDigit:
        // New digits roll in from below.
        return _OdometerCellMotion.slideFromBelow;
    }
  }

  /// Builds this cell's OWN entry transition for [animation] (incoming runs
  /// 0 → 1, so (begin, end) is (from, to): the digit arrives from the
  /// [motion] side). The transition wraps THE CELL ITSELF — the cell's
  /// content is never reconstructed by a transition.
  Widget buildTransition(Animation<double> animation) {
    switch (motion) {
      case _OdometerCellMotion.fade:
        return FadeTransition(opacity: animation, child: this);
      case _OdometerCellMotion.slideFromBelow:
        return slide(this, animation, 1.0);
      case _OdometerCellMotion.slideFromAbove:
        return slide(this, animation, -1.0);
    }
  }

  Widget _content() {
    if (char == null) return const SizedBox.shrink();
    return Text(char!, style: style);
  }

  /// Slides [child] in from [sign] (the incoming animation runs 0 → 1,
  /// so (begin, end) is (from, to): the child arrives from the [sign]
  /// side). The SAME geometry played in reverse — which is exactly what
  /// AnimatedSwitcher does to retire an entry — rolls the child OUT
  /// toward [sign]: sign +1 exits downward.
  static Widget slide(
    Widget child,
    Animation<double> animation,
    double sign,
  ) {
    return ClipRect(
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, sign),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _content();
}
