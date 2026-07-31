// =============================================================================
// MY ORDERS SCREEN — Flutter V3 Marketplace Sprint (2026-06-21)
//
// The customer's marketplace orders, filtered by All / Active / Completed.
// Each card shows the order ref, title, amount, a colour-coded status badge
// and date. Tapping an order with a linked ticket opens its workspace.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/tickets/ticket_workspace_screen.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:azaman/screens/orders/order_tracking_screen.dart';
import 'package:azaman/screens/storefront_screen.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';
import 'package:azaman/widgets/staggered_item.dart';

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
              ? const AzamanEmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'No orders here',
                  subtitle: 'Your marketplace orders will appear here.',
                )
              : AzPullToRefresh(
        onRefresh: () =>
                      ref.read(myOrdersProvider.notifier).load(),
        child: ListView.separated(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => StaggeredItem(
                      index: i,
                      child: _OrderCard(
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
      case BusinessOrderStatus.awaitingPayment: return colors.warning;
      case BusinessOrderStatus.paid:
      case BusinessOrderStatus.delivered: return colors.accent;
      case BusinessOrderStatus.completed: return colors.success;
      case BusinessOrderStatus.disputed: return colors.danger;
      case BusinessOrderStatus.refunded:
      case BusinessOrderStatus.cancelled: return colors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();
    return GestureDetector(
      onTap: onTap,
      child: PremiumGlassContainer(
        blur: 12, opacity: 0.04, borderRadius: 16, padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          AnimatedContainer(duration: 300.ms, width: 3, height: 48, decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(order.orderRef, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(order.title, style: TextStyle(fontSize: 12, color: colors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text(order.status.label.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: statusColor))),
              const SizedBox(width: 8),
              Text(_fmtDate(order.createdAt), style: TextStyle(fontSize: 10.5, color: colors.textTertiary)),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('\$${order.amountUsdc.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: colors.accent)),
            if (order.status == BusinessOrderStatus.paid || order.status == BusinessOrderStatus.delivered) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => OrderTrackingScreen(
                    orderId: order.id,
                    orderRef: order.orderRef,
                  ),
                )),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delivery_dining, size: 12, color: colors.accent),
                      const SizedBox(width: 3),
                      Text('Track', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: colors.accent)),
                    ],
                  ),
                ),
              ),
            ] else if (order.status == BusinessOrderStatus.completed) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () {
                  // Reorder: navigate to the business storefront for re-ordering
                  // The cart system handles adding items from the storefront
                  if (order.businessProfileId.isNotEmpty) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => StorefrontScreen(
                        businessProfileId: order.businessProfileId,
                        businessName: order.title,
                      ),
                    ));
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.replay_rounded, size: 12, color: colors.accent),
                      const SizedBox(width: 3),
                      Text('Reorder', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: colors.accent)),
                    ],
                  ),
                ),
              ),
            ] else
              Icon(Icons.chevron_right_rounded, size: 18, color: colors.textTertiary),
          ]),
        ]),
      ),
    ).animate().fadeIn(delay: 50.ms, duration: 250.ms).slideX(begin: 0.1, end: 0, delay: 50.ms, duration: 250.ms);
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}
