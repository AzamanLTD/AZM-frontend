// =============================================================================
// AZAMAN — VISA TRANSFER SEAM CONTROL  (Balance ↔ Visa card transfer)
//
// A circular transfer control anchored to the STABLE OVERLAP SEAM of the two
// Home cards: at rest the pull-reveal deck shows the balance card fully and
// the AZM Visa sample card peeking `restPeekPx` beneath it — the two faces
// overlap in one stable band ([cardHeight - peek, cardHeight]). This control
// pins to that band's centre on the deck's right edge, so it reads as part of
// the two-card composition, not as a floating FAB.
//
// On tap it hands off to the shell (Home owns the route), opening the
// full-height Card Transfer surface ([CardTransferScreen]).
//
// GEOMETRY: all constants come from the deck's own physics
// ([PullRevealPhysics.restPeekPx]) and the host's card height, so the anchor
// moves with the deck, never with a second opinion.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/home/pull_reveal_card_deck.dart'
    show PullRevealPhysics;

/// The circular control's footprint (>= the 44dp minimum touch target).
const double kSeamControlSize = 48;

/// Lays [child] (the pull-reveal deck) under the circular transfer control,
/// anchored to the two cards' stable overlap seam.
class VisaTransferSeamAnchor extends ConsumerWidget {
  const VisaTransferSeamAnchor({
    super.key,
    required this.child,
    required this.cardHeight,
    required this.onTransfer,
  });

  /// The deck (gesture surface). The control floats ABOVE it; the deck's own
  /// drag/tap grammar is untouched underneath.
  final Widget child;

  /// The deck's card height — the same `_cardHeight` the host passes to
  /// [PullRevealCardDeck], so the seam is computed from the real geometry.
  final double cardHeight;

  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    const peek = PullRevealPhysics.restPeekPx;
    // The stable overlap seam: at rest the under-card's top edge sits at
    // `cardHeight - peek` and the top card ends at `cardHeight`, so the two
    // faces share the band between them. The control's CENTRE rides the
    // band's centre line.
    final seamCentreY = cardHeight - peek / 2;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: AzSpace.md,
          top: seamCentreY - kSeamControlSize / 2,
          child: _SeamControlButton(onTransfer: onTransfer, colors: colors),
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
            // The card language: a raised dark/gold-accent chip that reads
            // as a control pinned to BOTH physical cards, not page chrome.
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
          child: Icon(
            Icons.swap_vert,
            size: 22,
            color: colors.accent,
          ),
        ),
      ),
    );
  }
}
