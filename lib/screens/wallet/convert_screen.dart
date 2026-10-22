import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/currency_provider.dart';
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
    final delay = staleAt.difference(kConvertNow()) +
        const Duration(milliseconds: 50);
    _stalenessTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        _stalenessArmedFor = null;
        if (mounted) setState(() {});
      },
    );
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
            _assetRow(colors),
            const SizedBox(height: 18),
            _EstimateCard(
              snapshot: snapshot.valueOrNull,
              loading: snapshot.isLoading,
            ),
            const SizedBox(height: 18),
            _AmountPanel(
              controller: _amountCtrl,
              snapshot: snapshot.valueOrNull,
              loading: snapshot.isLoading,
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

  Widget _assetRow(ColorScheme colors) {
    // Asset semantics mirror the ledger truth: USDC is the settled
    // currency; GHS is the display/quote currency of the pair. When a
    // native GHS balance ever exists, these rows are the seam to swap
    // for real balance reads.
    return Container(
      key: const Key('convert_asset_pair'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          _assetChip(colors, code: 'USDC', label: 'Settled balance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.swap_horiz, color: colors.onSurfaceVariant),
          ),
          _assetChip(colors, code: 'GHS', label: 'Display currency'),
        ],
      ),
    );
  }

  Widget _assetChip(ColorScheme colors,
      {required String code, required String label}) {
    return Expanded(
      child: Column(
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
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({required this.snapshot, required this.loading});

  final FxRateSnapshot? snapshot;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (loading) {
      return const _Panel(
        panelKey: Key('convert_estimate_loading'),
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    final snap = snapshot;
    // The verdict is evaluated against the CURRENT clock on every
    // build — combined with the staleness re-arm timer above, an
    // observation that expires while the screen is open flips this
    // panel the moment its window lapses.
    if (snap == null || !snap.isUsableAt(kConvertNow())) {
      // Honest unavailable state: no rate, no estimate. Never a stale
      // number dressed up as a quote — and the REASON is disclosed so
      // the user can tell a missing fact from a stale one.
      return _Panel(
        panelKey: const Key('convert_estimate_unavailable'),
        child: Text(
          'Live rate unavailable right now '
          '(${_unavailabilityReason(snap)}). Nothing is estimated and '
          'nothing is converted.',
          key: const Key('convert_estimate_unavailable_reason'),
          style: const TextStyle(fontSize: 13),
        ),
      );
    }

    // RATE-SOURCE + FRESHNESS DISCLOSURE — the observation age derives
    // from the LAST EXTERNAL SYNC (the server's market observation), never
    // from `fetchedAt` (when this client merely received the response).
    final age = kConvertNow().difference(snap.lastExternalSync!);

    return _Panel(
      panelKey: const Key('convert_estimate_live'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '1 USDC ≈ ${snap.ghsPerUsdc.toStringAsFixed(2)} GHS',
                  key: const Key('convert_estimate_rate'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
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
        ],
      ),
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
    final ageSeconds = kConvertNow()
        .difference(snap.lastExternalSync!)
        .inMilliseconds /
        1000.0;
    if (ageSeconds < -FxRateSnapshot.clockSkewAllowance.inSeconds) {
      return 'the observation timestamp contradicts the device clock '
          '(it claims to be in the future)';
    }
    if (ageSeconds > snap.rateFreshnessMaxAgeSeconds) {
      return 'the last market observation is older than the '
          '${snap.rateFreshnessMaxAgeSeconds.round()}s freshness window';
    }
    if (snap.externalRateAgeSeconds != null &&
        (snap.externalRateAgeSeconds! - ageSeconds).abs() >
            FxRateSnapshot.ageContradictionToleranceSeconds) {
      return 'the server\'s age observation contradicts ours';
    }
    return 'the rate metadata is incomplete';
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

/// §6 — real amount entry with a live, NONBINDING estimate at the
/// canonical fxRateProvider rate. Display-only by construction:
/// • typing mutates nothing but this local controller;
/// • the estimate is arithmetic on the DISPLAYED rate, never a quote,
///   never reserved, never settled;
/// • no usable rate (or a zero/blank amount) renders NO estimate —
///   an honest blank beats a fabricated number.
class _AmountPanel extends StatelessWidget {
  const _AmountPanel({
    required this.controller,
    required this.snapshot,
    required this.loading,
  });

  final TextEditingController controller;
  final FxRateSnapshot? snapshot;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    // The controller drives the estimate, so the panel REBUILDS on every
    // keystroke — the estimate is always consistent with the field.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => _build(context, value.text),
    );
  }

  Widget _build(BuildContext context, String raw) {
    final colors = Theme.of(context).colorScheme;
    final rate = (snapshot != null && snapshot!.isUsableAt(kConvertNow()))
        ? snapshot!.ghsPerUsdc
        : null;
    final amount = double.tryParse(raw.trim());
    final estimate =
        (rate != null && amount != null && amount > 0 && !loading)
            ? amount * rate
            : null;

    return _Panel(
      panelKey: const Key('convert_amount_panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount (USDC)',
            key: const Key('convert_amount_label'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('convert_amount_field'),
            controller: controller,
            enabled: !loading,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d{0,2}')),
            ],
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(color: colors.onSurfaceVariant),
              suffixText: 'USDC',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (estimate != null)
            Text(
              '≈ GH₵ ${estimate.toStringAsFixed(2)} GHS',
              key: const Key('convert_amount_estimate'),
              semanticsLabel:
                  'Nonbinding estimate, ${estimate.toStringAsFixed(2)} '
                  'cedis. Not a quote; nothing is converted.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            )
          else if (!loading)
            Text(
              rate == null
                  ? 'Enter an amount for a live estimate — requires a '
                      'usable rate.'
                  : 'Enter an amount for a live estimate.',
              key: const Key('convert_amount_estimate_pending'),
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          if (estimate != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'ESTIMATE ONLY — computed from the displayed rate. Not a '
                'quote, not reserved, nothing converts.',
                key: const Key('convert_amount_estimate_disclaimer'),
                style: TextStyle(
                    fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
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
          Icon(
            Icons.info_outline,
            size: 22,
            color: colors.onSurfaceVariant,
          ),
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
