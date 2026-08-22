// lib/widgets/restaurant_menu_flip_book.dart
// =============================================================================
// RESTAURANT MENU FLIP-BOOK — real page-turning menu for FOOD_BEVERAGE stores
//
// Rendering is handled by the in-house book engine in lib/widgets/book/
// (geometry solver → curl painter → spring controller). This file is purely
// the *menu*: how catalog sections become pages, what a dish row looks like,
// and how a tapped dish opens into an orderable detail card.
//
// Layout: a cover page (business name/logo/hero dish) followed by one page per
// chunk of menu section, each holding a short list of dish rows. Tapping a
// dish pops it out into a detail card (image, description, tags, price, add to
// order); tapping the scrim returns it to the book. Dragging any corner or the
// outer edge turns the page.
//
// Note on Hero: the book keeps up to three copies of a page mounted at once
// (leaf, page underneath, occluded pre-raster), so dish images deliberately do
// *not* use Hero — duplicate tags in one route are a crash waiting to happen.
// The detail card animates itself instead.
// =============================================================================
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/book/book.dart';

/// Paper palette. Kept here rather than in theme_provider because these are
/// physical paper tones, not app theme tokens.
const _paperEven = Color(0xFFFDF6E3); // warm cream
const _paperOdd = Color(0xFFF5EDE0); // slightly deeper parchment
const _ink = Color(0xFF2D2416); // dark warm brown for headings
const _inkSoft = Color(0xFF8B7A5A); // muted brown for body text
const _gold = Color(0xFFB8860B); // dark goldenrod for prices
const _rule = Color(0xFFE8DCC4); // separator lines on the page

/// One flat "page worth" of dishes, built from CatalogSections.
class _MenuPage {
  final String sectionTitle;
  final String? sectionSubtitle;
  final bool isSectionStart;
  final List<BusinessProduct> items;
  const _MenuPage({
    required this.sectionTitle,
    this.sectionSubtitle,
    required this.isSectionStart,
    required this.items,
  });
}

