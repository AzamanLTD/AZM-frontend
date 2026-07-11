// =============================================================================
// TICKET CREATE SHEET — Redesigned 2026-07-11
//
// Context-aware escrow / deal creator for 1-on-1 friend chats.
// The sheet NEVER asks the user for AZM-IDs or Business IDs — those are
// derived from the chat context (chatId = friendshipId, peer info passed in).
//
// Required fields from caller:
//   • friendshipId  — the chat / friendship ID
//   • peerName      — display name of the other person
//
// What the user fills in:
//   1. Ticket title / deal description  (1–80 chars)
//   2. Amount + currency                (numeric keypad)
//   3. Escrow toggle                    (yes / no — simplifies the UX)
//   4. Terms / memo                     (optional, 500 chars)
//
// Visual language mirrors the deposit screen:
//   dark surface card, accent border, same input decoration style.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/ticket_provider.dart';
import 'package:azaman/services/ticket_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';

// Supported currencies — shown as horizontal pill selectors.
const _kCurrencies = ['USDC', 'USD', 'GHS', 'USDT', 'AZM'];

class TicketCreateSheet extends ConsumerStatefulWidget {
  /// The friendship / chat ID — used as the ticket's friendshipId.
  final String? friendshipId;

  /// Display name of the other person in this chat.
  final String peerName;

  // Kept for marketplace compat — ignored in the new friend-chat flow.
  final dynamic preselectedBusiness;
  final dynamic preselectedProduct;

  const TicketCreateSheet({
    super.key,
    this.friendshipId,
    this.peerName = 'Other party',
    this.preselectedBusiness,
    this.preselectedProduct,
  });

  @override
  ConsumerState<TicketCreateSheet> createState() => _TicketCreateSheetState();
}

class _TicketCreateSheetState extends ConsumerState<TicketCreateSheet>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();

  String _currency = 'USDC';
  bool _enableEscrow = true; // default ON — the primary use-case
  bool _submitting = false;

  // Subtle shake animation on validation fail
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      _shakeCtrl.forward(from: 0);
      AzamanHaptics.warn();
      return;
    }
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      _shakeCtrl.forward(from: 0);
      return;
    }
    if (widget.friendshipId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No chat context found.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final notifier =
          ref.read(ticketDashboardProvider(widget.friendshipId!).notifier);
      final ticket = await notifier.createTicket(
        name: _titleCtrl.text.trim(),
        type: _enableEscrow ? TicketType.escrow : TicketType.buy,
        targetAmount: amount,
        targetCurrency: _currency,
        memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
      );
      if (!mounted) return;
      AzamanHaptics.commit();
      Navigator.of(context).pop(ticket);
    } catch (e) {
      if (!mounted) return;
      final colors = ref.read(themeProvider).colors;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not create ticket: $e'),
        backgroundColor: colors.danger,
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: colors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // ── Header ─────────────────────────────────────────────────
                _Header(colors: colors, peerName: widget.peerName),
                const SizedBox(height: 24),

                // ── Deal title ─────────────────────────────────────────────
                _FieldLabel(label: 'What is this deal about?', colors: colors),
                const SizedBox(height: 6),
                AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (ctx, child) => Transform.translate(
                    offset: Offset(
                        8 * _shakeAnim.value * (1 - _shakeAnim.value) * 4, 0),
                    child: child,
                  ),
                  child: TextFormField(
                    controller: _titleCtrl,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: _inputDeco(colors,
                        hint: 'e.g. "Payment for logo design"'),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Please describe the deal';
                      if (t.length > 80) return 'Max 80 characters';
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // ── Amount ─────────────────────────────────────────────────
                _FieldLabel(label: 'Amount', colors: colors),
                const SizedBox(height: 6),
                _AmountRow(
                  colors: colors,
                  amountCtrl: _amountCtrl,
                  currency: _currency,
                  onCurrencyChanged: (c) => setState(() => _currency = c),
                ),
                const SizedBox(height: 20),

                // ── Escrow toggle ──────────────────────────────────────────
                _EscrowToggle(
                  colors: colors,
                  enabled: _enableEscrow,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    setState(() => _enableEscrow = v);
                  },
                ),
                const SizedBox(height: 20),

                // ── Memo ───────────────────────────────────────────────────
                _FieldLabel(
                    label: 'Terms / Notes  (optional)', colors: colors),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _memoCtrl,
                  maxLength: 500,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: _inputDeco(colors,
                      hint: 'Delivery timeline, conditions, or anything else…'),
                ),
                const SizedBox(height: 24),

                // ── CTA ────────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _enableEscrow
                                    ? Icons.lock_outline_rounded
                                    : Icons.receipt_long_outlined,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _enableEscrow
                                    ? 'Create Escrow Deal'
                                    : 'Create Ticket',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                  ),
                ),

                // Small reassurance text
                if (_enableEscrow) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      '🔒 Funds are locked until both parties confirm.',
                      style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
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

  InputDecoration _inputDeco(AzamanColors colors, {String hint = ''}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
        filled: true,
        fillColor: colors.card,
        counterStyle:
            TextStyle(color: colors.textTertiary, fontSize: 10),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.danger),
        ),
      );
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final AzamanColors colors;
  final String peerName;
  const _Header({required this.colors, required this.peerName});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                colors.accent.withValues(alpha: 0.85),
                colors.accent.withValues(alpha: 0.4),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(Icons.lock_outline_rounded,
              color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'New Deal',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.1),
              ),
              const SizedBox(height: 2),
              Text(
                'With $peerName',
                style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final AzamanColors colors;
  const _FieldLabel({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3),
      );
}

class _AmountRow extends StatelessWidget {
  final AzamanColors colors;
  final TextEditingController amountCtrl;
  final String currency;
  final ValueChanged<String> onCurrencyChanged;
  const _AmountRow({
    required this.colors,
    required this.amountCtrl,
    required this.currency,
    required this.onCurrencyChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: TextFormField(
            controller: amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}')),
            ],
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800),
              filled: true,
              fillColor: colors.card,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.accent, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.danger),
              ),
            ),
            validator: (v) {
              final amt = double.tryParse((v ?? '').trim());
              if (amt == null || amt <= 0) return 'Enter an amount';
              return null;
            },
          ),
        ),
        const SizedBox(width: 10),
        // Currency picker column
        Expanded(
          flex: 3,
          child: Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.divider),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: currency,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                borderRadius: BorderRadius.circular(14),
                dropdownColor: colors.card,
                isExpanded: true,
                items: _kCurrencies
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c,
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onCurrencyChanged(v);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EscrowToggle extends StatelessWidget {
  final AzamanColors colors;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _EscrowToggle({
    required this.colors,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!enabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: enabled
              ? colors.accent.withValues(alpha: 0.10)
              : colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled
                ? colors.accent.withValues(alpha: 0.55)
                : colors.divider,
            width: enabled ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled
                    ? colors.accent.withValues(alpha: 0.18)
                    : colors.softSurface,
              ),
              child: Icon(
                enabled ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: enabled ? colors.accent : colors.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enable Escrow',
                    style: TextStyle(
                        color: enabled
                            ? colors.accent
                            : colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled
                        ? 'Funds are held securely until you both confirm.'
                        : 'No fund lock — this is a tracked deal only.',
                    style: TextStyle(
                        color: colors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: onChanged,
              activeColor: colors.accent,
            ),
          ],
        ),
      ),
    );
  }
}
