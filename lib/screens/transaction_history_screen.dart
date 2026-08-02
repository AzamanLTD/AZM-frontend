import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/widgets/dual_currency_text.dart';
import 'package:azaman/widgets/staggered_item.dart';


String _humanLabel(String type) {
  switch (type) {
    case "DEPOSIT_FIAT":             return "MoMo Deposit";
    case "DEPOSIT_CRYPTO":           return "Crypto Deposit";
    case "WITHDRAWAL_FIAT":          return "MoMo Withdrawal";
    case "WITHDRAWAL_CRYPTO":        return "Crypto Withdrawal";
    case "P2P_TRADE":                return "P2P Trade Payout";
    case "INTERNAL_TRANSFER":        return "Transfer";
    case "AZM_REWARD":               return "AZM Reward";
    case "VAULT_DEPOSIT":            return "Vault Lock";
    case "VAULT_RELEASE":            return "Vault Return";
    case "SUSU_CONTRIBUTION":        return "Susu Contribution";
    case "SUSU_PAYOUT":              return "Susu Payout";
    case "SUSU_REFUND":              return "Susu Refund";
    case "SMART_ROUTE_RUN":          return "Smart Route";
    case "TICKET_ESCROW_FUND":       return "Escrow Funded";
    case "TICKET_ESCROW_RELEASE":    return "Escrow Released";
    case "TICKET_ESCROW_REFUND":     return "Escrow Refunded";
    case "BUSINESS_INVOICE_PAYMENT": return "Invoice Payment";
    default:
      final words = type.split("_");
      return words.map((w) => w.isEmpty ? "" : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(" ");
  }
}

class TransactionHistoryScreen extends ConsumerStatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  ConsumerState<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends ConsumerState<TransactionHistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = "";
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future.microtask(() => ref.read(transactionHistoryProvider.notifier).loadMore());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 200) {
      ref.read(transactionHistoryProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(transactionHistoryProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Transactions',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: ['ALL', 'IN', 'OUT', 'INTERNAL'].map((f) {
                final isActive = state.filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => ref.read(transactionHistoryProvider.notifier).setFilter(f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive ? colors.accent : colors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive ? colors.accent : colors.divider,
                        ),
                      ),
                      child: Text(
                        f,
                        style: TextStyle(
                          color: isActive ? Colors.white : colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Search transactions...",
                hintStyle: TextStyle(color: colors.textTertiary),
                prefixIcon: Icon(Icons.search, color: colors.textTertiary, size: 18),
                filled: true, fillColor: colors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: state.error != null && state.items.isEmpty
                ? _buildErrorState(colors, state.error!)
                : state.isLoading && state.items.isEmpty
                    ? _buildShimmer(colors)
                    : _buildGroupedList(colors, state),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList(AzamanColors colors, TransactionHistoryState state) {
    final allTxns = state.items;
    final filtered = _searchQuery.isEmpty ? allTxns : allTxns.where((t) {
      final label = _humanLabel(t.rawType).toLowerCase();
      final amt = t.amountUsdc.toString();
      final id = t.id.toLowerCase();
      return label.contains(_searchQuery) || amt.contains(_searchQuery) || id.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HugeIconsStroke.transactionHistory, size: 48, color: colors.textTertiary),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isEmpty ? 'No transactions yet' : 'No matching transactions',
              style: TextStyle(color: colors.textTertiary, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    final Map<String, List<TransactionRecord>> grouped = {};
    for (final t in filtered) {
      grouped.putIfAbsent(_dateHeader(t.createdAt), () => []).add(t);
    }
    final keys = grouped.keys.toList();

    return ListView.builder(
      controller: _scrollController,
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final header = keys[i];
        final items = grouped[header]!;
        return StaggeredItem(
          index: i,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(header, style: TextStyle(
              color: colors.textTertiary, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ),
          ...items.map((txn) {
            final isExpanded = _expandedId == txn.id;
            return GestureDetector(
              onTap: () { setState(() { _expandedId = isExpanded ? null : txn.id; }); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: txn.category == 'WITHDRAWAL'
                                ? colors.danger.withValues(alpha: 0.1)
                                : txn.category == 'TRANSFER'
                                    ? colors.accent.withValues(alpha: 0.1)
                                    : colors.success.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            txn.category == 'WITHDRAWAL'
                                ? HugeIconsSolid.arrowUp01
                                : txn.category == 'TRANSFER'
                                    ? HugeIconsSolid.arrowDataTransferHorizontal
                                    : HugeIconsSolid.arrowDown01,
                            color: txn.category == 'WITHDRAWAL'
                                ? colors.danger
                                : txn.category == 'TRANSFER'
                                    ? colors.accent
                                    : colors.success,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _humanLabel(txn.rawType),
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${txn.provider.isNotEmpty ? txn.provider : 'Azaman'}  ·  GH₵ ${txn.amountGhs.toStringAsFixed(2)}',
                                style: TextStyle(color: colors.textSecondary, fontSize: 11),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _relativeDate(txn.createdAt),
                                style: TextStyle(color: colors.textTertiary, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${txn.category == 'WITHDRAWAL' ? "-" : "+"}${txn.amountUsdc.toStringAsFixed(2)} USDC',
                              style: TextStyle(
                                color: txn.category == 'WITHDRAWAL' ? colors.danger : colors.success,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                txn.status,
                                style: TextStyle(
                                  color: colors.success,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (isExpanded) ...[
                      const SizedBox(height: 12),
                      Divider(color: colors.divider),
                      _detailRow(colors, 'Reference', 'REF: ${txn.id.length > 12 ? txn.id.substring(0, 12) : txn.id}'),
                      _detailRow(colors, 'Provider', txn.provider),
                      if (txn.counterparty.isNotEmpty)
                        _detailRow(colors, 'Counterparty', txn.counterparty),
                      _detailRow(colors, 'GHS Equivalent', 'GH₵ ${txn.amountGhs.toStringAsFixed(2)}'),
                      _detailRow(colors, 'Rate', txn.rateAtInitiation.toStringAsFixed(2)),
                      _detailRow(colors, 'Settled', _formatDate(txn.createdAt)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showReceiptPopup(txn, colors),
                              icon: const Icon(Icons.receipt, size: 16),
                              label: const Text('Receipt', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colors.accent,
                                side: BorderSide(color: colors.accent),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _shareReceipt(txn),
                              icon: const Icon(Icons.share, size: 16),
                              label: const Text('Share', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colors.accent,
                                side: BorderSide(color: colors.accent),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          ],
        ),
      );
    },
  );
}

  String _dateHeader(DateTime dt) {
    final today = DateTime.now();
    final diff = today.difference(DateTime(dt.year, dt.month, dt.day)).inDays;
    if (diff == 0) return "Today";
    if (diff == 1) return "Yesterday";
    return DateFormat("EEEE, d MMM").format(dt);
  }

  Widget _detailRow(AzamanColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
          Text(value, style: TextStyle(color: colors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildErrorState(AzamanColors colors, String error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(HugeIconsSolid.alertCircle, size: 48, color: colors.danger),
          const SizedBox(height: 12),
          Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => ref.read(transactionHistoryProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry', style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.accent,
              side: BorderSide(color: colors.accent),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer(AzamanColors colors) {
    return Shimmer.fromColors(
      baseColor: colors.card,
      highlightColor: colors.softSurface,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 8,
        itemBuilder: (_, __) => _buildShimmerRow(colors),
      ),
    );
  }

  Widget _buildShimmerRow(AzamanColors colors) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(width: 18, height: 18, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 80, height: 10, color: Colors.white),
                const SizedBox(height: 4),
                Container(width: 120, height: 8, color: Colors.white),
              ],
            ),
          ),
          Container(width: 60, height: 12, color: Colors.white),
        ],
      ),
    );
  }

  void _showReceiptPopup(TransactionRecord txn, AzamanColors colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: colors.textTertiary.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),
            Text('Azaman', style: TextStyle(color: colors.accent, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: txn.category == 'WITHDRAWAL' ? colors.danger.withValues(alpha: 0.15) : colors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _humanLabel(txn.rawType),
                style: TextStyle(
                  color: txn.category == 'WITHDRAWAL' ? colors.danger : colors.success,
                  fontSize: 11, fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            DualCurrencyText(usdc: txn.amountUsdc, ghsRate: txn.rateAtInitiation),
            const SizedBox(height: 12),
            _detailRow(colors, 'Fee', '\$${txn.feeUsdc.toStringAsFixed(2)}'),
            _detailRow(colors, 'Reference', 'REF: ${txn.id.length > 12 ? txn.id.substring(0, 12) : txn.id}'),
            _detailRow(colors, 'Date', _formatDate(txn.createdAt)),
            _detailRow(colors, 'Status', txn.status),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _savePdf(txn);
                    },
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Save PDF', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _shareReceipt(txn),
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Share', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _savePdf(TransactionRecord txn) async {
    try {
      final pdfDoc = pw.Document();
      pdfDoc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text("AZAMAN", style: pw.TextStyle(
              fontSize: 28, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text("Transaction Receipt",
              style: const pw.TextStyle(fontSize: 14)),
            pw.Divider(height: 32),
            _pdfRow("Type",      _humanLabel(txn.rawType)),
            _pdfRow("Amount",    "${txn.amountUsdc.toStringAsFixed(2)} USDC"),
            _pdfRow("Fee",       "${txn.feeUsdc.toStringAsFixed(4)} USDC"),
            _pdfRow("Status",    txn.status),
            _pdfRow("Reference", txn.id),
            _pdfRow("Date",      _formatDate(txn.createdAt)),
            pw.SizedBox(height: 32),
            pw.Text("Azaman Financial Platform  |  Ghana",
              style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ));
      final dir  = await getApplicationDocumentsDirectory();
      final file = File("${dir.path}/azaman_receipt_${txn.id.substring(0,8)}.pdf");
      await file.writeAsBytes(await pdfDoc.save());
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not save PDF: $e")));
      }
    }
  }

  pw.Widget _pdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(value),
        ],
      ),
    );
  }

  Future<void> _shareReceipt(TransactionRecord txn) async {
    try {
      final pdfDoc = pw.Document();
      pdfDoc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text("AZAMAN", style: pw.TextStyle(
              fontSize: 28, fontWeight: pw.FontWeight.bold)),
            pw.Text("Transaction Receipt",
              style: const pw.TextStyle(fontSize: 14)),
            pw.Divider(height: 32),
            _pdfRow("Type",      _humanLabel(txn.rawType)),
            _pdfRow("Amount",    "${txn.amountUsdc.toStringAsFixed(2)} USDC"),
            _pdfRow("Fee",       "${txn.feeUsdc.toStringAsFixed(4)} USDC"),
            _pdfRow("Status",    txn.status),
            _pdfRow("Reference", txn.id),
            _pdfRow("Date",      _formatDate(txn.createdAt)),
            pw.SizedBox(height: 32),
            pw.Text("Azaman Financial Platform  |  Ghana",
              style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ));
      final bytes = await pdfDoc.save();
      final dir  = await getTemporaryDirectory();
      final file = File("${dir.path}/azaman_receipt_${txn.id.substring(0,8)}.pdf");
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: "Azaman Transaction Receipt",
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Share failed: $e")));
      }
    }
  }

  String _relativeDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _formatDate(dt);
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
