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

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/models/currency_model.dart'
    show currencyProvider, DisplayCurrency;
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/widgets/fx_typing_dots.dart';
import 'package:azaman/widgets/holographic_surface.dart';
import 'package:azaman/widgets/rate_refresh_indicator.dart';
import 'package:azaman/widgets/odometer_number.dart';

class HologramBalanceCard extends ConsumerStatefulWidget {
  /// WALLET POUCH (2026-10-16): the balance-visibility eye is REMOVED from
  /// this card — the Home wallet pouch is now the default privacy state
  /// (the tucked deck covers this entire face), so the card's own toggle
  /// control is redundant here. `balanceVisibleProvider` itself is
  /// untouched: the separate P2P/dashboard visibility controls keep their
  /// behaviour. When this card is OUT of the pouch its content is always
  /// fully visible.
  const HologramBalanceCard({super.key, this.flipGuard});

  /// Retained for source compatibility; no longer consumed (the eye is
  /// gone). Will be removed with the next host cleanup.
  final ValueNotifier<bool>? flipGuard;

  @override
  ConsumerState<HologramBalanceCard> createState() =>
      _HologramBalanceCardState();
}

class _HologramBalanceCardState extends ConsumerState<HologramBalanceCard>
    with SingleTickerProviderStateMixin {
  /// The primary figure as of the previous build. Compared against the new one
  /// to derive the delta chip — a change is only interesting if we know what
  /// the value was a moment ago.
  double? _lastValue;

  /// The signed change to display, or null when there is nothing to show.
  double? _delta;

  /// GHANA-FIRST (2026-10-20): the delta chip is denominated in the
  /// PRIMARY display unit. A display-unit switch or an FX move changes
  /// the figure's MEANING, not the balance — the baseline re-anchors
  /// silently so a rate move can never masquerade as balance movement.
  String? _deltaSignature;

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
  void _trackDelta(double value, {required String signature}) {
    // GHANA-FIRST: when the display unit or the rate changes, the
    // baseline re-anchors WITHOUT a chip — an FX move or a unit switch is
    // not balance movement (only the first paint baselines silently by
    // design: the entrance animation belongs to the screen, not a change).
    if (_deltaSignature != null && _deltaSignature != signature) {
      _deltaSignature = signature;
      _lastValue = value;
      _delta = null;
      _deltaTimer?.cancel();
      return;
    }
    _deltaSignature = signature;
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
    // The user's PUBLIC AZM ID for the brand header (never the internal
    // database id) — empty/unprovisioned renders "AZM-ID pending".
    final azmId = (ref.watch(authProvider).user?.azamanId ?? '').trim();
    final balance = ref.watch(balanceDataProvider);
    // WORKSTREAM B — readiness is explicit: a default all-zero
    // BalanceData is NOT a confirmed balance. Until an authoritative
    // fetch (login payload or canonical refresh) completes, the primary
    // amount slot shows the waiting indicator and never prints a
    // fabricated "0.00". A genuine, loaded zero renders as 0.00.
    final balanceReadiness = ref.watch(balanceReadinessProvider);
    final rate = ref.watch(oracleRateProvider);
    // GHANA-FIRST (2026-10-20): the Home hero follows the user's global
    // display preference — GHS primary by default, USDC primary only when
    // deliberately selected. The USDC ledger balance remains the
    // financial authority; only the presentation order moves.
    final pref = ref.watch(currencyProvider);
    final ghsFirst = pref == DisplayCurrency.ghs;
    // §5 — rate 0 means "unavailable", never a live zero: the card must
    // not render GH₵ 0.00 over a funded USDC ledger, and must never show
    // "1 USDC = GH₵0.00" as if it were a valid rate. The real USDC ledger
    // balance stays visible and the cedi equivalent is named unavailable.
    final rateUsable = rate > 0;
    final ghsValue = rateUsable ? balance.availableBalance * rate : 0.0;
    final primaryValue = ghsFirst && rateUsable ? ghsValue : balance.availableBalance;
    final primaryLabel = ghsFirst && rateUsable
        ? AzMoney.ghs(primaryValue)
        : AzMoney.usdcFirst(primaryValue);
    // WORKSTREAM B: while the FX rate is unresolved (or zero), the cedi
    // equivalent is NOT a value — it is pending. The slot renders a
    // restrained three-dot waiting indicator instead of "unavailable"
    // copy; a real amount arrives the moment a usable rate does.
    final secondaryLabel = rateUsable
        ? (ghsFirst
            ? AzMoney.usdcFirst(balance.availableBalance)
            : AzMoney.ghs(ghsValue))
        : null;

    // Derived during build so the chip always reflects the freshest value.
    // `_trackDelta` schedules a timer but never calls setState synchronously,
    // so this is safe to run inside build. The signature carries rate
    // availability so a rate recovering (or dropping) re-baselines the
    // delta rather than masquerading as balance movement.
    // REVIEW §2 — the delta baseline is owned by AUTHORITATIVE data only.
    // While readiness is unresolved (the default BalanceData's zero fields
    // are a placeholder, not a fact) or failed (no data at all), no baseline
    // is kept: `_lastValue` resets so the first authoritative load re-anchors
    // silently. Without this gate, an unresolved default 0.00 followed by the
    // real balance would fabricate a false positive "+balance" delta chip.
    if (balanceReadiness == BalanceReadiness.loaded) {
      _trackDelta(primaryValue,
          signature:
              '${ghsFirst ? 'ghs' : 'usdc'}|${rateUsable ? rate.toStringAsFixed(4) : 'unavailable'}');
    } else {
      _lastValue = null;
      _delta = null;
      _deltaSignature = null;
      _deltaTimer?.cancel();
    }

    final chipDelta = _delta;

    // Reduced motion: the chip appears without sliding. `accessibleDuration`
    // collapses to zero, and a zero-duration AnimatedSlide is an instant
    // position change — nothing moves.
    final chipMotion = MotionTokens.accessibleDuration(
      context,
      MotionTokens.control,
    );

    return HolographicSurface(
      // RICHTEXT CORRECTIONS §2C: the base stays `colors.card` — the
      // palette's neutral near-black graphite — but the iridescence tint
      // is no longer the accent. Tinting the whole material with the
      // gold accent produced exactly the muddy olive/khaki wash the
      // screenshots flagged: a broad hue wash across the card reads as
      // dirt, not as depth. The tint is now `textSecondary` — the
      // palette's own neutral — so the holographic grammar survives
      // (material + ceiling light + specular band + metallic rim) while
      // the surface reads as cool neutral graphite. The accent appears
      // only as small highlights (the header unit mark), never as the
      // dominant fill.
      base: colors.card,
      tint: colors.textSecondary,
      // PARTICLE FIELD (2026-10-06 correction; §10.E audit 2026-10-13): the
      // balance card's sole touch response is the reactive particle field —
      // the moving white specular band is OFF here (it reads as a rendering
      // artefact on the graphite card, and two competing touch responses
      // weaken both). The field DEFORMS around the finger and settles through
      // the surface's existing spring. It is now fully STATIC while idle
      // (the ~9s ambient breathing clock was removed in the §10.E audit:
      // a restrained interaction response, not perpetual idle animation).
      // Palette: the app's own accent family, restrained in light mode by the
      // painter's theme gate — never a rainbow, never above the content.
      showSheen: false,
      showReactiveParticles: true,
      // PR #142 VISUAL PASS (2026-10-06) — the palette was [accent,
      // accentSecondary, glow], which for the gold family resolves to three
      // nearly identical golds: the user correctly read the whole field as
      // "one gold family". The field now pairs the live brand accent (the
      // warm anchor channel) with the painter's two deliberately varied
      // fixed hues — a cool cyan and a soft violet (the Antigravity
      // reference's cyan/violet/gold trio) — so the three channels are
      // perceptibly different when visible together while staying Azaman-
      // compatible.
      particleColors: [colors.accent, kParticleCoolCyan, kParticleSoftViolet],
      borderRadius: AzRadius.xl,
      // 2026-10-12 footprint pass: vertical padding md (was lg) — the
      // card is 165px tall now and the interior must fit the relocated
      // 32px visibility control in the header without squeezing the hero
      // figure.
      padding: const EdgeInsets.fromLTRB(
        AzSpace.xl,
        AzSpace.md,
        AzSpace.xl,
        AzSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ── Header: the brand row ───────────────────────────────────
          // WALLET POUCH follow-up (2026-10-16): the header is the CARD'S
          // OWN brand identity — the real Azaman logo, the card's name and
          // the user's public AZM ID anchored far right. This exact row is
          // what the deck's tucked pouch leaves exposed above its mouth
          // (the pouch covers from 56px down), so the tucked header and
          // the open card are the SAME physical object at two stages of
          // extraction — there is no second, separately painted header.
          // `AVAILABLE` is retired here: the label said nothing the card's
          // own brand doesn't, and the eyebrow style crowded the logo.
          // The AZM ID is the user's PUBLIC identifier (never the internal
          // database id); "AZM-ID pending" covers the not-yet-provisioned
          // state.
          Row(
            children: [
              Image.asset(
                'assets/images/azaman_logo.png',
                height: 18,
                filterQuality: FilterQuality.medium,
              ),
              const SizedBox(width: AzSpace.sm),
              Flexible(
                child: Text(
                  'Azaman Balance',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  azmId.isEmpty ? 'AZM-ID pending' : azmId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
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
                height: 14,
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
                                color: chipDelta >= 0
                                    ? colors.success
                                    : colors.danger,
                              ),
                              const SizedBox(width: AzSpace.xxs),
                              Text(
                                AzMoney.delta(
                                  chipDelta,
                                  // The chip is denominated in the PRIMARY
                                  // display unit — it follows the wheel.
                                  symbol: ghsFirst
                                      ? AzMoney.ghsSymbol
                                      : AzMoney.usdcSymbol,
                                ),
                                style: AzText.delta(
                                  chipDelta >= 0
                                      ? colors.success
                                      : colors.danger,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),

              // RICHTEXT CORRECTIONS §2A/§2B + UX-CORRECTION §11: the
              // hero is the AMOUNT. "USDC" is a small unit/label beside
              // it — no longer part of the same giant typographic block —
              // and the figure's weight drops from the near-black w800 to
              // the financially-authoritative-but-not-headline w600. The
              // odometer keeps rolling only the digits that changed; the
              // USDC mark is outside it, so it never re-rolls.
              //
              // UX-CORRECTION §11 — the hidden state PRESERVES this
              // structure: the USDC unit label stays, and the SAME amount
              // region shows the mask. The row is never replaced by a
              // bare dots Text — the layout geometry between visible and
              // hidden differs only in the masking itself.
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // WORKSTREAM B: the inline display-currency wheel is GONE
                  // from the Home card — this surface follows the user's
                  // GLOBAL display preference (see `ghsFirst` above); the
                  // preference is switched elsewhere, never here. The
                  // USDC ledger remains the financial authority either way.
                  //
                  // The wheel's chip was the only visible unit mark on the
                  // figure, so its removal left the hero unitless. The unit
                  // returns as a quiet label — never a control.
                  Padding(
                    padding: const EdgeInsets.only(right: AzSpace.sm),
                    child: Text(
                      ghsFirst ? 'GH₵' : 'USDC',
                      key: const ValueKey('home-balance-primary-unit'),
                      style: AzText.label.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  // OdometerNumber rolls ONLY the digits that changed.
                  // Tabular figures (inside AzText.money) are required —
                  // without them the figure shifts sideways mid-roll.
                  //
                  // `Flexible` matters: this Row is mainAxisSize.min, and a
                  // min-axis Flex lays INFLEXIBLE children out with UNBOUNDED
                  // width — so a bare odometer would render its full natural
                  // width (its own internal FittedBox never sees a bound) and
                  // the Row would overflow a narrow card (the flip-card
                  // back-face tests catch this at 280px). As a flex child the
                  // odometer receives the width left after the unit label,
                  // and its internal scale-down guard engages exactly as it
                  // did when it sat directly in the Column.
                  Flexible(
                    // WORKSTREAM B — unresolved/failed: the slot holds the
                    // three-dot waiting indicator instead of a fabricated
                    // 0.00 figure. The unit label stays (identity, not a
                    // value); the slot height matches the hero line so
                    // the card geometry never moves when the balance
                    // lands. A loaded value — a genuine 0.00 included —
                    // rolls through the odometer as before.
                    child: balanceReadiness == BalanceReadiness.loaded
                        ? OdometerNumber(
                            value: AzMoney.amount(primaryValue),
                            style: AzText.money(
                              colors.textPrimary,
                              size: AzText.sizeHero,
                              weight: FontWeight.w600,
                            ),
                            semanticsLabel: '$primaryLabel available',
                          )
                        : SizedBox(
                            height: AzText.sizeHero * 1.25,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Semantics(
                                label: balanceReadiness ==
                                        BalanceReadiness.failed
                                    ? 'Balance unavailable'
                                    : 'Balance loading',
                                liveRegion: true,
                                // REVIEW §2 — a terminal failure is a STABLE
                                // unavailable state (a quiet em-dash figure),
                                // never an endlessly active loading
                                // animation. The dots belong only to the
                                // unresolved (still loading) state.
                                child: balanceReadiness ==
                                        BalanceReadiness.failed
                                    ? Text(
                                        '—',
                                        key: const ValueKey(
                                            'home-balance-amount-unavailable'),
                                        style: AzText.money(
                                          colors.textPrimary,
                                          size: AzText.sizeHero,
                                          weight: FontWeight.w600,
                                        ),
                                      )
                                    : FxTypingDots(
                                        key: const ValueKey(
                                            'home-balance-amount-dots'),
                                        color: colors.textPrimary,
                                        dotSize: 6,
                                        rise: 4.5,
                                        dotGap: 5,
                                      ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),

              const SizedBox(height: AzSpace.xs),

              // Secondary figure: the other side of the pair, so the user
              // always knows what they actually hold. While FX is
              // unresolved the slot shows the three-dot waiting indicator
              // (WORKSTREAM B) — fixed at the bodyS line height so the card
              // never changes height when the rate lands.
              secondaryLabel == null
                  ? Semantics(
                      label: 'Exchange rate loading',
                      liveRegion: true,
                      child: SizedBox(
                        height: 12 * 1.45, // AzText.bodyS line height
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FxTypingDots(
                            key: const ValueKey('home-balance-fx-dots'),
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : Text(
                      secondaryLabel,
                      style:
                          AzText.bodyS.copyWith(color: colors.textSecondary),
                    ),

              // EXPERIENCE PASS §1: the live FX rate row is BACK ON the
              // card — "1 USDC = GH₵ …" plus the refresh/countdown
              // affordance. The rate is public market data, so it stays
              // rendered even while the balance itself is masked.
              const SizedBox(height: AzSpace.sm),
              // RICHTEXT CORRECTIONS §3: the rate row now uses the card's
              // FULL width — the conversion text anchors the left, the
              // refresh/countdown anchors the right, via a real
              // Row/Expanded contract rather than the indicator trailing
              // immediately after the caption. `Expanded` claims the
              // remaining width after the indicator's own intrinsic
              // size, so the indicator always lands flush with the
              // card's right edge regardless of how long the rate
              // caption is.
              Row(
                children: [
                  Expanded(
                    // Narrow-screen guard: on a ~320dp device the caption
                    // can exceed the space left after the indicator. The
                    // rate line is tertiary info — it scales down rather
                    // than overflowing.
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          rateUsable
                              ? '1 USDC = ${AzMoney.ghs(rate)}'
                              : 'FX rate unavailable',
                          key: rateUsable
                              ? null
                              : const ValueKey('hologram-rate-unavailable'),
                          style: AzText.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
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
