// =============================================================================
// AZAMAN — HOME BALANCE CARD (PRODUCTION WRAPPER)
//
// The seam that puts the redesigned pair (BalanceCardPair) on the REAL
// Home deck: the typed valuation comes from the production adapter
// (balanceCardValuationProvider — authoritative providers only), the
// right-edge refresh slot is the live RateRefreshIndicator, and the
// deck's large-text affordance rides its familiar 48x48 overlay at the
// card's top-right, marking the SAME nested-gesture guard the frame
// reads so opening the detail sheet NEVER also flips the card.
//
// Nothing fixture lives here: every figure the card renders arrives
// through [BalanceCardValuation] and its documented sources. The old
// BalanceCardPreviewSection is gone from Home entirely (demo and
// non-demo alike).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/balance_card_valuation_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart';
import 'package:azaman/widgets/home/large_text_deck_sheet.dart'
    show LargeTextDeckButton;
import 'package:azaman/widgets/rate_refresh_indicator.dart';

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

  @override
  void dispose() {
    _flipGuard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valuation = ref.watch(balanceCardValuationProvider);
    final colors = ref.watch(themeProvider).colors;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        BalanceCardPair(
          key: const ValueKey('home-balance-card-pair'),
          valuation: valuation,
          colors: colors,
          trailingRefresh: const RateRefreshIndicator(),
          flipGuard: _flipGuard,
        ),
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
