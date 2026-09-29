import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/azaman_sheet.dart';

import 'retail_variant_swatches.dart';

// ── Retail shelf geometry (TASK-012) ─────────────────────────────────────────
// Exported so the permanent test can pin the parallax math and the lift rule.

/// Card width / gap / rail height of the shared retail shelf.
const double kRetailShelfCardWidth = 168;
const double kRetailShelfGap = 10;
const double kRetailShelfHeight = 250;

/// Damped downward travel that commits a lifted card to the tray.
const double kRetailLiftCommitTravel = 48;

/// Follow factor applied to each drag update (the "spring damping").
const double kRetailLiftDamping = 0.5;

/// Maximum visual travel of a lifted card, in px.
const double kRetailLiftMaxTravel = 96;

bool retailLiftCommits(double travel) => travel >= kRetailLiftCommitTravel;

/// Horizontal shelf-depth offset for card [index]: ±6px across the viewport,
/// 0 at the centre. Pure so it can be unit-tested.
double retailShelfParallaxOffset({
  required int index,
  required double scrollX,
  required double viewportWidth,
  double cardWidth = kRetailShelfCardWidth,
  double gap = kRetailShelfGap,
}) {
  if (viewportWidth <= 0) return 0;
  final cardCenter = index * (cardWidth + gap) + cardWidth / 2;
  final viewportCenter = scrollX + viewportWidth / 2;
  final progress = ((cardCenter - viewportCenter) / (viewportWidth / 2))
      .clamp(-1.0, 1.0)
      .toDouble();
  return progress * 6.0;
}

/// Depth scale for card [index]: 1.0 at the centre, 0.97 at the edges.
double retailShelfParallaxScale({
  required int index,
  required double scrollX,
  required double viewportWidth,
  double cardWidth = kRetailShelfCardWidth,
  double gap = kRetailShelfGap,
}) {
  if (viewportWidth <= 0) return 1.0;
  final cardCenter = index * (cardWidth + gap) + cardWidth / 2;
  final viewportCenter = scrollX + viewportWidth / 2;
  final progress = ((cardCenter - viewportCenter) / (viewportWidth / 2))
      .clamp(-1.0, 1.0)
      .toDouble()
      .abs();
  return 1.0 - progress * 0.03;
}

/// Luminance-preserving greyscale matrix for unavailable products.
const List<double> _kDesaturateMatrix = <double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
];

class RetailProduct {
  final String id;
  final String name;
  final String? description;
  final double? price;
  final String? currency;
  final List<String> imageUrls;
  final List<String> tags;
  final Map<String, dynamic> variants;
  final bool available;

  const RetailProduct({
    required this.id,
    required this.name,
    this.description,
    this.price,
    this.currency,
    this.imageUrls = const [],
    this.tags = const [],
    this.variants = const {},
    this.available = true,
  });

  factory RetailProduct.fromJson(Map<String, dynamic> json) {
    final images = json['imageUrls'] ?? json['images'];
    final tags = json['tags'];
    final variants = json['variants'];
    return RetailProduct(
      id: (json['id'] ?? json['productId'] ?? '').toString(),
      name: (json['name'] ?? json['title'] ?? 'Product').toString(),
      description: json['description']?.toString(),
      price: _toDouble(json['price'] ?? json['priceUsdc']),
      currency: json['currency']?.toString(),
      imageUrls: images is List
          ? images.map((v) => v.toString()).where((v) => v.isNotEmpty).toList()
          : const [],
      tags: tags is List
          ? tags.map((v) => v.toString()).where((v) => v.isNotEmpty).toList()
          : const [],
      variants: variants is Map
          ? Map<String, dynamic>.from(variants)
          : const {},
      available: json['available'] != false && json['isActive'] != false,
    );
  }

