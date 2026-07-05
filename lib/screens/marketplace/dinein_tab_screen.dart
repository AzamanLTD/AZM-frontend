// lib/screens/marketplace/dinein_tab_screen.dart
// =============================================================================
// DINE-IN TAB SCREEN — Customer side
// Shows live tab items added by waiter, allows confirm & pay
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';

class DineInTabScreen extends ConsumerStatefulWidget {
  final String tabId;
  const DineInTabScreen({super.key, required this.tabId});
  @override
  ConsumerState<DineInTabScreen> createState() => _DineInTabScreenState();
}

class _DineInTabScreenState extends ConsumerState<DineInTabScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref
        .read(marketplaceBookingProvider.notifier)
        .loadDineInTab(widget.tabId));
  }

  Future<void> _confirmAndPay() async {
    try {
      await ref.read(marketplaceBookingProvider.notifier)
          .confirmDineInTab(widget.tabId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment confirmed! Thank you.')));
        context.pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final tab = ref.watch(marketplaceBookingProvider).dineInTab;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('Dine-In Tab', style: TextStyle(color: colors.textPrimary)),
        leading: IconButton(icon: Icon(Icons.close, color: colors.textSecondary),
          onPressed: () => context.pop()),
      ),
      body: tab == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              // Business info
              Container(
                width: double.infinity, padding: const EdgeInsets.all(16),
                color: colors.surface,
                child: Row(children: [
                  Icon(Icons.restaurant, color: colors.accent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tab.businessName,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary))),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text(tab.status, style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600))),
                ]),
              ),
              // Items list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: tab.items.length,
                  itemBuilder: (_, i) {
                    final item = tab.items[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Text('${item.quantity}x', style: TextStyle(fontSize: 14, color: colors.textTertiary)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item.name,
                          style: TextStyle(fontSize: 14, color: colors.textPrimary))),
                        Text('${item.totalUsdc.toStringAsFixed(2)} USDC',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                      ]),
                    );
                  },
                ),
              ),
              // Total + CTA
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: colors.surface,
                  border: Border(top: BorderSide(color: colors.border, width: 0.5))),
                child: SafeArea(child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                    Text('${tab.totalUsdc.toStringAsFixed(2)} USDC',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: colors.accent)),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: ElevatedButton(
                    onPressed: tab.status == 'OPEN' ? _confirmAndPay : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text(tab.status == 'OPEN' ? 'Confirm & Pay' : 'Tab Closed',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  )),
                ])),
              ),
            ]),
    );
  }
}