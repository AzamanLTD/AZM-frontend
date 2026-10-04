// =============================================================================
// AZAMAN — EXPERIENCE VOCABULARY: INTENT
//
// What the user is trying to *do*. Rails, menus and CTAs are built from
// intents so that labels, icons and haptics are consistent app-wide.
// =============================================================================

import 'package:azaman/utils/azaman_haptics.dart';

/// A user intent. Surfaces offer intents; gateways commit them.
enum AzIntent {
  discover,
  search,
  compare,
  save,
  open,
  book,
  order,
  pay,
  chat,
  join,
  react,
  reply,
  share,
  report,
  mute,
  block,
}

extension AzIntentPresentation on AzIntent {
  /// Destructive intents render in the warning colour and are confirmed.
  bool get isDestructive => this == AzIntent.report || this == AzIntent.block;

  /// Intents that move money. Screens hosting them are
  /// [AzSpatialMode.transactionalConfirmation] once committed.
  bool get movesMoney =>
      this == AzIntent.pay || this == AzIntent.order || this == AzIntent.book;

  /// Haptic that fires when the intent *commits* (not when it is offered).
  /// Routes through [AzamanHaptics] so the sensory preference is honoured.
  Future<void> commitHaptic() => switch (this) {
        AzIntent.pay || AzIntent.order || AzIntent.book =>
          AzamanHaptics.commit(),
        AzIntent.save || AzIntent.react || AzIntent.mute =>
          AzamanHaptics.selection(),
        AzIntent.report || AzIntent.block => AzamanHaptics.warn(),
        _ => AzamanHaptics.selection(),
      };
}