  String get formattedPrice {
    if (price == null) return 'Price unavailable';
    final symbol = switch (currency?.toUpperCase()) {
      'GHS' => 'GH₵',
      'NGN' => '₦',
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      _ => currency?.isNotEmpty == true ? '${currency!} ' : '',
    };
    return '$symbol${price!.toStringAsFixed(2)}';
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class RetailCollection {
  final String id;
  final String title;
  final String? subtitle;
  final List<RetailProduct> products;

  const RetailCollection({
    required this.id,
    required this.title,
    this.subtitle,
    this.products = const [],
  });
}

typedef RetailLiftCommit = void Function(RetailProduct product);

class RetailCollectionBox extends ConsumerStatefulWidget {
  final RetailCollection collection;
  final ValueChanged<RetailProduct> onProductTap;

  /// When non-null, available cards can be dragged DOWN to commit to the
  /// tray (≥ [kRetailLiftCommitTravel] px of travel). The marketplace stage
  /// does not pass this — its shelf has no tray; the storefront does.
  final RetailLiftCommit? liftCommit;

  /// Scroll-linked shelf depth (per-card parallax). Disabled automatically
  /// under reduced motion (aligned with TASK-024).
  final bool enableParallax;

  const RetailCollectionBox({
    super.key,
    required this.collection,
    required this.onProductTap,
    this.liftCommit,
    this.enableParallax = true,
  });

  @override
  ConsumerState<RetailCollectionBox> createState() =>
      _RetailCollectionBoxState();
}

class _RetailCollectionBoxState extends ConsumerState<RetailCollectionBox> {
  final ScrollController _shelfCtrl = ScrollController();
  double _scrollX = 0;

  @override
  void initState() {
    super.initState();
    _shelfCtrl.addListener(() {
      if (mounted) setState(() => _scrollX = _shelfCtrl.offset);
    });
  }

  @override
  void dispose() {
    _shelfCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final products = widget.collection.products.take(6).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.collection.title,
                    style: AzText.titleL.copyWith(color: colors.textPrimary),
                  ),
                  if (widget.collection.subtitle?.isNotEmpty == true) ...[
                    const SizedBox(height: AzSpace.xxs),
                    Text(
                      widget.collection.subtitle!,
                      style: AzText.bodyS.copyWith(color: colors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.collection.products.length > 1)
              Text(
                // Honest count: when the shelf shows fewer products than
                // the collection holds, say so instead of understating.
                products.length < widget.collection.products.length
                    ? '${products.length} of '
                          '${widget.collection.products.length} items'
                    : '${products.length} items',
                style: AzText.caption.copyWith(color: colors.textTertiary),
              ),
          ],
        ),
        const SizedBox(height: AzSpace.md),
        SizedBox(
          height: kRetailShelfHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewportWidth = constraints.maxWidth;
              return ListView.separated(
                controller: _shelfCtrl,
                // Cards lift out of the rail during a drag — do not clip.
                clipBehavior: Clip.none,
                scrollDirection: Axis.horizontal,
                itemCount: products.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: kRetailShelfGap),
                itemBuilder: (context, index) => SizedBox(
                  width: kRetailShelfCardWidth,
                  child: _ParallaxCard(
                    index: index,
                    scrollX: _scrollX,
                    viewportWidth: viewportWidth,
                    enabled: widget.enableParallax && !reduceMotion,
                    child: _LiftableCard(
                      product: products[index],
                      onTap: () => widget.onProductTap(products[index]),
                      onCommit: widget.liftCommit == null
                          ? null
                          : () => widget.liftCommit!(products[index]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Scroll-linked depth: cards off the viewport centre translate and shrink
/// slightly, so the shelf reads as a shallow 3-D rack.
class _ParallaxCard extends StatelessWidget {
  final int index;
  final double scrollX;
  final double viewportWidth;
  final bool enabled;
  final Widget child;

  const _ParallaxCard({
    required this.index,
    required this.scrollX,
    required this.viewportWidth,
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final dx = retailShelfParallaxOffset(
      index: index,
      scrollX: scrollX,
      viewportWidth: viewportWidth,
    );
    final scale = retailShelfParallaxScale(
      index: index,
      scrollX: scrollX,
      viewportWidth: viewportWidth,
    );
    return Transform.translate(
      offset: Offset(dx, 0),
      child: Transform.scale(scale: scale, child: child),
    );
  }
}

/// The lift gesture: a vertical drag claims the card (the horizontal list
/// keeps horizontal drags), the card follows with damping, and a release
/// after ≥ [kRetailLiftCommitTravel] px commits. A miss settles back with an
/// easeOutBack spring. Reduced motion disables the gesture entirely — the
/// quick-look button remains the primary path.
class _LiftableCard extends StatefulWidget {
  final RetailProduct product;
  final VoidCallback onTap;
  final VoidCallback? onCommit;

  const _LiftableCard({
    required this.product,
    required this.onTap,
    this.onCommit,
  });

  @override
  State<_LiftableCard> createState() => _LiftableCardState();
}

class _LiftableCardState extends State<_LiftableCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle;
  double _travel = 0;
  double _settleFrom = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this, duration: MotionTokens.standard);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  bool get _liftEnabled {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return widget.onCommit != null &&
        widget.product.available &&
        // An unknown price can never be a blind commit — the tray must not
        // accept a product whose price the server did not send.
        widget.product.price != null &&
        !reduceMotion;
  }

  double get _visualTravel => _dragging
      ? _travel
      : _settleFrom * (1 - Curves.easeOutBack.transform(_settle.value));

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _dragging = true;
      _settleFrom = 0;
      _travel = 0;
    });
    _settle.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _travel = (_travel + details.delta.dy * kRetailLiftDamping)
          .clamp(0.0, kRetailLiftMaxTravel)
          .toDouble();
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final committed = retailLiftCommits(_travel);
    setState(() {
      _dragging = false;
      _settleFrom = _travel;
      _travel = 0;
    });
    if (committed) widget.onCommit!();
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final travel = _visualTravel;
    final liftRatio = (travel / kRetailLiftMaxTravel).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: _liftEnabled ? _onDragStart : null,
      onVerticalDragUpdate: _liftEnabled ? _onDragUpdate : null,
      onVerticalDragEnd: _liftEnabled ? _onDragEnd : null,
      child: Transform.translate(
        offset: Offset(0, travel),
        child: Transform.scale(
          scale: 1.0 + liftRatio * 0.06,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AzRadius.lg),
              boxShadow: travel > 0
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20 * liftRatio),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : const [],
            ),
            child: RetailProductCard(
              product: widget.product,
              onTap: widget.onTap,
            ),
          ),
        ),
      ),
    );
  }
}

