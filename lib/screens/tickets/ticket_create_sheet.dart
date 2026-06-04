// =============================================================================
// TICKET CREATE SHEET — Phase UI-4 (2026-05-26)
//
// Bottom sheet form for spawning a new ticket workspace inside a friendship.
// Required fields:
//   • Ticket Name           (1–80 chars)
//   • Transaction Type      (Buy / Sell / Escrow / Service Swap)
//   • Target Amount         (positive decimal)
//   • Asset Currency        (USD, GHS, USDC, USDT, AZM, +)
//   • Memo / Terms of Deal  (optional, ≤500 chars)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/ticket_provider.dart';
import 'package:azaman/services/ticket_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';

const _kCurrencies = ['USD', 'GHS', 'USDC', 'USDT', 'AZM', 'EUR', 'GBP', 'NGN'];

class TicketCreateSheet extends ConsumerStatefulWidget {
  final String friendshipId;
  const TicketCreateSheet({super.key, required this.friendshipId});

  @override
  ConsumerState<TicketCreateSheet> createState() => _TicketCreateSheetState();
}

class _TicketCreateSheetState extends ConsumerState<TicketCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  TicketType _type = TicketType.buy;
  String _currency = 'USD';
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null) return;
    setState(() => _submitting = true);
    try {
      final notifier = ref.read(ticketDashboardProvider(widget.friendshipId).notifier);
      final ticket = await notifier.createTicket(
        name: _nameCtrl.text.trim(),
        type: _type,
        targetAmount: amount,
        targetCurrency: _currency,
        memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
      );
      if (!mounted) return;
      AzamanHaptics.commit();
      Navigator.of(context).pop(ticket);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not create ticket: $e'),
        backgroundColor: ref.read(themeProvider).colors.danger,
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.confirmation_number_rounded,
                        color: colors.accent, size: 20),
                    const SizedBox(width: 8),
                    Text('New Ticket',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        )),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Create an isolated workspace to track this deal.',
                  style: TextStyle(color: colors.textTertiary, fontSize: 12),
                ),
                const SizedBox(height: 18),

                _Label('Ticket Name', colors),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _decoration(colors, 'e.g. "AAPL stock buy" or "Logo redesign deal"'),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Required';
                    if (t.length > 80) return 'Max 80 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                _Label('Transaction Type', colors),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: TicketType.values.map((t) {
                    final selected = t == _type;
                    return ChoiceChip(
                      label: Text(t.label),
                      selected: selected,
                      onSelected: (_) => setState(() => _type = t),
                      backgroundColor: colors.card,
                      selectedColor: colors.accent.withOpacity(0.18),
                      side: BorderSide(
                        color: selected ? colors.accent : colors.divider,
                        width: selected ? 1.4 : 1,
                      ),
                      labelStyle: TextStyle(
                        color: selected ? colors.accent : colors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                _Label('Target Amount', colors),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,8}')),
                        ],
                        decoration: _decoration(colors, '0.00'),
                        validator: (v) {
                          final amt = double.tryParse((v ?? '').trim());
                          if (amt == null || amt <= 0) return 'Positive number';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _currency,
                        decoration: _decoration(colors, ''),
                        items: _kCurrencies
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c,
                                      style: TextStyle(
                                          color: colors.textPrimary)),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _currency = v);
                        },
                        dropdownColor: colors.card,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                _Label('Memo / Terms of Deal (optional)', colors),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _memoCtrl,
                  maxLength: 500,
                  maxLines: 4,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _decoration(
                    colors,
                    'Specifics, timeline, escrow conditions, etc.',
                  ),
                ),
                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.isDark ? Colors.black : Colors.white,
                            ),
                          )
                        : const Icon(Icons.confirmation_number_rounded, size: 18),
                    label: Text(_submitting ? 'Creating…' : 'Create Ticket'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor:
                          colors.isDark ? Colors.black : Colors.white,
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
        ),
      ),
    );
  }

  InputDecoration _decoration(AzamanColors colors, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
      filled: true,
      fillColor: colors.card,
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.accent, width: 1.2),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final AzamanColors colors;
  const _Label(this.text, this.colors);
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: colors.textTertiary,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }
}
