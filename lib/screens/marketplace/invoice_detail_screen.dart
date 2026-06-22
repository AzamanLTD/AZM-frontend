// =============================================================================
// INVOICE DETAIL SCREEN — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Full invoice view: business header, line items, tax lines, totals. For a
// SENT invoice it shows the payment section — optional tip, a "cover platform
// fee" toggle, a customer note, and a SlideToConfirm gated by the biometric
// gate. PAID shows a receipt; VOIDED shows a notice.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/utils/biometric_gate.dart';
import 'package:azaman/widgets/slide_to_confirm.dart';

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  ConsumerState<InvoiceDetailScreen> createState() =>
      _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  final _service = BusinessService();
  final _slideKey = GlobalKey<SlideToConfirmState>();
  final _tipCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  BusinessInvoice? _invoice;
  bool _loading = true;
  bool _coverFee = false;
  bool _paying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tipCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final invoice = await _service.getInvoice(widget.invoiceId);
      if (!mounted) return;
      setState(() {
        _invoice = invoice;
        _coverFee = invoice.customerCoveredFee;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  double get _tip => double.tryParse(_tipCtrl.text.trim()) ?? 0;

  double get _totalToPay {
    final inv = _invoice;
    if (inv == null) return 0;
    final fee = _coverFee ? inv.feeUsdc : 0;
    return inv.billTotalUsdc + _tip + fee;
  }

  Future<void> _pay() async {
    final inv = _invoice;
    if (inv == null) return;
    await AzamanBiometricGate.run(
      context,
      () async {
        setState(() => _paying = true);
        try {
          final updated = await _service.payInvoice(
            invoiceId: inv.id,
            tipUsdc: _tip,
            customerNote:
                _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
            customerCoveredFee: _coverFee,
          );
          if (!mounted) return;
          AzamanHaptics.commit();
          setState(() {
            _invoice = updated;
            _paying = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Invoice paid. Thank you!'),
            behavior: SnackBarBehavior.floating,
          ));
        } catch (e) {
          if (!mounted) return;
          setState(() => _paying = false);
          _slideKey.currentState?.reset();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Payment failed: $e'),
            backgroundColor: ref.read(themeProvider).colors.danger,
            behavior: SnackBarBehavior.floating,
          ));
        }
      },
      reason: 'Authenticate to pay invoice',
      onCancelled: () => _slideKey.currentState?.reset(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text('Invoice',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _invoice == null
              ? Center(
                  child: Text(_error ?? 'Invoice not found',
                      style: TextStyle(color: colors.textTertiary)),
                )
              : _body(colors, _invoice!),
    );
  }

  Widget _body(AzamanColors colors, BusinessInvoice inv) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header(colors, inv),
        const SizedBox(height: 16),
        _section(colors, 'Items', _lineItems(colors, inv)),
        const SizedBox(height: 12),
        _totals(colors, inv),
        const SizedBox(height: 16),
        if (inv.status == InvoiceStatus.sent) _paymentSection(colors, inv),
        if (inv.status == InvoiceStatus.paid) _paidReceipt(colors, inv),
        if (inv.status == InvoiceStatus.voided) _voidedNotice(colors),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _header(AzamanColors colors, BusinessInvoice inv) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accentSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(HugeIconsSolid.store01, color: colors.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  inv.businessName ?? 'Business',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(inv.invoiceRef,
                    style:
                        TextStyle(color: colors.textTertiary, fontSize: 12)),
                if (inv.locationLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${inv.locationLabel}${inv.tableLabel != null ? ' · ${inv.tableLabel}' : ''}',
                      style:
                          TextStyle(color: colors.textTertiary, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(AzamanColors colors, String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            )),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _lineItems(AzamanColors colors, BusinessInvoice inv) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          for (final item in inv.lineItems)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(item.description,
                            style: TextStyle(
                                color: colors.textPrimary, fontSize: 13.5)),
                        Text(
                          '${item.quantity} × ${item.unitPriceUsdc.toStringAsFixed(2)}',
                          style: TextStyle(
                              color: colors.textTertiary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${item.lineTotalUsdc.toStringAsFixed(2)} USDC',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          if (inv.lineItems.isEmpty)
            Text('No line items',
                style: TextStyle(color: colors.textTertiary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _totals(AzamanColors colors, BusinessInvoice inv) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          _totalRow(colors, 'Subtotal', inv.subtotalUsdc),
          for (final tax in inv.taxLines)
            _totalRow(
              colors,
              '${tax.label} (${tax.isPercentage ? '${tax.value.toStringAsFixed(1)}%' : 'flat'})',
              tax.amountUsdc,
            ),
          if (inv.tipUsdc > 0) _totalRow(colors, 'Tip', inv.tipUsdc),
          Divider(color: colors.divider, height: 18),
          _totalRow(colors, 'Bill total', inv.billTotalUsdc, emphasize: true),
        ],
      ),
    );
  }

  Widget _totalRow(AzamanColors colors, String label, double value,
      {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                color: emphasize ? colors.textPrimary : colors.textSecondary,
                fontSize: 13,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
              )),
          Text('${value.toStringAsFixed(2)} USDC',
              style: TextStyle(
                color: emphasize ? colors.textPrimary : colors.textSecondary,
                fontSize: 13,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              )),
        ],
      ),
    );
  }

  Widget _paymentSection(AzamanColors colors, BusinessInvoice inv) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PAY THIS INVOICE',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            )),
        const SizedBox(height: 10),
        // Tip
        TextField(
          controller: _tipCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Tip (optional)',
            labelStyle: TextStyle(color: colors.textTertiary),
            prefixIcon: Icon(HugeIconsStroke.coins01,
                size: 18, color: colors.textTertiary),
            filled: true,
            fillColor: colors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Cover fee toggle
        Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SwitchListTile(
            value: _coverFee,
            onChanged: (v) {
              AzamanHaptics.toggle();
              setState(() => _coverFee = v);
            },
            activeColor: colors.success,
            title: Text('Cover platform fee',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            subtitle: Text(
              'Add ${inv.feeUsdc.toStringAsFixed(2)} USDC so the business receives the full amount',
              style: TextStyle(color: colors.textTertiary, fontSize: 11.5),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Note
        TextField(
          controller: _noteCtrl,
          maxLines: 2,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Note to business (optional)',
            labelStyle: TextStyle(color: colors.textTertiary),
            filled: true,
            fillColor: colors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total to pay',
                style: TextStyle(
                    color: colors.textSecondary, fontSize: 13)),
            Text('${_totalToPay.toStringAsFixed(2)} USDC',
                style: TextStyle(
                    color: colors.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 12),
        SlideToConfirm(
          key: _slideKey,
          text: 'Slide to pay',
          backgroundColor: colors.card,
          thumbColor: colors.accent,
          isLoading: _paying,
          onConfirmed: _pay,
        ),
      ],
    );
  }

  Widget _paidReceipt(AzamanColors colors, BusinessInvoice inv) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(HugeIconsSolid.checkmarkCircle01,
              color: colors.success, size: 40),
          const SizedBox(height: 8),
          Text('Paid',
              style: TextStyle(
                  color: colors.success,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'You paid ${(inv.customerPaidUsdc ?? inv.billTotalUsdc).toStringAsFixed(2)} USDC',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          if (inv.paidAt != null)
            Text(
              _fmtDate(inv.paidAt!),
              style: TextStyle(color: colors.textTertiary, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _voidedNotice(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(HugeIconsSolid.cancelCircle, color: colors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('This invoice was voided by the business.',
                style: TextStyle(color: colors.textTertiary, fontSize: 13)),
          ),
        ],
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
