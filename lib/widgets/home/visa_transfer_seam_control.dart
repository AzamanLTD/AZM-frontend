// =============================================================================
// AZAMAN — VISA TRANSFER SEAM CONTROL  (Balance ↔ Visa card transfer)
//
// The tucked wallet pouch is the only pose with a free, unclaimed surface:
// the pocket's front face. The two exposed header bands (the Visa strip
// and the balance card's brand row) are the deck's established selection
// gestures — the control must never cover them, their marks, or their
// taps. The control therefore rides as a CLASP on the pocket mouth, fully
// on the absorbing pouch surface, and exists only while the deck is
// tucked: once a card is out, the card's own gestures own the surface.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/home/wallet_card_deck.dart'
    show WalletCardDeckState;

/// The circular control's footprint (>= the 44dp minimum touch target).
const double kSeamControlSize = 48;

/// The tucked pose's pocket mouth (stack coordinates): the bottom edge of
/// the balance card's exposed brand header, where the pouch begins.
const double kPocketMouthY =
    WalletCardDeckState.visaHeaderTop +
    WalletCardDeckState.visaPeek +
    WalletCardDeckState.balanceHeaderBand;

/// The clasp's vertical centre: fully on the pocket front, tangent to the
/// balance header's bottom edge, clear of the mouth curve's dip.
const double kPocketClaspCentreY = kPocketMouthY + kSeamControlSize / 2;

/// Places the transfer control over the current wallet-pouch deck using the
/// deck's public geometry constants.
class VisaTransferSeamAnchor extends ConsumerWidget {
  const VisaTransferSeamAnchor({
    super.key,
    required this.child,
    required this.onTransfer,
    this.visible = true,
  });

  /// The real wallet deck (gesture surface), underneath the control.
  final Widget child;

  final VoidCallback onTransfer;

  /// The clasp exists only in the tucked pose (see the header comment).
  /// Hosts pass the deck's live state; the default keeps stand-alone
  /// test mounts simple.
  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (visible)
          Positioned(
            left: 0,
            right: 0,
            top: kPocketClaspCentreY - kSeamControlSize / 2,
            child: Center(
              child: _SeamControlButton(onTransfer: onTransfer, colors: colors),
            ),
          ),
      ],
    );
  }
}

class _SeamControlButton extends StatelessWidget {
  const _SeamControlButton({required this.onTransfer, required this.colors});

  final VoidCallback onTransfer;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Transfer between Balance and Visa card',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AzamanHaptics.selection();
          onTransfer();
        },
        child: Container(
          key: const ValueKey('visa-transfer-seam-control'),
          width: kSeamControlSize,
          height: kSeamControlSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.card,
            border: Border.all(color: colors.accent.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(Icons.swap_vert, size: 22, color: colors.accent),
        ),
      ),
    );
  }
}
