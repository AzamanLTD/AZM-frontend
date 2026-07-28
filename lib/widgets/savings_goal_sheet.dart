// =============================================================================
// AZAMAN — SAVINGS GOAL MANAGEMENT SHEET
//
// Bottom sheet that opens when a user taps on a savings goal card.
// Surfaces the four backend operations the SavingsScreen previously could
// not reach:
//
//   POST /api/savings/goals/:id/deposit   — Fund the goal
//   POST /api/savings/goals/:id/withdraw  — Withdraw from the goal
//   PUT  /api/savings/goals/:id/pause     — Pause an active goal
//   PUT  /api/savings/goals/:id/resume    — Resume a paused goal
//
// Phase E addition (2026-05): backend already exposed all four; the
// SavingsScreen only used overview + create-goal. Users could declare
// intent to save but couldn't actually save into a goal once it was made.
// This sheet closes that gap.
//
// Behaviour notes:
// - Withdraws on locked-and-not-matured goals show a 2% penalty preview
//   in red BEFORE submission.
// - Successful action closes the sheet and calls onChanged() so the parent
//   can refresh the overview.
// - All side-effects are inside the sheet's own state — caller passes only
//   the goal map and the onChanged callback.
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/utils/biometric_gate.dart';
import 'package:azaman/utils/idempotency_key.dart';
import 'package:azaman/widgets/slide_to_confirm.dart';


/// Public entry-point. Call from the SavingsScreen goal card `onTap`.
class SavingsGoalSheet {
  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> goal,
    required VoidCallback onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SheetBody(goal: goal, onChanged: onChanged),
    );
  }
}

class _SheetBody extends ConsumerStatefulWidget {
  final Map<String, dynamic> goal;
  final VoidCallback onChanged;

  const _SheetBody({required this.goal, required this.onChanged});

  @override
  ConsumerState<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends ConsumerState<_SheetBody> {
  // Local mirror of the goal so optimistic UI updates work between
  // sheet-internal actions (e.g. pause -> button flips to resume).
  late Map<String, dynamic> _goal;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _goal = Map<String, dynamic>.from(widget.goal);
  }

  // -- Helpers --------------------------------------------------------------

  String get _goalId => _goal['id']?.toString() ?? '';
  String get _status => _goal['status']?.toString() ?? 'ACTIVE';
  String get _name => _goal['name']?.toString() ?? 'Savings Goal';
  bool get _isLocked => _goal['isLocked'] == true;
  bool get _isMatured {
    final endStr = _goal['endDate']?.toString();
    if (endStr == null || endStr.isEmpty) return false;
    final end = DateTime.tryParse(endStr);
    return end != null && !end.isAfter(DateTime.now());
  }

  bool get _earlyWithdrawalApplies => _isLocked && !_isMatured;

  double get _currentGhs =>
      (_goal['currentAmountGhs'] as num?)?.toDouble() ?? 0;
  double get _targetGhs =>
      (_goal['targetAmountGhs'] as num?)?.toDouble() ?? 0;
  double get _frequencyAmount =>
      (_goal['frequencyAmount'] as num?)?.toDouble() ?? 0;
  String get _frequency => _goal['frequency']?.toString() ?? 'WEEKLY';

  double get _progress =>
      _targetGhs <= 0 ? 0 : (_currentGhs / _targetGhs).clamp(0.0, 1.0);

