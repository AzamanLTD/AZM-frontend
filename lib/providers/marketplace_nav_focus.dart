// =============================================================================
// AZAMAN — MARKETPLACE-FOCUSED NAV STATE  (correction I)
//
// At the Marketplace ROOT the bottom navigation reorganises itself around
// Shopping: [ … Marketplace (search field) ]. This provider is the ONE
// shared seam between the shell (tab selection), the nav band (the focused
// presentation) and the Marketplace screen (the content-tap re-entry).
//
// Semantics:
//   * focused == true  → the focused Marketplace nav is showing.
//   * Entering the Marketplace tab sets it true.
//   * The "…" control sets it false (normal nav restored, Marketplace stays
//     selected — a PRESENTATION change, never a navigation).
//   * Tapping anywhere on Marketplace content sets it back to true while
//     the user is still on the Marketplace root.
//   * Selecting Home or Chat sets it false (leaving Marketplace normally).
//
// It is a contextual presentation of the ROOT TAB state, never a pushed
// route, and the Marketplace screen stays mounted and unchanged through
// every transition of this flag.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the bottom navigation is in the focused Marketplace state.
/// Only meaningful while the Marketplace tab is the selected root tab.
final marketplaceNavFocusProvider = StateProvider<bool>((ref) => false);
