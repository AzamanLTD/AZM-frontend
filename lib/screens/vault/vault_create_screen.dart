// =============================================================================
// VAULT CREATE SCREEN  (Master Sprint, 2026-05-27)
//
// Two-step flow:
//   1. "Rules of the Game" overlay (BackdropFilter, must scroll to bottom
//      AND check the consent box AND tap "I Agree" before continuing).
//   2. The creation form: name, target amount, maturity date, optional
//      auto-rule (amount + frequency).
// =============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/vault_provider.dart';
import 'package:azaman/widgets/azaman_sheet.dart';


class VaultCreateScreen extends ConsumerStatefulWidget {
  const VaultCreateScreen({super.key});

  @override
  ConsumerState<VaultCreateScreen> createState() => _VaultCreateScreenState();
}

class _VaultCreateScreenState extends ConsumerState<VaultCreateScreen> {
  bool _rulesAccepted = false;
  final _name = TextEditingController(text: 'My Vault');
  final _target = TextEditingController();
  DateTime _maturity = DateTime.now().add(const Duration(days: 30));

  bool _autoRule = false;
  String _autoFreq = 'WEEKLY';
  final _autoAmount = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _autoAmount.dispose();
    super.dispose();
  }

  Future<void> _showRules(AzamanColors colors) async {
    // NEW-B / 4th pass — weight: Panel. Seven rules of free-text legal copy
    // plus a consent gate that only unlocks once the reader reaches the
    // bottom. The commit row is PINNED (§I.8.3): the checkbox is disabled
    // until the scroll completes, so a scrolling commit hides the very
    // instruction that explains why it is disabled. The body scrolls through
    // the controller `showPanel` hands the builder (§I.3.4) so drag-to-dismiss
    // and the detent stay one system — no nested DraggableScrollableSheet
    // (§I.13.3).
    final accepted = await AzamanSheet.showPanel<bool>(
      context,
      builder: (_, scrollController) =>
          _RulesSheet(colors: colors, scrollController: scrollController),
    );
    if (accepted == true && mounted) setState(() => _rulesAccepted = true);
  }

  Future<void> _submit() async {
    if (!_rulesAccepted) return;
    final name = _name.text.trim();
    final target = double.tryParse(_target.text.trim());
    if (name.isEmpty || target == null || target <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a name and a positive target.')),
      );
      return;
    }
    Map<String, dynamic>? rule;
    if (_autoRule) {
      final amt = double.tryParse(_autoAmount.text.trim());
      if (amt == null || amt <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Auto-rule amount must be positive.')),
        );
        return;
      }
      rule = {'enabled': true, 'amountUsdc': amt, 'frequency': _autoFreq};
    }

    setState(() => _submitting = true);
    try {
      await ref.read(vaultsProvider.notifier).create(
            name: name,
            targetAmountUsdc: target,
            maturityDate: _maturity,
            autoRule: rule,
          );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    // Auto-prompt rules sheet on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_rulesAccepted) _showRules(colors);
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'New Vault',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: AbsorbPointer(
        absorbing: !_rulesAccepted,
        child: Opacity(
          opacity: _rulesAccepted ? 1 : 0.4,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(colors, 'Vault Name'),
                _input(colors, _name, hint: 'e.g. Lagos Trip 2026'),
                const SizedBox(height: 14),
                _label(colors, 'Target Amount (USDC)'),
                _input(colors, _target,
                    hint: '500.00',
                    keyboard: const TextInputType.numberWithOptions(decimal: true)),
                const SizedBox(height: 14),
                _label(colors, 'Maturity Date'),
                _DatePill(
                  date: _maturity,
                  colors: colors,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _maturity,
                      firstDate: DateTime.now().add(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    );
                    if (picked != null) setState(() => _maturity = picked);
                  },
                ),
                const SizedBox(height: 18),
                _label(colors, 'Auto-Deposit Rule'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _autoRule,
                        onChanged: (v) => setState(() => _autoRule = v),
                        title: Text(
                          'Pull from available balance on schedule',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          _autoRule
                              ? 'I\'ll auto-deduct on a schedule.'
                              : 'You will deposit manually.',
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                        activeColor: colors.accent,
                      ),
                      if (_autoRule) ...[
                        const SizedBox(height: 6),
                        _input(colors, _autoAmount,
                            hint: 'Amount per deposit (USDC)',
                            keyboard: const TextInputType.numberWithOptions(decimal: true)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: ['DAILY', 'WEEKLY', 'BIWEEKLY', 'MONTHLY']
                              .map(
                                (f) => ChoiceChip(
                                  selected: _autoFreq == f,
                                  label: Text(f),
                                  selectedColor: colors.accent.withValues(alpha: 0.20),
                                  onSelected: (_) => setState(() => _autoFreq = f),
                                  labelStyle: TextStyle(
                                    color: _autoFreq == f
                                        ? colors.accent
                                        : colors.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: colors.isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _submitting ? 'Creating…' : 'Create Vault',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                )
                    .animate(target: _submitting ? 0 : 1)
                    .shimmer(
                        delay: 600.ms,
                        duration: 1400.ms,
                        color: Colors.white.withValues(alpha: 0.30)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(AzamanColors colors, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          s.toUpperCase(),
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _input(AzamanColors colors, TextEditingController c,
      {String? hint, TextInputType? keyboard}) {
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
        ),
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  final DateTime date;
  final AzamanColors colors;
  final VoidCallback onTap;
  const _DatePill({required this.date, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: colors.accent, size: 16),
            const SizedBox(width: 8),
            Text(
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Icon(Icons.calendar_today_outlined, color: colors.textTertiary, size: 14),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// RULES SHEET — frosted glass overlay, must scroll-to-bottom + check consent
// ─────────────────────────────────────────────────────────────────────────
/// The vault rules sheet. Scrolling is owned by the Panel weight: the
/// controller handed to the builder IS the sheet's detent controller, so the
/// reader's drag moves the content and the sheet together (§I.3.4). The surface
/// container, the top radius and the drag handle are supplied by
/// `AzSheetSurface` and are deliberately NOT re-declared here (§I.8.1).
class _RulesSheet extends StatefulWidget {
  final AzamanColors colors;

  /// The Panel's own scroll controller. Owned by the sheet; this widget only
  /// reads `hasClients` and disposes nothing.
  final ScrollController scrollController;

  const _RulesSheet({
    required this.colors,
    required this.scrollController,
  });

  @override
  State<_RulesSheet> createState() => _RulesSheetState();
}

class _RulesSheetState extends State<_RulesSheet> {
  bool _scrolledToBottom = false;
  bool _consent = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant _RulesSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final c = widget.scrollController;
    if (!c.hasClients || _scrolledToBottom) return;
    if (c.offset >= c.position.maxScrollExtent - 8) {
      setState(() => _scrolledToBottom = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final canAccept = _scrolledToBottom && _consent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      child: Column(
        children: [
              Row(
                children: [
                  Icon(Icons.gavel, color: colors.warning, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Rules of the Game',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: widget.scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rule(colors, '1. Lockup',
                          'Funds inside this vault are LOCKED until the maturity date. You cannot spend them.'),
                      _rule(colors, '2. Early Break Penalty',
                          'Breaking the vault early forfeits a 5% penalty on the locked balance. The remainder returns to your wallet.'),
                      _rule(colors, '3. AZM Intensity Rewards',
                          'Every deposit earns AZM scaled by your deposit amount, frequency cadence, and current streak. The breakdown is delivered with each deposit.'),
                      _rule(colors, '4. Auto-Deposit',
                          'If enabled, your auto-rule pulls from your available balance on schedule. Missed pulls cost your streak.'),
                      _rule(colors, '5. Streak Discipline',
                          'Consistent on-time deposits multiply your AZM rewards up to +100%. Missed pulls reset the streak.'),
                      _rule(colors, '6. Maturity Sweep',
                          'On maturity, the full locked balance returns to your wallet automatically with a completion bonus and a receipt.'),
                      _rule(colors, '7. Disputes',
                          'These rules are final. Admins do not unlock vaults outside of the maturity sweep or early-break flow.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile.adaptive(
                value: _consent,
                onChanged: _scrolledToBottom ? (v) => setState(() => _consent = v ?? false) : null,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: colors.accent,
                title: Text(
                  _scrolledToBottom
                      ? 'I have read and accept these rules.'
                      : 'Scroll to the bottom to enable consent.',
                  style: TextStyle(
                    color: _scrolledToBottom ? colors.textPrimary : colors.textTertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canAccept
                      ? () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context, true);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.isDark ? Colors.black : Colors.white,
                    disabledBackgroundColor: colors.accent.withValues(alpha: 0.30),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'I Agree — Continue',
                    style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
                  ),
                ),
              ),
            ],
          ),
      );
  }

  Widget _rule(AzamanColors colors, String head, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              head,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
}
