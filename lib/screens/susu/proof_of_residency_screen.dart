// =============================================================================
// PROOF OF RESIDENCY SCREEN — Phase 5 / Workstream A (2026-06-01)
//
// The second Susu gate (after ID KYC). A user uploads a residency document
// (utility bill / bank statement / government letter, JPEG/PNG/PDF,
// >10 KB and ≤10 MB) which an admin reviews. This screen drives the full
// status lifecycle:
//
//   NOT_SUBMITTED → upload CTA
//   PENDING_REVIEW → "under review" (yellow)
//   VERIFIED       → green check, done
//   REJECTED       → red + reason + re-upload
//   EXPIRED        → re-upload (365-day sweep flips VERIFIED→EXPIRED)
//
// Posts multipart to POST /api/users/proof-of-residency (field `file`) via
// susuService.uploadPoR, then refreshes proofOfResidencyProvider.
//
// UI guardrails: transparent scaffold over the themed backdrop; AzamanColors;
// matches the deposit / KYC visual language.
// =============================================================================

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/proof_of_residency_model.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/susu_service.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class ProofOfResidencyScreen extends ConsumerStatefulWidget {
  const ProofOfResidencyScreen({super.key});

  @override
  ConsumerState<ProofOfResidencyScreen> createState() =>
      _ProofOfResidencyScreenState();
}

class _ProofOfResidencyScreenState
    extends ConsumerState<ProofOfResidencyScreen> {
  static const _minBytes = 10 * 1024; // strictly greater than 10 KB
  static const _maxBytes = 10 * 1024 * 1024; // ≤ 10 MB

  File? _picked;
  String? _pickedName;
  bool _uploading = false;
  String? _localError;

  Future<void> _pick() async {
    setState(() => _localError = null);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.single;
      if (f.path == null) {
        setState(() => _localError = 'Could not read the selected file.');
        return;
      }
      final size = f.size;
      // Client-side mirror of the backend rule (Req 3.2 / 3.3).
      if (size <= _minBytes) {
        setState(() => _localError = 'File too small (must be larger than 10 KB).');
        return;
      }
      if (size > _maxBytes) {
        setState(() => _localError = 'File too large (max 10 MB).');
        return;
      }
      setState(() {
        _picked = File(f.path!);
        _pickedName = f.name;
      });
    } catch (e) {
      setState(() => _localError = 'Could not open file picker: $e');
    }
  }

  Future<void> _upload() async {
    if (_picked == null) return;
    setState(() => _uploading = true);
    HapticFeedback.mediumImpact();
    try {
      await susuService.uploadPoR(_picked!);
      if (!mounted) return;
      // Refresh status; the provider drives the UI back to PENDING_REVIEW.
      await ref.read(proofOfResidencyProvider.notifier).refresh();
      if (!mounted) return;
      setState(() {
        _picked = null;
        _pickedName = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document submitted — under review.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _localError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _localError = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final porAsync = ref.watch(proofOfResidencyProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01,
              color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Proof of Residency',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: colors.warning,
          onRefresh: () => ref.read(proofOfResidencyProvider.notifier).refresh(),
          child: porAsync.when(
            loading: () => const _CenterLoader(),
            error: (e, _) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                _ErrorBlock(error: e.toString(), colors: colors),
              ],
            ),
            data: (state) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              children: [
                _StatusCard(state: state, colors: colors),
                const SizedBox(height: 16),
                if (state.status.canSubmit) ...[
                  _Explainer(colors: colors),
                  const SizedBox(height: 16),
                  _UploadArea(
                    pickedName: _pickedName,
                    colors: colors,
                    onPick: _uploading ? null : _pick,
                  ),
                  if (_localError != null) ...[
                    const SizedBox(height: 10),
                    _InlineError(text: _localError!, colors: colors),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          (_picked == null || _uploading) ? null : _upload,
                      icon: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(HugeIconsSolid.cloudUpload, size: 16),
                      label: Text(
                        _uploading ? 'Uploading…' : 'Submit document',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, letterSpacing: 0.3),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final ProofOfResidencyState state;
  final AzamanColors colors;
  const _StatusCard({required this.state, required this.colors});

  @override
  Widget build(BuildContext context) {
    final (icon, tint, headline, sub) = switch (state.status) {
      ProofOfResidencyStatus.notSubmitted => (
        HugeIconsSolid.file01,
        colors.textTertiary,
        'Not submitted',
        'Upload a recent residency document to unlock Susu participation.',
      ),
      ProofOfResidencyStatus.pendingReview => (
        HugeIconsSolid.hourglass,
        colors.warning,
        'Under review',
        'Your document is being reviewed by our team. We\'ll notify you once a decision is made.',
      ),
      ProofOfResidencyStatus.verified => (
        HugeIconsSolid.checkmarkCircle01,
        colors.success,
        'Verified',
        'Your residency is verified. This is valid for 365 days.',
      ),
      ProofOfResidencyStatus.rejected => (
        HugeIconsSolid.cancel01,
        colors.danger,
        'Rejected',
        state.rejectionReason?.trim().isNotEmpty == true
            ? 'Reason: ${state.rejectionReason}'
            : 'Your document was rejected. Please re-upload a valid document.',
      ),
      ProofOfResidencyStatus.expired => (
        HugeIconsSolid.calendar01,
        colors.danger,
        'Expired',
        'Your residency verification has expired. Re-upload a recent document.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withOpacity(0.30), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tint, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                if (state.submittedAt != null &&
                    state.status == ProofOfResidencyStatus.pendingReview) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Submitted ${_fmt(state.submittedAt!)}',
                    style: TextStyle(color: colors.textTertiary, fontSize: 10.5),
                  ),
                ],
                if (state.verifiedAt != null &&
                    state.status == ProofOfResidencyStatus.verified) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Verified ${_fmt(state.verifiedAt!)}',
                    style: TextStyle(color: colors.textTertiary, fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }
}

class _Explainer extends StatelessWidget {
  final AzamanColors colors;
  const _Explainer({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accepted documents',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          _bullet(colors, 'Utility bill, bank statement, or government letter'),
          _bullet(colors, 'Dated within the last 90 days'),
          _bullet(colors, 'Shows your name and residential address'),
          _bullet(colors, 'JPEG, PNG or PDF · larger than 10 KB, up to 10 MB'),
        ],
      ),
    );
  }

  Widget _bullet(AzamanColors colors, String t) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(HugeIconsSolid.checkmarkCircle01,
                color: colors.success, size: 13),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t,
                style: TextStyle(
                    color: colors.textSecondary, fontSize: 11.5, height: 1.4),
              ),
            ),
          ],
        ),
      );
}

