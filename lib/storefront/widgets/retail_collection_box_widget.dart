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
              onPressed: _openCart,
            ),
          ),
      ],
    );
  }

  Future<void> _openCart() => showRetailCartSheet(
        context,
        cart: _cart,
        onChanged: (next) {
          if (mounted) setState(() => _cart = next);
        },
        onCheckout: _submitCheckout,
      );

  Future<void> _submitCheckout() async {
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

    final options = RetailCheckoutOptions(
      escrowProtectionAvailable: widget.business.escrowProtectionAvailable,
      paymentProtection: paymentProtection,
    );
    final result = await RetailCheckoutController(gateway).submit(
      _cart,
      options: options,
    );
    if (!mounted) return;

    switch (result) {
      case RetailCheckoutSuccess(
          :final confirmationMessage,
          :final orderId,
          :final escrowId,
        ):
        if (escrowId != null && escrowId.isNotEmpty) {
          final funded = await _fundEscrow(
            gateway,
            escrowId,
            orderId: orderId,
          );
          if (!mounted) return;
          if (funded) {
            setState(() => _cart = _cart.clear());
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  confirmationMessage == null
                      ? 'Order $orderId created and escrow funded.'
                      : '$confirmationMessage Escrow funded.',
                ),
              ),
            );
          }
          return;
        }

        setState(() => _cart = _cart.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(confirmationMessage ?? 'Order $orderId created.')),
        );
        return;

      case RetailCheckoutFailure(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        return;

      case RetailCheckoutUnavailable(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        return;
    }
  }

  Future<bool> _fundEscrow(
    RetailCheckoutGateway gateway,
    String escrowId, {
    required String orderId,
  }) async {
    final credentials = await _showEscrowCredentials(orderId);
    if (!mounted || credentials == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order created, but escrow payment was not completed.'),
          ),
        );
      }
      return false;
    }

    try {
      await gateway.fundEscrow(
        escrowId,
        totpToken: credentials.totpToken,
        password: credentials.password,
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      final retry = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Escrow funding failed'),
          content: Text(error.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Leave unpaid'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
      if (retry == true) {
        return _fundEscrow(gateway, escrowId, orderId: orderId);
      }
      return false;
    }
  }

  Future<_EscrowCredentials?> _showEscrowCredentials(String orderId) {
    return showDialog<_EscrowCredentials>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _EscrowCredentialsDialog(orderId: orderId),
    );
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

class _EscrowCredentials {
  final String? totpToken;
  final String? password;

  const _EscrowCredentials({this.totpToken, this.password});
}

class _EscrowCredentialsDialog extends StatefulWidget {
  final String orderId;

  const _EscrowCredentialsDialog({required this.orderId});

  @override
  State<_EscrowCredentialsDialog> createState() =>
      _EscrowCredentialsDialogState();
}

class _EscrowCredentialsDialogState extends State<_EscrowCredentialsDialog> {
  final _totpController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _totpController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fund escrow'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confirm payment for order ${widget.orderId}.'),
            const SizedBox(height: 16),
            TextField(
              controller: _totpController,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: const InputDecoration(
                labelText: '2FA code',
                helperText: 'Use this when two-factor authentication is enabled.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Account password',
                helperText: 'Use this when 2FA is not enabled.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _EscrowCredentials(
              totpToken: _totpController.text.trim().isEmpty
                  ? null
                  : _totpController.text.trim(),
              password: _passwordController.text.isEmpty
                  ? null
                  : _passwordController.text,
            ),
          ),
          child: const Text('Fund escrow'),
        ),
      ],
    );
  }
}

class _BagButton extends StatelessWidget {
  final int itemCount;
  final VoidCallback onPressed;

  const _BagButton({required this.itemCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Material(
      elevation: 2,
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 18,
                color: onPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                '$itemCount',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCollection extends StatelessWidget {
  final String title;

  const _EmptyCollection({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '$title is empty',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
