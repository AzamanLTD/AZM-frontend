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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/ticket_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/ticket_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';


const _kCurrencies = ['USD', 'GHS', 'USDC', 'USDT', 'AZM', 'EUR', 'GBP', 'NGN'];

class TicketCreateSheet extends ConsumerStatefulWidget {
  // V3 Marketplace Sprint: friendshipId is now optional. When the sheet is
  // opened in business mode (preselectedBusiness != null, or the user flips
  // the Friend/Business toggle) the ticket is bound to a businessProfileId
  // instead of a friendshipId.
  final String? friendshipId;
  final BusinessProfile? preselectedBusiness;
  final BusinessProduct? preselectedProduct;

  const TicketCreateSheet({
    super.key,
    this.friendshipId,
    this.preselectedBusiness,
    this.preselectedProduct,
  });

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

  // ── V3 Marketplace Sprint: business mode + escrow fields ──
  bool _isBusinessMode = false;
  BusinessProfile? _selectedBusiness;
  BusinessProduct? _selectedProduct;
  final _escrowAmountCtrl = TextEditingController();
  final _deliveryTermsCtrl = TextEditingController();
  DateTime? _dueDate;

  // Business search (only used when business mode and no preselected business).
  final _bizSearchCtrl = TextEditingController();
  Timer? _bizDebounce;
  List<BusinessProfile> _bizResults = const [];
  bool _bizSearching = false;

  @override
  void initState() {
    super.initState();
    // Seed from preselected business / product when opened from the marketplace.
    if (widget.preselectedBusiness != null) {
      _isBusinessMode = true;
      _selectedBusiness = widget.preselectedBusiness;
    }
    if (widget.preselectedProduct != null) {
      _isBusinessMode = true;
      _selectedProduct = widget.preselectedProduct;
      _type = TicketType.escrow;
      _nameCtrl.text = widget.preselectedProduct!.name;
      _escrowAmountCtrl.text =
          widget.preselectedProduct!.priceUsdc.toStringAsFixed(2);
      if (widget.preselectedProduct!.deliveryTerms != null) {
        _deliveryTermsCtrl.text = widget.preselectedProduct!.deliveryTerms!;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    _escrowAmountCtrl.dispose();
    _deliveryTermsCtrl.dispose();
    _bizSearchCtrl.dispose();
    _bizDebounce?.cancel();
    super.dispose();
  }

  void _onBizSearchChanged(String value) {
    _bizDebounce?.cancel();
    _bizDebounce = Timer(const Duration(milliseconds: 400), () async {
      final q = value.trim();
      if (q.isEmpty) {
        if (mounted) setState(() => _bizResults = const []);
        return;
      }
      setState(() => _bizSearching = true);
      try {
        final page = await BusinessService().searchBusinesses(q: q, limit: 5);
        if (!mounted) return;
        setState(() {
          _bizResults = page.businesses.take(5).toList();
          _bizSearching = false;
        });
      } catch (_) {
        if (mounted) setState(() => _bizSearching = false);
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null) return;

    final business = widget.preselectedBusiness ?? _selectedBusiness;
    if (_isBusinessMode && business == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Pick a business first.'),
        backgroundColor: ref.read(themeProvider).colors.danger,
      ));
      return;
    }
    if (!_isBusinessMode && widget.friendshipId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('No friendship context for this deal.'),
        backgroundColor: ref.read(themeProvider).colors.danger,
      ));
      return;
    }
    // Escrow amount is required (> 0) when the type is escrow.
    double? escrowAmount;
    if (_type == TicketType.escrow) {
      escrowAmount = double.tryParse(_escrowAmountCtrl.text.trim());
      if (escrowAmount == null || escrowAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Enter a valid escrow amount.'),
          backgroundColor: ref.read(themeProvider).colors.danger,
        ));
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      if (_isBusinessMode && business != null) {
        final ticket = await _createBusinessTicket(amount, business, escrowAmount);
        if (!mounted) return;
        AzamanHaptics.commit();
        Navigator.of(context).pop(ticket);
        return;
      }

      final notifier =
          ref.read(ticketDashboardProvider(widget.friendshipId!).notifier);
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

  /// Business-mode create. The backend /tickets endpoint accepts either a
  /// friendshipId OR a businessProfileId; here we send the latter plus the
  /// escrow fields, and parse the returned ticket directly (the friendship
  /// dashboard notifier doesn't apply because there is no friendship).
  Future<Ticket> _createBusinessTicket(
    double amount,
    BusinessProfile business,
    double? escrowAmount,
  ) async {
    final body = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'type': _type.wire,
      'targetAmount': amount,
      'targetCurrency': _currency,
      'businessProfileId': business.id,
    };
    if (_type == TicketType.escrow) {
      body['escrowAmount'] = escrowAmount;
      if (_deliveryTermsCtrl.text.trim().isNotEmpty) {
        body['deliveryTerms'] = _deliveryTermsCtrl.text.trim();
      }
      if (_dueDate != null) body['dueDate'] = _dueDate!.toIso8601String();
      final product = widget.preselectedProduct ?? _selectedProduct;
      if (product != null) body['productId'] = product.id;
    } else if (_memoCtrl.text.trim().isNotEmpty) {
      body['memo'] = _memoCtrl.text.trim();
    }
    final res = await apiClient.post('/tickets', body);
    final decoded = jsonDecode(res.body);
    if (res.statusCode != 201 || decoded['ticket'] == null) {
      throw Exception(decoded['message']?.toString() ?? 'Create failed');
    }
    return Ticket.fromJson(decoded['ticket'] as Map<String, dynamic>);
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
                    Icon(Icons.confirmation_number_outlined,
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

                // ── V3: Friend vs Business mode toggle (hidden when a business
                //    was preselected from the marketplace). ──
                if (widget.preselectedBusiness == null &&
                    widget.preselectedProduct == null) ...[
                  _modeToggle(colors),
                  const SizedBox(height: 16),
                ],

                // ── V3: Business selector (search or selected card). ──
                if (_isBusinessMode) ...[
                  _businessSelector(colors),
                  const SizedBox(height: 16),
                ],

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

                // ── V3: Escrow-specific fields (amount + fee preview + terms
                //    + due date) shown only when the type is Escrow. ──
                if (_type == TicketType.escrow) ...[
                  _escrowFields(colors),
                  const SizedBox(height: 14),
                ],

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
                        : const Icon(Icons.confirmation_number_outlined, size: 18),
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

  // ── V3 Marketplace Sprint — business mode + escrow UI builders ──

  Widget _modeToggle(AzamanColors colors) {
    Widget seg(String label, bool active, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? colors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active
                    ? (colors.isDark ? Colors.black : Colors.white)
                    : colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          seg('Friend Deal', !_isBusinessMode, () {
            AzamanHaptics.toggle();
            setState(() => _isBusinessMode = false);
          }),
          seg('Business Deal', _isBusinessMode, () {
            AzamanHaptics.toggle();
            setState(() => _isBusinessMode = true);
          }),
        ],
      ),
    );
  }