/// Ambient dining-room stage behind the book — a warm radial vignette with a
/// blurred interior photo, giving the book a room to sit in.
class _AmbientStage extends StatelessWidget {
  const _AmbientStage();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.85,
          colors: [
            const Color(0xFF1F1409).withValues(alpha: 0.0),
            const Color(0xFF1F1409).withValues(alpha: 0.82),
          ],
        ),
      ),
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: ui.TileMode.mirror),
        child: Image.asset(
          'assets/images/food/restaurant_interior.jpg',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class RestaurantMenuFlipBook extends StatefulWidget {
  final String businessName;
  final String? logoUrl;
  final List<CatalogSection> sections;
  final List<BusinessProduct> uncategorisedProducts;
  final AzamanColors colors;
  final void Function(BusinessProduct product) onOrder;

  /// Whether to render the ambient dining-room stage behind the book.
  final bool ambient;
  final bool idleHint;

  const RestaurantMenuFlipBook({
    super.key,
    required this.businessName,
    required this.sections,
    required this.uncategorisedProducts,
    required this.colors,
    required this.onOrder,
    this.logoUrl,
    this.ambient = true,
    this.idleHint = true,
  });

  @override
  State<RestaurantMenuFlipBook> createState() => _RestaurantMenuFlipBookState();
}

class _RestaurantMenuFlipBookState extends State<RestaurantMenuFlipBook> {
  static const _itemsPerPage = 4;
  final GlobalKey<FlipBookState> _bookKey = GlobalKey<FlipBookState>();
  late FlipBookController _controller;

  BusinessProduct? _poppedItem;
  List<_MenuPage> _pages = const [];
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = FlipBookController();
    _pages = _buildPages();
  }

  @override
  void didUpdateWidget(covariant RestaurantMenuFlipBook oldWidget) {
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

  List<_MenuPage> _buildPages() {
    final pages = <_MenuPage>[];

    void addSection(String title, String? subtitle, List<BusinessProduct> items) {
      if (items.isEmpty) return;
      for (var i = 0; i < items.length; i += _itemsPerPage) {
        final end = i + _itemsPerPage > items.length ? items.length : i + _itemsPerPage;
        pages.add(_MenuPage(
          sectionTitle: title,
          sectionSubtitle: i == 0 ? subtitle : null,
          isSectionStart: i == 0,
          items: items.sublist(i, end),
        ));
      }
    }

    for (final section in widget.sections) {
      addSection(section.name, section.description, section.products);
    }
    addSection('Other Items', null, widget.uncategorisedProducts);

    return pages;
  }

  List<BusinessProduct> get _allProducts => [
        ...widget.sections.expand((s) => s.products),
        ...widget.uncategorisedProducts,
      ];

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    if (_pages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, size: 40, color: colors.textTertiary),
              const SizedBox(height: 10),
              Text('Menu not yet available',
                  style: TextStyle(color: colors.textSecondary, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    final pageCount = _pages.length + 1; // +1 for the cover

    final book = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: FlipBookFrame(
        child: FlipBook(
          key: _bookKey,
          controller: _controller,
          pageCount: pageCount,
          onPageChanged: (i) => setState(() => _page = i),
          idleHint: widget.idleHint,
          material: const BookMaterial(
            paper: _paperEven,
            castShadow: Color(0xFF1A1206),
            edge: Color(0xFFD8C6A2),
          ),
          pageBuilder: (context, index) =>
              index == 0 ? _coverPage(colors) : _sectionPage(_pages[index - 1], colors, index),
        ),
      ),
    );

    final content = Column(
      children: [
        Expanded(child: book),
        _bookControls(pageCount),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.ambient) const _AmbientStage(),
        content,
        if (_poppedItem != null) _popOutOverlay(_poppedItem!, colors),
      ],
    );
  }

  // ── Chrome under the book ─────────────────────────────────────────────────

  Widget _bookControls(int pageCount) {
    final onDark = widget.ambient;
    final fg = onDark ? Colors.white : _ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _navButton(
            icon: Icons.chevron_left_rounded,
            enabled: _page > 0,
            onTap: () => _bookKey.currentState?.turnBackward(),
            fg: fg,
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 96,
            child: Text(
              _page == 0 ? 'Cover' : '$_page / ${pageCount - 1}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fg.withValues(alpha: 0.72),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 18),
          _navButton(
            icon: Icons.chevron_right_rounded,
            enabled: _page < pageCount - 1,
            onTap: () => _bookKey.currentState?.turnForward(),
            fg: fg,
          ),
        ],
      ),
    );
  }

  Widget _navButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required Color fg,
  }) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: icon == Icons.chevron_left_rounded ? 'Previous page' : 'Next page',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.28,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fg.withValues(alpha: 0.10),
              border: Border.all(color: fg.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, size: 20, color: fg),
          ),
        ),
      ),
    );
  }

  // ── Pages ──────────────────────────────────────────────────────────────────

  Widget _pageSurface({required int pageIndex, required Widget child}) {
    final even = pageIndex.isEven;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: even
              ? const [Color(0xFFF3E9D2), _paperEven, Color(0xFFFFFBF0)]
              : const [Color(0xFFEDE3CD), _paperOdd, Color(0xFFFDF7E8)],
          stops: const [0.0, 0.42, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 24, 20, 16),
        child: child,
      ),
    );
  }

  Widget _coverPage(AzamanColors colors) {
    final products = _allProducts;
    final heroImage = products.where((p) => p.primaryImage != null).firstOrNull?.primaryImage;

    return _pageSurface(
      pageIndex: 0,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (heroImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AzamanNetworkImage(
                imageUrl: heroImage,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
              ),
            )
          else if (widget.logoUrl != null && widget.logoUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AzamanNetworkImage(
                imageUrl: widget.logoUrl!,
                width: 84,
                height: 84,
                fit: BoxFit.cover,
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/images/food/restaurant_cover.jpg',
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.restaurant_menu_rounded, size: 64, color: colors.accent),
              ),
            ),
          const SizedBox(height: 18),
          Text(
            widget.businessName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ink,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'MENU',
            style: TextStyle(
              color: colors.accent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${products.length} dishes',
            style: const TextStyle(color: _inkSoft, fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swipe_left_rounded, size: 16, color: _inkSoft),
              SizedBox(width: 6),
              Text('Drag a corner to open', style: TextStyle(color: _inkSoft, fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionPage(_MenuPage page, AzamanColors colors, int pageIndex) {
    return _pageSurface(
      pageIndex: pageIndex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (page.isSectionStart) ...[
            Text(
              page.sectionTitle,
              style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if (page.sectionSubtitle != null && page.sectionSubtitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  page.sectionSubtitle!,
                  style: const TextStyle(color: _inkSoft, fontSize: 11),
                ),
              ),
            const SizedBox(height: 10),
            const Divider(color: _rule, height: 1),
            const SizedBox(height: 10),
          ] else ...[
            Text(
              '${page.sectionTitle} (cont.)',
              style: const TextStyle(color: _inkSoft, fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: page.items.length,
              separatorBuilder: (_, __) => const Divider(color: _rule, height: 18),
              itemBuilder: (_, i) => _dishRow(page.items[i], colors),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '$pageIndex',
              style: const TextStyle(
                color: Color(0xFFB8A88A),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dishRow(BusinessProduct product, AzamanColors colors) {
    final tags = product.tags.map((t) => t.toLowerCase()).toList(growable: false);
    final isVeg = tags.any((t) => t.contains('veg'));
    final isSpicy = tags.any((t) => t.contains('spicy'));
    final isPopular = tags.any((t) => t.contains('popular'));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _poppedItem = product),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: product.primaryImage != null
                ? AzamanNetworkImage(
                    imageUrl: product.primaryImage!,
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 46,
                    height: 46,
                    color: colors.softSurface,
                    child: Icon(Icons.restaurant_rounded, size: 20, color: colors.textTertiary),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (isVeg)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                    ),
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isPopular)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Popular',
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ]),
                if (product.description != null && product.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      product.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _inkSoft, fontSize: 10.5),
                    ),
                  ),
                const SizedBox(height: 3),
                Row(children: [
                  Text(
                    '${product.priceUsdc.toStringAsFixed(2)} USDC',
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (isSpicy) ...[
                    const SizedBox(width: 6),
                    const Text('🌶', style: TextStyle(fontSize: 10)),
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Dish detail ────────────────────────────────────────────────────────────

  Widget _popOutOverlay(BusinessProduct product, AzamanColors colors) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _poppedItem = null),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(product.id),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => ColoredBox(
            color: Colors.black.withValues(alpha: 0.55 * t),
            child: Center(
              child: Transform.scale(
                scale: 0.92 + 0.08 * t,
                child: Opacity(opacity: t, child: child),
              ),
            ),
          ),
          child: GestureDetector(
            onTap: () {},
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        child: product.primaryImage != null
                            ? AzamanNetworkImage(
                                imageUrl: product.primaryImage!,
                                height: 170,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                height: 170,
                                color: colors.softSurface,
                                child: Icon(Icons.restaurant_rounded,
                                    size: 48, color: colors.textTertiary),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (product.description != null && product.description!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  product.description!,
                                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                                ),
                              ),
                            if (product.tags.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final tag in product.tags.take(5))
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: colors.softSurface,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          tag,
                                          style: TextStyle(
                                            color: colors.textSecondary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '${product.priceUsdc.toStringAsFixed(2)} USDC',
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: colors.accent,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colors.accent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 12),
                                  ),
                                  onPressed: () {
                                    setState(() => _poppedItem = null);
                                    widget.onOrder(product);
                                  },
                                  child: const Text(
                                    'Add to order',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
