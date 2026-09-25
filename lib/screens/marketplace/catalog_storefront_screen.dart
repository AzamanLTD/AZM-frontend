import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/parallax_header_delegate.dart';

/// Extracted from business_profile_screen.dart to reduce its size.
/// Full-screen catalog view with parallax hero + pinned category bar.
class CatalogStorefrontScreen extends StatefulWidget {
  final BusinessProfile business;
  final List<CatalogSection> sections;
  final List<BusinessProduct> uncategorisedProducts;
  final AzamanColors colors;
  final String catalogLabel;
  final Widget Function(BusinessProduct product) productRowBuilder;

  const CatalogStorefrontScreen({
    super.key,
    required this.business,
    required this.sections,
    required this.uncategorisedProducts,
    required this.colors,
    required this.catalogLabel,
    required this.productRowBuilder,
  });

  @override
  State<CatalogStorefrontScreen> createState() => _CatalogStorefrontScreenState();
}

class _CatalogStorefrontScreenState extends State<CatalogStorefrontScreen> {
  static const double _kCategoryBarHeight = 46;
  static const double _kHeroMaxExtent = 250;

  final ScrollController _scrollCtrl = ScrollController();
  late final List<String> _categoryNames;
  late final List<GlobalKey> _sectionKeys;
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _categoryNames = [
      ...widget.sections.map((s) => s.name),
      if (widget.uncategorisedProducts.isNotEmpty) 'Other Items',
    ];
    _sectionKeys = List.generate(_categoryNames.length, (_) => GlobalKey());
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final threshold =
        MediaQuery.of(context).padding.top + 56 + _kCategoryBarHeight + 8;
    int newIndex = _activeIndex;
    for (int i = 0; i < _sectionKeys.length; i++) {
      final box = _sectionKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y <= threshold) newIndex = i;
    }
    if (newIndex != _activeIndex && mounted) {
      setState(() => _activeIndex = newIndex);
    }
  }

  Future<void> _scrollToSection(int index) async {
    HapticFeedback.selectionClick();
    setState(() => _activeIndex = index);
    final ctx = _sectionKeys[index].currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      alignment: 0.0,
    );
    if (_scrollCtrl.hasClients) {
      final target = (_scrollCtrl.offset - _kCategoryBarHeight)
          .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
      if ((target - _scrollCtrl.offset).abs() > 1) {
        _scrollCtrl.animateTo(target,
            duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final business = widget.business;
    final heroImage =
        business.showcaseUrls.isNotEmpty ? business.showcaseUrls.first : business.logoUrl;
    final heroMinExtent = 56 + MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: colors.background,
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: ParallaxHeaderDelegate(
              imageUrl: heroImage,
              title: business.businessName,
              subtitle: widget.catalogLabel,
              minExtent: heroMinExtent,
              maxExtent: _kHeroMaxExtent,
              accentColor: business.adAccentColorValue,
            ),
          ),
          if (_categoryNames.length > 1)
            SliverPersistentHeader(
              pinned: true,
              delegate: _StorefrontCategoryBarDelegate(
                height: _kCategoryBarHeight,
                child: Container(
                  color: colors.surface,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    itemCount: _categoryNames.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final active = i == _activeIndex;
                      return GestureDetector(
                        onTap: () => _scrollToSection(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active ? colors.accent : colors.softSurface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _categoryNames[i],
                            style: TextStyle(
                              color: active ? Colors.white : colors.textSecondary,
                              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                for (int i = 0; i < widget.sections.length; i++)
                  Padding(
                    key: _sectionKeys[i],
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _sectionBlock(
                      widget.sections[i].name,
                      widget.sections[i].description,
                      widget.sections[i].products,
                      colors,
                    ),
                  ),
                if (widget.uncategorisedProducts.isNotEmpty)
                  Padding(
                    key: _sectionKeys[widget.sections.length],
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _sectionBlock(
                        'Other Items', null, widget.uncategorisedProducts, colors),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionBlock(String name, String? description,
      List<BusinessProduct> products, AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name,
            style: TextStyle(
                color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
        if (description != null && description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(description,
                style: TextStyle(color: colors.textTertiary, fontSize: 12.5)),
          ),
        const SizedBox(height: 10),
        ...products.map((p) => widget.productRowBuilder(p)),
      ],
    );
  }
}

class _StorefrontCategoryBarDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _StorefrontCategoryBarDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(_StorefrontCategoryBarDelegate oldDelegate) =>
      height != oldDelegate.height || child != oldDelegate.child;
}