  // -- Network actions ------------------------------------------------------

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    final colors = ref.read(themeProvider).colors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? colors.danger : colors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deposit(double amountGhs) async {
    setState(() => _busy = true);
    try {
      final res = await apiClient.post(
        '/savings/goals/$_goalId/deposit',
        {
          'amountGhs': amountGhs,
          // Phase H12 (2026-05-27): client-supplied idempotency key so
          // a network retry doesn't double-debit the user. The BE uses
          // this to derive the savings deposit's `txHash`, which is
          // @unique on TransactionHistory — concurrent duplicates trip
          // P2002 and the whole transaction (including the user
          // availableBalance debit) rolls back.
          'clientRequestId': IdempotencyKey.generate(),
        },
      );

      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        HapticFeedback.heavyImpact();
        widget.onChanged();
        if (mounted) {
          Navigator.pop(context);
          _toast('Deposited GHS ${amountGhs.toStringAsFixed(2)} into "$_name".');
        }
      } else {
        _toast(body['message']?.toString() ?? 'Deposit failed.', error: true);
      }
    } catch (e) {
      _toast('Network error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw(double? amountGhs) async {
    setState(() => _busy = true);
    try {
      final res = await apiClient.post(
        '/savings/goals/$_goalId/withdraw',
        amountGhs == null ? {} : {'amountGhs': amountGhs},
      );

      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        HapticFeedback.heavyImpact();
        widget.onChanged();
        if (mounted) {
          Navigator.pop(context);
          _toast(body['message']?.toString() ?? 'Withdrawal successful.');
        }
      } else {
        _toast(body['message']?.toString() ?? 'Withdrawal failed.', error: true);
      }
    } catch (e) {
      _toast('Network error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleStatus() async {
    final isPaused = _status == 'PAUSED';
    final endpoint = isPaused ? 'resume' : 'pause';

    setState(() => _busy = true);
    try {
      final res = await apiClient.put(
        '/savings/goals/$_goalId/$endpoint',
        {},
      );

      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        HapticFeedback.mediumImpact();
        // Optimistically update local mirror so the sheet immediately
        // reflects the new status without a re-open.
        setState(() {
          _goal['status'] = isPaused ? 'ACTIVE' : 'PAUSED';
        });
        widget.onChanged();
        _toast(body['message']?.toString() ??
            (isPaused ? 'Goal resumed.' : 'Goal paused.'));
      } else {
        _toast(body['message']?.toString() ?? 'Action failed.', error: true);
      }
    } catch (e) {
      _toast('Network error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final canFund = _status == 'ACTIVE';
    final canWithdraw = _currentGhs > 0 && _status != 'CANCELLED';
    final isPaused = _status == 'PAUSED';

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header — name, status badge, progress bar, balance summary
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.savings_outlined,
                    color: colors.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        )),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _statusBadge(colors),
                        const SizedBox(width: 8),
                        if (_isLocked)
                          Icon(Icons.lock_outline,
                              size: 12, color: colors.textTertiary),
                        if (_isLocked)
                          const SizedBox(width: 3),
                        Text(
                          '$_frequency \u00b7 GHS ${_frequencyAmount.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 6,
              backgroundColor: colors.divider,
              valueColor: AlwaysStoppedAnimation(colors.accent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'GHS ${_currentGhs.toStringAsFixed(2)} / ${_targetGhs.toStringAsFixed(2)}',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${(_progress * 100).toStringAsFixed(0)}% saved',
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Action grid — Fund + Withdraw side-by-side
          Row(
            children: [
              Expanded(
                child: _ActionTile(
                  icon: Icons.add,
                  label: 'Fund',
                  color: colors.success,
                  enabled: canFund && !_busy,
                  onTap: () => _showFundSheet(colors),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionTile(
                  icon: Icons.north_east,
                  label: 'Withdraw',
                  color: colors.accent,
                  enabled: canWithdraw && !_busy,
                  onTap: () => _showWithdrawSheet(colors),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Pause / Resume toggle button
          OutlinedButton.icon(
            icon: Icon(
              isPaused ? Icons.play_circle_outline : Icons.pause_circle_outline,
              color: isPaused ? colors.success : colors.warning,
              size: 18,
            ),
            label: Text(
              isPaused ? 'Resume Goal' : 'Pause Goal',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: _busy || _status == 'COMPLETED' || _status == 'CANCELLED'
                ? null
                : _toggleStatus,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: colors.divider),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          if (_busy) ...[
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accent,
                ),
              ),
            ),
          ],

          if (_status == 'COMPLETED') ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.celebration_outlined,
                      color: colors.success, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Goal complete. You can withdraw the full balance with no penalty.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(AzamanColors colors) {
    final color = switch (_status) {
      'ACTIVE' => colors.success,
      'PAUSED' => colors.warning,
      'COMPLETED' => colors.accent,
      'CANCELLED' => colors.textTertiary,
      _ => colors.textTertiary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _status,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  void _showFundSheet(AzamanColors colors) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AmountPromptSheet(
        title: 'Fund "$_name"',
        ctaLabel: 'Deposit',
        ctaColor: colors.success,
        suggestion: _frequencyAmount > 0 ? _frequencyAmount : null,
        onSubmit: (amount) async {
          Navigator.pop(context);
          await _deposit(amount);
        },
      ),
    );
  }

  void _showWithdrawSheet(AzamanColors colors) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AmountPromptSheet(
        title: 'Withdraw from "$_name"',
        subtitle: _earlyWithdrawalApplies
            ? 'Locked goal \u2014 a 2% early-withdrawal penalty applies.'
            : 'Available: GHS ${_currentGhs.toStringAsFixed(2)}.',
        subtitleColor: _earlyWithdrawalApplies ? colors.danger : null,
        ctaLabel: _earlyWithdrawalApplies ? 'Withdraw with Penalty' : 'Withdraw',
        ctaColor: _earlyWithdrawalApplies ? colors.danger : colors.accent,
        suggestion: _currentGhs,
        max: _currentGhs,
        showWithdrawAllShortcut: true,
        onSubmit: (amount) async {
          Navigator.pop(context);
          await _withdraw(amount);
        },
      ),
    );
  }
}

// -- Sub-sheet: amount input -------------------------------------------------

class _AmountPromptSheet extends ConsumerStatefulWidget {
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final String ctaLabel;
  final Color ctaColor;
  final double? suggestion;
  final double? max;
  final bool showWithdrawAllShortcut;
  final Future<void> Function(double amount) onSubmit;

  const _AmountPromptSheet({
    required this.title,
    this.subtitle,
    this.subtitleColor,
    required this.ctaLabel,
    required this.ctaColor,
    this.suggestion,
    this.max,
    this.showWithdrawAllShortcut = false,
    required this.onSubmit,
  });

  @override
  ConsumerState<_AmountPromptSheet> createState() => _AmountPromptSheetState();
}

class _AmountPromptSheetState extends ConsumerState<_AmountPromptSheet> {
  late TextEditingController _controller;
  String? _error;
  // Phase H3 — GlobalKey for the slider so we can reset() it after a
  // biometric-cancelled or auth-failed gate run.
  final GlobalKey<SlideToConfirmState> _slideKey =
      GlobalKey<SlideToConfirmState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.suggestion?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    final amount = double.tryParse(raw);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a positive amount.');
      return;
    }
    if (widget.max != null && amount > widget.max!) {
      setState(() => _error =
          'Cannot exceed GHS ${widget.max!.toStringAsFixed(2)}.');
      return;
    }
    widget.onSubmit(amount);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).viewInsets.bottom + 22,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.subtitle!,
                style: TextStyle(
                  color: widget.subtitleColor ?? colors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                prefixText: 'GHS ',
                prefixStyle: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                hintText: '0.00',
                filled: true,
                fillColor: colors.card,
                errorText: _error,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (widget.showWithdrawAllShortcut && widget.max != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    _controller.text = widget.max!.toStringAsFixed(2);
                  },
                  child: Text(
                    'Withdraw all (GHS ${widget.max!.toStringAsFixed(2)})',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            // Phase H2 — slide-to-confirm replaces ElevatedButton on this
            // amount-prompt. The widget already routes through
            // `_submit()` for validation (positive, within max), so we
            // re-use it as the confirmed callback. Adds a `commit` haptic
            // on the actual fire so the user feels the moment value moves.
            SlideToConfirm(
              key: _slideKey,
              text: widget.ctaLabel,
              backgroundColor: colors.card,
              thumbColor: widget.ctaColor,
              onConfirmed: () {
                // Phase H3 — biometric pre-gate. No-op when biometric lock is
                // disabled in Settings (opt-in); blocks _submit() if enabled
                // and the prompt fails. Funding/withdrawing a savings goal
                // moves USDC out of availableBalance, so this is treated as
                // a financial confirm. The commit() haptic is now inside the
                // gate's success path so a cancelled auth doesn't emit a
                // "transaction sent" buzz.
                AzamanBiometricGate.runSync(
                  context,
                  () {
                    AzamanHaptics.commit();
                    _submit();
                  },
                  reason: 'Authenticate to ${widget.ctaLabel.toLowerCase()}',
                  onCancelled: () => _slideKey.currentState?.reset(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// -- Action tile (Fund / Withdraw quick buttons) -----------------------------

class _ActionTile extends ConsumerWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final fg = enabled ? color : colors.textTertiary;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: fg.withValues(alpha: 0.16)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: fg, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
