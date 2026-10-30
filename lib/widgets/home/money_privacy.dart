// AZAMAN — MONEY PRIVACY VALUES
//
// The app-wide gate HIDES a figure; it must never destroy the surface that
// holds it. The owner was explicit: the Balance and Visa cards stay tucked in
// the pouch exactly as they are, and only the protected INFORMATION and
// FUNCTIONS lock. So a locked card keeps its geometry, artwork, gradients and
// gestures — and renders this mask where a figure would be.
//
// The mask is a replacement string, not a blur over a live number: the real
// value is never formatted while locked, so it cannot leak through semantics,
// a screen reader, a screen capture or the widget tree.

import 'package:flutter/foundation.dart';

/// The mask a locked money surface paints where a figure lives.
const String kRedactedMoney = '••••';

/// One policy object threaded down the card faces, so no face has to reach for
/// a provider of its own (the cards stay pure widgets).
@immutable
class MoneyVisibility {
  const MoneyVisibility({required this.canViewMoney});

  static const MoneyVisibility visible = MoneyVisibility(canViewMoney: true);
  static const MoneyVisibility redacted = MoneyVisibility(canViewMoney: false);

  final bool canViewMoney;

  bool get isRedacted => !canViewMoney;

  /// Lazy form: [build] is not called at all while locked, so the figure is
  /// never even formatted.
  String masked(String Function() build) =>
      canViewMoney ? build() : kRedactedMoney;
}
