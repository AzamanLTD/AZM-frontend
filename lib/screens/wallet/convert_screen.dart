import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/currency_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/pull_down_dismissible_surface.dart';

/// ============================================================================
/// CONVERT — an honest shell, not a fake converter.
///
/// CAPABILITY GATE: the backend currently has NO server-authoritative
/// conversion quote/accept contract (no swap/convert route, no separate
/// native GHS wallet balance — USDC is the only settled ledger currency;
/// GHS is a display/quote currency). This screen therefore does not and
/// cannot execute a conversion. When the backend ships a real contract:
///   1. flip [kConvertExecutionSupported] to true,
///   2. wire the quote/accept flow against the verified canonical
///      endpoint only — never a guessed one,
///   3. the estimate section stays a display-only aid unless the server
///      returns a binding quote with expiry.
/// The shell, asset rows and estimate rendering below need no rework.
/// ============================================================================
const bool kConvertExecutionSupported = false;

/// The single capability gate the launcher and any future deep link can
/// read to decide how to present Convert. Deliberately not derived from
/// the FX rate, the display preference or any backend field NAME — only
/// a verified conversion contract may flip it.
bool get convertExecutionAvailable => kConvertExecutionSupported;

/// The wall clock this screen's freshness verdicts derive from.
/// Production uses the device clock. Tests substitute a controllable
/// clock so a rate can be made to AGE (and expire) deterministically —
/// the same seam pattern as debugDefaultTargetPlatformOverride. Every
/// freshness computation on this screen goes through it: the estimate
/// verdict, the staleness re-arm and the disclosed ages.
DateTime Function() kConvertNow = () => DateTime.now().toUtc();

/// The Convert screen shell.
///
/// Truthful by construction:
/// • the live FX rate, when usable, is shown ONLY as a NONBINDING
///   estimate — labeled as such, never as a quote or a settled value;
/// • the execution CTA is disabled and mutates nothing while
///   [kConvertExecutionSupported] is false — no provider calls, no
///   optimistic state, no fabricated success;
/// • currency facts come from the canonical catalog/FX source only
///   ([fxRateProvider]); no competing preference path is built here.
///   Global display preference (GHS-first) and executing a conversion
///   remain different concepts — this screen never writes the
///   preference, and the preference never debits a wallet.
class ConvertScreen extends ConsumerStatefulWidget {
  const ConvertScreen({super.key});

