// =============================================================================
// AZ REFRESH REWARD  (NEW-D)
//
// The pull-to-refresh gesture already exists (az_pull_to_refresh.dart /
// AzLogoRefreshIndicator) and is NOT rewritten here. This is the pure
// decision layer for the reward semantics §G.8 asks Home's refresh seam
// to add:
//
//   1. ONE threshold haptic when the user commits the pull — that is the
//      gesture's receipt, fired by the existing `_onRefresh` seam and never
//      doubled.
//   2. AFTER the refresh completes, a single `moneyLanded()` ONLY when a
//      trusted monetary balance actually increased between the moment the
//      pull committed and the moment the world was re-read.
//
// §H.7 standing rule: motion and haptics may confirm something the user
// did — they may not ask for attention the user did not give. A balance
// tick-up is a receipt for money that really moved; a haptic with no
// movement is a summons. Nothing here invents a balance, a settlement or
// an idle timer, and the comparison is only made from the authoritative
// balance source Home already renders.
// =============================================================================

/// Pure boolean decision — no providers, no context, fully unit-testable.
class AzRefreshReward {
  /// True only when [after] is a real, observed increase over [before].
  ///
  /// Equality is NOT a reward: a refresh that kept the same balance is a
  /// receipt for "nothing changed", not a celebration. Null on either side
  /// means the comparison cannot be made honestly, so no reward is given.
  static bool landed({required double? before, required double? after}) {
    if (before == null || after == null) return false;
    return after > before;
  }
}
