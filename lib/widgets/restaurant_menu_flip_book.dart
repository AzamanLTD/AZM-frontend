// lib/widgets/restaurant_menu_flip_book.dart
// =============================================================================
// RESTAURANT MENU FLIP-BOOK — real page-turning menu for FOOD_BEVERAGE stores
//
// Uses `turnable_page` (pinned 1.0.1 — proprietary license, approved-PR-only
// upstream, so the version is pinned exactly and never auto-upgraded).
//
// Layout: a cover page (business name/logo) followed by one page per menu
// section, each holding a short list of dish rows. Tapping a dish's photo
// pops it out into a full detail card (image, description, price, add to
// order); tapping anywhere on that overlay returns it to the book. Dragging
// near a page corner flips pages — turnable_page's smart-gesture system
// keeps the two interactions from fighting each other.
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:turnable_page/turnable_page.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

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

class RestaurantMenuFlipBook extends StatefulWidget {
  final String businessName;
  final String? logoUrl;
  final List<CatalogSection> sections;
  final List<BusinessProduct> uncategorisedProducts;
  final AzamanColors colors;
  final void Function(BusinessProduct product) onOrder;

  const RestaurantMenuFlipBook({
    super.key,
    required this.businessName,
    required this.sections,
    required this.uncategorisedProducts,
    required this.colors,
    required this.onOrder,
    this.logoUrl,
  });

  @override
  State<RestaurantMenuFlipBook> createState() => _RestaurantMenuFlipBookState();
}