  @override
  ConsumerState<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends ConsumerState<ConvertScreen> {
  // Amount entry is LOCAL, uncommitted state — typing never touches a
  // provider and never mutates anything.
  final TextEditingController _amountCtrl = TextEditingController();

  // FRESHNESS EDGE — a nonbinding estimate must not keep LOOKING fresh
  // after its observation window has lapsed. The estimate panel's
  // verdict is computed against the CURRENT clock, but nothing rebuilds
  // while the screen sits open, so a screen that outlives its rate's
  // freshness window would keep rendering the live panel. This one-shot
  // timer fires at the snapshot's own staleAt (+50ms scheduling slack)
  // and forces a re-evaluation, flipping the panel to the honest
  // unavailable state at the moment the observation expires. No polling:
  // exactly one armed timer per usable snapshot; disarmed whenever there
  // is nothing left to expire; cancelled on dispose.
  Timer? _stalenessTimer;
  DateTime? _stalenessArmedFor;

  // DIRECTION (Workstream D) — the Binance-style From/To presentation is
  // still a DISPLAY-ONLY estimate tool. Forward (default) reads as
  // 'this many USDC ≈ that many GHS'; reversed reads as 'this many GHS
  // ≈ that many USDC'. Switching direction NEVER relabels digits (the
  // send-screen principle: a typed figure is never silently re-denominated),
  // so the amount field CLEARS on switch — an empty field is honest, a
  // relabelled one is a lie. Nothing about either direction implies a
  // conversion, reservation or balance change: the gate below is what
  // keeps that truthful.
  bool _reversed = false;

  void _switchDirection() {
    setState(() {
      _reversed = !_reversed;
      _amountCtrl.clear();
    });
  }

  @override
  void dispose() {
    _stalenessTimer?.cancel();
    _amountCtrl.dispose();
    super.dispose();
  }

  /// Arms/keeps the one-shot staleness re-check for [snap]. Idempotent
  /// per distinct expiry moment so rebuilds never stack timers.
  void _armStalenessRecheck(FxRateSnapshot? snap) {
    final staleAt = snap?.staleAt;
    if (snap == null || staleAt == null || !snap.isUsableAt(kConvertNow())) {
      _stalenessTimer?.cancel();
      _stalenessTimer = null;
      _stalenessArmedFor = null;
      return;
    }
    if (_stalenessTimer != null && _stalenessArmedFor == staleAt) return;
    _stalenessTimer?.cancel();
    _stalenessArmedFor = staleAt;
    final delay =
        staleAt.difference(kConvertNow()) + const Duration(milliseconds: 50);
    _stalenessTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _stalenessArmedFor = null;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final snapshot = ref.watch(fxRateProvider);

    _armStalenessRecheck(snapshot.valueOrNull);

    return PullDownDismissibleSurface(
      // §6: Convert is a transient surface like Receive — a committed
      // downward pull closes it. Nothing is pending on this screen, so
      // the pull is always accepted.
      onDismiss: () => Navigator.of(context).maybePop(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: colors.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          centerTitle: true,
          // WORKSTREAM D SURFACE GRAMMAR — the same X-close top-left as
          // the Send/Withdraw surfaces: one explicit close affordance,
          // no back arrow, matching the launcher grammar this surface
          // family shares. Nothing is in flight here, so it always pops.
          leading: IconButton(
            key: const Key('convert_close'),
            icon: Icon(Icons.close, color: colors.onSurface, size: 20),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            'Convert',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              _FromPanel(
                controller: _amountCtrl,
                reversed: _reversed,
                onSwitchDirection: _switchDirection,
              ),
              const SizedBox(height: 18),
              _ToPanel(
                snapshot: snapshot.valueOrNull,
                loading: snapshot.isLoading,
                controller: _amountCtrl,
                reversed: _reversed,
              ),
              const SizedBox(height: 18),
              _ExecutionGate(
                colors: colors,
                supported: convertExecutionAvailable,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// §D — FROM PANEL. The amount side of the pair. Ledger truth drives
// what it can honestly say: USDC is the settled currency, so the
// balance line exists ONLY when the canonical balance read has actually
// loaded (never a fabricated figure) and ONLY on the USDC side — GHS
// has no balance to disclose (it is a display/quote currency).
class _FromPanel extends StatelessWidget {
  const _FromPanel({
    required this.controller,
    required this.reversed,
    required this.onSwitchDirection,
  });

  final TextEditingController controller;
  final bool reversed;
  final VoidCallback onSwitchDirection;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return _Panel(
      panelKey: const Key('convert_from_panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _assetHeading(
                  colors,
                  code: reversed ? 'GHS' : 'USDC',
                  label: reversed ? 'Display currency' : 'Settled balance',
                ),
              ),
              _DirectionSwitchButton(
                reversed: reversed,
                onPressed: onSwitchDirection,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Amount (${reversed ? 'GHS' : 'USDC'})',
                  key: const Key('convert_amount_label'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              // IMAGE-A FIDELITY — the 'Max' quick-fill from the Buy/Sell
              // reference. It appears ONLY in the forward direction when
              // the canonical balance read has actually loaded; the fill
              // is the raw available figure (no invented buffer math,
              // no rounding games — the estimate above stays
              // display-only and the execution gate stays closed).
              if (!reversed) _MaxFillButton(controller: controller),
            ],
          ),
          const SizedBox(height: 8),
          _AmountField(controller: controller, reversed: reversed),
          // BALANCE INFO — only where the contract supports it: the
          // canonical USDC balance read has loaded AND the From asset is
          // the settled currency. Any other state omits the line rather
          // than inventing a number.
          if (!reversed) const _UsdcBalanceLine(),
        ],
      ),
    );
  }

  Widget _assetHeading(
    ColorScheme colors, {
    required String code,
    required String label,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          code,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: colors.onSurface,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The direction switch. Subtle by design: a 180° icon rotation over
/// 220ms — under reduced motion (`disableAnimations`) the framework
/// snaps it with no transit. It NEVER implies money moved: switching
/// clears the amount (digits are never relabelled) and nothing else on
/// the screen carries a value across the switch.
class _DirectionSwitchButton extends StatelessWidget {
  const _DirectionSwitchButton({
    required this.reversed,
    required this.onPressed,
  });

  final bool reversed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: const Key('convert_direction_switch'),
      button: true,
      tooltip: 'Switch conversion direction. Display only — nothing converts.',
      child: IconButton(
        onPressed: onPressed,
        icon: AnimatedRotation(
          turns: reversed ? 0.5 : 0.0,
          duration: const Duration(milliseconds: 220),
          child: Icon(
            Icons.swap_vert,
            color: colors.onSurfaceVariant,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// The settled USDC balance disclosure, read from the canonical balance
/// providers the Home balance card uses. Rendered ONLY when the
/// canonical read has loaded and the figure is a finite non-negative
/// number; every other state is an honest omission.
class _UsdcBalanceLine extends ConsumerWidget {
  const _UsdcBalanceLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readiness = ref.watch(balanceReadinessProvider);
    if (readiness != BalanceReadiness.loaded) {
      return const SizedBox.shrink(key: Key('convert_from_balance_absent'));
    }
    final balance = ref.watch(balanceDataProvider).availableBalance;
    if (!balance.isFinite || balance < 0) {
      return const SizedBox.shrink(key: Key('convert_from_balance_absent'));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'USDC balance ${balance.toStringAsFixed(2)}',
        key: const Key('convert_from_balance'),
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// IMAGE-A FIDELITY — 'Max'. Fills the From field with the FULL
/// available USDC balance straight from the canonical read. The control
/// only renders when that read has loaded and is a sane non-negative
/// figure; with no honest number to fill there is no button at all
/// (never a fabricated figure). Filling is a pure text edit — it does
/// not touch money, and the gate below still owns what the screen can
/// actually do.
class _MaxFillButton extends ConsumerWidget {
  const _MaxFillButton({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readiness = ref.watch(balanceReadinessProvider);
    if (readiness != BalanceReadiness.loaded) {
      return const SizedBox.shrink(key: Key('convert_max_absent'));
    }
    final balance = ref.watch(balanceDataProvider).availableBalance;
    if (!balance.isFinite || balance <= 0) {
      return const SizedBox.shrink(key: Key('convert_max_absent'));
    }
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      key: const Key('convert_max'),
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        // Trim sub-pesewa dust that the display does not carry — the
        // field holds the same figure the balance line shows.
        final shown = balance.toStringAsFixed(2);
        controller.value = TextEditingValue(
          text: shown,
          selection: TextSelection.collapsed(offset: shown.length),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'Max',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: colors.primary,
          ),
        ),
      ),
    );
  }
}

/// Amount entry with the money contract (numeric family, ≈/₵ glyph
/// source) and the DISPLAY-ONLY arithmetic guards. Kept as its own
/// widget so the From panel reads as a composition, not a monolith.
class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, required this.reversed});

  final TextEditingController controller;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextField(
      key: const Key('convert_amount_field'),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        // DOCUMENTED BOUND — 16 characters caps the field at
        // 9999999999999.99: sensible for a wallet, and the figure times
        // any realistic rate can never overflow a double. Programmatic
        // controller writes bypass formatters, which is why the
        // isFinite guards in the estimate panel are also enforced.
        LengthLimitingTextInputFormatter(16),
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      style: AzText.money(
        colors.onSurface,
        size: 20,
        weight: FontWeight.w800,
        tracking: 0,
      ),
      decoration: InputDecoration(
        hintText: reversed ? '0.00 GHS' : '0.00',
        hintStyle: AzText.money(
          colors.onSurfaceVariant,
          size: 20,
          weight: FontWeight.w800,
          tracking: 0,
        ),
        suffixText: reversed ? 'GHS' : 'USDC',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
      ),
    );
  }
}

// §D — TO PANEL: the estimated-receive side of the pair plus the truthful
// rate/freshness strip. All the honesty machinery of the old estimate
// card lives here, with its keys preserved:
// • the live FX rate, when usable, is shown ONLY as a NONBINDING
//   estimate — labeled as such, never a quote or a settled value;
// • a rate that is missing, stale or contradictory renders the honest
//   unavailable state WITH its reason — never a stale number dressed
//   up as a quote;
// • the receive figure is arithmetic on the DISPLAYED rate (forward:
//   amount × rate GHS; reversed: amount ÷ rate USDC), never a quote,
//   never reserved, never settled;
// • no fees are shown because no fee contract exists — an invented
//   fee line would be a fabricated financial fact.
class _ToPanel extends StatelessWidget {
  const _ToPanel({
    required this.snapshot,
    required this.loading,
    required this.controller,
    required this.reversed,
  });

  final FxRateSnapshot? snapshot;
  final bool loading;
  final TextEditingController controller;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return _Panel(
      panelKey: const Key('convert_to_panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _assetHeading(colors),
          const SizedBox(height: 12),
          _rateStrip(context, colors),
        ],
      ),
    );
  }

  Widget _assetHeading(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          reversed ? 'USDC' : 'GHS',
          key: const Key('convert_to_asset'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: colors.onSurface,
          ),
        ),
        Text(
          reversed ? 'Settled currency' : 'Display currency',
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _rateStrip(BuildContext context, ColorScheme colors) {
    if (loading) {
      return const SizedBox(
        key: Key('convert_estimate_loading'),
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      );
    }

    final snap = snapshot;
    // The verdict is evaluated against the CURRENT clock on every
    // build — combined with the staleness re-arm timer in the shell,
    // an observation that expires while the screen is open flips this
    // strip the moment its window lapses.
    if (snap == null || !snap.isUsableAt(kConvertNow())) {
      // Honest unavailable state: no rate, no estimate. The REASON is
      // disclosed so the user can tell a missing fact from a stale one.
      // Two-key contract (Workstream G tests): the wrapper carries the
      // unavailable verdict, the inner Text carries the REASON — so a
      // test can assert the disclosure without matching prose.
      return KeyedSubtree(
        key: const Key('convert_estimate_unavailable'),
        child: Text(
          'Live rate unavailable right now '
          '(${_unavailabilityReason(snap)}). Nothing is estimated and '
          'nothing is converted.',
          key: const Key('convert_estimate_unavailable_reason'),
          style: TextStyle(fontSize: 13, color: colors.onSurface),
        ),
      );
    }

    // RATE-SOURCE + FRESHNESS DISCLOSURE — the observation age derives
    // from the LAST EXTERNAL SYNC (the server's market observation), never
    // from `fetchedAt` (when this client merely received the response).
    final age = kConvertNow().difference(snap.lastExternalSync!);

    return Column(
      key: const Key('convert_estimate_live'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '1 USDC ≈ ${snap.ghsPerUsdc.toStringAsFixed(2)} GHS',
                key: const Key('convert_estimate_rate'),
                // MONEY CONTRACT (az_text): figures live in the numeric
                // family. This also carries the U+2248 (≈) and U+20B5 (₵)
                // glyphs the UI family does not ship.
                style: AzText.money(
                  colors.onSurface,
                  size: 16,
                  weight: FontWeight.w700,
                  tracking: 0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Source: ${snap.source} — last market observation '
          '${_describeAge(age)} (fresh within '
          '${snap.rateFreshnessMaxAgeSeconds.round()}s)',
          key: const Key('convert_estimate_source_disclosure'),
          style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Text(
          'NONBINDING ESTIMATE — not a quote. Display only: no funds '
          'move, nothing is reserved, and this number is not a settled '
          'value.',
          key: const Key('convert_estimate_disclaimer'),
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _receiveEstimate(colors, snap),
      ],
    );
  }

  Widget _receiveEstimate(ColorScheme colors, FxRateSnapshot snap) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) =>
          _buildReceiveEstimate(colors, snap, value.text),
    );
  }

  Widget _buildReceiveEstimate(
    ColorScheme colors,
    FxRateSnapshot snap,
    String raw,
  ) {
    final rate = snap.ghsPerUsdc;
    final amount = double.tryParse(raw.trim());
    final amountEligible = amount != null && amount.isFinite && amount > 0;
    // FORWARD: USDC × rate → GHS. REVERSED: GHS ÷ rate → USDC (rate is
    // guaranteed positive by isUsableAt; the division can still overflow
    // only for absurd inputs, guarded below).
    final double? estimate = amountEligible
        ? (reversed ? amount / rate : amount * rate)
        : null;
    final estimateUsable = estimate != null && estimate.isFinite;
    // The honest non-numeric state fires for BOTH overflow paths: a
    // programmatic controller write that parses as non-finite (Infinity
    // parses > 0 — do NOT gate this on amountEligible, which requires
    // isFinite) and a finite amount whose product with the rate is not
    // finite.
    final amountTooLarge = !estimateUsable && amount != null && amount > 0;
    final toCode = reversed ? 'USDC' : 'GHS';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (estimateUsable)
          Text(
            '≈ ${reversed ? '' : 'GH₵ '}${estimate.toStringAsFixed(2)} $toCode',
            key: const Key('convert_amount_estimate'),
            semanticsLabel:
                'Nonbinding estimate, ${estimate.toStringAsFixed(2)} '
                '${reversed ? 'USDC' : 'cedis'}. Not a quote; nothing is '
                'converted.',
            // MONEY CONTRACT: the numeric family carries the ≈ and ₵
            // glyphs the UI family does not ship (see the rate line).
            style: AzText.money(
              colors.onSurface,
              size: 16,
              weight: FontWeight.w700,
              tracking: 0,
            ),
          )
        else if (amountTooLarge)
          const Text(
            'Amount is too large to estimate — enter a smaller figure.',
            key: Key('convert_amount_estimate_too_large'),
            style: TextStyle(fontSize: 12),
          )
        else
          Text(
            'Enter an amount for a live estimate.',
            key: const Key('convert_amount_estimate_pending'),
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        if (estimateUsable)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'ESTIMATE ONLY — computed from the displayed rate. Not a '
              'quote, not reserved, nothing converts.',
              key: const Key('convert_amount_estimate_disclaimer'),
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  /// Honest human phrasing of WHY the rate is unusable. Mirrors the exact
  /// checks of [FxRateSnapshot.isUsableAt] so the disclosed reason can
  /// never disagree with the verdict — including MISSING metadata (no
  /// observation time) and CONTRADICTORY metadata (server age vs ours).
  static String _unavailabilityReason(FxRateSnapshot? snap) {
    if (snap == null) return 'no rate data received yet';
    if (!snap.isCanonical) {
      return 'the server did not confirm this as canonical retail '
          'USDC/GHS metadata';
    }
    if (!snap.ghsPerUsdc.isFinite || snap.ghsPerUsdc <= 0) {
      return 'the rate figure is missing or not a positive number';
    }
    if (!snap.serverFresh) return 'the server freshness gate failed';
    if (snap.lastExternalSync == null) {
      return 'the last external market observation time is missing, so '
          'its age cannot be verified';
    }
    if (!snap.rateFreshnessMaxAgeSeconds.isFinite ||
        snap.rateFreshnessMaxAgeSeconds <= 0) {
      return 'the freshness window is missing or invalid';
    }
    // Float seconds — the exact precision of isUsableAt, so the
    // disclosed reason can never disagree with the verdict near a
    // window boundary (a 6.3s-old observation is NOT 'still fresh').
    final ageSeconds =
        kConvertNow().difference(snap.lastExternalSync!).inMilliseconds /
        1000.0;
    if (ageSeconds < -FxRateSnapshot.clockSkewAllowance.inSeconds) {
      return 'the observation timestamp contradicts the device clock '
          '(it claims to be in the future)';
    }
    if (ageSeconds > snap.rateFreshnessMaxAgeSeconds) {
      return 'the last market observation is older than the '
          '${_windowLabel(snap.rateFreshnessMaxAgeSeconds)} freshness '
          'window';
    }
    if (snap.serverAgeContradictsAt(kConvertNow())) {
      return 'the server\'s age observation contradicts ours';
    }
    return 'the rate metadata is incomplete';
  }

  /// The freshness window disclosed to the user, preserving fractional
  /// seconds: the verdict compares against the exact double, so a 6.6s
  /// window must not be disclosed as a rounded "7s" (or vice versa).
  static String _windowLabel(double seconds) {
    final whole = seconds.roundToDouble();
    return seconds == whole
        ? '${whole.toInt()}s'
        : '${seconds.toStringAsFixed(1)}s';
  }

  static String _describeAge(Duration age) {
    // CLOCK-SKEW EDGE — an observation timestamp a few seconds in the
    // future is tolerated by the model (within its skew allowance), so
    // the age can be NEGATIVE here. It is a fresh observation, never a
    // "-3s ago" disclosure.
    if (age <= Duration.zero) return 'just now';
    if (age.inSeconds < 60) return '${age.inSeconds}s ago';
    if (age.inMinutes < 60) return '${age.inMinutes} min ago';
    return '${age.inHours}h ago';
  }
}

class _ExecutionGate extends StatelessWidget {
  const _ExecutionGate({required this.colors, required this.supported});

  final ColorScheme colors;
  final bool supported;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      panelKey: supported
          ? const Key('convert_execution_ready')
          : const Key('convert_execution_unavailable'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 22, color: colors.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            supported
                ? 'Conversion is available. Review the server quote '
                      'before confirming.'
                : 'Converting between GHS and USDC balances isn\'t '
                      'available yet. Your money is safe — nothing can be '
                      'converted, moved or spent from this screen.',
            style: TextStyle(fontSize: 13, color: colors.onSurface),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              key: const Key('convert_cta'),
              // CAPABILITY GATE: while the backend has no conversion
              // contract the CTA is inert — onPressed is null, so no
              // handler runs, no provider is touched, no data mutates.
              // Never a no-op enabled callback: an enabled-looking
              // button that does nothing is a lie.
              onPressed: null,
              child: Text(
                supported ? 'Continue' : 'Unavailable',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.panelKey});

  final Key? panelKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: panelKey,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );
  }
}
