import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/models/currency_model.dart'
    show currencyProvider, DisplayCurrency;
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/widgets/home/home_reminder_deck.dart';

// LARGE-TEXT DECK DETAIL SURFACE (PR #186 visual-accessibility review).
//
// The fixed-geometry deck clamps its faces at measured maxima (1.25x front
// / 1.3x visa / 1.8x reminder) because the card geometry is a hard budget:
// beyond those scales the faces overflow. That clamp is correct for the
// deck — but it must not be the END of the story for a low-vision user who
// selected 2.0x system text: a screen reader announcing "GH₵ 100.00" does
// not help someone who needs the amount VISIBLE at their chosen scale.
//
// This sheet is the deck's large-text alternative: an expanded, reflowed
// presentation of the SAME data at the user's FULL system text scale — no
// clamp, no FittedBox, no fixed height. It scrolls; text wraps. Whatever
// scale the OS asks for is the scale the amount renders at.
//
// Reachable through the expand affordance on the balance card face —
// present at EVERY scale (a low-vision user must be able to find it, not
// have it appear only once they are already struggling).

/// Opens the deck's large-text detail sheet at the user's REAL text
/// scale. [ambientScaler] is captured ABOVE the deck faces' clamps (see
/// `HologramBalanceCard`) — the sheet never renders at a clamped scale.
Future<void> showLargeTextDeckSheet(
  BuildContext context, {
  TextScaler? ambientScaler,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => MediaQuery(
      data: MediaQuery.of(sheetContext).copyWith(
        // Explicit, not inherited-by-accident: bottom-sheet routes
        // resolve their MediaQuery at the navigator, and the contract
        // here is the AMBIENT system scale, never a deck clamp.
        textScaler: ambientScaler ?? MediaQuery.textScalerOf(sheetContext),
      ),
      child: const LargeTextDeckSheet(),
    ),
  );
}

class LargeTextDeckSheet extends ConsumerWidget {
  const LargeTextDeckSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final azmId = (ref.watch(authProvider).user?.azamanId ?? '').trim();
    final balance = ref.watch(balanceDataProvider);
    final readiness = ref.watch(balanceReadinessProvider);
    final rate = ref.watch(oracleRateProvider);
    final pref = ref.watch(currencyProvider);
    final ghsFirst = pref == DisplayCurrency.ghs;

    // The same derivation contract as the balance card face: rate 0 is
    // "unavailable", never a live zero; an unresolved readiness is a
    // waiting state, never a fabricated 0.00.
    final rateUsable = rate > 0;
    final ghsValue = rateUsable ? balance.availableBalance * rate : 0.0;
    final primaryValue =
        ghsFirst && rateUsable ? ghsValue : balance.availableBalance;
    final primaryUnit = ghsFirst && rateUsable ? 'GH₵' : 'USDC';
    final secondaryLabel = rateUsable
        ? (ghsFirst
            ? AzMoney.usdcFirst(balance.availableBalance)
            : AzMoney.ghs(ghsValue))
        : null;

