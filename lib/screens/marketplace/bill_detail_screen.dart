import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/skeleton_loader.dart';

/// §37 — BillDetailScreen: Customer confirms a finalized dine-in bill.
/// Shows line items, subtotal, tax, tip, and grand total.
/// Customer can confirm (triggers escrow) or dispute.
class BillDetailScreen extends ConsumerStatefulWidget {
  final String tabId;
  const BillDetailScreen({super.key, required this.tabId});

  @override
  ConsumerState<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends ConsumerState<BillDetailScreen> {
  bool _isConfirming = false;

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final tabState = ref.watch(dineInTabProvider(widget.tabId));
    final tab = tabState.valueOrNull;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Bill Details',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: tabState.isLoading
          ? _buildSkeleton(colors)
          : tabState.hasError
              ? _buildError(colors)
              : tab == null
                  ? _buildError(colors)
                  : _buildBillContent(colors, tab),
      bottomNavigationBar: tab != null && tab.status == 'FINALIZED'
          ? _buildConfirmButton(colors, tab)
          : tab != null && tab.status == 'PAID'
              ? _buildPaidBanner(colors)
              : null,
    );
  }

  Widget _buildSkeleton(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SkeletonBlock(height: 120, width: double.infinity, borderRadius: BorderRadius.circular(16)),
          const SizedBox(height: 16),
          SkeletonBlock(height: 60, width: double.infinity, borderRadius: BorderRadius.circular(12)),
          const SizedBox(height: 12),
          SkeletonBlock(height: 60, width: double.infinity, borderRadius: BorderRadius.circular(12)),
          const SizedBox(height: 12),
          SkeletonBlock(height: 60, width: double.infinity, borderRadius: BorderRadius.circular(12)),
        ],
      ),
    );
  }

  Widget _buildError(AzamanColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: colors.danger.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('Could not load bill', style: TextStyle(color: colors.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.invalidate(dineInTabProvider(widget.tabId)),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.isDark ? Colors.black : Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildBillContent(AzamanColors colors, dynamic tab) {
    final items = tab.items as List;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Business info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.divider.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.restaurant, color: colors.accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tab.businessName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tab #${tab.id.length > 8 ? tab.id.substring(0, 8) : tab.id}',
                      style: TextStyle(color: colors.textTertiary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              _buildStatusChip(colors, tab.status),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Line items
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.divider.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Items',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No items yet', style: TextStyle(color: colors.textTertiary)),
                  ),
                )
              else
                ...items.map((item) => _buildLineItem(colors, item)),
              Divider(color: colors.divider.withValues(alpha: 0.5), height: 24),
              _buildTotalRow(colors, 'Subtotal', tab.subtotal),
              const SizedBox(height: 6),
              _buildTotalRow(colors, 'Tax', tab.taxTotal),
              const SizedBox(height: 6),
              _buildTotalRow(colors, 'Tip', tab.tip),
              Divider(color: colors.divider.withValues(alpha: 0.5), height: 20),
              _buildTotalRow(colors, 'Total', tab.grandTotal, isBold: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLineItem(AzamanColors colors, dynamic item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${item.name} × ${item.quantity}',
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ),
          Text(
            '\$${item.lineTotal.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(AzamanColors colors, String label, double amount, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: isBold ? colors.textPrimary : colors.textSecondary,
          ),
        ),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(AzamanColors colors, String status) {
    final Color chipColor;
    final Color textColor;
    switch (status) {
      case 'FINALIZED':
        chipColor = colors.warning.withValues(alpha: 0.12);
        textColor = colors.warning;
        break;
      case 'PAID':
        chipColor = colors.success.withValues(alpha: 0.12);
        textColor = colors.success;
        break;
      case 'OPEN':
        chipColor = colors.accent.withValues(alpha: 0.12);
        textColor = colors.accent;
        break;
      default:
        chipColor = colors.danger.withValues(alpha: 0.12);
        textColor = colors.danger;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildConfirmButton(AzamanColors colors, dynamic tab) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isConfirming
                ? null
                : () async {
                    HapticFeedback.lightImpact();
                    setState(() => _isConfirming = true);
                    try {
                      await ref.read(dineInTabProvider(widget.tabId).notifier)
                          .payTab(widget.tabId);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Bill confirmed! Payment processing...',
                              style: TextStyle(color: colors.textPrimary),
                            ),
                            backgroundColor: colors.success,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        context.pop();
                      }
                    } catch (e) {
                      setState(() => _isConfirming = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e', style: TextStyle(color: colors.textPrimary)),
                            backgroundColor: colors.danger,
                          ),
                        );
                      }
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.success,
              foregroundColor: colors.isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isConfirming
                ? SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.isDark ? Colors.black : Colors.white,
                    ),
                  )
                : const Text(
                    'Confirm & Pay',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaidBanner(AzamanColors colors) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: colors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.success.withValues(alpha: 0.3)),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: colors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                'Bill Paid',
                style: TextStyle(
                  color: colors.success,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
