// =============================================================================
// AZAMAN — @-HANDLE FORMATTER (2026-10-20)
//
// ONE idempotent display formatter for canonical handles. The bug it
// replaces: the success panel interpolated '@' onto a username that
// ALREADY carried one — '@ama' became '(@@ama)'. Canonical username data
// stays unprefixed everywhere internally; ONLY this formatter adds the
// glyph, AT MOST once, and omits it entirely when there is no real
// canonical username (a display name is never promoted into a handle).
// =============================================================================

abstract final class AtHandle {
  const AtHandle._();

  /// '@ama' → '@ama', 'ama' → '@ama', '@@ama' → '@ama', '' / null → ''.
  static String format(String? username) {
    final raw = (username ?? '').trim();
    if (raw.isEmpty) return '';
    final bare = raw.startsWith('@') ? raw.substring(1).trim() : raw;
    if (bare.isEmpty) return '';
    return '@$bare';
  }
}