class RetailProductCard extends ConsumerStatefulWidget {
  final RetailProduct product;
  final VoidCallback onTap;

  const RetailProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  @override
  ConsumerState<RetailProductCard> createState() => _RetailProductCardState();
}

class _RetailProductCardState extends ConsumerState<RetailProductCard> {
  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final product = widget.product;
    final image = product.imageUrls.isEmpty ? null : product.imageUrls.first;
    return Semantics(
      button: true,
      label: '${product.name}, ${product.formattedPrice}',
      child: Material(
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AzRadius.lg),
          side: BorderSide(color: colors.divider),
        ),
        child: InkWell(
          onTap: product.available ? widget.onTap : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: image == null
                    ? _desaturateWhenUnavailable(const _RetailImageFallback())
                    : _desaturateWhenUnavailable(
                        Image.network(
                          image,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const _RetailImageFallback(),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The unavailable state covers the whole card: the
                    // title greys out with the image. The state line below
                    // deliberately stays at full strength so the reason is
                    // always readable.
                    _desaturateWhenUnavailable(
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AzText.bodyL.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.available
                          ? product.formattedPrice
                          : 'Currently unavailable',
                      style: AzText.bodyS.copyWith(
                        color: product.available
                            ? colors.accent
                            : colors.textTertiary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Applies the unavailable presentation — luminance-preserving
  /// desaturation plus a dim — to ANY part of the card (image, title), so
  /// the whole product reads as out of stock. The state line is never
  /// wrapped: its text must stay readable.
  Widget _desaturateWhenUnavailable(Widget content) {
    if (widget.product.available) return content;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(_kDesaturateMatrix),
      child: Opacity(opacity: 0.55, child: content),
    );
  }
}

Future<void> showRetailQuickLook(
  BuildContext context, {
  required RetailProduct product,
  required ValueChanged<RetailCartSelection> onAddToCart,
}) {
  // NEW-B: Panel weight. The quick-look body is a SingleChildScrollView, so
  // classify() returns panel, and the add-to-cart row is the pinned commit.
  return AzamanSheet.showPanel<void>(
    context,
    builder: (sheetContext, scrollController) => RetailQuickLookSheet(
      product: product,
      scrollController: scrollController,
      onAddToCart: (selection) {
        Navigator.of(sheetContext).pop();
        onAddToCart(selection);
      },
    ),
  );
}

class RetailCartSelection {
  final RetailProduct product;
  final Map<String, String> variants;
  final int quantity;

  const RetailCartSelection({
    required this.product,
    this.variants = const {},
    this.quantity = 1,
  });
}

class RetailQuickLookSheet extends ConsumerStatefulWidget {
  final RetailProduct product;
  final ValueChanged<RetailCartSelection> onAddToCart;

  /// The sheet's own scroll controller, supplied by [showRetailQuickLook].
  final ScrollController scrollController;

  const RetailQuickLookSheet({
    super.key,
    required this.product,
    required this.onAddToCart,
    required this.scrollController,
  });

  @override
  ConsumerState<RetailQuickLookSheet> createState() =>
      _RetailQuickLookSheetState();
}

class _RetailQuickLookSheetState extends ConsumerState<RetailQuickLookSheet> {
  final Map<String, String> _selections = {};
  int _quantity = 1;

  bool get _allVariantsSelected =>
      widget.product.variants.keys.every(_selections.containsKey);

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final image = widget.product.imageUrls.isEmpty
        ? null
        : widget.product.imageUrls.first;
    final variants = widget.product.variants;

    // NEW-B: the weight owns surface, radius, handle and safe-area, so the old
    // SafeArea + Material + clip are deleted. The Add-to-bag row is PINNED
    // below the scroll area — see §I.8.3. It used to be the last child of the
    // scroll view, and on a Panel opened at the 45% rest detent that put the
    // one control the whole sheet exists for below the fold.
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: SingleChildScrollView(
              controller: widget.scrollController,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Quick look',
                          style: AzText.titleL.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          HugeIconsSolid.cancel01,
                          size: 20,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  if (image != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AzRadius.lg),
                      child: AspectRatio(
                        aspectRatio: 1.2,
                        child: AzamanNetworkImage(
                          imageUrl: image,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              const _RetailImageFallback(),
                        ),
                      ),
                    ),
                  const SizedBox(height: AzSpace.md),
                  Text(
                    widget.product.name,
                    style: AzText.titleL.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AzSpace.xxs),
                  Text(
                    widget.product.formattedPrice,
                    style: AzText.money(colors.accent, size: AzText.sizeTitle),
                  ),
                  if (widget.product.description?.isNotEmpty == true) ...[
                    const SizedBox(height: AzSpace.sm),
                    Text(
                      widget.product.description!,
                      style: AzText.body.copyWith(color: colors.textSecondary),
                    ),
                  ],
                  if (variants.isNotEmpty) ...[
                    const SizedBox(height: AzSpace.md),
                    for (final entry in variants.entries)
                      RetailVariantSwatches(
                        keyName: entry.key,
                        values: _variantValues(entry.value),
                        selected: _selections[entry.key],
                        colors: colors,
                        onSelected: (value) =>
                            setState(() => _selections[entry.key] = value),
                      ),
                  ],
                  const SizedBox(height: AzSpace.md),
                  Row(
                    children: [
                      Text(
                        'Quantity',
                        style: AzText.label.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Decrease quantity',
                        onPressed: _quantity > 1
                            ? () => setState(() => _quantity--)
                            : null,
                        icon: Icon(
                          HugeIconsStroke.minusSign,
                          size: 18,
                          color: _quantity > 1
                              ? colors.textSecondary
                              : colors.divider,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      AnimatedSwitcher(
                        duration: MotionTokens.microInteraction,
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(scale: animation, child: child),
                        child: Text(
                          '$_quantity',
                          key: ValueKey(_quantity),
                          style: AzText.title.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Increase quantity',
                        onPressed: () => setState(() => _quantity++),
                        icon: Icon(
                          HugeIconsStroke.plusSign,
                          size: 18,
                          color: colors.accent,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              // An unknown price is not zero — never commit it to the tray.
              onPressed:
                  widget.product.available &&
                      widget.product.price != null &&
                      _allVariantsSelected
                  ? () => widget.onAddToCart(
                      RetailCartSelection(
                        product: widget.product,
                        variants: Map.unmodifiable(_selections),
                        quantity: _quantity,
                      ),
                    )
                  : null,
              icon: const Icon(HugeIconsStroke.shoppingBag01, size: 18),
              label: Text(
                !widget.product.available
                    ? 'Unavailable'
                    : widget.product.price == null
                    ? 'Price unavailable'
                    : 'Add to bag',
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _variantValues(dynamic raw) {
    final values = raw is List
        ? raw
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toList()
        : [raw.toString()];
    return values;
  }
}

class _RetailImageFallback extends ConsumerWidget {
  const _RetailImageFallback();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    return ColoredBox(
      color: colors.softSurface,
      child: Center(
        child: Icon(
          Icons.shopping_bag_outlined,
          size: 34,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}
