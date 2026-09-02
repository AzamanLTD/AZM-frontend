import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/marketplace_extensions_models.dart';
import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/business_book_tab.dart';
import 'package:azaman/widgets/skeleton_loader.dart';

class DineInRestaurantOrderingScreen extends ConsumerStatefulWidget {
  final DineInTab tab;

  const DineInRestaurantOrderingScreen({
    super.key,
    required this.tab,
  });

  @override
  ConsumerState<DineInRestaurantOrderingScreen> createState() =>
      _DineInRestaurantOrderingScreenState();
}

class _DineInRestaurantOrderingScreenState
    extends ConsumerState<DineInRestaurantOrderingScreen> {
  BusinessProfile? _business;
  List<CatalogSection> _sections = const [];
  List<BusinessProduct> _uncategorisedProducts = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bizId = widget.tab.businessBizId;
    if (bizId == null || bizId.isEmpty) {
      setState(() => _error = 'This restaurant is no longer available.');
      return;
    }

    try {
      final business = await BusinessService().getBusinessByBizId(bizId);
      if (business == null) {
        if (mounted) setState(() => _error = 'This restaurant is no longer available.');
        return;
      }

      final response = await apiClient.get('/business/$bizId/menu', requireAuth: false);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rawSections = body['sections'] as List<dynamic>? ?? const [];
      final rawUncategorised = body['uncategorisedProducts'] as List<dynamic>? ?? const [];

      if (!mounted) return;
      setState(() {
        _business = business;
        _sections = rawSections
            .whereType<Map<String, dynamic>>()
            .map(CatalogSection.fromJson)
            .toList(growable: false);
        _uncategorisedProducts = rawUncategorised
            .whereType<Map<String, dynamic>>()
            .map(BusinessProduct.fromJson)
            .toList(growable: false);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _addToTab(
    BusinessProduct product,
    Map<String, String> selections,
    int quantity,
  ) async {
    final item = await ref.read(dineInTabProvider(widget.tab.id).notifier).addItem(
          widget.tab.id,
          productId: product.id,
          selection: selections,
          quantity: quantity,
        );
    if (!mounted) return;
    if (item == null) {
      throw StateError('The restaurant could not add this dish to the open tab.');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} added to your table tab.'),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final business = _business;

    if (_error != null) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.surface,
          title: const Text('Order at the restaurant'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
        ),
      );
    }

    if (business == null) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.surface,
          title: const Text('Order at the restaurant'),
        ),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: SkeletonList(itemHeight: 84, count: 4),
        ),
      );
    }

    final tableContext = widget.tab.tableLabel == null || widget.tab.tableLabel!.isEmpty
        ? 'Dine-in'
        : 'Dine-in · ${widget.tab.tableLabel}';

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text(
          business.businessName,
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colors.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: colors.surface,
            child: Row(
              children: [
                Icon(Icons.table_restaurant_outlined, size: 18, color: colors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tableContext,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'Open tab',
                  style: TextStyle(color: colors.textTertiary, fontSize: 10.5),
                ),
              ],
            ),
          ),
          Expanded(
            child: BusinessBookTab(
              business: business,
              colors: colors,
              menuSections: _sections,
              uncategorisedProducts: _uncategorisedProducts,
              dineInContext: tableContext,
              onDineInAddToTab: _addToTab,
            ),
          ),
        ],
      ),
    );
  }
}
