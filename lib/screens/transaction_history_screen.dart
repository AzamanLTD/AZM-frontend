import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/widgets/dual_currency_text.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class TransactionHistoryScreen extends ConsumerStatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  ConsumerState<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends ConsumerState<TransactionHistoryScreen> {
  final ScrollController _scrollController = ScrollController();
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
      backgroundColor: Colors.transparent,
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
          Expanded(
            child: state.isLoading && state.items.isEmpty
                ? _buildShimmer(colors)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: state.items.length + (state.isLoading ? 3 : 0),
                    itemBuilder: (_, i) {
                      if (i >= state.items.length) {
                        return _buildShimmerRow(colors);
                      }
                      final txn = state.items[i];
                      final isExpanded = _expandedId == txn.id;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _expandedId = isExpanded ? null : txn.id;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    txn.type == 'OUT'
                                        ? HugeIconsSolid.arrowUp01
                                        : txn.type == 'INTERNAL'
                                            ? HugeIconsSolid.arrowsRight
                                            : HugeIconsSolid.arrowDown01,
                                    color: txn.type == 'OUT'
                                        ? colors.danger
                                        : txn.type == 'INTERNAL'
                                            ? colors.accent
                                            : colors.success,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          txn.type == 'OUT' ? 'Sent' : txn.type == 'INTERNAL' ? 'Internal' : 'Received',
                                          style: TextStyle(
                                            color: colors.textPrimary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          _relativeDate(txn.createdAt),
                                          style: TextStyle(
                                            color: colors.textSecondary,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${txn.type == 'OUT' ? '-' : '+'}\$${txn.amountUsdc.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: txn.type == 'OUT' ? colors.danger : colors.success,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              if (isExpanded) ...[
                                const SizedBox(height: 12),
                                Divider(color: colors.divider),
                                _detailRow(colors, 'Reference', 'REF: ${txn.id.length > 12 ? txn.id.substring(0, 12) : txn.id}'),
                                _detailRow(colors, 'Provider', txn.provider),
                                _detailRow(colors, 'GHS Equivalent', 'GH₵ ${txn.amountGhs.toStringAsFixed(2)}'),
                                _detailRow(colors, 'Rate', '${txn.rateAtInitiation.toStringAsFixed(2)}'),
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
                    },
                  ),
          ),
        ],
      ),
    );
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
              decoration: BoxDecoration(color: colors.textTertiary.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),
            Text('Azaman', style: TextStyle(color: colors.accent, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: txn.type == 'OUT' ? colors.danger.withOpacity(0.15) : colors.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                txn.type == 'OUT' ? 'Sent' : 'Received',
                style: TextStyle(
                  color: txn.type == 'OUT' ? colors.danger : colors.success,
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
                    onPressed: () {},
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

  void _shareReceipt(TransactionRecord txn) {
    Share.share(
      'Azaman Transaction\n'
      'Amount: \$${txn.amountUsdc.toStringAsFixed(2)}\n'
      'Type: ${txn.type}\n'
      'Status: ${txn.status}\n'
      'Reference: ${txn.id}\n'
      'Date: ${_formatDate(txn.createdAt)}',
    );
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