class _RestaurantMenuFlipBookState extends State<RestaurantMenuFlipBook>
    with SingleTickerProviderStateMixin {
  static const _itemsPerPage = 4;
  BusinessProduct? _poppedItem;

  List<_MenuPage> _buildPages() {
    final pages = <_MenuPage>[];

    void addSection(String title, String? subtitle, List<BusinessProduct> items) {
      if (items.isEmpty) return;
      for (var i = 0; i < items.length; i += _itemsPerPage) {
        final chunk = items.sublist(
          i,
          i + _itemsPerPage > items.length ? items.length : i + _itemsPerPage,
        );
        pages.add(_MenuPage(
          sectionTitle: title,
          sectionSubtitle: i == 0 ? subtitle : null,
          isSectionStart: i == 0,
          items: chunk,
        ));
      }
    }

    for (final section in widget.sections) {
      addSection(section.name, section.description, section.products);
    }
    addSection('Other Items', null, widget.uncategorisedProducts);

    return pages;
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final pages = _buildPages();

    if (pages.isEmpty) {
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

    final totalPages = pages.length + 1; // +1 for cover

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: AspectRatio(
              aspectRatio: 0.68,
              child: TurnablePage(
                pageCount: totalPages,
                pageViewMode: PageViewMode.single,
                autoResponseSize: true,
                paperBoundaryDecoration: PaperBoundaryDecoration.modern,
                settings: FlipSettings(
                  drawShadow: true,
                  flippingTime: 700,
                  maxShadowOpacity: 0.6,
                  swipeDistance: 50,
                  cornerTriggerAreaSize: 0.22,
                ),
                builder: (context, index, constraints) {
                  if (index == 0) {
                    return _coverPage(colors);
                  }
                  return _sectionPage(pages[index - 1], colors, pageIndex: index);
                },
              ),
            ),
          ),
        ),
        if (_poppedItem != null) _popOutOverlay(_poppedItem!, colors),
      ],
    );
  }

  Widget _bookPageChrome({required Widget child, required AzamanColors colors, int pageIndex = 0}) {
    // Alternating warm parchment tones for visual distinction between pages
    final isEvenPage = pageIndex % 2 == 0;
    final pageBg = isEvenPage
        ? const Color(0xFFFDF6E3) // warm cream
        : const Color(0xFFF5EDE0); // slightly deeper parchment
    final pageBorder = isEvenPage
        ? const Color(0xFFE8DCC4)
        : const Color(0xFFDDD0B8);

    return Container(
      decoration: BoxDecoration(
        color: pageBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: pageBorder, width: 1.2),
        boxShadow: [
          // Inner bezel — creates the "page edge" depth
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
            spreadRadius: 0,
          ),
          // Outer drop shadow
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 14,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      child: child,
    );
  }

  Widget _coverPage(AzamanColors colors) {
    // Find the dish with the best image for the cover hero
    final allProducts = [
      ...widget.sections.expand((s) => s.products),
      ...widget.uncategorisedProducts,
    ];
    final heroDish = allProducts
        .where((p) => p.primaryImage != null)
        .firstOrNull ?? allProducts.firstOrNull;

    return _bookPageChrome(
      colors: colors,
      pageIndex: 0,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (heroDish != null && heroDish.primaryImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AzamanNetworkImage(
                imageUrl: heroDish.primaryImage!,
                width: 120, height: 120, fit: BoxFit.cover,
              ),
            )
          else if (widget.logoUrl != null && widget.logoUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AzamanNetworkImage(
                imageUrl: widget.logoUrl!,
                width: 84, height: 84, fit: BoxFit.cover,
              ),
            )
          else
            Icon(Icons.restaurant_menu_rounded, size: 64, color: colors.accent),
          const SizedBox(height: 18),
          Text(
            widget.businessName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF2D2416),
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
            '${allProducts.length} dishes',
            style: TextStyle(
              color: const Color(0xFF8B7A5A),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swipe_left_rounded, size: 16, color: colors.textTertiary),
              const SizedBox(width: 6),
              Text(
                'Drag a corner to open',
                style: TextStyle(color: const Color(0xFF8B7A5A), fontSize: 11.5),
              ),
            ],
          ).animate().fadeIn(delay: 800.ms, duration: 600.ms),
        ],
      ),
    );
  }

  Widget _sectionPage(_MenuPage page, AzamanColors colors, {int pageIndex = 1}) {
    return _bookPageChrome(
      colors: colors,
      pageIndex: pageIndex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (page.isSectionStart) ...[
            Text(
              page.sectionTitle,
              style: TextStyle(
                color: const Color(0xFF2D2416),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (page.sectionSubtitle != null && page.sectionSubtitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  page.sectionSubtitle!,
                  style: TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
              ),
            const SizedBox(height: 10),
            Divider(color: colors.divider, height: 1),
            const SizedBox(height: 10),
          ] else ...[
            Text(
              '${page.sectionTitle} (cont.)',
              style: TextStyle(
                color: const Color(0xFF8B7A5A),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: page.items.length,
              separatorBuilder: (_, __) => Divider(
                color: const Color(0xFFE8DCC4).withValues(alpha: 0.5),
                height: 18,
              ),
              itemBuilder: (_, i) => _dishRow(page.items[i], colors),
            ),
          ),
          const SizedBox(height: 6),
          // Page number — helps user see their position in the book
          Center(
            child: Text(
              '${pageIndex}',
              style: TextStyle(
                color: const Color(0xFFB8A88A),
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
    final isVeg = product.tags.any((t) => t.toLowerCase().contains('veg'));
    final isSpicy = product.tags.any((t) => t.toLowerCase().contains('spicy'));
    final isPopular = product.tags.any((t) => t.toLowerCase().contains('popular'));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _poppedItem = product),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Hero(
            tag: 'menu-dish-${product.id}',
            child: ClipRRect(
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
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (isVeg)
                    Container(
                      width: 8, height: 8,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFF2D2416),
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
                      child: Text('Popular',
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
                      style: TextStyle(color: const Color(0xFF8B7A5A), fontSize: 10.5),
                    ),
                  ),
                const SizedBox(height: 3),
                Row(children: [
                  Text(
                    '${product.priceUsdc.toStringAsFixed(2)} USDC',
                    style: TextStyle(
                      color: const Color(0xFFB8860B),
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

  Widget _popOutOverlay(BusinessProduct product, AzamanColors colors) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _poppedItem = null),
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: GestureDetector(
              // Absorb taps on the card itself so tapping the button/card
              // doesn't fall through and instantly dismiss.
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
                        Hero(
                          tag: 'menu-dish-${product.id}',
                          child: ClipRRect(
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
                                    child: Icon(Icons.restaurant_rounded, size: 48, color: colors.textTertiary),
                                  ),
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
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Text(
                                    '${product.priceUsdc.toStringAsFixed(2)} USDC',
                                    style: TextStyle(
                                      color: colors.accent,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const Spacer(),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: colors.accent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
      ),
    );
  }
}
