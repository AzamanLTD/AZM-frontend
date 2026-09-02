import 'package:flutter/material.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/book/book.dart';

const _paper = Color(0xFFFDF6E3);
const _paperAlt = Color(0xFFF5EDE0);
const _ink = Color(0xFF2D2416);
const _mutedInk = Color(0xFF8B7A5A);
const _rule = Color(0xFFE8DCC4);

class RestaurantNativeMenuExperience extends StatefulWidget {
  final String businessName;
  final String? logoUrl;
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
  final bool ambient;

  const RestaurantNativeMenuExperience({
    super.key,
    required this.businessName,
    required this.sections,
    required this.uncategorisedProducts,
    required this.dishesById,
    required this.colors,
    required this.onAddToTray,
    this.logoUrl,
    this.showGallery = true,
    this.showSpecifications = true,
    this.showOptions = true,
    this.showQuantity = true,
    this.dineInContext,
    this.ambient = true,
  });

  @override
  State<RestaurantNativeMenuExperience> createState() => _RestaurantNativeMenuExperienceState();
}

class _RestaurantPage {
  final String title;
  final String? subtitle;
  final bool sectionStart;
  final List<BusinessProduct> products;
  const _RestaurantPage({required this.title, this.subtitle, required this.sectionStart, required this.products});
}

