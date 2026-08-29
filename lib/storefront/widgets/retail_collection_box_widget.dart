import 'package:flutter/material.dart';

import '../../marketplace/experiences/retail/retail_cart.dart';
import '../../marketplace/experiences/retail/retail_cart_sheet.dart';
import '../../marketplace/experiences/retail/retail_checkout.dart';
import '../../marketplace/experiences/retail/retail_experience.dart';
import '../models/storefront_models.dart';

class RetailCollectionBoxWidget extends StatefulWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;
  final RetailCheckoutGateway? checkoutGateway;

  const RetailCollectionBoxWidget({
    super.key,
    required this.props,
    required this.business,
    this.checkoutGateway,
  });

  @override
  State<RetailCollectionBoxWidget> createState() =>
      _RetailCollectionBoxWidgetState();
}

class _RetailCollectionBoxWidgetState
    extends State<RetailCollectionBoxWidget> {
  RetailCart _cart = const RetailCart();
  bool _checkoutInFlight = false;
  String? _checkoutCartFingerprint;
  String? _checkoutIdempotencyKey;

  @override
  Widget build(BuildContext context) {
    final collection = RetailCollection(
      id: (widget.props['id'] ?? widget.props['collectionId'] ??
              'retail-collection')
          .toString(),
      title: (widget.props['title'] ?? 'Collection').toString(),
      subtitle: widget.props['subtitle']?.toString(),
      products: _parseProducts(widget.props['products']),
    );

    if (collection.products.isEmpty) {
      return _EmptyCollection(title: collection.title);
    }

    return Stack(
      children: [
        RetailCollectionBox(
          collection: collection,
          onProductTap: (product) => showRetailQuickLook(
            context,
            product: product,
            onAddToCart: (selection) {
              if (!mounted) return;
              setState(() {
                _cart = _cart.add(
                  selection.product,
                  variants: selection.variants,
                  quantity: selection.quantity,
                );
                // A cart mutation starts a new checkout attempt identity.
                _checkoutCartFingerprint = null;
                _checkoutIdempotencyKey = null;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${selection.product.name} added to bag')),
              );
            },
          ),
        ),
        if (_cart.itemCount > 0)
          Positioned(
            right: 8,
            top: 0,
            child: _BagButton(
              itemCount: _cart.itemCount,
              onPressed: _checkoutInFlight ? null : _openCart,
            ),
          ),
      ],
    );
  }

  Future<void> _openCart() => showRetailCartSheet(
        context,
        cart: _cart,
        onChanged: (next) {
          if (!mounted) return;
          setState(() {
            _cart = next;
            _checkoutCartFingerprint = null;
            _checkoutIdempotencyKey = null;
          });
        },
        onCheckout: _submitCheckout,
      );

  Future<void> _submitCheckout() async {
    if (_checkoutInFlight || _cart.lines.isEmpty) return;

    Navigator.of(context).pop();
    final gateway = widget.checkoutGateway;
    if (gateway == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checkout is not available for this store yet.'),
          ),
        );
      }
      return;
    }

    final paymentProtection = widget.business.escrowProtectionAvailable
        ? await _choosePaymentProtection()
        : RetailPaymentProtection.direct;
    if (!mounted || paymentProtection == null) return;

    final cartSnapshot = _cart;
    final fingerprint = cartSnapshot.lines
        .map((line) => '${line.key}:${line.quantity}')
        .join(';');
    if (_checkoutCartFingerprint != fingerprint ||
        _checkoutIdempotencyKey == null) {
      _checkoutCartFingerprint = fingerprint;
      _checkoutIdempotencyKey =
          'retail-${DateTime.now().microsecondsSinceEpoch}-${fingerprint.hashCode.abs()}';
    }

    setState(() => _checkoutInFlight = true);
    try {
      final options = RetailCheckoutOptions(
        escrowProtectionAvailable: widget.business.escrowProtectionAvailable,
        paymentProtection: paymentProtection,
        idempotencyKey: _checkoutIdempotencyKey,
      );
      final result = await RetailCheckoutController(gateway).submit(
        cartSnapshot,
        options: options,
      );
      if (!mounted) return;

      final message = switch (result) {
        RetailCheckoutSuccess(
          :final confirmationMessage,
          :final orderId,
        ) => () {
            // Only a confirmed server success clears the local cart.
            setState(() {
              _cart = _cart.clear();
              _checkoutCartFingerprint = null;
              _checkoutIdempotencyKey = null;
            });
            return confirmationMessage ?? 'Order $orderId created.';
          }(),
        RetailCheckoutFailure(:final message) => message,
        RetailCheckoutUnavailable(:final message) => message,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _checkoutInFlight = false);
    }
  }

  Future<RetailPaymentProtection?> _choosePaymentProtection() {
    return showDialog<RetailPaymentProtection>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose payment protection'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(
              context,
              RetailPaymentProtection.direct,
            ),
            child: const ListTile(
              leading: Icon(Icons.payment_outlined),
              title: Text('Pay normally'),
              subtitle: Text('Pay the store directly.'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(
              context,
              RetailPaymentProtection.escrow,
            ),
            child: const ListTile(
              leading: Icon(Icons.verified_user_outlined),
              title: Text('Use escrow protection'),
              subtitle: Text(
                'Hold your payment in protection until the order conditions are met.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<RetailProduct> _parseProducts(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => RetailProduct.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((product) => product.id.isNotEmpty)
        .toList(growable: false);
  }
}

class _BagButton extends StatelessWidget {
  final int itemCount;
  final VoidCallback? onPressed;

  const _BagButton({required this.itemCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onPressed,
      icon: const Icon(Icons.shopping_bag_outlined),
      label: Text('$itemCount'),
    );
  }
}

class _EmptyCollection extends StatelessWidget {
  final String title;

  const _EmptyCollection({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text('$title is currently unavailable.'),
    );
  }
}