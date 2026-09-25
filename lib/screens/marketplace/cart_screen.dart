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
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

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
    final colors = ref.read(themeProvider).colors;

    AzamanHaptics.confirm();
    setState(() => _isPlacingOrder = true);
    ref.read(cartProvider.notifier).setCheckingOut(true);

    try {
      final service = ref.read(storefrontServiceProvider);

      final combinedNotes = [
        if (_orderNotesCtrl.text.trim().isNotEmpty)
          'Order notes: ${_orderNotesCtrl.text.trim()}',
      ].join(' | ');

      final combinedDelivery = [
        if (_deliveryAddressCtrl.text.trim().isNotEmpty)
          _deliveryAddressCtrl.text.trim(),
      ].join(' | ');

      final itemsJson = cart.toCheckoutItems();

      final result = await service.checkoutCart(
        businessProfileId: cart.businessProfileId!,
        items: itemsJson,
        customerNotes: combinedNotes.isNotEmpty ? combinedNotes : null,
        deliveryNotes: combinedDelivery.isNotEmpty ? combinedDelivery : null,
        idempotencyKey: 'cart_${DateTime.now().millisecondsSinceEpoch}',
      );

      ref.read(cartProvider.notifier).clearCart();

      if (mounted) {
        AzamanHaptics.confirm();
        final orderData = result['data']?['order'] as Map<String, dynamic>?;
        _showOrderConfirmation(
          cart.items.length,
          cart.businessName,
          orderRef: orderData?['orderRef'] as String?,
          colors: colors,
        );
        widget.onCheckoutComplete?.call();
      }
    } catch (e) {
      if (mounted) {
        AzamanHaptics.warn();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order failed: $e'),
            backgroundColor: colors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
      ref.read(cartProvider.notifier).setCheckingOut(false);
    }
  }

  void _showOrderConfirmation(int itemCount, String? businessName, {String? orderRef, required AzamanColors colors}) {
    final cart = ref.read(cartProvider);
    final presentation = _CartPresentation.fromPreset(cart.experiencePreset);
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
                color: colors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                HugeIconsSolid.checkmarkCircle02,
                color: colors.success,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              presentation.successTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '$itemCount ${itemCount == 1 ? "item" : "items"} from ${businessName ?? "the store"}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
            if (orderRef != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: colors.softSurface, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  orderRef,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary, fontFamily: 'monospace'),
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
                Navigator.pop(ctx);
                Navigator.pop(context);
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
    final colors = ref.read(themeProvider).colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text('This will remove all items from your cart.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(cartProvider.notifier).clearCart();
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: colors.danger),
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
    final presentation = _CartPresentation.fromPreset(cart.experiencePreset);
    final motion = MotionTokens.accessibleDuration(context, MotionTokens.standard);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: AnimatedSwitcher(
          duration: motion,
          switchInCurve: MotionTokens.enter,
          switchOutCurve: MotionTokens.exit,
          child: Text(presentation.title, key: ValueKey(presentation.title)),
        ),
        leading: IconButton(
          icon: const Icon(HugeIconsStroke.arrowLeft01),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!cart.isEmpty)
            IconButton(
              tooltip: 'Clear ${presentation.itemWord.toLowerCase()}',
              icon: Icon(HugeIconsStroke.delete01, color: colors.danger),
              onPressed: _confirmClearCart,
            ),
        ],
      ),
      body: cart.isEmpty ? _buildEmptyState(colors, presentation) : _buildCartList(colors, cart, presentation),
      bottomNavigationBar: cart.isEmpty ? null : _buildCheckoutBar(colors, cart, presentation),
    );
  }

  Widget _buildEmptyState(AzamanColors colors, _CartPresentation presentation) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: colors.accent.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: Icon(presentation.icon, size: 42, color: colors.accent),
            ),
            const SizedBox(height: 20),
            Text(
              presentation.emptyTitle,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: colors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              presentation.emptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.45, color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartList(AzamanColors colors, CartState cart, _CartPresentation presentation) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 108),
      children: [
        if (cart.businessName != null)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: colors.accent.withValues(alpha: 0.10), shape: BoxShape.circle),
                  child: Icon(presentation.icon, size: 19, color: colors.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cart.businessName!, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: colors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(presentation.merchantHint, style: TextStyle(fontSize: 11.5, color: colors.textTertiary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ...cart.items.map((item) => _CartTile(
              item: item,
              colors: colors,
              onIncrement: () {
                AzamanHaptics.toggle();
                ref.read(cartProvider.notifier).incrementLine(item.lineKey);
              },
              onDecrement: () {
                AzamanHaptics.toggle();
                ref.read(cartProvider.notifier).decrementLine(item.lineKey);
              },
              onRemove: () {
                AzamanHaptics.nav();
                ref.read(cartProvider.notifier).removeLine(item.lineKey);
              },
            )),
        const SizedBox(height: 16),
        _SectionHeader(title: presentation.detailsTitle, colors: colors),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: colors.divider.withValues(alpha: 0.55))),
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
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: colors.divider.withValues(alpha: 0.55))),
          child: TextField(
            controller: _orderNotesCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: presentation.notesHint,
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
        const SizedBox(height: 20),
        _SectionHeader(title: presentation.summaryTitle, colors: colors),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.divider.withValues(alpha: 0.55))),
          child: Column(
            children: [
              _SummaryRow(label: 'Subtotal', value: '\$${cart.subtotal.toStringAsFixed(2)}', colors: colors),
              const SizedBox(height: 8),
              _SummaryRow(label: 'Items', value: '${cart.itemCount} ${cart.itemCount == 1 ? "item" : "items"}', colors: colors),
              const SizedBox(height: 10),
              Divider(color: colors.divider, height: 1),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: MotionTokens.accessibleDuration(context, MotionTokens.microInteraction),
                transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: ScaleTransition(scale: animation, child: child)),
                child: _SummaryRow(
                  key: ValueKey(cart.subtotal),
                  label: 'Total',
                  value: '\$${cart.subtotal.toStringAsFixed(2)}',
                  colors: colors,
                  isBold: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutBar(AzamanColors colors, CartState cart, _CartPresentation presentation) {
    final duration = MotionTokens.accessibleDuration(context, MotionTokens.control);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.divider.withValues(alpha: 0.65), width: 0.5)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: _isPlacingOrder ? null : _placeOrder,
            style: FilledButton.styleFrom(backgroundColor: colors.accent, foregroundColor: colors.isDark ? Colors.black : Colors.white, shape: const StadiumBorder()),
            icon: AnimatedSwitcher(
              duration: duration,
              child: _isPlacingOrder
                  ? const SizedBox(key: ValueKey('loading'), width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(presentation.checkoutIcon, key: const ValueKey('icon'), size: 19),
            ),
            label: AnimatedSwitcher(
              duration: duration,
              switchInCurve: MotionTokens.enter,
              switchOutCurve: MotionTokens.exit,
              child: _isPlacingOrder
                  ? const Text('Sending…', key: ValueKey('sending'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))
                  : Text('${presentation.checkoutLabel} · \$${cart.subtotal.toStringAsFixed(2)}', key: ValueKey('${presentation.checkoutLabel}:${cart.subtotal}'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ),
    );
  }
}

class _CartPresentation {
  final String title;
  final String itemWord;
  final String merchantHint;
  final String detailsTitle;
  final String summaryTitle;
  final String notesHint;
  final String checkoutLabel;
  final String emptyTitle;
  final String emptyBody;
  final String successTitle;
  final IconData icon;
  final IconData checkoutIcon;

  const _CartPresentation({
    required this.title,
    required this.itemWord,
    required this.merchantHint,
    required this.detailsTitle,
    required this.summaryTitle,
    required this.notesHint,
    required this.checkoutLabel,
    required this.emptyTitle,
    required this.emptyBody,
    required this.successTitle,
    required this.icon,
    required this.checkoutIcon,
  });

  static _CartPresentation fromPreset(String? preset) {
    switch (preset) {
      case 'DINING_JOURNEY':
        return const _CartPresentation(
          title: 'Your order tray',
          itemWord: 'Tray',
          merchantHint: 'Your table order · ready to send to the kitchen',
          detailsTitle: 'Where should it arrive?',
          summaryTitle: 'Tray summary',
          notesHint: 'Kitchen notes, allergies, preferences…',
          checkoutLabel: 'Send order',
          emptyTitle: 'Your tray is waiting',
          emptyBody: 'Pick a dish from the menu and it will land here before you send the order.',
          successTitle: 'Order sent!',
          icon: Icons.restaurant_menu_outlined,
          checkoutIcon: Icons.restaurant_rounded,
        );
      case 'SHOP_FLOOR':
        return const _CartPresentation(
          title: 'Your bag',
          itemWord: 'Bag',
          merchantHint: 'Items selected from this store',
          detailsTitle: 'Delivery details',
          summaryTitle: 'Bag summary',
          notesHint: 'Delivery notes or preferences…',
          checkoutLabel: 'Checkout',
          emptyTitle: 'Your bag is empty',
          emptyBody: 'Explore the store and add something worth taking home.',
          successTitle: 'Purchase confirmed!',
          icon: Icons.shopping_bag_outlined,
          checkoutIcon: Icons.lock_rounded,
        );
      default:
        return const _CartPresentation(
          title: 'Your cart',
          itemWord: 'Cart',
          merchantHint: 'Your selected items',
          detailsTitle: 'Delivery Details',
          summaryTitle: 'Order Summary',
          notesHint: 'Order notes, preferences…',
          checkoutLabel: 'Place order',
          emptyTitle: 'Your cart is empty',
          emptyBody: 'Browse the marketplace and add items to get started.',
          successTitle: 'Order placed!',
          icon: HugeIconsStroke.shoppingBag01,
          checkoutIcon: Icons.arrow_forward_rounded,
        );
    }
  }
}

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
      key: Key(item.lineKey),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: colors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
        child: Icon(HugeIconsStroke.delete01, color: colors.danger, size: 24),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: colors.divider.withValues(alpha: 0.45))),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: item.image_url != null
                  ? AzamanNetworkImage(imageUrl: item.image_url!, width: 60, height: 60, fit: BoxFit.cover, errorWidget: (_, __, ___) => _placeholderImage())
                  : _placeholderImage(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                  const SizedBox(height: 4),
                  Text('\$${item.unitPrice.toStringAsFixed(2)} each', style: TextStyle(fontSize: 13, color: colors.textTertiary)),
                  if (item.variants.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(item.variants.entries.map((entry) => '${entry.key}: ${entry.value}').join(' • '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: colors.textSecondary, fontWeight: FontWeight.w600)),
                  ],
                  if (item.notes != null && item.notes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(item.notes!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.textTertiary, fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(11), border: Border.all(color: colors.divider, width: 0.5)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(onPressed: onDecrement, icon: Icon(HugeIconsStroke.minusSign, size: 18, color: colors.textSecondary), visualDensity: VisualDensity.compact, constraints: const BoxConstraints(minWidth: 34, minHeight: 34)),
                  AnimatedSwitcher(
                    duration: MotionTokens.microInteraction,
                    transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                    child: Text('${item.quantity}', key: ValueKey(item.quantity), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colors.textPrimary)),
                  ),
                  IconButton(onPressed: onIncrement, icon: Icon(HugeIconsStroke.plusSign, size: 18, color: colors.accent), visualDensity: VisualDensity.compact, constraints: const BoxConstraints(minWidth: 34, minHeight: 34)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderImage() {
    return Container(width: 60, height: 60, color: colors.background, child: Icon(HugeIconsStroke.shoppingBag01, size: 24, color: colors.textTertiary));
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final AzamanColors colors;

  const _SectionHeader({required this.title, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary));
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final AzamanColors colors;
  final bool isBold;

  const _SummaryRow({super.key, required this.label, required this.value, required this.colors, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: isBold ? 16 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: isBold ? colors.textPrimary : colors.textSecondary)),
        Text(value, style: TextStyle(fontSize: isBold ? 18 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: isBold ? colors.accent : colors.textPrimary)),
      ],
    );
  }
}
