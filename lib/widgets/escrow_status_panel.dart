// =============================================================================
// ESCROW STATUS PANEL — Flutter V3 Marketplace Sprint (2026-06-21)
//
// A collapsible card rendered ABOVE the message list in the ticket workspace
// when the ticket is an ESCROW. Collapsed it shows a status dot, the locked
// amount and the status label. Expanded it reveals the fee, delivery terms,
// due date, both parties' satisfaction state and the role/status-appropriate
// action buttons.
//
// All financial actions (fund / mark delivered / confirm release / cancel)
// route through AzamanConfirmSheet and the AzamanBiometricGate so they match
// the rest of the app's "confirm + authenticate" doctrine. Raising a dispute
// opens a reason sheet.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/escrow_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/utils/biometric_gate.dart';
import 'package:azaman/widgets/azaman_confirm_sheet.dart';

class EscrowStatusPanel extends ConsumerStatefulWidget {
  final SmartEscrow? escrow;
  final int currentUserId;
  final bool isLoading;
  final VoidCallback onFund;
  final Future<bool> Function() onSatisfy;
  final Future<void> Function(String reason, List<String> urls) onDispute;
  final Future<void> Function(String terms) onUpdateTerms;
  final VoidCallback onCancel;

  const EscrowStatusPanel({
    super.key,
    required this.escrow,
    required this.currentUserId,
    required this.isLoading,
    required this.onFund,
    required this.onSatisfy,
    required this.onDispute,
    required this.onUpdateTerms,
    required this.onCancel,
  });

  @override
  ConsumerState<EscrowStatusPanel> createState() => _EscrowStatusPanelState();
}

