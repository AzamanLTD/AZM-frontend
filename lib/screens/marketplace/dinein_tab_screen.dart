// lib/screens/marketplace/dinein_tab_screen.dart
// =============================================================================
// DINE-IN TAB SCREEN — Customer side
// Uses the canonical customer tab endpoint and can return to the same
// restaurant journey with the active table context.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/dinein_restaurant_ordering_screen.dart';
import 'package:azaman/widgets/skeleton_loader.dart';

class DineInTabScreen extends ConsumerStatefulWidget {
  final String tabId;
  const DineInTabScreen({super.key, required this.tabId});
  @override
  ConsumerState<DineInTabScreen> createState() => _DineInTabScreenState();
}

class _DineInTabScreenState extends ConsumerState<DineInTabScreen> {
  Future<void> _confirmAndPay() async {
    try {
      await ref.read(dineInTabProvider(widget.tabId).notifier).payTab(widget.tabId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment confirmed! Thank you.')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment failed: $e')),
        );
      }
    }
  }

  Future<void> _browseMenu() async {
    final state = ref.read(dineInTabProvider(widget.tabId));
    final tab = state.valueOrNull;
    if (tab == null || tab.businessBizId == null || tab.businessBizId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restaurant menu context is unavailable.')),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DineInRestaurantOrderingScreen(tab: tab),
      ),
    );
    ref.invalidate(dineInTabProvider(widget.tabId));
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final asyncTab = ref.watch(dineInTabProvider(widget.tabId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('Dine-In Tab', style: TextStyle(color: colors.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.close, color: colors.textSecondary),
          onPressed: () => context.pop(),
        ),
      ),
      body: asyncTab.when(
        loading: () => const SkeletonList(itemHeight: 100, count: 4),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
        ),
        data: (tab) {
          if (tab == null) {
            return Center(
              child: Text('Dine-in tab not found.', style: TextStyle(color: colors.textSecondary)),
            );
          }
          final tableLabel = tab.tableLabel;
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: colors.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.restaurant, color: colors.accent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tab.businessName,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.textPrimary),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(tab.status, style: TextStyle(fontSize: 11, color: colors.success, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    if (tableLabel != null && tableLabel.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.table_restaurant_outlined, size: 16, color: colors.textTertiary),
                          const SizedBox(width: 6),
                          Text(
                            tableLabel,
                            style: TextStyle(color: colors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: tab.items.length,
                  itemBuilder: (_, i) {
                    final item = tab.items[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Text('${item.quantity}x', style: TextStyle(fontSize: 14, color: colors.textTertiary)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(item.name, style: TextStyle(fontSize: 14, color: colors.textPrimary))),
                          Text('${item.lineTotal.toStringAsFixed(2)} USDC', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.divider, width: 0.5)),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      if (tab.status == 'OPEN' && tab.businessBizId != null && tab.businessBizId!.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _browseMenu,
                            icon: const Icon(Icons.menu_book_outlined),
                            label: Text(tableLabel == null || tableLabel.isEmpty ? 'Browse menu' : 'Browse menu for $tableLabel'),
                          ),
                        ),
                      if (tab.status == 'OPEN' && tab.businessBizId != null && tab.businessBizId!.isNotEmpty) const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                          Text('${tab.grandTotal.toStringAsFixed(2)} USDC', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: colors.accent)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: tab.status == 'FINALIZED' ? _confirmAndPay : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor: colors.isDark ? Colors.black : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(
                            tab.status == 'FINALIZED' ? 'Confirm & Pay' : (tab.status == 'OPEN' ? 'Waiting for final bill' : 'Tab Closed'),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