class _RestaurantNativeMenuExperienceState extends State<RestaurantNativeMenuExperience> {
  static const _itemsPerPage = 4;
  final _bookKey = GlobalKey<FlipBookState>();
  late final FlipBookController _controller;
  late List<_RestaurantPage> _pages;
  int _page = 0;
  BusinessProduct? _selectedProduct;
  RestaurantDish? _selectedDish;
  Map<String, String> _selections = {};
  final Map<String, Set<String>> _multiSelections = {};
  int _quantity = 1;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _controller = FlipBookController(edgeAnchored: true);
    _pages = _buildPages();
  }

  @override
  void didUpdateWidget(covariant RestaurantNativeMenuExperience oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sections, widget.sections) ||
        !identical(oldWidget.uncategorisedProducts, widget.uncategorisedProducts)) {
      _pages = _buildPages();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_RestaurantPage> _buildPages() {
    final pages = <_RestaurantPage>[];
    void add(String title, String? subtitle, List<BusinessProduct> products) {
      if (products.isEmpty) return;
      for (var i = 0; i < products.length; i += _itemsPerPage) {
        final end = (i + _itemsPerPage).clamp(0, products.length);
        pages.add(_RestaurantPage(
          title: title,
          subtitle: i == 0 ? subtitle : null,
          sectionStart: i == 0,
          products: products.sublist(i, end),
        ));
      }
    }
    for (final section in widget.sections) {
      add(section.name, section.description, section.products);
    }
    add('Other Items', null, widget.uncategorisedProducts);
    return pages;
  }

  List<BusinessProduct> get _products => [
        ...widget.sections.expand((section) => section.products),
        ...widget.uncategorisedProducts,
      ];

  RestaurantDish _dishFor(BusinessProduct product) {
    return widget.dishesById[product.id] ??
        RestaurantDish(
          id: product.id,
          name: product.name,
          description: product.description,
          price: product.priceUsdc,
          imageUrls: product.imageUrls,
          locationId: product.locationId,
          deliveryTerms: product.deliveryTerms,
          estimatedDelivery: product.estimatedDelivery,
          available: product.isActive && product.isAvailable,
        );
  }

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.menu_book_outlined, size: 42, color: widget.colors.textTertiary),
          const SizedBox(height: 10),
          Text('Menu not yet available', style: TextStyle(color: widget.colors.textSecondary)),
        ]),
      );
    }

    final pageCount = _pages.length + 1;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.ambient)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [Colors.transparent, Colors.black.withValues(alpha: 0.60)]),
            ),
            child: Image.asset(
              'assets/images/food/restaurant_interior.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        Column(
          children: [
            if (widget.dineInContext != null && widget.dineInContext!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.34),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.table_restaurant_outlined, size: 15, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(widget.dineInContext!, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: FlipBookFrame(
                  child: FlipBook(
                    key: _bookKey,
                    controller: _controller,
                    pageCount: pageCount,
                    onPageChanged: (index) => setState(() => _page = index),
                    idleHint: true,
                    material: const BookMaterial(paper: _paper, castShadow: Color(0xFF1A1206), edge: Color(0xFFD8C6A2)),
                    pageBuilder: (context, index) => index == 0 ? _cover() : _menuPage(_pages[index - 1], index),
                  ),
                ),
              ),
            ),
            _controls(pageCount),
          ],
        ),
        if (_selectedProduct != null) _detailOverlay(_selectedProduct!, _selectedDish ?? _dishFor(_selectedProduct!)),
        if (_adding) _paperRipOverlay(),
      ],
    );
  }

  Widget _cover() {
    final hero = _products.firstWhere((p) => p.primaryImage != null, orElse: () => _products.first);
    return _surface(
      even: true,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (hero.primaryImage != null)
          ClipRRect(borderRadius: BorderRadius.circular(20), child: AzamanNetworkImage(imageUrl: hero.primaryImage!, width: 118, height: 118, fit: BoxFit.cover))
        else if (widget.logoUrl != null && widget.logoUrl!.isNotEmpty)
          ClipRRect(borderRadius: BorderRadius.circular(20), child: AzamanNetworkImage(imageUrl: widget.logoUrl!, width: 86, height: 86, fit: BoxFit.cover))
        else
          Icon(Icons.restaurant_menu_rounded, size: 64, color: widget.colors.accent),
        const SizedBox(height: 18),
        Text(widget.businessName, textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text('MENU', style: TextStyle(color: widget.colors.accent, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 4)),
        const SizedBox(height: 7),
        Text('${_products.length} dishes', style: const TextStyle(color: _mutedInk, fontSize: 11)),
        const SizedBox(height: 23),
        const Text('Turn the page to browse by section', style: TextStyle(color: _mutedInk, fontSize: 11.5)),
      ]),
    );
  }

  Widget _menuPage(_RestaurantPage page, int index) {
    return _surface(
      even: index.isEven,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (page.sectionStart) ...[
          Text(page.title, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800)),
          if (page.subtitle != null && page.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(page.subtitle!, style: const TextStyle(color: _mutedInk, fontSize: 11)),
          ],
          const SizedBox(height: 10),
          const Divider(color: _rule, height: 1),
          const SizedBox(height: 10),
        ] else ...[
          Text('${page.title} · continued', style: const TextStyle(color: _mutedInk, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: page.products.length,
            separatorBuilder: (_, __) => const Divider(color: _rule, height: 18),
            itemBuilder: (_, itemIndex) => _dishRow(page.products[itemIndex]),
          ),
        ),
        Center(child: Text('$index', style: const TextStyle(color: Color(0xFFB8A88A), fontSize: 10, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _dishRow(BusinessProduct product) {
    final dish = _dishFor(product);
    final tags = product.tags.map((tag) => tag.toLowerCase()).toList(growable: false);
    final dietary = tags.where((tag) => tag.contains('veg') || tag.contains('vegan')).take(1).firstOrNull;
    final hasChoices = dish.variants.isNotEmpty || dish.optionGroups.isNotEmpty;
    return Semantics(
      button: true,
      label: '${product.name}${hasChoices ? ', customizable' : ''}',
      child: InkWell(
        onTap: () => _selectProduct(product),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: product.primaryImage != null
                  ? AzamanNetworkImage(imageUrl: product.primaryImage!, width: 48, height: 48, fit: BoxFit.cover)
                  : Container(width: 48, height: 48, color: widget.colors.softSurface, child: Icon(Icons.restaurant_rounded, size: 20, color: widget.colors.textTertiary)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (dietary != null)
                  Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 5), decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                Expanded(child: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w700))),
                if (hasChoices)
                  const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.tune_rounded, size: 14, color: _mutedInk)),
              ]),
              if (product.description != null && product.description!.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(product.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _mutedInk, fontSize: 10.5))),
              const SizedBox(height: 3),
              Text('${product.priceUsdc.toStringAsFixed(2)} USDC', style: const TextStyle(color: Color(0xFFB8860B), fontSize: 11.5, fontWeight: FontWeight.w800)),
            ])),
          ]),
        ),
      ),
    );
  }

  void _selectProduct(BusinessProduct product) {
    final dish = _dishFor(product);
    setState(() {
      _selectedProduct = product;
      _selectedDish = dish;
      _selections = {};
      _multiSelections.clear();
      _quantity = 1;
    });
  }

  Widget _detailOverlay(BusinessProduct product, RestaurantDish dish) {
    final normalDuration = MotionTokens.accessibleDuration(context, MotionTokens.standard);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selectedProduct = null),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.58),
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.95, end: 1),
              duration: normalDuration,
              curve: MotionTokens.enter,
              builder: (_, value, child) => Transform.scale(scale: value, child: child),
              child: GestureDetector(
                onTap: () {},
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 370, maxHeight: 640),
                  child: Material(
                    color: widget.colors.card,
                    borderRadius: BorderRadius.circular(22),
                    clipBehavior: Clip.antiAlias,
                    child: _detailContent(product, dish),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailContent(BusinessProduct product, RestaurantDish dish) {
    final choices = dish.variants.isNotEmpty || dish.optionGroups.isNotEmpty;
    final totalUnit = _computedUnitPrice(dish);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (widget.showGallery && dish.imageUrls.isNotEmpty)
        SizedBox(
          height: 190,
          child: PageView.builder(
            itemCount: dish.imageUrls.length,
            itemBuilder: (_, index) => AzamanNetworkImage(imageUrl: dish.imageUrls[index], width: double.infinity, height: 190, fit: BoxFit.cover),
          ),
        )
      else
        Container(height: 118, color: widget.colors.softSurface, child: Icon(Icons.restaurant_menu_rounded, size: 42, color: widget.colors.textTertiary)),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(product.name, style: TextStyle(color: widget.colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800))),
              IconButton(onPressed: _adding ? null : () => setState(() => _selectedProduct = null), icon: const Icon(Icons.close_rounded)),
            ]),
            if (dish.description != null && dish.description!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(dish.description!, style: TextStyle(color: widget.colors.textSecondary, fontSize: 13, height: 1.35))),
            if (widget.dineInContext != null && widget.dineInContext!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 10), child: Text(widget.dineInContext!, style: TextStyle(color: widget.colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600))),
            if (widget.showSpecifications && (dish.preparationMins != null || dish.calorieCount != null || dish.estimatedDelivery != null || dish.deliveryTerms != null))
              Padding(padding: const EdgeInsets.only(top: 14), child: Wrap(spacing: 7, runSpacing: 7, children: [
                if (dish.preparationMins != null) _specChip('${dish.preparationMins} min prep'),
                if (dish.calorieCount != null) _specChip('${dish.calorieCount} kcal'),
                if (dish.estimatedDelivery != null && dish.estimatedDelivery!.isNotEmpty) _specChip(dish.estimatedDelivery!),
                if (dish.deliveryTerms != null && dish.deliveryTerms!.isNotEmpty) _specChip(dish.deliveryTerms!),
              ])),
            if (widget.showOptions && choices) ...[
              const SizedBox(height: 16),
              if (dish.variants.isNotEmpty) _variantGroup(dish),
              for (final group in dish.optionGroups) ...[
                const SizedBox(height: 12),
                _optionGroup(group),
              ],
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('${totalUnit.toStringAsFixed(2)} USDC', style: TextStyle(color: widget.colors.accent, fontSize: 18, fontWeight: FontWeight.w900))),
              if (widget.showQuantity) _quantityStepper(),
            ]),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _canAdd(product, dish) && !_adding ? _startAdd : null,
              icon: Icon(_canAdd(product, dish) ? Icons.add_shopping_cart_rounded : Icons.info_outline_rounded),
              label: Text(_canAdd(product, dish) ? 'Add to tray · ${(totalUnit * _quantity).toStringAsFixed(2)}' : 'Choose required options'),
            )),
          ]),
        ),
      ),
    ]);
  }

  Widget _specChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: widget.colors.softSurface, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: widget.colors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600)),
      );

  Widget _variantGroup(RestaurantDish dish) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Size', style: TextStyle(color: widget.colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
      const SizedBox(height: 7),
      Wrap(spacing: 7, runSpacing: 7, children: dish.variants.map((variant) {
        final selected = _selections['size'] == variant.id;
        return ChoiceChip(
          label: Text('${variant.name}${variant.priceDelta == 0 ? '' : ' +${variant.priceDelta.toStringAsFixed(2)}'}'),
          selected: selected,
          onSelected: (_) => setState(() => _selections['size'] = variant.id),
        );
      }).toList()),
    ]);
  }

  Widget _optionGroup(RestaurantOptionGroup group) {
    final selected = _multiSelections.putIfAbsent(group.id, () => <String>{});
    final multi = group.maxSelection > 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(group.name, style: TextStyle(color: widget.colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13))),
        Text(group.required ? 'Required' : (multi ? 'Up to ${group.maxSelection}' : 'Optional'), style: TextStyle(color: widget.colors.textTertiary, fontSize: 10)),
      ]),
      const SizedBox(height: 7),
      ...group.options.map((option) {
        final isSelected = selected.contains(option.id);
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: isSelected,
          onChanged: (checked) {
            setState(() {
              if (checked == true) {
                if (!multi) selected
                  ..clear()
                  ..add(option.id);
                else if (selected.length < group.maxSelection) selected.add(option.id);
              } else {
                selected.remove(option.id);
              }
              if (!multi) _selections[group.id] = selected.isEmpty ? '' : selected.first;
              else _selections[group.id] = selected.toList()..sort();
            });
          },
          title: Text(option.name, style: TextStyle(color: widget.colors.textPrimary, fontSize: 12)),
          secondary: option.priceDelta == 0 ? null : Text('+${option.priceDelta.toStringAsFixed(2)}', style: TextStyle(color: widget.colors.textSecondary, fontSize: 10)),
        );
      }),
    ]);
  }

  double _computedUnitPrice(RestaurantDish dish) {
    var total = dish.price ?? 0;
    if (_selections['size'] != null) {
      final variant = dish.variants.where((item) => item.id == _selections['size']).firstOrNull;
      if (variant != null) total += variant.priceDelta;
    }
    for (final group in dish.optionGroups) {
      final chosen = _multiSelections[group.id] ?? const <String>{};
      for (final option in group.options.where((item) => chosen.contains(item.id))) {
        total += option.priceDelta;
      }
    }
    return total;
  }

  bool _canAdd(BusinessProduct product, RestaurantDish dish) {
    if (!product.isActive || !product.isAvailable || !dish.available) return false;
    if (!widget.showOptions) return true;
    if (dish.variants.isNotEmpty && (_selections['size'] == null || _selections['size']!.isEmpty)) return false;
    for (final group in dish.optionGroups) {
      if (group.required && (_multiSelections[group.id]?.isEmpty ?? true)) return false;
    }
    return true;
  }

  Widget _quantityStepper() {
    return DecoratedBox(
      decoration: BoxDecoration(color: widget.colors.softSurface, borderRadius: BorderRadius.circular(13)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: _quantity > 1 ? () => setState(() => _quantity -= 1) : null, icon: const Icon(Icons.remove_rounded, size: 18)),
        SizedBox(width: 22, child: Text('$_quantity', textAlign: TextAlign.center, style: TextStyle(color: widget.colors.textPrimary, fontWeight: FontWeight.w800))),
        IconButton(onPressed: _quantity < 20 ? () => setState(() => _quantity += 1) : null, icon: const Icon(Icons.add_rounded, size: 18)),
      ]),
    );
  }

  void _startAdd() {
    final product = _selectedProduct;
    final dish = _selectedDish;
    if (product == null || dish == null) return;
    final selections = <String, String>{};
    for (final entry in _selections.entries) {
      if (entry.value.isNotEmpty) selections[entry.key] = entry.value;
    }
    setState(() => _adding = true);
    final duration = MotionTokens.accessibleDuration(context, MotionTokens.spatial);
    Future<void>.delayed(duration == Duration.zero ? Duration.zero : duration, () {
      if (!mounted) return;
      widget.onAddToTray(product, selections, widget.showQuantity ? _quantity : 1);
      if (MotionTokens.accessibleDuration(context, MotionTokens.microInteraction) == Duration.zero) {
        _finishAdd();
      } else {
        setState(() => _adding = false);
        setState(() => _selectedProduct = null);
      }
    });
  }

  void _finishAdd() {
    if (!mounted) return;
    setState(() {
      _adding = false;
      _selectedProduct = null;
    });
  }

  Widget _paperRipOverlay() {
    final duration = MotionTokens.accessibleDuration(context, MotionTokens.spatial);
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: duration,
          opacity: _adding ? 1 : 0,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: duration,
              curve: MotionTokens.decelerate,
              builder: (_, value, __) => Transform.translate(
                offset: Offset(0, -70 * (1 - value)),
                child: Transform.rotate(
                  angle: 0.012 * (1 - value),
                  child: Opacity(
                    opacity: value,
                    child: Container(
                      width: 220,
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: _paper,
                        border: Border.all(color: const Color(0xFFD8C6A2)),
                        boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 14, offset: Offset(0, 6))],
                      ),
                      child: const Row(children: [
                        Icon(Icons.restaurant_menu_rounded, color: _ink, size: 18),
                        SizedBox(width: 8),
                        Expanded(child: Text('Added to your order tray', style: TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w800))),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _surface({required bool even, required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: even ? const [Color(0xFFF3E9D2), _paper, Color(0xFFFFFBF0)] : const [Color(0xFFEDE3CD), _paperAlt, Color(0xFFFDF7E8)],
        ),
      ),
      child: Padding(padding: const EdgeInsets.fromLTRB(26, 24, 20, 16), child: child),
    );
  }

  Widget _controls(int pageCount) {
    final fg = widget.ambient ? Colors.white : _ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _navButton(Icons.chevron_left_rounded, 'Previous page', _page > 0, () => _bookKey.currentState?.turnBackward(), fg),
        const SizedBox(width: 18),
        SizedBox(width: 108, child: Text(_page == 0 ? 'Cover' : '$_page / ${pageCount - 1}', textAlign: TextAlign.center, style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 11.5, fontWeight: FontWeight.w600))),
        const SizedBox(width: 18),
        _navButton(Icons.chevron_right_rounded, 'Next page', _page < pageCount - 1, () => _bookKey.currentState?.turnForward(), fg),
      ]),
    );
  }

  Widget _navButton(IconData icon, String label, bool enabled, VoidCallback onTap, Color fg) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: MotionTokens.accessibleDuration(context, MotionTokens.control),
          opacity: enabled ? 1 : 0.28,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, color: fg.withValues(alpha: 0.10), border: Border.all(color: fg.withValues(alpha: 0.18))),
            child: Icon(icon, size: 20, color: fg),
          ),
        ),
      ),
    );
  }
}
