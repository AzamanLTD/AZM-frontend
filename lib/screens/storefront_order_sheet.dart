// =============================================================================
// Storefront Order Sheet
//
// A bottom sheet that lets customers place a direct order from a business's
// storefront. Creates a BusinessOrder via POST /api/storefront/:bizId/order.
//
// Phase 4: Direct Ordering from Storefront
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storefront/providers/storefront_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/azaman_haptics.dart';

class StorefrontOrderSheet extends ConsumerStatefulWidget {
  final String businessProfileId;
  final String businessName;
  final Map<String, dynamic> product;

  const StorefrontOrderSheet({
    super.key,
    required this.businessProfileId,
    required this.businessName,
    required this.product,
  });

  @override
  ConsumerState<StorefrontOrderSheet> createState() => _StorefrontOrderSheetState();
}

class _StorefrontOrderSheetState extends ConsumerState<StorefrontOrderSheet> {
  int _quantity = 1;
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _unitPrice => (widget.product['priceUsdc'] as num?)?.toDouble() ?? 0.0;
  double get _total => _unitPrice * _quantity;
  String get _productName => widget.product['name'] as String? ?? 'Product';
  String? get _imageUrl {
    final urls = (widget.product['imageUrls'] as List?)?.cast<String>();
    return urls != null && urls.isNotEmpty ? urls.first : null;
  }

  Future<void> _placeOrder() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    AzamanHaptics.confirm();

    try {
      final service = ref.read(storefrontServiceProvider);
      final result = await service.placeStorefrontOrder(
        businessProfileId: widget.businessProfileId,
        productId: widget.product['id'] as String,
        quantity: _quantity,
        customerNotes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        AzamanHaptics.warn();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final tags = (widget.product['tags'] as List?)?.cast<String>() ?? [];
    final prepMins = widget.product['preparationMins'] as int?;
    final description = widget.product['description'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: colors.divider, borderRadius: BorderRadius.circular(2)),
                ),
              ),

              // Product header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 64, height: 64,
                      child: _imageUrl != null
                          ? Image.network(_imageUrl!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: colors.background, child: Icon(Icons.inventory_2, color: colors.textSecondary)))
                          : Container(color: colors.background, child: Icon(Icons.inventory_2, color: colors.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_productName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                        if (description != null) ...[
                          const SizedBox(height: 2),
                          Text(description, style: TextStyle(fontSize: 12, color: colors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text('\$${_unitPrice.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.accent)),
                            if (prepMins != null) ...[
                              const SizedBox(width: 8),
                              Text('~${prepMins}min', style: TextStyle(fontSize: 11, color: colors.textSecondary)),
                            ],
                            if (tags.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              ...tags.take(2).map((t) => Container(
                                margin: const EdgeInsets.only(right: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: colors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                child: Text(t, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: colors.accent)),
                              )),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Quantity selector
              Text('Quantity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _QtyButton(icon: Icons.remove, onTap: () => setState(() { if (_quantity > 1) _quantity--; })),
                  Container(
                    width: 56, height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.divider),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$_quantity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                  ),
                  _QtyButton(icon: Icons.add, onTap: () => setState(() { if (_quantity < 99) _quantity++; })),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: colors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        Text('Total: ', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                        Text('\$${_total.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.accent)),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Notes
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Add notes (optional)...',
                  hintStyle: TextStyle(color: colors.textSecondary, fontSize: 14),
                  filled: true, fillColor: colors.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.divider)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.accent, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),

              const SizedBox(height: 20),

              // Order button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _placeOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shopping_bag, size: 18),
                            const SizedBox(width: 8),
                            Text('Place Order · \$${_total.toStringAsFixed(2)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Order from ${widget.businessName}',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _QtyButton({required IconData icon, required VoidCallback onTap}) {
    final colors = ref.read(themeProvider).colors;
    return GestureDetector(
      onTap: () { AzamanHaptics.nav(); onTap(); },
      child: Container(
        width: 44, height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: colors.background,
          border: Border.all(color: colors.divider),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: colors.textPrimary),
      ),
    );
  }
}
