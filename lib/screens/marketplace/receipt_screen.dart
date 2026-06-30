import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/receipt_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_button.dart';

class ReceiptScreen extends ConsumerStatefulWidget {
  final BusinessInvoice invoice;
  final String businessName;
  final String? businessLogoUrl;

  const ReceiptScreen({
    super.key,
    required this.invoice,
    required this.businessName,
    this.businessLogoUrl,
  });

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.elasticOut,
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  String get _invoiceRef => widget.invoice.invoiceRef;

  String _shareText() {
    final inv = widget.invoice;
    final buf = StringBuffer();
    buf.writeln('Azaman Receipt');
    buf.writeln('${widget.businessName}');
    buf.writeln('Ref: ${inv.invoiceRef}');
    buf.writeln('---');
    for (final item in inv.lineItems) {
      buf.writeln('${item.description}  ${item.lineTotalUsdc.toStringAsFixed(2)} USDC');
    }
    if (inv.taxLines.isNotEmpty) {
      buf.writeln('---');
      for (final tax in inv.taxLines) {
        buf.writeln('${tax.label}  ${tax.amountUsdc.toStringAsFixed(2)} USDC');
      }
    }
    buf.writeln('---');
    buf.writeln('Total: ${inv.billTotalUsdc.toStringAsFixed(2)} USDC');
    if (inv.paidAt != null) {
      buf.writeln('Paid: ${inv.paidAt.toString()}');
    }
    return buf.toString();
  }

  Future<void> _downloadPdf() async {
    AzamanHaptics.confirm();
    try {
      await ReceiptService.downloadInvoiceReceipt(_invoiceRef);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt downloaded'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: ref.read(themeProvider).colors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _share() {
    AzamanHaptics.confirm();
    Share.share(_shareText());
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final inv = widget.invoice;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text('Receipt',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: Column(
          children: [
            // Success animation
            ScaleTransition(
              scale: _scaleAnim,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.success.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle_outline,
                    color: colors.success, size: 40),
              ),
            ),
            const SizedBox(height: 8),
            Text('Payment Successful',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 24),

            // Receipt card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.divider),
              ),
              child: Column(
                children: [
                  _businessHeader(colors),
                  const SizedBox(height: 16),
                  Divider(color: colors.divider),
                  const SizedBox(height: 12),
                  // Ref + date
                  _infoRow(
                      colors, 'Reference', _invoiceRef),
                  const SizedBox(height: 6),
                  if (inv.paidAt != null)
                    _infoRow(colors, 'Date', _fmtDate(inv.paidAt!)),
                  const SizedBox(height: 14),
                  Divider(color: colors.divider),
                  const SizedBox(height: 10),
                  // Line items
                  ...inv.lineItems.map((item) => _lineRow(colors, item)),
                  // Tax lines
                  ...inv.taxLines.map((tax) => _taxRow(colors, tax)),
                  const SizedBox(height: 10),
                  Divider(color: colors.divider, thickness: 1.5),
                  const SizedBox(height: 8),
                  _totalRow(colors, 'Subtotal', inv.subtotalUsdc),
                  if (inv.tipUsdc > 0)
                    _totalRow(colors, 'Tip', inv.tipUsdc),
                  _totalRow(colors, 'Total', inv.billTotalUsdc,
                      emphasize: true),
                  const SizedBox(height: 20),

                  // QR Code
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: _invoiceRef,
                      version: QrVersions.auto,
                      size: 120,
                      eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Scan to verify receipt',
                      style: TextStyle(
                          color: colors.textTertiary, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Action buttons
            AzamanButton(
              label: 'Share Receipt',
              icon: Icons.ios_share_outlined,
              variant: AzamanButtonVariant.primary,
              size: AzamanButtonSize.large,
              fullWidth: true,
              onPressed: _share,
            ),
            const SizedBox(height: 12),
            AzamanButton(
              label: 'Download PDF',
              icon: Icons.download_outlined,
              variant: AzamanButtonVariant.secondary,
              size: AzamanButtonSize.large,
              fullWidth: true,
              onPressed: _downloadPdf,
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  Widget _businessHeader(AzamanColors colors) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accentSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.storefront_outlined, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.businessName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              Text('Azaman Marketplace',
                  style: TextStyle(
                      color: colors.textTertiary, fontSize: 11.5)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(AzamanColors colors, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(color: colors.textTertiary, fontSize: 12)),
        Text(value,
            style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _lineRow(AzamanColors colors, InvoiceLineItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.description,
                    style: TextStyle(
                        color: colors.textPrimary, fontSize: 13)),
                Text('${item.quantity} × ${item.unitPriceUsdc.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: colors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          Text('${item.lineTotalUsdc.toStringAsFixed(2)} USDC',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _taxRow(AzamanColors colors, InvoiceTaxLine tax) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${tax.label} (${tax.isPercentage ? '${tax.value.toStringAsFixed(1)}%' : 'flat'})',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          Text('${tax.amountUsdc.toStringAsFixed(2)} USDC',
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
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
                color:
                    emphasize ? colors.textPrimary : colors.textSecondary,
                fontSize: 13,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
              )),
          Text('${value.toStringAsFixed(2)} USDC',
              style: TextStyle(
                color:
                    emphasize ? colors.textPrimary : colors.textSecondary,
                fontSize: 13,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              )),
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
