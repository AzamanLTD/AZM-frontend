// =============================================================================
// LIABILITY ACCEPTANCE SCREEN — Phase 4 (Master Sprint, 2026-05-31)
//
// Renders the version pinned to a Susu (GET /api/susu/groups/:id/contract)
// in a scrollable view. The mandatory checkbox gate prevents the Accept
// button from enabling. On submission posts to the contract acceptance
// endpoint with `{ contractVersion, contractHash, agreed: true }`.
//
// Error handling:
//   • CONTRACT_VERSION_MISMATCH 409 → reload the current contract and
//     show a banner so the user re-reads the latest text. Idempotency
//     (Req 4.7) means a successful re-accept is safe.
//   • Any other error → SnackBar with the BE message.
//
// This screen is distinct from the legacy `SusuWarningScreen` which is
// still wired into the GroupChat-based legacy susu flow.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/susu_service.dart';

class LiabilityAcceptanceScreen extends ConsumerStatefulWidget {
  final String susuId;
  const LiabilityAcceptanceScreen({super.key, required this.susuId});

  @override
  ConsumerState<LiabilityAcceptanceScreen> createState() =>
      _LiabilityAcceptanceScreenState();
}

class _LiabilityAcceptanceScreenState
    extends ConsumerState<LiabilityAcceptanceScreen> {
  Future<LiabilityContract>? _contract;
  bool _agreed = false;
  bool _busy = false;
  String? _versionMismatchBanner;

  @override
  void initState() {
    super.initState();
    _loadContract();
  }

  void _loadContract() {
    setState(() {
      _contract = susuService.getSusuContract(widget.susuId);
      _agreed = false;
      _versionMismatchBanner = null;
    });
  }

  Future<void> _accept(LiabilityContract contract) async {
    if (!_agreed) return;
    setState(() => _busy = true);
    HapticFeedback.heavyImpact();
    try {
      await susuService.acceptContract(
        susuId: widget.susuId,
        contractVersion: contract.version,
        contractHash: contract.contractHash,
      );
      if (!mounted) return;
      // Activation may have happened — refresh the dashboard data and
      // route back to it. The dashboard's auto-subscribed socket room
      // will then catch any subsequent state changes.
      ref.invalidate(susuDetailV2Provider(widget.susuId));
      ref.invalidate(susuMembersProvider(widget.susuId));
      ref.invalidate(susuCyclesProvider(widget.susuId));
      ref.invalidate(susuListProvider);
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/susu/${widget.susuId}');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      // CONTRACT_VERSION_MISMATCH 409 → reload (Req 4.5).
      if (e.statusCode == 409 &&
          e.message.toUpperCase().contains('CONTRACT_VERSION_MISMATCH')) {
        setState(() {
          _versionMismatchBanner =
              'The contract was updated. Please re-read and accept the new version.';
        });
        _loadContract();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not accept contract: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Liability Contract',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<LiabilityContract>(
          future: _contract,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Center(
                child: CircularProgressIndicator(color: colors.warning),
              );
            }
            if (snap.hasError || snap.data == null) {
              return _ErrorView(
                error: snap.error?.toString() ?? 'Contract unavailable',
                colors: colors,
                onRetry: _loadContract,
              );
            }
            final contract = snap.data!;
            return _ContractBody(
              contract: contract,
              banner: _versionMismatchBanner,
              agreed: _agreed,
              busy: _busy,
              onToggle: (v) => setState(() => _agreed = v),
              onAccept: () => _accept(contract),
              colors: colors,
            );
          },
        ),
      ),
    );
  }
}

class _ContractBody extends StatelessWidget {
  final LiabilityContract contract;
  final String? banner;
  final bool agreed;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onAccept;
  final AzamanColors colors;

  const _ContractBody({
    required this.contract,
    required this.banner,
    required this.agreed,
    required this.busy,
    required this.onToggle,
    required this.onAccept,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (banner != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.warning.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: colors.warning.withOpacity(0.30), width: 0.7),
            ),
            child: Row(
              children: [
                Icon(Icons.refresh_rounded,
                    color: colors.warning, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    banner!,
                    style: TextStyle(
                      color: colors.warning,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.danger.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: colors.danger.withOpacity(0.30), width: 0.7),
          ),
          child: Row(
            children: [
              Icon(Icons.gavel_rounded, color: colors.danger, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Defaulting on a Susu authorises automatic seizure of '
                  'available USDC, AZM deduction from your inviter, and a '
                  'permanent trust-rating penalty.',
                  style: TextStyle(
                    color: colors.danger,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(
                'Version ${contract.version}',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Hash ${_short(contract.contractHash)}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: SelectableText(
              contract.body,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            MediaQuery.of(context).padding.bottom + 14,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.divider)),
          ),
          child: Column(
            children: [
              CheckboxListTile.adaptive(
                value: agreed,
                onChanged: busy ? null : (v) => onToggle(v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: colors.warning,
                title: Text(
                  'I have read and agree to the terms of this contract.',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: agreed && !busy ? onAccept : null,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.check_rounded, size: 16),
                  label: Text(
                    busy ? 'Recording…' : 'Accept Contract',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.warning,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor:
                        colors.warning.withOpacity(0.30),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _short(String h) =>
      h.length <= 12 ? h : '${h.substring(0, 6)}…${h.substring(h.length - 6)}';
}

class _ErrorView extends StatelessWidget {
  final String error;
  final AzamanColors colors;
  final VoidCallback onRetry;
  const _ErrorView(
      {required this.error, required this.colors, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: colors.danger),
            const SizedBox(height: 12),
            Text(
              'Could not load the contract',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textTertiary, fontSize: 11),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.warning,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
