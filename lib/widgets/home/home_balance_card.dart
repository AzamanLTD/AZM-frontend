// =============================================================================
// AZAMAN — HOME BALANCE CARD (PRODUCTION WRAPPER)
//
// The seam that puts the redesigned pair (BalanceCardPair) on the REAL
// Home deck: the typed valuation comes from the production adapter
// (balanceCardValuationProvider — authoritative providers only), and
// the deck's large-text affordance rides its familiar 48x48 overlay at
// the card's top-right, marking the SAME nested-gesture guard the frame
// reads so opening the detail sheet NEVER also flips the card. There is
// deliberately no separate right-edge refresh slot: the front face's
// single left-side rate cluster is the ONE status surface.
//
// Nothing fixture lives here: every figure the card renders arrives
// through [BalanceCardValuation] and its documented sources. The old
// BalanceCardPreviewSection is gone from Home entirely (demo and
// non-demo alike).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/balance_card_valuation_provider.dart';
import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart';
import 'package:azaman/widgets/home/balance_card_selector.dart';
import 'package:azaman/widgets/home/large_text_deck_sheet.dart'
    show LargeTextDeckButton;
import 'package:azaman/widgets/home/money_lock_blocked_feedback.dart';
import 'package:azaman/widgets/home/money_privacy.dart';

class HomeBalanceCard extends ConsumerStatefulWidget {
  const HomeBalanceCard({super.key});

  @override
  ConsumerState<HomeBalanceCard> createState() => _HomeBalanceCardState();
}

class _HomeBalanceCardState extends ConsumerState<HomeBalanceCard> {
  // ONE guard shared by the pair's frame listener and the large-text
  // overlay: a tap on the affordance marks it, the frame sees the mark on
  // pointer-up and cedes the gesture — the card does not flip.
  final ValueNotifier<bool> _flipGuard = ValueNotifier<bool>(false);

  /// The card's own key: the selector needs the card's REAL on-screen rect so
  /// the lift begins exactly where the card sits in the wallet.
  final GlobalKey _cardKey = GlobalKey(debugLabel: 'home-balance-card');

  @override
  void dispose() {
    _flipGuard.dispose();
    super.dispose();
  }

  /// Opens the wallet selector from the card's current position. The rect is
  /// measured from the live render box (never guessed), so the lift starts
  /// at the card the user actually pressed.
  Future<void> _openSelector() async {
    final theme = ref.read(themeProvider);
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    final size = MediaQuery.sizeOf(context);
    final fallback = Rect.fromLTWH(
      16,
      size.height * 0.34,
      size.width - 32,
      BalanceCardGeometry.height,
    );
    final rect = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : fallback;
    await showBalanceCardSelector(
      context,
      current: theme.cardVariant,
      originRect: rect,
    );
  }

  @override
  Widget build(BuildContext context) {
    final valuation = ref.watch(balanceCardValuationProvider);
    final theme = ref.watch(themeProvider);
    // THE GATE, INSIDE THE CARD (owner requirement 2026-10-30): the deck stays
    // exactly where it is — same pouch, same artwork, same 180dp geometry.
    // What locks is the money: the figures mask, the flip and the selector
    // refuse, and the large-text sheet (which would print the balance) is not
    // mounted at all.
    final canViewMoney = ref.watch(moneyAccessProvider).canViewMoney;
    final visibility = canViewMoney
        ? MoneyVisibility.visible
        : MoneyVisibility.redacted;
    final colors = theme.colors;
    final variant = theme.cardVariant;

    return Stack(
      key: _cardKey,
      fit: StackFit.passthrough,
      children: [
        BalanceCardPair(
          key: const ValueKey('home-balance-card-pair'),
          valuation: valuation,
          colors: colors,
          variant: variant,
          flipGuard: _flipGuard,
          onCardLongPress: canViewMoney ? _openSelector : null,
          visibility: visibility,
          onBlockedInteraction: () {
            blockedMoneyAccessFeedback(ref);
            showMoneyLockedHint(context);
          },
        ),
        if (canViewMoney)
          // LARGE-TEXT HIT TARGET — the same card-level 48x48 overlay the
          // retired FlippableBalanceCard hosted: the interactive +
          // semantic target is this transparent overlay, topmost, so a
          // near-miss tap opens the sheet instead of flipping the card.
          Positioned(
            top: 12,
            right: 2,
            width: LargeTextDeckButton.hitExtent,
            height: LargeTextDeckButton.hitExtent,
            child: LargeTextDeckButton(
              flipGuard: _flipGuard,
              ambientScaler: MediaQuery.textScalerOf(context),
            ),
          ),
      ],
    );
  }
}
