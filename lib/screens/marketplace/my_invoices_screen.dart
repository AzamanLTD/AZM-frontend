// =============================================================================
// MY INVOICES SCREEN — Flutter V3 Marketplace Sprint (2026-06-21)
//
// The customer's invoices, filtered by Unpaid / Paid / All. Each card shows
// the invoice ref, business name, total, a status badge and the date. Tapping
// opens the invoice detail (payment screen for unpaid, receipt for paid).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/invoice_detail_screen.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';
import 'package:azaman/widgets/staggered_item.dart';

class MyInvoicesScreen extends ConsumerStatefulWidget {
  const MyInvoicesScreen({super.key});

  @override
  ConsumerState<MyInvoicesScreen> createState() => _MyInvoicesScreenState();
}

class _MyInvoicesScreenState extends ConsumerState<MyInvoicesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() => setState(() {}));
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(myInvoicesProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      ref.read(myInvoicesProvider.notifier).loadMore();
    }
  }

  List<BusinessInvoice> _filtered(List<BusinessInvoice> all) {
    switch (_tabs.index) {
      case 0: // Unpaid
        return all.where((i) => i.status == InvoiceStatus.sent).toList();
      case 1: // Paid
        return all.where((i) => i.status == InvoiceStatus.paid).toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(myInvoicesProvider);
    final invoices = _filtered(state.invoices);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text('My Invoices',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
        bottom: TabBar(
          controller: _tabs,
          labelColor: colors.accent,
          unselectedLabelColor: colors.textTertiary,
          indicatorColor: colors.accent,
          labelStyle:
              const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          tabs: [
            Tab(text: 'Unpaid  (${state.invoices.where((i) => i.status == InvoiceStatus.sent).length})'),
            Tab(text: 'Paid  (${state.invoices.where((i) => i.status == InvoiceStatus.paid).length})'),
            Tab(text: 'All  (${state.invoices.length})'),
          ],
        ),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : invoices.isEmpty
              ? const AzamanEmptyState(
                  icon: Icons.receipt_outlined,
                  title: 'No invoices here',
                  subtitle: 'Invoices from businesses will appear here.',
                )
              : AzPullToRefresh(
        onRefresh: () =>
                      ref.read(myInvoicesProvider.notifier).load(),
        child: ListView.separated(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: invoices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => StaggeredItem(
                      index: i,
                      child: _InvoiceCard(
                      invoice: invoices[i],
                      colors: colors,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InvoiceDetailScreen(
                                invoiceId: invoices[i].id),
                          ),
                        );
                        if (mounted) {
                          ref.read(myInvoicesProvider.notifier).load();
                        }
                      },
                    ),
                    ),
                  ),
                ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final BusinessInvoice invoice;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _InvoiceCard({
    required this.invoice,
    required this.colors,
    required this.onTap,
  });

  Color _statusColor() {
    switch (invoice.status) {
      case InvoiceStatus.sent:
        return colors.warning;
      case InvoiceStatus.paid:
        return colors.success;
      case InvoiceStatus.voided:
        return colors.textTertiary;
      case InvoiceStatus.draft:
        return colors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tint = _statusColor();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.receipt_outlined,
                  color: colors.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    invoice.businessName ?? invoice.invoiceRef,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    invoice.invoiceRef,
                    style:
                        TextStyle(color: colors.textTertiary, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${invoice.billTotalUsdc.toStringAsFixed(2)} USDC',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    invoice.status.label,
                    style: TextStyle(
                      color: tint,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
