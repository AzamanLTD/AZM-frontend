// lib/screens/storefront_order_history_screen.dart
// Customer's storefront order history — view past orders, track status, reorder.
//
// Each order says where its payment is and what the buyer can do:
//   saved, not paid  → Pay (within the 24-hour payment hold)
//   paid             → held until the store hands it over
//   handed over      → Got it (pays the store) or Report a problem; with no
//                      answer the store is paid 3 days after hand-over
//   problem reported → held for review
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/marketplace/store_order_pay.dart';
import 'package:azaman/widgets/security/second_factor.dart';
import '../storefront/providers/storefront_provider.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/azaman_sheet.dart';
import 'package:go_router/go_router.dart';
import 'package:azaman/router/route_registry.dart';

double _orderNum(Object? v) =>
    v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

/// What the buyer can do with an order's held payment now.
enum StoreOrderStage { pay, heldUntilHandover, confirm, reported, none }

StoreOrderStage storeOrderStage(Map<String, dynamic> order) {
  if (StoreOrderPayment.fromOrder(order) != null) return StoreOrderStage.pay;
  final escrow = order['escrow'];
  if (escrow is! Map) return StoreOrderStage.none;
  final es = '${escrow['status'] ?? ''}'.toUpperCase();
  final os = '${order['status'] ?? ''}'.toUpperCase();
  if (es == 'DISPUTED' || es == 'ADMIN_REVIEW') return StoreOrderStage.reported;
  const held = {'FUNDED', 'IN_PROGRESS', 'PENDING_SETTLEMENT'};
  if (!held.contains(es)) return StoreOrderStage.none;
  if (os == 'DELIVERED' && escrow['payerSatisfied'] != true) {
    return StoreOrderStage.confirm;
  }
  if (os == 'PAID') return StoreOrderStage.heldUntilHandover;
  return StoreOrderStage.none;
}

class StorefrontOrderHistoryScreen extends ConsumerStatefulWidget {
  const StorefrontOrderHistoryScreen({super.key, this.secondFactorPrompt});

  /// Replaces the second-factor sheet (tests).
  final Future<SecondFactor?> Function({
    required SecondFactorKind kind,
    String? errorText,
  })?
  secondFactorPrompt;

  @override
  ConsumerState<StorefrontOrderHistoryScreen> createState() =>
      _StorefrontOrderHistoryScreenState();
}

class _StorefrontOrderHistoryScreenState
    extends ConsumerState<StorefrontOrderHistoryScreen> {
  bool _loadingMore = false;
  String? _nextCursor;
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders({bool reset = true}) async {
    if (reset) {
      setState(() {
        _orders = [];
        _nextCursor = null;
        _loading = true;
      });
    }

    try {
      final service = ref.read(storefrontServiceProvider);
      final result = await service.getMyOrders(
        status: _statusFilter,
        limit: 20,
        cursor: _nextCursor,
      );
      final newOrders =
          (result['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) {
        setState(() {
          _orders.addAll(newOrders);
          _nextCursor = result['nextCursor'] as String?;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load orders: $e')));
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextCursor == null) return;
    setState(() => _loadingMore = true);
    await _loadOrders(reset: false);
    setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() => _statusFilter = value);
              _loadOrders();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: null, child: Text('All Orders')),
              const PopupMenuItem(
                value: 'AWAITING_PAYMENT',
                child: Text('Awaiting Payment'),
              ),
              const PopupMenuItem(value: 'PAID', child: Text('Paid')),
              const PopupMenuItem(value: 'FULFILLED', child: Text('Fulfilled')),
              const PopupMenuItem(value: 'DELIVERED', child: Text('Delivered')),
              const PopupMenuItem(value: 'CANCELLED', child: Text('Cancelled')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
          ? _buildEmptyState()
          : NotificationListener<ScrollNotification>(
              onNotification: (notif) {
                if (notif is ScrollEndNotification &&
                    notif.metrics.pixels >=
                        notif.metrics.maxScrollExtent - 200) {
                  _loadMore();
                }
                return false;
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _orders.length + (_nextCursor != null ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i >= _orders.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final o = _orders[i];
                  return _OrderCard(
                    order: o,
                    onReorder: () => _reorder(o),
                    busy: _busyOrderId == o['id'],
                    onPay: () => _pay(o),
                    onGotIt: () => _gotIt(o),
                    onReport: () => _report(o),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            _statusFilter != null
                ? 'No ${_statusFilter!.toLowerCase().replaceAll('_', ' ')} orders'
                : 'No orders yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Orders you place from storefronts will appear here.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  String? _busyOrderId;

  String _messageOf(Object e, String fallback) =>
      e is ApiException ? e.message : fallback;

  Future<void> _run(
    Map<String, dynamic> order,
    Future<void> Function() action,
  ) async {
    setState(() => _busyOrderId = order['id']?.toString());
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  Future<void> _pay(Map<String, dynamic> order) => _run(order, () async {
    final payment = StoreOrderPayment.fromOrder(order);
    if (payment == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await payStoreOrder(
        context,
        ref,
        payment,
        ask: widget.secondFactorPrompt,
      );
      if (r == StorePayResult.paid) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Paid. The money is held until you get your order.'),
          ),
        );
        await _loadOrders();
      } else if (r == StorePayResult.shortBalance) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Not enough in your wallet for this order.'),
            action: SnackBarAction(
              label: 'Add money',
              onPressed: () => context.push('/deposit'),
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(_messageOf(e, 'Payment failed. Try again.'))),
      );
    }
  });

  Future<void> _gotIt(Map<String, dynamic> order) => _run(order, () async {
    final escrow = order['escrow'];
    if (escrow is! Map) return;
    final store =
        order['businessProfile']?['businessName']?.toString() ?? 'the store';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Got your order?'),
        content: Text(
          '$store is paid when you confirm. Only confirm once you have everything you ordered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            key: const ValueKey('order-got-it-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, pay the store'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final settled = await withSecondFactor<bool>(
        context,
        initial: secondFactorKindFor(ref.read(authProvider).user),
        title: 'Confirm you got it',
        actionLabel: 'Confirm',
        ask: widget.secondFactorPrompt,
        attempt: (factor) {
          final wire = factor.toWire();
          return ref
              .read(storefrontServiceProvider)
              .confirmOrderReceived(
                escrowId: escrow['id'].toString(),
                totpToken: wire['totpToken'],
                password: wire['password'],
              );
        },
      );
      if (settled == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            settled
                ? 'Thanks. $store has been paid.'
                : 'Thanks. $store is paid once they confirm the hand-over.',
          ),
        ),
      );
      await _loadOrders();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(_messageOf(e, 'Could not confirm. Try again.'))),
      );
    }
  });

  Future<void> _report(Map<String, dynamic> order) => _run(order, () async {
    final escrow = order['escrow'];
    if (escrow is! Map) return;
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReportProblemSheet(),
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(storefrontServiceProvider)
          .reportOrderProblem(
            escrowId: escrow['id'].toString(),
            reason: reason.trim(),
          );
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Reported. The payment stays held while Azaman reviews it.',
          ),
        ),
      );
      await _loadOrders();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(_messageOf(e, 'Could not report. Try again.'))),
      );
    }
  });

  void _reorder(Map<String, dynamic> order) {
    final bizId = order['businessProfile']?['id'];
    if (bizId != null) {
      // NEW-A: canonical storefront route (fixes the latent pushNamed bug
      // — '/storefront' matched no route name).
      context.push(AzRoutes.storefront(bizId));
    }
  }
}

