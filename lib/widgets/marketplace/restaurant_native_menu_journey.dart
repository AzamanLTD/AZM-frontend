import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/book/book.dart';
import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/marketplace/experiences/restaurant/restaurant_order_mode.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_sheet.dart';
import 'package:azaman/widgets/marketplace/marketplace_detail_surface.dart';
import 'package:azaman/widgets/marketplace/restaurant_order_mode_switch.dart';

/// Modifier selections for one restaurant dish build (TASK-013 audit
/// hardening: make the ID/name boundary explicit).
///
/// Invariant:
/// - map key = `RestaurantOptionGroup.id`;
/// - each set contains `RestaurantOption.id`s — never option *names*;
/// - ID -> option-name translation happens ONLY at the commit boundary
///   (`_RestaurantNativeMenuJourneyState._commit`), because the backend
///   storefront configuration validation/pricing consumes option NAMES
///   on the wire.
typedef SelectedOptionIdsForGroup = Map<String, Set<String>>;

class RestaurantNativeMenuJourney extends StatefulWidget {
  final String businessName;
  final List<CatalogSection> sections;
  final List<BusinessProduct> uncategorisedProducts;
  final Map<String, RestaurantDish> dishesById;
  final AzamanColors colors;
  final void Function(BusinessProduct product, Map<String, String> selections, int quantity) onAddToTray;
  final bool showGallery;
  final bool showSpecifications;
  final bool showOptions;
  final bool showQuantity;
  final String? dineInContext;
  final RestaurantOrderMode orderMode;
  final ValueChanged<RestaurantOrderMode>? onOrderModeChanged;
  final bool dineInAvailable;
  final MarketplaceDetailPresentation detailPresentation;

  const RestaurantNativeMenuJourney({
    super.key,
    required this.businessName,
    required this.sections,
    required this.uncategorisedProducts,
    required this.dishesById,
    required this.colors,
    required this.onAddToTray,
    this.showGallery = true,
    this.showSpecifications = true,
    this.showOptions = true,
    this.showQuantity = true,
    this.dineInContext,
    this.orderMode = RestaurantOrderMode.takeaway,
    this.onOrderModeChanged,
    this.dineInAvailable = true,
    this.detailPresentation = MarketplaceDetailPresentation.dishDossier,
  });

  @override
  State<RestaurantNativeMenuJourney> createState() => _RestaurantNativeMenuJourneyState();
}

class _MenuPage {
  final String title;
  final String? description;
  final List<BusinessProduct> products;
  const _MenuPage(this.title, this.description, this.products);
}

