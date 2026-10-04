// =============================================================================
// AZAMAN — EXPERIENCE VOCABULARY: SPATIAL MODE
//
// Where the user *is*. Screens expose their current mode so that motion,
// semantics announcements and analytics speak one language. This is NOT a
// new state machine: existing screens map their own state onto these values.
// =============================================================================

/// Where the user *is* in the product's spatial model.
enum AzSpatialMode {
  /// Destination entry (Marketplace portal, Chat inbox at rest).
  portal,

  /// Browsing a catalogue (explore list/map, store shopping depth).
  explore,

  /// Quick peek without leaving the list (dossier sheet, quick peek).
  preview,

  /// Full detail of one entity (product, room, trip).
  detail,

  /// Immersive media (story viewer, media viewer).
  fullScreenMedia,

  /// Cart/tray active, purchase affordances docked.
  shopping,

  /// Keyboard-bound or form-bound task (search, compose, Add Cash).
  focusedAction,

  /// Conversation / group / Susu context.
  social,

  /// Money is about to move or has moved; UI must stay calm.
  transactionalConfirmation;

  /// Calm modes forbid expressive motion and companion reactions.
  bool get isCalm =>
      this == AzSpatialMode.transactionalConfirmation ||
      this == AzSpatialMode.focusedAction;

  /// Modes where media or a sheet owns the whole viewport; the shell nav is
  /// expected to be hidden or collapsed.
  bool get isImmersive =>
      this == AzSpatialMode.fullScreenMedia || this == AzSpatialMode.detail;
}