// =============================================================================
// ADVANCED FILTER SHEET — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Modal bottom sheet opened from the marketplace home's Filter button. Lets
// the user refine by price range, minimum rating, verified-only, delivery
// availability and physical-location presence. Returns a MarketplaceFilters
// on Apply (or null on dismiss); Reset clears everything.
//
// Note: the backend /search endpoint currently filters on category + verified
// + query; the remaining facets (price, rating, delivery, location) are applied
// client-side over the loaded results, so this sheet drives both.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class MarketplaceFilters {
  final double? minPrice;
  final double? maxPrice;
  final int minRating; // 0 = any
  final bool verifiedOnly;
  final bool deliveryAvailable;
  final bool hasPhysicalLocation;

  const MarketplaceFilters({
    this.minPrice,
    this.maxPrice,
    this.minRating = 0,
    this.verifiedOnly = false,
    this.deliveryAvailable = false,
    this.hasPhysicalLocation = false,
  });

  bool get isEmpty =>
      minPrice == null &&
      maxPrice == null &&
      minRating == 0 &&
      !verifiedOnly &&
      !deliveryAvailable &&
      !hasPhysicalLocation;
}

class AdvancedFilterSheet extends ConsumerStatefulWidget {
  final MarketplaceFilters initial;
  const AdvancedFilterSheet({super.key, required this.initial});

  static Future<MarketplaceFilters?> show(
    BuildContext context,
    MarketplaceFilters initial,
  ) {
    return showModalBottomSheet<MarketplaceFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdvancedFilterSheet(initial: initial),
    );
  }

  @override
  ConsumerState<AdvancedFilterSheet> createState() =>
      _AdvancedFilterSheetState();
}

class _AdvancedFilterSheetState extends ConsumerState<AdvancedFilterSheet> {
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  late int _minRating;
  late bool _verifiedOnly;
  late bool _delivery;
  late bool _location;

  @override
  void initState() {
    super.initState();
    _minCtrl = TextEditingController(
        text: widget.initial.minPrice?.toStringAsFixed(0) ?? '');
    _maxCtrl = TextEditingController(
        text: widget.initial.maxPrice?.toStringAsFixed(0) ?? '');
    _minRating = widget.initial.minRating;
    _verifiedOnly = widget.initial.verifiedOnly;
    _delivery = widget.initial.deliveryAvailable;
    _location = widget.initial.hasPhysicalLocation;
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    AzamanHaptics.commit();
    Navigator.pop(
      context,
      MarketplaceFilters(
        minPrice: double.tryParse(_minCtrl.text.trim()),
        maxPrice: double.tryParse(_maxCtrl.text.trim()),
        minRating: _minRating,
        verifiedOnly: _verifiedOnly,
        deliveryAvailable: _delivery,
        hasPhysicalLocation: _location,
      ),
    );
  }

  void _reset() {
    AzamanHaptics.toggle();
    setState(() {
      _minCtrl.clear();
      _maxCtrl.clear();
      _minRating = 0;
      _verifiedOnly = false;
      _delivery = false;
      _location = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(HugeIconsSolid.filterHorizontal,
                    color: colors.accent, size: 20),
                const SizedBox(width: 8),
                Text('Filters',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    )),
                const Spacer(),
                TextButton(
                  onPressed: _reset,
                  child: Text('Reset',
                      style: TextStyle(color: colors.textTertiary)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _label(colors, 'Price range (USDC)'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _priceField(colors, _minCtrl, 'Min')),
                const SizedBox(width: 12),
                Expanded(child: _priceField(colors, _maxCtrl, 'Max')),
              ],
            ),
            const SizedBox(height: 16),
            _label(colors, 'Minimum rating'),
            const SizedBox(height: 8),
            Row(
              children: [
                for (int r = 1; r <= 5; r++)
                  GestureDetector(
                    onTap: () {
                      AzamanHaptics.toggle();
                      setState(() => _minRating = _minRating == r ? 0 : r);
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        HugeIconsSolid.star,
                        size: 30,
                        color: r <= _minRating
                            ? colors.warning
                            : colors.divider,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _switch(colors, 'Verified only', _verifiedOnly,
                (v) => setState(() => _verifiedOnly = v)),
            _switch(colors, 'Delivery available', _delivery,
                (v) => setState(() => _delivery = v)),
            _switch(colors, 'Has physical location', _location,
                (v) => setState(() => _location = v)),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _apply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.isDark ? Colors.black : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Apply Filters',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(AzamanColors colors, String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      );

  Widget _priceField(
      AzamanColors colors, TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      style: TextStyle(color: colors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.textTertiary),
        filled: true,
        fillColor: colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _switch(
      AzamanColors colors, String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      activeColor: colors.success,
      onChanged: (v) {
        AzamanHaptics.toggle();
        onChanged(v);
      },
      title: Text(label,
          style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
    );
  }
}
