// =============================================================================
// HOLOGRAM BALANCE CARD — the front face, on the hero substrate
//
// The app's most-seen surface, now rendered on HolographicSurface (TASK-009c):
// a fixed iridescent material whose specular band follows the pointer. The
// figure rolls per-digit via OdometerNumber (TASK-009b), and a rate or balance
// change surfaces as a delta chip that fades in above the figure and out after
// ~1.8s — the number itself never moves. The chip obeys the visibility mask:
// while the balance is hidden it is not rendered, so a rate or balance refresh
// cannot leak how much the balance just changed.
//
// EXPERIENCE PASS §1: the Home hero is USDC-FIRST — the principal figure
// reads "USDC 123.45" (AzMoney.usdcFirst), with the GHS equivalent as the
// smaller secondary figure. The truncated wallet-id line is GONE from the
// front face (it served no purpose and read as "1" on demo accounts); the
// underlying user/account data is untouched elsewhere. The live FX rate
// row + RateRefreshIndicator are BACK ON the card (they belong here, not
// in a separate below-the-fold section). The balance-visibility mask driven
// by balanceVisibleProvider is preserved, as are the odometer figure, the
// delta chip and the flip-to-breakdown behaviour.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/widgets/holographic_surface.dart';
import 'package:azaman/widgets/rate_refresh_indicator.dart';
import 'package:azaman/widgets/odometer_number.dart';

class HologramBalanceCard extends ConsumerStatefulWidget {
  const HologramBalanceCard({super.key});

  @override
  ConsumerState<HologramBalanceCard> createState() =>
      _HologramBalanceCardState();
}

class _HologramBalanceCardState extends ConsumerState<HologramBalanceCard> {
  /// The primary figure as of the previous build. Compared against the new one
  /// to derive the delta chip — a change is only interesting if we know what
  /// the value was a moment ago.
  double? _lastValue;

  /// The signed change to display, or null when there is nothing to show.
  double? _delta;

  /// Clears [_delta] after it has been on screen long enough to read.
  Timer? _deltaTimer;

  @override
  void dispose() {
    _deltaTimer?.cancel();
    super.dispose();
  }