class _EscrowStatusPanelState extends ConsumerState<EscrowStatusPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final escrow = widget.escrow;

    // No escrow loaded yet — show a slim loading / placeholder bar.
    if (escrow == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        height: 56,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider, width: 1),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(HugeIconsSolid.lockKey, size: 18, color: colors.textTertiary),
            const SizedBox(width: 10),
            Text(
              widget.isLoading ? 'Loading escrow…' : 'No escrow on this ticket',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (widget.isLoading)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final statusColor = _statusColor(escrow.status, colors);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.35), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Collapsed header (always visible, tap to toggle) ──
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AzamanHaptics.toggle();
              setState(() => _expanded = !_expanded);
            },
            child: SizedBox(
              height: 60,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: statusColor, blurRadius: 5),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Escrow · ${escrow.amountUsdc.toStringAsFixed(2)} USDC',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            escrow.status.label,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(HugeIconsStroke.arrowDown01,
                          size: 20, color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Expanded body ──
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? _ExpandedBody(
                    escrow: escrow,
                    colors: colors,
                    currentUserId: widget.currentUserId,
                    statusColor: statusColor,
                    onFund: _confirmFund,
                    onSatisfy: _confirmSatisfy,
                    onCancel: _confirmCancel,
                    onDispute: _openDisputeSheet,
                    onUpdateTerms: _openTermsSheet,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _confirmFund() async {
    final escrow = widget.escrow;
    if (escrow == null) return;
    final ok = await AzamanConfirmSheet.show(
      context,
      title: 'Fund Escrow',
      message:
          'Lock ${escrow.totalLocked.toStringAsFixed(2)} USDC (incl. ${escrow.feeUsdc.toStringAsFixed(2)} fee) into escrow?',
      confirmLabel: 'Fund',
      icon: HugeIconsSolid.lockKey,
    );
    if (ok != true || !mounted) return;
    await AzamanBiometricGate.run(
      context,
      () async => widget.onFund(),
      reason: 'Authenticate to fund escrow',
    );
  }

  Future<void> _confirmSatisfy(String title, String message) async {
    final ok = await AzamanConfirmSheet.show(
      context,
      title: title,
      message: message,
      confirmLabel: 'Confirm',
      icon: HugeIconsSolid.checkmarkCircle01,
    );
    if (ok != true || !mounted) return;
    await AzamanBiometricGate.run(
      context,
      () async {
        final settled = await widget.onSatisfy();
        if (settled && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Escrow settled — funds released.'),
            behavior: SnackBarBehavior.floating,
          ));
        }
      },
      reason: 'Authenticate to confirm release',
    );
  }

  Future<void> _confirmCancel() async {
    final ok = await AzamanConfirmSheet.show(
      context,
      title: 'Cancel Escrow',
      message:
          'Cancel this escrow? If it was funded, the locked amount is refunded to the payer.',
      confirmLabel: 'Cancel Escrow',
      cancelLabel: 'Keep',
      destructive: true,
      icon: HugeIconsSolid.cancelCircle,
    );
    if (ok != true || !mounted) return;
    widget.onCancel();
  }

  Future<void> _openDisputeSheet() async {
    final controller = TextEditingController();
    final colors = ref.read(themeProvider).colors;
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(HugeIconsSolid.alertCircle,
                      color: colors.danger, size: 20),
                  const SizedBox(width: 8),
                  Text('Raise a Dispute',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      )),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Tell us what went wrong. An admin will review the escrow.',
                style: TextStyle(color: colors.textTertiary, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                maxLines: 4,
                minLines: 3,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Describe the issue…',
                  hintStyle: TextStyle(color: colors.textTertiary),
                  filled: true,
                  fillColor: colors.card,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    Navigator.pop(ctx, text);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.danger,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Submit Dispute',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    try {
      await widget.onDispute(reason, const []);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not raise dispute: $e'),
          backgroundColor: colors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _openTermsSheet() async {
    final escrow = widget.escrow;
    final controller =
        TextEditingController(text: escrow?.deliveryTerms ?? '');
    final colors = ref.read(themeProvider).colors;
    final terms = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Update Delivery Terms',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                maxLines: 5,
                minLines: 3,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Scope, timeline, conditions…',
                  hintStyle: TextStyle(color: colors.textTertiary),
                  filled: true,
                  fillColor: colors.card,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(ctx, controller.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.isDark ? Colors.black : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Save Terms',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (terms == null || !mounted) return;
    try {
      await widget.onUpdateTerms(terms);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not update terms: $e'),
          backgroundColor: colors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Color _statusColor(EscrowStatus status, AzamanColors colors) {
    switch (status) {
      case EscrowStatus.draft:
      case EscrowStatus.expired:
      case EscrowStatus.refunded:
        return colors.textTertiary;
      case EscrowStatus.funded:
      case EscrowStatus.inProgress:
        return colors.accent;
      case EscrowStatus.pendingSettlement:
        return colors.warning;
      case EscrowStatus.settled:
      case EscrowStatus.released:
        return colors.success;
      case EscrowStatus.disputed:
      case EscrowStatus.adminReview:
        return colors.danger;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expanded body — details + action buttons.
// ─────────────────────────────────────────────────────────────────────────────

class _ExpandedBody extends StatelessWidget {
  final SmartEscrow escrow;
  final AzamanColors colors;
  final int currentUserId;
  final Color statusColor;
  final Future<void> Function() onFund;
  final Future<void> Function(String title, String message) onSatisfy;
  final Future<void> Function() onCancel;
  final Future<void> Function() onDispute;
  final Future<void> Function() onUpdateTerms;

  const _ExpandedBody({
    required this.escrow,
    required this.colors,
    required this.currentUserId,
    required this.statusColor,
    required this.onFund,
    required this.onSatisfy,
    required this.onCancel,
    required this.onDispute,
    required this.onUpdateTerms,
  });

  bool get _isPayer => currentUserId == escrow.payerId;
  bool get _isPayee => currentUserId == escrow.payeeId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(color: colors.divider, height: 1),
          const SizedBox(height: 12),
          _row('Amount', '${escrow.amountUsdc.toStringAsFixed(2)} USDC'),
          const SizedBox(height: 6),
          _row('Platform fee', '${escrow.feeUsdc.toStringAsFixed(2)} USDC'),
          const SizedBox(height: 6),
          _row('Total locked', '${escrow.totalLocked.toStringAsFixed(2)} USDC',
              emphasize: true),
          if (escrow.dueDate != null) ...[
            const SizedBox(height: 6),
            _row('Due date', _fmtDate(escrow.dueDate!)),
          ],
          if (escrow.deliveryTerms != null &&
              escrow.deliveryTerms!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('DELIVERY TERMS',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                )),
            const SizedBox(height: 4),
            Text(
              escrow.deliveryTerms!.trim(),
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Satisfaction indicators
          Row(
            children: [
              _satisfactionChip('Payer', escrow.payerSatisfied),
              const SizedBox(width: 8),
              _satisfactionChip('Payee', escrow.payeeSatisfied),
            ],
          ),
          if (escrow.dispute != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(HugeIconsSolid.alertCircle,
                      size: 16, color: colors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Dispute open: ${escrow.dispute!.reason}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          ..._actions(context),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final status = escrow.status;

    if (status.isTerminal) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.softSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'This escrow is ${escrow.status.label.toLowerCase()} — no further actions.',
            style: TextStyle(color: colors.textTertiary, fontSize: 12.5),
          ),
        ),
      ];
    }

    final buttons = <Widget>[];

    // DRAFT — payer funds.
    if (status == EscrowStatus.draft && _isPayer) {
      buttons.add(_primaryButton('Fund Escrow', HugeIconsSolid.lockKey, onFund));
    }

    // FUNDED / IN_PROGRESS.
    if (status == EscrowStatus.funded || status == EscrowStatus.inProgress) {
      if (_isPayee) {
        buttons.add(_primaryButton('Mark Delivered',
            HugeIconsSolid.checkmarkCircle01, () => onSatisfy(
                'Mark Delivered',
                'Confirm you have delivered. This moves the escrow toward settlement.')));
      }
      // Update terms (both parties may refine).
      buttons.add(_secondaryButton(
          'Update Terms', HugeIconsStroke.pencilEdit01, onUpdateTerms));
      if (_isPayer) {
        buttons.add(_dangerButton(
            'Cancel Escrow', HugeIconsStroke.cancelCircle, onCancel));
      }
      // Either party can dispute.
      buttons.add(_dangerButton(
          'Raise Dispute', HugeIconsStroke.alertCircle, onDispute));
    }

    // PENDING_SETTLEMENT — the other party confirms release.
    if (status == EscrowStatus.pendingSettlement) {
      final iHaveConfirmed =
          (_isPayer && escrow.payerSatisfied) ||
              (_isPayee && escrow.payeeSatisfied);
      if (!iHaveConfirmed) {
        buttons.add(_primaryButton('Confirm Release',
            HugeIconsSolid.checkmarkCircle01, () => onSatisfy(
                'Confirm Release',
                'Release the locked funds? This settles the escrow.')));
      } else {
        buttons.add(_infoBar('Waiting for the other party to confirm.'));
      }
      buttons.add(_dangerButton(
          'Raise Dispute', HugeIconsStroke.alertCircle, onDispute));
    }

    // DISPUTED / ADMIN_REVIEW — read-only, awaiting admin.
    if (status == EscrowStatus.disputed ||
        status == EscrowStatus.adminReview) {
      buttons.add(_infoBar('Under admin review. We\'ll update you here.'));
    }

    if (buttons.isEmpty) {
      buttons.add(_infoBar('No actions available for your role right now.'));
    }

    // Space the buttons out.
    final spaced = <Widget>[];
    for (var i = 0; i < buttons.length; i++) {
      spaced.add(buttons[i]);
      if (i != buttons.length - 1) spaced.add(const SizedBox(height: 8));
    }
    return spaced;
  }

  Widget _primaryButton(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.isDark ? Colors.black : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: colors.textSecondary),
        label: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _dangerButton(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: colors.danger),
        label: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.danger)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.danger.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _infoBar(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: colors.textTertiary, fontSize: 12.5),
      ),
    );
  }

  Widget _row(String label, String value, {bool emphasize = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(color: colors.textTertiary, fontSize: 12.5)),
        Text(
          value,
          style: TextStyle(
            color: emphasize ? colors.textPrimary : colors.textSecondary,
            fontSize: 13,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _satisfactionChip(String who, bool satisfied) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: satisfied
              ? colors.success.withValues(alpha: 0.10)
              : colors.softSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              satisfied
                  ? HugeIconsSolid.checkmarkCircle01
                  : HugeIconsStroke.clock01,
              size: 14,
              color: satisfied ? colors.success : colors.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              '$who ${satisfied ? 'ready' : 'pending'}',
              style: TextStyle(
                color: satisfied ? colors.success : colors.textTertiary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
