// =============================================================================
// AZAMAN — SHELL/HOME ACTIVE VISIBILITY
//
// NEW-HOME audit: "MainWrapper keeps pages mounted, therefore Home-local
// security state cannot be treated as indefinitely valid." The shell owns
// which tab is displayed; Home (and any Home-mounted state machine) reads
// THIS provider to know whether it is the active surface.
//
// Rules of use:
//   * The SHELL is the only writer — on every tab selection it writes
//     `selectedIndex == 0` (Home's tab).
//   * Home-side widgets only READ/LISTEN. A default of `true` keeps
//     standalone-pumped Home widgets (tests, previews) behaving as active.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the Home tab is the shell's currently displayed tab.
final homeShellActiveProvider = StateProvider<bool>((ref) => true);