class _RestaurantNativeMenuJourneyState extends State<RestaurantNativeMenuJourney> {
  static const _pageSize = 4;
  final _bookKey = GlobalKey<FlipBookState>();
  late final FlipBookController _bookController;
  late List<_MenuPage> _pages;
  int _page = 0;
  BusinessProduct? _product;
  RestaurantDish? _dish;
  String? _size;
  final SelectedOptionIdsForGroup _options = {};
  int _quantity = 1;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _bookController = FlipBookController(edgeAnchored: true);
    _pages = _buildPages();
  }

  @override
  void dispose() {
    _bookController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RestaurantNativeMenuJourney oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sections, widget.sections) || !identical(oldWidget.uncategorisedProducts, widget.uncategorisedProducts)) {
      _pages = _buildPages();
    }
  }

  List<_MenuPage> _buildPages() {
    final pages = <_MenuPage>[];
    void addSection(String title, String? description, List<BusinessProduct> products) {
      for (var start = 0; start < products.length; start += _pageSize) {
        final end = start + _pageSize < products.length ? start + _pageSize : products.length;
        pages.add(_MenuPage(title, start == 0 ? description : null, products.sublist(start, end)));
      }
    }
    for (final section in widget.sections) {
      addSection(section.name, section.description, section.products);
    }
    addSection('Other Items', null, widget.uncategorisedProducts);
    return pages;
  }

  RestaurantDish _dishFor(BusinessProduct product) => widget.dishesById[product.id] ?? RestaurantDish(
        id: product.id,
        name: product.name,
        description: product.description,
        price: product.priceUsdc,
        imageUrls: product.imageUrls,
        available: product.isActive,
      );

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return Center(child: Text('Menu not yet available', style: TextStyle(color: widget.colors.textSecondary)));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            if (widget.onOrderModeChanged != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: RestaurantOrderModeSwitch(
                  selected: widget.orderMode,
                  onChanged: widget.onOrderModeChanged!,
                  colors: widget.colors,
                  dineInEnabled: widget.dineInAvailable,
                ),
              ),
            if (widget.orderMode == RestaurantOrderMode.dineIn && widget.dineInContext != null && widget.dineInContext!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.34), borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Text(widget.dineInContext!, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: FlipBookFrame(
                  child: FlipBook(
                    key: _bookKey,
                    controller: _bookController,
                    pageCount: _pages.length + 1,
                    onPageChanged: (index) => setState(() => _page = index),
                    idleHint: true,
                    material: const BookMaterial(
                      paper: Color(0xFFFDF6E3),
                      castShadow: Color(0x441A1206),
                      edge: Color(0xFFD8C6A2),
                    ),
                    pageBuilder: (_, index) => index == 0 ? _cover() : _menuPage(_pages[index - 1], index),
                  ),
                ),
              ),
            ),
            _navigationControls(),
          ],
        ),
        if (_product != null && _dish != null) _detailSheet(_product!, _dish!),
        if (_committing) _commitFeedback(),
      ],
    );
  }

  Widget _cover() {
    final products = <BusinessProduct>[...widget.sections.expand((section) => section.products), ...widget.uncategorisedProducts];
    BusinessProduct? hero;
    for (final product in products) {
      if (product.primaryImage != null) {
        hero = product;
        break;
      }
    }
    return _paperSurface(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hero?.primaryImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AzamanNetworkImage(imageUrl: hero!.primaryImage!, width: 120, height: 120, fit: BoxFit.cover),
            )
          else
            Icon(Icons.restaurant_menu_rounded, size: 58, color: widget.colors.accent),
          const SizedBox(height: 16),
          Text(widget.businessName, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF2D2416), fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('MENU', style: TextStyle(color: widget.colors.accent, fontSize: 12, letterSpacing: 4, fontWeight: FontWeight.w800)),
          const SizedBox(height: 22),
          const Text('Turn from the edge to browse', style: TextStyle(color: Color(0xFF8B7A5A), fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _menuPage(_MenuPage page, int index) {
    return _paperSurface(
      Stack(
        fit: StackFit.expand,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 92),
                child: Text(page.title, style: const TextStyle(color: Color(0xFF2D2416), fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              if (page.description != null && page.description!.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4, right: 92), child: Text(page.description!, style: const TextStyle(color: Color(0xFF8B7A5A), fontSize: 10.5))),
              const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(color: Color(0xFFE8DCC4), height: 1)),
              Expanded(child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: page.products.length,
                separatorBuilder: (_, __) => const Divider(color: Color(0xFFE8DCC4), height: 16),
                itemBuilder: (_, itemIndex) => _dishRow(page.products[itemIndex]),
              )),
              Align(alignment: Alignment.center, child: Text('$index', style: const TextStyle(color: Color(0xFFB8A88A), fontSize: 10))),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: _RibbonBookmark(
              title: page.title,
              color: widget.colors.accent,
              textColor: widget.colors.isDark ? Colors.black : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dishRow(BusinessProduct product) {
    final dish = _dishFor(product);
    final configurable = dish.variants.isNotEmpty || dish.optionGroups.isNotEmpty;
    return Semantics(
      button: true,
      label: '${product.name}${configurable ? ', customizable' : ''}',
      child: InkWell(
        onTap: () => setState(() {
          _product = product;
          _dish = dish;
          _size = null;
          _options.clear();
          _quantity = 1;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: product.primaryImage == null
                    ? Container(width: 48, height: 48, color: widget.colors.softSurface, child: Icon(Icons.restaurant_rounded, color: widget.colors.textTertiary, size: 20))
                    : AzamanNetworkImage(imageUrl: product.primaryImage!, width: 48, height: 48, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF2D2416), fontSize: 12.5, fontWeight: FontWeight.w700)),
                    if (product.description != null && product.description!.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 2), child: Text(product.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF8B7A5A), fontSize: 10.5))),
                    const SizedBox(height: 3),
                    Text(configurable ? 'From ${product.priceUsdc.toStringAsFixed(2)} USDC' : '${product.priceUsdc.toStringAsFixed(2)} USDC', style: const TextStyle(color: Color(0xFFB8860B), fontSize: 11.5, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFB8A88A), size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailSheet(BusinessProduct product, RestaurantDish dish) {
    final duration = MotionTokens.accessibleDuration(context, MotionTokens.standard);
    return MarketplaceDetailSurface(
      presentation: widget.detailPresentation,
      colors: widget.colors,
      duration: duration,
      onDismiss: _closeDetail,
      child: _detailBody(product, dish),
    );
  }

  Widget _detailBody(BusinessProduct product, RestaurantDish dish) {
    final canAdd = _canAdd(product, dish);
    final unit = _unitPrice(dish, product);
    final priceUnavailable = unit == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showGallery && dish.imageUrls.isNotEmpty)
          SizedBox(height: 190, child: PageView.builder(itemCount: dish.imageUrls.length, itemBuilder: (_, index) => AzamanNetworkImage(imageUrl: dish.imageUrls[index], fit: BoxFit.cover)))
        else
          Container(height: 112, color: widget.colors.softSurface, child: Icon(Icons.restaurant_menu_rounded, size: 42, color: widget.colors.textTertiary)),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 17, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Expanded(child: Text(product.name, style: TextStyle(color: widget.colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800))), IconButton(onPressed: _committing ? null : _closeDetail, icon: const Icon(Icons.close_rounded))]),
                if (dish.description != null && dish.description!.isNotEmpty) Text(dish.description!, style: TextStyle(color: widget.colors.textSecondary, fontSize: 13, height: 1.35)),
                if (widget.orderMode == RestaurantOrderMode.dineIn && widget.dineInContext != null && widget.dineInContext!.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 9), child: Row(children: [Icon(Icons.table_restaurant_outlined, size: 15, color: widget.colors.textTertiary), const SizedBox(width: 5), Expanded(child: Text(widget.dineInContext!, style: TextStyle(color: widget.colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600)))])),
                if (widget.showSpecifications && (dish.preparationMins != null || dish.calorieCount != null || dish.estimatedDelivery != null))
                  Padding(padding: const EdgeInsets.only(top: 13), child: Wrap(spacing: 7, runSpacing: 7, children: [
                    if (dish.preparationMins != null) _chip('${dish.preparationMins} min prep'),
                    if (dish.calorieCount != null) _chip('${dish.calorieCount} kcal'),
                    if (dish.estimatedDelivery != null && dish.estimatedDelivery!.isNotEmpty) _chip(dish.estimatedDelivery!),
                  ])),
                if (widget.showOptions && (dish.variants.isNotEmpty || dish.optionGroups.isNotEmpty)) _buildSheetLauncher(dish),
                const SizedBox(height: 15),
                Row(children: [Expanded(child: priceUnavailable ? Text('Price unavailable', style: TextStyle(color: widget.colors.textTertiary, fontSize: 15, fontWeight: FontWeight.w800)) : Text('${unit.toStringAsFixed(2)} USDC', style: TextStyle(color: widget.colors.accent, fontSize: 18, fontWeight: FontWeight.w900))), if (widget.showQuantity) _quantityControl()]),
                const SizedBox(height: 13),
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: canAdd && !priceUnavailable && !_committing ? _commit : null, icon: Icon(canAdd && !priceUnavailable ? Icons.add_shopping_cart_rounded : Icons.info_outline_rounded), label: Text(_addLabel(product, canAdd, unit)))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: widget.colors.softSurface, borderRadius: BorderRadius.circular(999)), child: Text(label, style: TextStyle(color: widget.colors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600)));

  /// Fail-closed Add label: a missing/invalid effective price renders an
  /// explicit unavailable state — never a misleading 0.00 total.
  String _addLabel(BusinessProduct product, bool canAdd, double? unit) {
    if (!product.isActive) return 'Unavailable';
    if (unit == null) return 'Price unavailable';
    if (!canAdd) return 'Choose required options';
    return 'Add to tray · ${(unit * _quantity).toStringAsFixed(2)}';
  }

  Widget _buildSheetLauncher(RestaurantDish dish) {
    final progress = restaurantBuildProgress(
      hasVariants: dish.variants.isNotEmpty,
      sizeChosen: _size != null && _size!.isNotEmpty,
      requiredGroupsSatisfied: [
        for (final group in dish.optionGroups.where((group) => group.required))
          _options[group.id]?.isNotEmpty ?? false,
      ],
    );
    final requiredTotal = (dish.variants.isEmpty ? 0 : 1) +
        dish.optionGroups.where((group) => group.required).length;
    final complete = progress >= 1;
    final summary = dish.variants.isEmpty && dish.optionGroups.isEmpty
        ? 'No options required'
        : complete
            ? 'Ready — all choices made'
            : '${(progress * requiredTotal).round()} of $requiredTotal required chosen';
    return Padding(
      padding: const EdgeInsets.only(top: 15),
      child: Semantics(
        button: true,
        label: 'Build your dish — $summary',
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openBuildSheet(dish),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: widget.colors.softSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: complete ? widget.colors.accent.withValues(alpha: 0.55) : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                _buildRing(progress, complete),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Build your dish', style: TextStyle(color: widget.colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: complete ? widget.colors.accent : widget.colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Icon(Icons.tune_rounded, size: 18, color: widget.colors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRing(double progress, bool complete) {
    return SizedBox(
      width: 34,
      height: 34,
      child: CustomPaint(
        painter: _CompletionRingPainter(
          progress: complete ? 1 : progress,
          complete: complete,
          trackColor: widget.colors.textTertiary.withValues(alpha: 0.25),
          accent: widget.colors.accent,
        ),
        child: complete
            ? Center(child: Icon(Icons.check_rounded, size: 17, color: widget.colors.accent))
            : Center(child: Text('${(progress * 100).round()}', style: TextStyle(color: widget.colors.textSecondary, fontSize: 9, fontWeight: FontWeight.w800))),
      ),
    );
  }

  void _openBuildSheet(RestaurantDish dish) {
    AzamanHaptics.nav();
    AzamanSheet.showPanel<void>(
      context,
      builder: (sheetContext, scrollController) => _RestaurantBuildSheet(
        dish: dish,
        basePrice: _product?.priceUsdc,
        colors: widget.colors,
        scrollController: scrollController,
        initialSize: _size,
        initialOptions: _options,
        onDone: (size, options) => setState(() {
          _size = size;
          _options
            ..clear()
            ..addAll({
              for (final entry in options.entries) entry.key: Set<String>.from(entry.value),
            });
          AzamanHaptics.confirm();
        }),
      ),
    );
  }

  /// Fail-closed detail pricing (TASK-013 audit correction): the effective
  /// base price resolves `RestaurantDish.price ?? BusinessProduct.priceUsdc`.
  /// An unavailable, non-finite, or non-positive base price — or a
  /// non-finite / non-positive effective total after variant and option
  /// deltas — yields `null`. The detail must never substitute 0.00 for an
  /// unknown price, and Add must stay disabled while the price is unknown.
  double? _unitPrice(RestaurantDish dish, BusinessProduct product) {
    // BusinessProduct.priceUsdc is non-nullable, so the effective base price
    // is unknown only when it resolves non-finite or <= 0 (unconfigured
    // catalog price) — both fail closed below.
    final basePrice = dish.price ?? product.priceUsdc;
    if (!basePrice.isFinite || basePrice <= 0) return null;
    var total = basePrice;
    for (final variant in dish.variants) {
      if (variant.name == _size) total += variant.priceDelta;
    }
    for (final group in dish.optionGroups) {
      final chosen = _options[group.id] ?? const <String>{};
      for (final option in group.options) {
        if (chosen.contains(option.id)) total += option.priceDelta;
      }
    }
    if (!total.isFinite || total <= 0) return null;
    return total;
  }

  bool _canAdd(BusinessProduct product, RestaurantDish dish) {
    if (!product.isActive || !dish.available) return false;
    if (!widget.showOptions) return true;
    if (dish.variants.isNotEmpty && (_size == null || _size!.isEmpty)) return false;
    for (final group in dish.optionGroups) {
      if (group.required && (_options[group.id]?.isEmpty ?? true)) return false;
    }
    return true;
  }

  Widget _quantityControl() {
    return Container(
      decoration: BoxDecoration(color: widget.colors.softSurface, borderRadius: BorderRadius.circular(13)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null, icon: const Icon(Icons.remove_rounded, size: 18)),
          SizedBox(width: 22, child: Text('$_quantity', textAlign: TextAlign.center, style: TextStyle(color: widget.colors.textPrimary, fontWeight: FontWeight.w800))),
          IconButton(onPressed: _quantity < 20 ? () => setState(() => _quantity++) : null, icon: const Icon(Icons.add_rounded, size: 18)),
        ],
      ),
    );
  }

  void _commit() {
    final product = _product;
    final dish = _dish;
    if (product == null || dish == null) return;
    final selections = <String, String>{};
    if (_size != null && _size!.isNotEmpty) selections['size'] = _size!;
    for (final group in dish.optionGroups) {
      final chosen = _options[group.id] ?? const <String>{};
      final names = group.options.where((option) => chosen.contains(option.id)).map((option) => option.name).toList()..sort();
      if (names.isNotEmpty) selections[group.name] = names.join(', ');
    }
    final duration = MotionTokens.accessibleDuration(context, MotionTokens.microInteraction);
    setState(() => _committing = true);
    Future<void>.delayed(duration, () {
      if (!mounted) return;
      widget.onAddToTray(product, selections, widget.showQuantity ? _quantity : 1);
      setState(() { _committing = false; _product = null; _dish = null; });
    });
  }

  void _closeDetail() {
    if (_committing) return;
    setState(() { _product = null; _dish = null; });
  }

  Widget _commitFeedback() {
    final duration = MotionTokens.accessibleDuration(context, MotionTokens.spatial);
    final content = Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: const BoxDecoration(
        color: Color(0xFFFDF6E3),
        border: Border.fromBorderSide(BorderSide(color: Color(0xFFD8C6A2))),
        boxShadow: [BoxShadow(color: Color(0x44000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.restaurant_menu_rounded, size: 18, color: Color(0xFF2D2416)),
        SizedBox(width: 8),
        Text('Dish added from the menu', style: TextStyle(color: Color(0xFF2D2416), fontSize: 12.5, fontWeight: FontWeight.w800)),
      ]),
    );
    return Positioned.fill(child: IgnorePointer(child: Align(alignment: Alignment.bottomCenter, child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.7, end: 1), duration: duration, curve: MotionTokens.enter,
      builder: (_, value, child) => Transform.translate(offset: Offset(0, 70 * (1 - value)), child: Opacity(opacity: value, child: child)),
      child: content,
    ))));
  }

  Widget _paperSurface(Widget child) => DecoratedBox(
    decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF3E9D2), Color(0xFFFDF6E3), Color(0xFFFFFBF0)])),
    child: Padding(padding: const EdgeInsets.fromLTRB(26, 24, 20, 15), child: child),
  );

  Widget _navigationControls() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 13),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _navButton(Icons.chevron_left_rounded, 'Previous page', _page > 0, () => _bookKey.currentState?.turnBackward()),
      const SizedBox(width: 18),
      SizedBox(width: 100, child: Text(_page == 0 ? 'Cover' : '$_page / ${_pages.length}', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 11.5, fontWeight: FontWeight.w600))),
      const SizedBox(width: 18),
      _navButton(Icons.chevron_right_rounded, 'Next page', _page < _pages.length, () => _bookKey.currentState?.turnForward()),
    ]),
  );

  Widget _navButton(IconData icon, String label, bool enabled, VoidCallback onTap) => Semantics(
    button: true, enabled: enabled, label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: MotionTokens.accessibleDuration(context, MotionTokens.control),
        opacity: enabled ? 1 : 0.3,
        child: Container(width: 34, height: 34, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.10), border: Border.all(color: Colors.white.withValues(alpha: 0.18))), child: Icon(icon, color: Colors.white, size: 20)),
      ),
    ),
  );
}

