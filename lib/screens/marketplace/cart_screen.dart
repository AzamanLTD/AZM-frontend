// =============================================================================
// CART SCREEN — Phase 12 (Marketplace Cart)
//
// Full cart view with quantity controls, item removal, special instructions,
// order summary, and checkout flow.
//
// Reference: Bolt Food / Uber Eats cart screen — clean, fast, minimal friction.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CartScreen extends ConsumerStatefulWidget {
  /// Called after a successful checkout. Typically navigates back to the marketplace.
  final VoidCallback? onCheckoutComplete;

  const CartScreen({super.key, this.onCheckoutComplete});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _deliveryAddressCtrl = TextEditingController();
  final _orderNotesCtrl = TextEditingController();
  bool _isPlacingOrder = false;

  @override
  void dispose() {
    _deliveryAddressCtrl.dispose();
    _orderNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty || cart.businessProfileId == null) return;

    AzamanHaptics.confirm();
    setState(() => _isPlacingOrder = true);
    ref.read(cartProvider.notifier).setCheckingOut(true);

    try {
      final service = ref.read(storefrontServiceProvider);

      // Build combined notes
      final combinedNotes = [
        if (_orderNotesCtrl.text.trim().isNotEmpty)
          'Order notes: ${_orderNotesCtrl.text.trim()}',
      ].join(' | ');

      final combinedDelivery = [
        if (_deliveryAddressCtrl.text.trim().isNotEmpty)
          _deliveryAddressCtrl.text.trim(),
      ].join(' | ');

      // Use the multi-item checkout endpoint (single BusinessOrder with items)
      final itemsJson = cart.items.map((item) => {
        'productId': item.productId,
        'quantity': item.quantity,
        if (item.notes != null && item.notes!.isNotEmpty)
          'notes': item.notes,
      }).toList();

      final result = await service.checkoutCart(
        businessProfileId: cart.businessProfileId!,
        items: itemsJson,
        customerNotes: combinedNotes.isNotEmpty ? combinedNotes : null,
        deliveryNotes: combinedDelivery.isNotEmpty ? combinedDelivery : null,
        idempotencyKey: 'cart_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Clear cart on success
      ref.read(cartProvider.notifier).clearCart();

      if (mounted) {
        AzamanHaptics.confirm();
        final orderData = result['data']?['order'] as Map<String, dynamic>?;
        _showOrderConfirmation(
          cart.items.length,
          cart.businessName,
          orderRef: orderData?['orderRef'] as String?,
        );
        widget.onCheckoutComplete?.call();
      }
    } catch (e) {
      if (mounted) {
        AzamanHaptics.warn();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
      ref.read(cartProvider.notifier).setCheckingOut(false);
    }
  }

  void _showOrderConfirmation(int itemCount, String? businessName, {String? orderRef}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                HugeIconsSolid.checkmarkCircle02,
                color: Colors.green.shade600,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Order Placed!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$itemCount ${itemCount == 1 ? "item" : "items"} from ${businessName ?? "the store"}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            if (orderRef != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  orderRef,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(ctx); // close dialog
                Navigator.pop(context); // close cart screen
              },
              child: const Text('Track Order'),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearCart() {
    AzamanHaptics.nav();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text('This will remove all items from your cart.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(cartProvider.notifier).clearCart();
              Navigator.pop(ctx);
              Navigator.pop(context); // close cart screen too
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final colors = ref.watch(themeProvider.select((t) => t.colors));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: const Text('Your Cart'),
        leading: IconButton(
          icon: const Icon(HugeIconsStroke.arrowLeft01),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!cart.isEmpty)
            IconButton(
              icon: Icon(HugeIconsStroke.delete01, color: colors.danger),
              onPressed: _confirmClearCart,
            ),
        ],
      ),
      body: cart.isEmpty
          ? _buildEmptyState(colors)
          : _buildCartList(colors, cart),
      bottomNavigationBar: cart.isEmpty ? null : _buildCheckoutBar(colors, cart),
    );
  }

  Widget _buildEmptyState(AzamanColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            HugeIconsStroke.shoppingBag01,
            size: 64,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'Your cart is empty',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Browse the marketplace and add items to get started.',
            style: TextStyle(
              fontSize: 14,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartList(AzamanColors colors, CartState cart) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        // ── Business header ─────────────────────────────────────────────
        if (cart.businessName != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(HugeIconsStroke.store01, size: 20, color: colors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cart.businessName!,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Cart items ───────────────────────────────────────────────────
        ...cart.items.map((item) => _CartTile(
              item: item,
              colors: colors,
              onIncrement: () {
                AzamanHaptics.toggle();
                ref.read(cartProvider.notifier).incrementItem(item.productId);
              },
              onDecrement: () {
                AzamanHaptics.toggle();
                ref.read(cartProvider.notifier).decrementItem(item.productId);
              },
              onRemove: () {
                AzamanHaptics.nav();
                ref.read(cartProvider.notifier).removeItem(item.productId);
              },
            )),

        // ── Delivery address ─────────────────────────────────────────────
        const SizedBox(height: 16),
        _SectionHeader(title: 'Delivery Details', colors: colors),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _deliveryAddressCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Delivery address (optional)',
              hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(14),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12),
                child: Icon(HugeIconsStroke.location01, size: 20, color: colors.accent),
              ),
            ),
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
          ),
        ),

        // ── Order notes ──────────────────────────────────────────────────
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _orderNotesCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Order notes (allergies, preferences, etc.)',
              hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(14),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12),
                child: Icon(HugeIconsStroke.pencilEdit01, size: 20, color: colors.accent),
              ),
            ),
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
          ),
        ),

        // ── Order summary ────────────────────────────────────────────────
        const SizedBox(height: 20),
        _SectionHeader(title: 'Order Summary', colors: colors),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _SummaryRow(label: 'Subtotal', value: '\$${cart.subtotal.toStringAsFixed(2)}', colors: colors),
              const SizedBox(height: 8),
              _SummaryRow(
                label: 'Items',
                value: '${cart.itemCount} ${cart.itemCount == 1 ? "item" : "items"}',
                colors: colors,
              ),
              const SizedBox(height: 8),
              Divider(color: colors.divider, height: 1),
              const SizedBox(height: 8),
              _SummaryRow(
                label: 'Total',
                value: '\$${cart.subtotal.toStringAsFixed(2)}',
                colors: colors,
                isBold: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutBar(AzamanColors colors, CartState cart) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            top: BorderSide(color: colors.divider, width: 0.5),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _isPlacingOrder ? null : _placeOrder,
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isPlacingOrder
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Place Order · \$${cart.subtotal.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Helper Widgets ─────────────────────────────────────────────────────────────

class _CartTile extends StatelessWidget {
  final CartItem item;
  final AzamanColors colors;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  const _CartTile({
    required this.item,
    required this.colors,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(item.productId),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: colors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(HugeIconsStroke.delete01, color: colors.danger, size: 24),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // ── Product image ───────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: item.image_url != null
                  ? CachedNetworkImage(imageUrl: 
                      item.image_url!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _placeholderImage(),
                    )
                  : _placeholderImage(),
            ),
            const SizedBox(width: 12),
            // ── Name + price ──────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${item.unitPrice.toStringAsFixed(2)} each',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textTertiary,
                    ),
                  ),
                  if (item.notes != null && item.notes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.notes!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ── Quantity stepper ──────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.divider, width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onDecrement,
                    icon: Icon(HugeIconsStroke.minusSign, size: 18, color: colors.textSecondary),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  Text(
                    '${item.quantity}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  IconButton(
                    onPressed: onIncrement,
                    icon: Icon(HugeIconsStroke.plusSign, size: 18, color: colors.accent),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.05);
  }

  Widget _placeholderImage() {
    return Container(
      width: 56,
      height: 56,
      color: colors.surface,
      child: Icon(HugeIconsStroke.shoppingBag01, size: 24, color: colors.textTertiary),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final AzamanColors colors;

  const _SectionHeader({required this.title, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final AzamanColors colors;
  final bool isBold;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.colors,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
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
          value,
          style: TextStyle(
            fontSize: isBold ? 18 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: isBold ? colors.accent : colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