class _UploadArea extends StatelessWidget {
  final String? pickedName;
  final AzamanColors colors;
  final VoidCallback? onPick;
  const _UploadArea({
    required this.pickedName,
    required this.colors,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final has = pickedName != null;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: has ? colors.success.withOpacity(0.40) : colors.divider,
            width: 0.9,
          ),
        ),
        child: Column(
          children: [
            Icon(
              has ? HugeIconsSolid.note01 : HugeIconsSolid.imageAdd01,
              color: has ? colors.success : colors.textTertiary,
              size: 34,
            ),
            const SizedBox(height: 10),
            Text(
              has ? pickedName! : 'Tap to choose a document',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: has ? colors.textPrimary : colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (has) ...[
              const SizedBox(height: 4),
              Text(
                'Tap again to replace',
                style: TextStyle(color: colors.textTertiary, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String text;
  final AzamanColors colors;
  const _InlineError({required this.text, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(HugeIconsSolid.alertCircle, color: colors.danger, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: colors.danger, fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final String error;
  final AzamanColors colors;
  const _ErrorBlock({required this.error, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HugeIconsSolid.alertCircle, size: 44, color: colors.danger),
            const SizedBox(height: 12),
            Text(
              'Could not load status',
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
          ],
        ),
      ),
    );
  }
}

class _CenterLoader extends StatelessWidget {
  const _CenterLoader();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}