class _CompletionRingPainter extends CustomPainter {
  final double progress;
  final bool complete;
  final Color trackColor;
  final Color accent;

  const _CompletionRingPainter({
    required this.progress,
    required this.complete,
    required this.trackColor,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 2.5;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, track);
    if (progress <= 0) return;
    final arc = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, 2 * math.pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(covariant _CompletionRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.complete != complete ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.accent != accent;
}

class _RestaurantBuildSheet extends StatefulWidget {
  final RestaurantDish dish;
  final double? basePrice;
  final AzamanColors colors;
  final ScrollController scrollController;
  final String? initialSize;
  final SelectedOptionIdsForGroup initialOptions;
  final void Function(String? size, SelectedOptionIdsForGroup options) onDone;

  const _RestaurantBuildSheet({
    required this.dish,
    required this.basePrice,
    required this.colors,
    required this.scrollController,
    required this.initialSize,
    required this.initialOptions,
    required this.onDone,
  });

  @override
  State<_RestaurantBuildSheet> createState() => _RestaurantBuildSheetState();
}

class _RestaurantBuildSheetState extends State<_RestaurantBuildSheet> {
  late String? _size = widget.initialSize;
  late final SelectedOptionIdsForGroup _options = {
    for (final entry in widget.initialOptions.entries) entry.key: Set<String>.from(entry.value),
  };

  double? _unitPrice() {
    final basePrice = widget.dish.price ?? widget.basePrice;
    if (basePrice == null || !basePrice.isFinite || basePrice <= 0) return null;
    var total = basePrice;
    for (final variant in widget.dish.variants) {
      if (variant.name == _size) total += variant.priceDelta;
    }
    for (final group in widget.dish.optionGroups) {
      final chosen = _options[group.id] ?? const <String>{};
      for (final option in group.options) {
        if (chosen.contains(option.id)) total += option.priceDelta;
      }
    }
    if (!total.isFinite || total <= 0) return null;
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final dish = widget.dish;
    final unitPrice = _unitPrice();
    final canClose =
        unitPrice != null &&
        !dish.optionGroups.any(
          (group) => group.required && (_options[group.id]?.isEmpty ?? true),
        ) &&
        (dish.variants.isEmpty || (_size != null && _size!.isNotEmpty));

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Build your ${dish.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close build sheet',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: widget.colors.textSecondary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dish.variants.isNotEmpty) _variantChoices(),
                  ...dish.optionGroups.map(_modifierGroup),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canClose
                  ? () {
                      widget.onDone(_size, _options);
                      Navigator.pop(context);
                    }
                  : null,
              child: Text(
                unitPrice == null
                    ? 'Price unavailable'
                    : canClose
                        ? 'Done · ${unitPrice.toStringAsFixed(2)} USDC'
                        : 'Choose required options',
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _variantChoices() => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Size', style: TextStyle(color: widget.colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 7),
      Wrap(spacing: 7, runSpacing: 7, children: widget.dish.variants.map((variant) => ChoiceChip(
        label: Text(variant.priceDelta == 0 ? variant.name : '${variant.name} +${variant.priceDelta.toStringAsFixed(2)}'),
        selected: _size == variant.name,
        onSelected: (_) => setState(() => _size = variant.name),
      )).toList()),
    ]),
  );

  Widget _modifierGroup(RestaurantOptionGroup group) {
    final selected = _options.putIfAbsent(group.id, () => <String>{});
    final multi = group.maxSelection > 1;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(group.name, style: TextStyle(color: widget.colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700))), Text(group.required ? 'Required' : (multi ? 'Up to ${group.maxSelection}' : 'Optional'), style: TextStyle(color: widget.colors.textTertiary, fontSize: 10))]),
        const SizedBox(height: 4),
        ...group.options.map((option) {
          final checked = selected.contains(option.id);
          // The paper sheet paints a ColoredBox background between the tile
          // and the nearest Material ancestor, which would hide ink
          // splashes (and trips the ListTile debug assertion). Give each
          // modifier row its own transparent Material.
          return Material(
            color: Colors.transparent,
            child: CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: checked,
            onChanged: (value) => setState(() {
              if (value == true) {
                if (!multi) {
                  selected..clear()..add(option.id);
                } else if (selected.length < group.maxSelection) {
                  selected.add(option.id);
                }
              } else {
                selected.remove(option.id);
              }
            }),
            title: Text(option.name, style: TextStyle(color: widget.colors.textPrimary, fontSize: 12)),
            secondary: option.priceDelta == 0 ? null : Text('+${option.priceDelta.toStringAsFixed(2)}', style: TextStyle(color: widget.colors.textSecondary, fontSize: 10)),
            ),
          );
        }),
      ]),
    );
  }
}

class _RibbonBookmark extends StatelessWidget {
  final String title;
  final Color color;
  final Color textColor;

  const _RibbonBookmark({required this.title, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 5, offset: Offset(0, 2))],
      ),
      child: ClipPath(
        clipper: const _RibbonNotchClipper(),
        child: Container(
          width: 84,
          height: 30,
          color: color,
          padding: const EdgeInsets.only(right: 10, bottom: 3),
          alignment: Alignment.center,
          child: Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColor, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.4),
          ),
        ),
      ),
    );
  }
}

class _RibbonNotchClipper extends CustomClipper<Path> {
  const _RibbonNotchClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width - 10, size.height - 8)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _RibbonNotchClipper oldClipper) => false;
}
