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


import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:flutter_animate/flutter_animate.dart';

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
    return PremiumGlassContainer(
      blur: 30, opacity: 0.12, borderRadius: 24,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, top: 16, left: 20, right: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: colors.divider, borderRadius: BorderRadius.circular(2)))),
          Text('Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.textPrimary)).animate().fadeIn(duration: 200.ms),
          const SizedBox(height: 20),
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
          Text('Minimum Rating', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.textSecondary)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Slider(value: _minRating.toDouble(), min: 0, max: 5, divisions: 5,
              activeColor: colors.accent, inactiveColor: colors.divider, label: '${_minRating.toStringAsFixed(0)}★',
              onChanged: (v) => setState(() => _minRating = v.toInt()))),
            Text('${_minRating.toStringAsFixed(0)}★', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.accent)),
          ]),
          const SizedBox(height: 16),
          _premiumToggleRow('Verified businesses only', Icons.verified_rounded, _verifiedOnly, (v) => setState(() => _verifiedOnly = v), colors),
          const SizedBox(height: 12),
          _premiumToggleRow('Delivery available', Icons.local_shipping_rounded, _delivery, (v) => setState(() => _delivery = v), colors),
          const SizedBox(height: 12),
          _premiumToggleRow('Has physical location', Icons.storefront_rounded, _location, (v) => setState(() => _location = v), colors),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: GestureDetector(onTap: _reset, child: Container(height: 48,
              decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: colors.divider)),
              child: Center(child: Text('Reset', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.textSecondary)))))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: GestureDetector(onTap: _apply, child: Container(height: 48,
              decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: colors.accent.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 4))]),
              child: Center(child: Text('Apply Filters', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colors.background)))))),
          ]),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0, duration: 300.ms, curve: Curves.easeOutCubic);
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

  Widget _premiumToggleRow(String label, IconData icon, bool value, ValueChanged<bool> onChanged, dynamic colors) {
    return GestureDetector(
      onTap: () { AzamanHaptics.toggle(); onChanged(!value); },
      child: Row(children: [
        Icon(icon, size: 18, color: colors.textSecondary), const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary))),
        AnimatedContainer(
          duration: 200.ms, width: 44, height: 26,
          decoration: BoxDecoration(color: value ? colors.accent : colors.softSurface, borderRadius: BorderRadius.circular(13),
            border: Border.all(color: value ? Colors.transparent : colors.divider)),
          child: AnimatedAlign(
            duration: 200.ms, curve: Curves.easeOutCubic,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(width: 20, height: 20, margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: value ? colors.background : colors.textTertiary, shape: BoxShape.circle)),
          ),
        ),
      ]),
    );
  }
}
