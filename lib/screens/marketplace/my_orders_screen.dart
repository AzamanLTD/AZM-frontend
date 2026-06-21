// =============================================================================
// MY ORDERS SCREEN — Flutter V3 Marketplace Sprint (2026-06-21)
//
// The customer's marketplace orders, filtered by All / Active / Completed.
// Each card shows the order ref, title, amount, a colour-coded status badge
// and date. Tapping an order with a linked ticket opens its workspace.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/tickets/ticket_workspace_screen.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen>
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
      ref.read(myOrdersProvider.notifier).load();
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
      ref.read(myOrdersProvider.notifier).loadMore();
    }
  }

  List<BusinessOrder> _filtered(List<BusinessOrder> all) {
    switch (_tabs.index) {
      case 1:
        return all.where((o) => o.status.isActive).toList();
      case 2:
        return all.where((o) => o.status.isDone).toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(myOrdersProvider);
    final orders = _filtered(state.orders);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text('My Orders',
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
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Active'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
              ? AzamanEmptyState(
                  icon: HugeIconsSolid.shoppingBag01,
                  title: 'No orders here',
                  subtitle: 'Your marketplace orders will appear here.',
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(myOrdersProvider.notifier).load(),
                  child: ListView.separated(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _OrderCard(
                      order: orders[i],
                      colors: colors,
                      onTap: () {
                        final tid = orders[i].ticketId;
                        if (tid != null && tid.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TicketWorkspaceScreen(
                                ticketId: tid,
                                friendUsername: orders[i].title,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final BusinessOrder order;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _OrderCard({
    required this.order,
    required this.colors,
    required this.onTap,
  });

  Color _statusColor() {
    switch (order.status) {
      case BusinessOrderStatus.awaitingPayment:
        return colors.warning;
      case BusinessOrderStatus.paid:
      case BusinessOrderStatus.delivered:
        return colors.accent;
      case BusinessOrderStatus.completed:
        return colors.success;
      case BusinessOrderStatus.disputed:
        return colors.danger;
      case BusinessOrderStatus.refunded:
      case BusinessOrderStatus.cancelled:
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.orderRef,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                _Badge(label: order.status.label, tint: tint),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              order.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${order.amountUsdc.toStringAsFixed(2)} USDC',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  _fmtDate(order.createdAt),
                  style: TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color tint;
  const _Badge({required this.label, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tint,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
