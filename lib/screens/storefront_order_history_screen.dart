// lib/screens/storefront_order_history_screen.dart
// Customer's storefront order history — view past orders, track status, reorder.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storefront/providers/storefront_provider.dart';

class StorefrontOrderHistoryScreen extends ConsumerStatefulWidget {
  const StorefrontOrderHistoryScreen({super.key});

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load orders: $e')),
        );
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
              const PopupMenuItem(value: 'AWAITING_PAYMENT', child: Text('Awaiting Payment')),
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
                       notif.metrics.pixels >= notif.metrics.maxScrollExtent - 200) {
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
                      return _OrderCard(
                        order: _orders[i],
                        onReorder: () => _reorder(_orders[i]),
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
          Icon(Icons.shopping_bag_outlined, size: 64,
              color: Theme.of(context).colorScheme.outline),
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

  void _reorder(Map<String, dynamic> order) {
    final bizId = order['businessProfile']?['id'];
    if (bizId != null) {
      Navigator.pushNamed(context, '/storefront', arguments: {'businessProfileId': bizId});
    }
  }
}

// ── Order Card ─────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onReorder;

  const _OrderCard({required this.order, required this.onReorder});

  @override
  Widget build(BuildContext context) {
    final business = order['businessProfile'] as Map<String, dynamic>?;
    final product = order['product'] as Map<String, dynamic>?;
    final status = order['status'] as String? ?? 'PENDING';
    final amount = (order['amountUsdc'] as num?)?.toDouble() ?? 0;
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
                      child: Image.network(
                        business!['logoUrl'],
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _logoPlaceholder(context),
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
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (createdAt != null)
                          Text(
                            _formatDate(DateTime.tryParse(createdAt)),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                      child: Image.network(
                        product!['imageUrl'],
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _productPlaceholder(context),
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
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$amount USDC',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
        child: Icon(Icons.store, size: 20, color: Theme.of(context).colorScheme.outline),
      );

  Widget _productPlaceholder(BuildContext context) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(Icons.inventory_2_outlined, size: 20, color: Theme.of(context).colorScheme.outline),
      );

  void _showOrderDetail(BuildContext context, Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _OrderDetailSheet(order: order, onReorder: onReorder),
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
        return (Colors.orange, 'Awaiting Payment');
      case 'PAID':
        return (Colors.blue, 'Paid');
      case 'FULFILLED':
        return (Colors.indigo, 'Fulfilled');
      case 'DELIVERED':
        return (Colors.green, 'Delivered');
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

  const _OrderDetailSheet({required this.order, required this.onReorder});

  @override
  Widget build(BuildContext context) {
    final business = order['businessProfile'] as Map<String, dynamic>?;
    final product = order['product'] as Map<String, dynamic>?;
    final status = order['status'] as String? ?? 'PENDING';
    final amount = (order['amountUsdc'] as num?)?.toDouble() ?? 0;
    final orderRef = order['orderRef'] as String? ?? '';
    final customerNotes = order['customerNotes'] as String?;
    final deliveryNotes = order['deliveryNotes'] as String?;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: ListView(
          controller: scrollController,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order Details', style: Theme.of(context).textTheme.titleLarge),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 20),
            _section(context, 'Order Reference', orderRef),
            _section(context, 'Business', business?['businessName'] ?? '—'),
            _section(context, 'Product', product?['name'] ?? order['title'] ?? '—'),
            _section(context, 'Amount', '$amount USDC'),
            if (customerNotes != null && customerNotes.isNotEmpty)
              _section(context, 'Customer Notes', customerNotes),
            if (deliveryNotes != null && deliveryNotes.isNotEmpty)
              _section(context, 'Delivery Notes', deliveryNotes),
            if (business?['contactPhone'] != null)
              _section(context, 'Contact', business!['contactPhone']),
            const SizedBox(height: 24),
            if (status == 'DELIVERED' || status == 'FULFILLED')
              FilledButton.icon(
                onPressed: onReorder,
                icon: const Icon(Icons.refresh),
                label: const Text('Reorder'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                    fontWeight: FontWeight.w500,
                  )),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