    // The deck's reminders, derived by the SAME shared function the
    // reminder deck renders from — one source of truth, no duplicated
    // logic.
    final reminders = homeReminderCards(ref, context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AzSpace.xl,
        vertical: AzSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Heading ──────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  'Deck details',
                  key: const ValueKey('deck-sheet-heading'),
                  style: AzText.titleXl.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('deck-sheet-close'),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
                icon: Icon(
                  HugeIconsStroke.cancel01,
                  size: 20,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AzSpace.lg),

          Flexible(
            // Reflowed, not fixed-height: the sheet grows with the text
            // scale and scrolls only when it must.
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Section(
                    colors: colors,
                    eyebrow: 'BALANCE',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The unit mark at full scale — the accessibility
                        // requirement covers the unit, not only the amount.
                        Text(
                          primaryUnit,
                          key: const ValueKey('deck-sheet-balance-unit'),
                          style: AzText.bodyL.copyWith(
                            color: colors.textTertiary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        // The amount at the user's FULL text scale.
                        // softWrap + unbounded lines: at 2.0x a long
                        // figure reflows instead of overflowing or being
                        // shrunk — the amount is never smaller than the
                        // user asked for.
                        Text(
                          readiness == BalanceReadiness.loaded
                              ? AzMoney.amount(primaryValue)
                              : '—',
                          key: const ValueKey('deck-sheet-balance-amount'),
                          softWrap: true,
                          maxLines: null,
                          semanticsLabel:
                              readiness == BalanceReadiness.loaded
                                  ? '$primaryUnit ${AzMoney.amount(primaryValue)} available'
                                  : 'Balance unavailable',
                          style: AzText.hero.copyWith(
                            color: readiness == BalanceReadiness.loaded
                                ? colors.textPrimary
                                : colors.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AzSpace.xs),
                        secondaryLabel == null
                            ? Text(
                                'FX rate unavailable',
                                key: const ValueKey(
                                    'deck-sheet-rate-unavailable'),
                                style: AzText.body.copyWith(
                                  color: colors.textTertiary,
                                ),
                              )
                            : Text(
                                secondaryLabel,
                                style: AzText.body.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                        const SizedBox(height: AzSpace.xxs),
                        Text(
                          rateUsable
                              ? '1 USDC = ${AzMoney.ghs(rate)}'
                              : 'FX rate unavailable',
                          key: const ValueKey('deck-sheet-rate'),
                          style: AzText.bodyS.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Section(
                    colors: colors,
                    eyebrow: 'CARD',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          azmId.isEmpty ? 'AZM-ID pending' : azmId,
                          style: AzText.body.copyWith(
                            color: colors.textSecondary,
                            fontFeatures: AzText.tabular,
                          ),
                        ),
                        const SizedBox(height: AzSpace.xxs),
                        Text(
                          '4\u2022\u2022\u2022 \u2022\u2022\u2022\u2022 \u2022\u2022\u2022\u2022 \u2022224',
                          style: AzText.body.copyWith(
                            color: colors.textSecondary,
                            letterSpacing: 1.2,
                            fontFeatures: AzText.tabular,
                          ),
                        ),
                        const SizedBox(height: AzSpace.xxs),
                        Text(
                          'Sample programme · Transfers disabled',
                          style: AzText.bodyS.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (reminders.isNotEmpty)
                    _Section(
                      colors: colors,
                      eyebrow: 'REMINDERS',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final card in reminders)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AzSpace.sm),
                              child: Text(
                                '${card.eyebrow} — ${card.title}\n${card.subtitle}',
                                style: AzText.body.copyWith(
                                  color: colors.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-scale section of the sheet: an ALL-CAPS eyebrow plus reflowed
/// content. Colors come from the sheet's palette — the section never
/// invents its own.
class _Section extends StatelessWidget {
  const _Section({
    required this.colors,
    required this.eyebrow,
    required this.child,
  });

  final AzamanColors colors;
  final String eyebrow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AzSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: AzText.eyebrow.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AzSpace.xs),
          child,
        ],
      ),
    );
  }
}

/// The deck's expand affordance — a compact, always-visible control that
/// opens the large-text detail sheet. [flipGuard] mirrors the retired
/// balance-visibility eye's nested-gesture contract: the flip card's raw
/// Listener still receives every pointer event, so the affordance marks
/// the guard on pointer-down and the flip listener cedes on pointer-up —
/// tapping the affordance opens the sheet WITHOUT also flipping the card.
class LargeTextDeckButton extends ConsumerWidget {
  const LargeTextDeckButton({
    super.key,
    this.flipGuard,
    this.ambientScaler,
  });

  final ValueNotifier<bool>? flipGuard;

  /// The system text scaler captured ABOVE the deck's clamp — the scale
  /// the sheet renders at. See [showLargeTextDeckSheet].
  final TextScaler? ambientScaler;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        if (flipGuard != null) flipGuard!.value = true;
      },
      // A 24px box, centered on the 16px glyph: the header row's height
      // is already 24px at the clamped scale (its own text), so this
      // box rides inside the row without adding a single pixel — but
      // the HAND gets a 24px target, not the glyph's 16.
      child: SizedBox(
        width: 24,
        height: 24,
        child: IconButton(
        key: const ValueKey('deck-large-text-button'),
        onPressed: () =>
            showLargeTextDeckSheet(context, ambientScaler: ambientScaler),
        tooltip: 'View deck details in large text',
        // GEOMETRY BUDGET: the balance card's face is a fixed 165px slot
        // with zero slack — the header row's height must stay exactly the
        // height its TEXT already gives it. A default 48px tap target
        // (or even 28px) inflates the row and overflows the face at the
        // 1.25x clamped scale. So: a 24px affordance, sitting neatly
        // inside the row's existing line box. The card itself remains
        // the large tap target; this button is a pointer, and the sheet
        // it opens is the accessibility surface.
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          minimumSize: const Size(24, 24),
          // shrinkWrap is the load-bearing half: without it the 48px
          // a11y tap-target floor inflates the button to 40px even at
          // density compact, the header row grows, and the 165px face
          // overflows at the clamped scale.
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
          icon: Icon(
            HugeIconsStroke.expand,
            size: 16,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