  Widget _businessSelector(AzamanColors colors) {
    final business = widget.preselectedBusiness ?? _selectedBusiness;
    if (business != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.accentSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.accent.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.storefront_outlined, color: colors.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(business.businessName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      )),
                  Text(business.bizId,
                      style: TextStyle(
                          color: colors.textTertiary, fontSize: 11)),
                ],
              ),
            ),
            // Only allow clearing when the business wasn't preselected.
            if (widget.preselectedBusiness == null)
              GestureDetector(
                onTap: () => setState(() {
                  _selectedBusiness = null;
                  _bizResults = const [];
                  _bizSearchCtrl.clear();
                }),
                child: Icon(Icons.cancel_outlined,
                    color: colors.textTertiary, size: 20),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label('Business', colors),
        const SizedBox(height: 6),
        TextFormField(
          controller: _bizSearchCtrl,
          onChanged: _onBizSearchChanged,
          decoration: _decoration(colors, 'Search business or BIZ-ID'),
        ),
        if (_bizSearching)
          const Padding(
            padding: EdgeInsets.all(10),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ..._bizResults.map((b) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading:
                  Icon(Icons.storefront_outlined, color: colors.accent, size: 18),
              title: Text(b.businessName,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700)),
              subtitle: Text(b.bizId,
                  style: TextStyle(color: colors.textTertiary, fontSize: 11)),
              onTap: () => setState(() {
                _selectedBusiness = b;
                _bizResults = const [];
              }),
            )),
      ],
    );
  }

  Widget _escrowFields(AzamanColors colors) {
    final amt = double.tryParse(_escrowAmountCtrl.text.trim()) ?? 0;
    final fee = amt * 0.005;
    final total = amt + fee;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label('Escrow Amount (USDC)', colors),
        const SizedBox(height: 6),
        TextFormField(
          controller: _escrowAmountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}')),
          ],
          onChanged: (_) => setState(() {}),
          decoration: _decoration(colors, '0.00'),
        ),
        if (amt > 0) ...[
          const SizedBox(height: 6),
          Text(
            'Platform fee: ${fee.toStringAsFixed(2)} USDC — Total: ${total.toStringAsFixed(2)} USDC',
            style: TextStyle(color: colors.textTertiary, fontSize: 11.5),
          ),
        ],
        const SizedBox(height: 12),
        _Label('Delivery Terms (optional)', colors),
        const SizedBox(height: 6),
        TextFormField(
          controller: _deliveryTermsCtrl,
          maxLength: 1000,
          maxLines: 3,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: _decoration(colors, 'Scope, timeline, conditions…'),
        ),
        const SizedBox(height: 12),
        _Label('Due Date (optional)', colors),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _dueDate ?? now.add(const Duration(days: 7)),
              firstDate: now,
              lastDate: now.add(const Duration(days: 365)),
            );
            if (picked != null) setState(() => _dueDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.widgets_outlined,
                    size: 18, color: colors.textTertiary),
                const SizedBox(width: 10),
                Text(
                  _dueDate == null
                      ? 'Select a due date'
                      : '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: _dueDate == null
                        ? colors.textTertiary
                        : colors.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
