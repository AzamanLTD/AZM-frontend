import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/currency_provider.dart';

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
class ConvertScreen extends ConsumerWidget {
  const ConvertScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final snapshot = ref.watch(fxRateProvider);

    return Scaffold(
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
            _ExecutionGate(
              colors: colors,
              supported: convertExecutionAvailable,
            ),
          ],
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
    if (snap == null || !snap.isUsable) {
      // Honest unavailable state: no rate, no estimate. Never a stale
      // number dressed up as a quote.
      return const _Panel(
        panelKey: Key('convert_estimate_unavailable'),
        child: Text(
          'Live rate unavailable right now. Nothing is estimated and '
          'nothing is converted.',
          style: TextStyle(fontSize: 13),
        ),
      );
    }

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
              onPressed: supported ? () {} : null,
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
