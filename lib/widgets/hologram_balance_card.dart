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
// Existing behaviours preserved on top of the rebuild (spec-silent, see the
// 009d sign-off): the DisplayCurrency toggle (GHS-first vs USDC-first), the
// oracle rate line with RateRefreshIndicator, the truncated wallet-id line,
// and the balance-visibility mask driven by balanceVisibleProvider.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/widgets/holographic_surface.dart';
import 'package:azaman/widgets/odometer_number.dart';
import 'package:azaman/widgets/rate_refresh_indicator.dart';

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

  /// Which currency was primary at the last track. A currency-toggle changes
  /// the figure's *meaning*, not its *value* — switching must re-baseline
  /// silently instead of firing a bogus "+GH₵ …" chip.
  bool? _lastGhsFirst;

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
  void _trackDelta(double value, {required bool ghsFirst}) {
    if (_lastGhsFirst != ghsFirst) {
      // Currency switched (or first paint) — re-baseline without a chip. The
      // mount animation belongs to the screen's entrance choreography.
      _lastValue = value;
      _lastGhsFirst = ghsFirst;
      if (_delta != null) {
        _delta = null;
        _deltaTimer?.cancel();
      }
      return;
    }
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
    final user = ref.watch(authProvider).user;
    final ghsFirst = ref.watch(currencyProvider) == DisplayCurrency.ghs;

    final ghsValue = balance.availableBalance * rate;
    final primaryValue = ghsFirst ? ghsValue : balance.availableBalance;
    final primaryLabel =
        ghsFirst ? AzMoney.ghs(primaryValue) : AzMoney.usdc(primaryValue);
    final secondaryLabel = ghsFirst
        ? AzMoney.usdc(balance.availableBalance)
        : AzMoney.ghs(ghsValue);
    final secondaryMask =
        '•••• ${ghsFirst ? AzMoney.usdcSymbol : AzMoney.ghsSymbol}';

    // Derived during build so the chip always reflects the freshest value.
    // `_trackDelta` schedules a timer but never calls setState synchronously,
    // so this is safe to run inside build.
    _trackDelta(primaryValue, ghsFirst: ghsFirst);

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

    final uid = user?.id ?? '';
    final truncatedId = uid.length > 6
        ? '\u00b7\u00b7 ${uid.substring(uid.length - 4)}'
        : uid;

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
              if (isVisible)
                Text(
                  'USDC',
                  style: AzText.caption.copyWith(color: colors.textTertiary),
                )
              else
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
              // The wallet id — the user's own account fingerprint, carried
              // over from the previous card so the rebuild loses no information.
              if (truncatedId.isNotEmpty) ...[
                Text(
                  truncatedId,
                  style: AzText.label.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AzSpace.xs),
              ],

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
                                  symbol: ghsFirst
                                      ? AzMoney.ghsSymbol
                                      : AzMoney.usdcSymbol,
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

              const SizedBox(height: AzSpace.xs),

              // The live oracle rate + its refresh affordance, carried over
              // from the previous card.
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '1 USDC = GH₵ ${rate.toStringAsFixed(2)}',
                      overflow: TextOverflow.ellipsis,
                      style:
                          AzText.caption.copyWith(color: colors.textTertiary),
                    ),
                  ),
                  const SizedBox(width: AzSpace.sm),
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