  /// Called during build (before the figure is painted) so the delta is always
  /// computed from the freshest value. Deliberately NOT in `didUpdateWidget`:
  /// the value comes from a provider, so there is no widget-level update hook.
  void _trackDelta(double value) {
    // EXPERIENCE PASS §1: the hero's unit is fixed (USDC-first), so there is
    // no currency-toggle re-baseline path any more — only the first paint
    // baselines silently (the mount animation belongs to the screen's
    // entrance choreography, not to a value change).
    final previous = _lastValue;
    if (previous == null || previous == value) {
      _lastValue = value;
      return;
    }

    _lastValue = value;
    final change = value - previous;

    // A change below half a pesewa is rounding noise, not information. Showing
    // a chip for it would make the card twitch on every refresh.
    if (change.abs() < 0.005) return;

    _delta = change;
    _deltaTimer?.cancel();
    _deltaTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _delta = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final balance = ref.watch(balanceDataProvider);
    final isVisible = ref.watch(balanceVisibleProvider);
    final rate = ref.watch(oracleRateProvider);
    // EXPERIENCE PASS §1: the Home hero is ALWAYS USDC-first. The
    // DisplayCurrency toggle infrastructure survives for other surfaces,
    // but this presentation is fixed: USDC is the principal, GHS the
    // secondary equivalent.
    final ghsValue = balance.availableBalance * rate;
    final primaryValue = balance.availableBalance;
    final primaryLabel = AzMoney.usdcFirst(primaryValue);
    final secondaryLabel = AzMoney.ghs(ghsValue);
    final secondaryMask = '•••• ${AzMoney.ghsSymbol}';

    // Derived during build so the chip always reflects the freshest value.
    // `_trackDelta` schedules a timer but never calls setState synchronously,
    // so this is safe to run inside build.
    _trackDelta(primaryValue);

    // The chip announces a change in the balance, so it must obey the same
    // visibility mask as the figure itself — a hidden balance must not leak
    // how much it just moved. Tracking continues while hidden (the baseline
    // stays honest); only the rendering is suppressed.
    final chipDelta = isVisible ? _delta : null;

    // Reduced motion: the chip appears without sliding. `accessibleDuration`
    // collapses to zero, and a zero-duration AnimatedSlide is an instant
    // position change — nothing moves.
    final chipMotion = MotionTokens.accessibleDuration(
      context,
      MotionTokens.control,
    );

    return HolographicSurface(
      // `card` is the material's base colour; `accent` drives the iridescence and
      // the specular band. This is the ONE full-intensity holographic surface on
      // Home — every other surface is Level 2 or 3. Premium is scarcity.
      base: colors.card,
      tint: colors.accent,
      borderRadius: AzRadius.xl,
      padding: const EdgeInsets.fromLTRB(
        AzSpace.xl,
        AzSpace.lg,
        AzSpace.xl,
        AzSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ── Header: label + visibility state ──────────────────────────
          Row(
            children: [
              Icon(HugeIconsSolid.wallet01, size: 14, color: colors.textTertiary),
              const SizedBox(width: AzSpace.sm),
              Text(
                'AVAILABLE',
                style: AzText.eyebrow.copyWith(color: colors.textTertiary),
              ),
              const Spacer(),
              // EXPERIENCE PASS §1: the 'USDC' header chip is gone — the
              // principal figure itself now reads "USDC 123.45", so a second
              // unit label above it would be a duplicate. Only the hidden
              // state keeps a visible affordance.
              if (!isVisible)
                Icon(
                  HugeIconsSolid.viewOff,
                  size: 13,
                  color: colors.textTertiary,
                ),
            ],
          ),

          // ── The figure ────────────────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The delta chip sits ABOVE the figure and fades in/out, so the
              // number itself never moves to make room for it.
              SizedBox(
                height: 18,
                child: AnimatedOpacity(
                  opacity: chipDelta == null ? 0.0 : 1.0,
                  duration: chipMotion,
                  curve: MotionTokens.enter,
                  child: AnimatedSlide(
                    offset: chipDelta == null
                        ? const Offset(0, 0.25)
                        : Offset.zero,
                    duration: chipMotion,
                    curve: MotionTokens.enter,
                    child: chipDelta == null
                        ? const SizedBox.shrink()
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                chipDelta >= 0
                                    ? HugeIconsSolid.arrowUp01
                                    : HugeIconsSolid.arrowDown01,
                                size: 12,
                                color: chipDelta >= 0 ? colors.success : colors.danger,
                              ),
                              const SizedBox(width: AzSpace.xxs),
                              Text(
                                AzMoney.delta(
                                  chipDelta,
                                  symbol: AzMoney.usdcSymbol,
                                ),
                                style: AzText.delta(
                                  chipDelta >= 0 ? colors.success : colors.danger,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),

              if (isVisible)
                // OdometerNumber rolls ONLY the digits that changed. Tabular
                // figures (inside AzText.money) are required — without them the
                // figure shifts sideways mid-roll.
                OdometerNumber(
                  value: primaryLabel,
                  style: AzText.money(
                    colors.textPrimary,
                    size: AzText.sizeHero,
                  ),
                  semanticsLabel: '$primaryLabel available',
                )
              else
                Text(
                  '••••••',
                  style: AzText.money(
                    colors.textPrimary,
                    size: AzText.sizeHero,
                  ),
                ),

              const SizedBox(height: AzSpace.xs),

              // Secondary figure: the other side of the pair, so the user
              // always knows what they actually hold.
              Text(
                isVisible ? secondaryLabel : secondaryMask,
                style: AzText.bodyS.copyWith(color: colors.textSecondary),
              ),

              // EXPERIENCE PASS §1: the live FX rate row is BACK ON the
              // card — "1 USDC = GH₵ …" plus the refresh/countdown
              // affordance. The rate is public market data, so it stays
              // rendered even while the balance itself is masked.
              const SizedBox(height: AzSpace.sm),
              const SizedBox(height: AzSpace.sm),
              Row(
                children: [
                  // Narrow-screen guard: on a ~320dp device the caption +
                  // indicator can exceed the card's inner width. The rate
                  // line is tertiary info — it scales down rather than
                  // overflowing.
                  Flexible(
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '1 USDC = ${AzMoney.ghs(rate)}',
                        style:
                            AzText.caption.copyWith(color: colors.textTertiary),
                      ),
                    ),
                  ),
                  const SizedBox(width: AzSpace.xs),
                  const RateRefreshIndicator(),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