// ── Order Card ─────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onReorder;
  final VoidCallback onPay;
  final VoidCallback onGotIt;
  final VoidCallback onReport;
  final bool busy;

  const _OrderCard({
    required this.order,
    required this.onReorder,
    required this.onPay,
    required this.onGotIt,
    required this.onReport,
    this.busy = false,
  });

  Widget _paymentRow(BuildContext context) {
    final id = order['id']?.toString() ?? '';
    final outline = Theme.of(context).colorScheme.outline;
    Text note(String t) => Text(
      t,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: outline),
    );
    switch (storeOrderStage(order)) {
      case StoreOrderStage.pay:
        final payment = StoreOrderPayment.fromOrder(order)!;
        return Row(
          children: [
            Expanded(
              child: note('Not paid yet. Pay within 24 hours of ordering.'),
            ),
            FilledButton(
              key: ValueKey('order-pay-$id'),
              onPressed: busy ? null : onPay,
              child: Text('Pay ${storeUsdcLabel(payment.totalUsdc)}'),
            ),
          ],
        );
      case StoreOrderStage.heldUntilHandover:
        return note('Paid · held until the store hands your order over.');
      case StoreOrderStage.confirm:
        final delivered = DateTime.tryParse('${order['deliveredAt'] ?? ''}');
        final until = delivered?.add(const Duration(hours: 72)).toLocal();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            note(
              until == null
                  ? 'Handed over. Got everything?'
                  : 'Handed over. Got everything? If you report nothing, the store is paid on ${until.day}/${until.month}.',
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  key: ValueKey('order-got-it-$id'),
                  onPressed: busy ? null : onGotIt,
                  child: const Text('Got it'),
                ),
                TextButton(
                  key: ValueKey('order-report-$id'),
                  onPressed: busy ? null : onReport,
                  child: const Text('Report a problem'),
                ),
              ],
            ),
          ],
        );
      case StoreOrderStage.reported:
        return note('Problem reported · payment held while Azaman reviews it.');
      case StoreOrderStage.none:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final business = order['businessProfile'] as Map<String, dynamic>?;
    final product = order['product'] as Map<String, dynamic>?;
    final status = order['status'] as String? ?? 'PENDING';
    final amount = _orderNum(order['amountUsdc']);
    final orderRef = order['orderRef'] as String? ?? '';
    final createdAt = order['createdAt'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showOrderDetail(context, order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (business?['logoUrl'] != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AzamanNetworkImage(
                        imageUrl: business!['logoUrl'],
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _logoPlaceholder(context),
                      ),
                    )
                  else
                    _logoPlaceholder(context),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          business?['businessName'] ?? 'Unknown Business',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (createdAt != null)
                          Text(
                            _formatDate(DateTime.tryParse(createdAt)),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                      ],
                    ),
                  ),
                  _StatusChip(status: status),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (product?['imageUrl'] != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: AzamanNetworkImage(
                        imageUrl: product!['imageUrl'],
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            _productPlaceholder(context),
                      ),
                    )
                  else
                    _productPlaceholder(context),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product?['name'] ?? order['title'] ?? 'Order',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$amount USDC',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    orderRef,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
              if (storeOrderStage(order) != StoreOrderStage.none) ...[
                const SizedBox(height: 12),
                _paymentRow(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _logoPlaceholder(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(
      Icons.store,
      size: 20,
      color: Theme.of(context).colorScheme.outline,
    ),
  );

  Widget _productPlaceholder(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Icon(
      Icons.inventory_2_outlined,
      size: 20,
      color: Theme.of(context).colorScheme.outline,
    ),
  );

  void _showOrderDetail(BuildContext context, Map<String, dynamic> order) {
    // NEW-B: Panel weight. The detail body is a scrolling list and it already
    // carried its own DraggableScrollableSheet(0.7/0.4/0.9) — deleted here,
    // because two detent systems on one gesture means the inner one wins the
    // drag and the panel never reaches its extended detent.
    AzamanSheet.showPanel<void>(
      context,
      builder: (_, scrollController) => _OrderDetailSheet(
        order: order,
        onReorder: onReorder,
        scrollController: scrollController,
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Status Chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = _statusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  (Color, String) _statusStyle(String s) {
    switch (s) {
      case 'AWAITING_PAYMENT':
        return (Colors.orange, 'Not paid');
      case 'PAID':
        return (Colors.blue, 'Paid');
      case 'FULFILLED':
        return (Colors.indigo, 'Fulfilled');
      case 'DELIVERED':
        return (Colors.green, 'Handed over');
      case 'COMPLETED':
        return (Colors.teal, 'Completed');
      case 'DISPUTED':
        return (Colors.deepOrange, 'Problem reported');
      case 'CANCELLED':
        return (Colors.red, 'Cancelled');
      case 'REFUNDED':
        return (Colors.purple, 'Refunded');
      default:
        return (Colors.grey, s);
    }
  }
}

// ── Order Detail Sheet ───────────────────────────────────────────────────────

class _OrderDetailSheet extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onReorder;

  /// The Panel's own scroll controller.
  final ScrollController scrollController;

  const _OrderDetailSheet({
    required this.order,
    required this.onReorder,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final business = order['businessProfile'] as Map<String, dynamic>?;
    final product = order['product'] as Map<String, dynamic>?;
    final status = order['status'] as String? ?? 'PENDING';
    final amount = _orderNum(order['amountUsdc']);
    final orderRef = order['orderRef'] as String? ?? '';
    final customerNotes = order['customerNotes'] as String?;
    final deliveryNotes = order['deliveryNotes'] as String?;
    // NEW-B: the weight owns surface, radius, safe-area and the handle, so
    // the old Container and the inline handle bar are deleted.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: ListView(
        controller: scrollController,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order Details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _StatusChip(status: status),
            ],
          ),
          const SizedBox(height: 20),
          _section(context, 'Order Reference', orderRef),
          _section(context, 'Business', business?['businessName'] ?? '—'),
          _section(
            context,
            'Product',
            product?['name'] ?? order['title'] ?? '—',
          ),
          _section(context, 'Amount', '$amount USDC'),
          if (customerNotes != null && customerNotes.isNotEmpty)
            _section(context, 'Customer Notes', customerNotes),
          if (deliveryNotes != null && deliveryNotes.isNotEmpty)
            _section(context, 'Delivery Notes', deliveryNotes),
          if (business?['contactPhone'] != null)
            _section(context, 'Contact', business!['contactPhone']),
          const SizedBox(height: 24),
          if (status == 'COMPLETED' || status == 'FULFILLED')
            FilledButton.icon(
              onPressed: onReorder,
              icon: const Icon(Icons.refresh),
              label: const Text('Reorder'),
            ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// "Report a problem": what went wrong (required, so review has something
/// to go on). Returns the text, or null when closed.
class _ReportProblemSheet extends StatefulWidget {
  const _ReportProblemSheet();

  @override
  State<_ReportProblemSheet> createState() => _ReportProblemSheetState();
}

class _ReportProblemSheetState extends State<_ReportProblemSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Report a problem',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'The payment stays held and the store is not paid while Azaman reviews it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('order-report-reason'),
            controller: _reason,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'What went wrong?',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('order-report-send'),
              onPressed: _reason.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_reason.text),
              child: const Text('Report'),
            ),
          ),
        ],
      ),
    );
  }
}
