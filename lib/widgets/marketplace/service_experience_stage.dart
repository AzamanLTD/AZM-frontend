import 'package:flutter/material.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

class ServiceExperienceStage extends StatefulWidget {
  final BusinessProfile business;
  final AzamanColors colors;
  final List<BusinessProduct> offerings;
  final MarketplaceExperienceBlueprint blueprint;
  final VoidCallback? onContinue;
  final VoidCallback? onOpenCatalog;

  const ServiceExperienceStage({
    super.key,
    required this.business,
    required this.colors,
    required this.offerings,
    required this.blueprint,
    this.onContinue,
    this.onOpenCatalog,
  });

  @override
  State<ServiceExperienceStage> createState() => _ServiceExperienceStageState();
}

class _ServiceExperienceStageState extends State<ServiceExperienceStage> {
  final PageController _pageController = PageController(viewportFraction: 0.84);
  int _page = 0;
  BusinessProduct? _selected;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<BusinessProduct> get _available => widget.offerings
      .where((item) => item.isActive)
      .take(8)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final offerings = _available;
    if (offerings.isEmpty) return _emptyState();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.blueprint.showNavigationContext)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Explore ${widget.business.businessName}', style: TextStyle(color: widget.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(widget.blueprint.navigationLabel, style: TextStyle(color: widget.colors.textTertiary, fontSize: 11)),
                    ],
                  ),
                ),
                Text('${_page + 1} / ${offerings.length}', style: TextStyle(color: widget.colors.textTertiary, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        SizedBox(
          height: 224,
          child: PageView.builder(
            controller: _pageController,
            itemCount: offerings.length,
            onPageChanged: (index) => setState(() => _page = index),
            itemBuilder: (_, index) => _OfferingCard(
              product: offerings[index],
              colors: widget.colors,
              active: index == _page,
              onTap: () => setState(() => _selected = offerings[index]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 2),
          child: Row(
            children: [
              ...List.generate(
                offerings.length > 6 ? 6 : offerings.length,
                (index) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedContainer(
                      duration: MotionTokens.accessibleDuration(context, MotionTokens.microInteraction),
                      height: 3,
                      decoration: BoxDecoration(
                        color: index == _page ? widget.colors.accent : widget.colors.divider.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onOpenCatalog,
                  icon: const Icon(Icons.grid_view_rounded, size: 17),
                  label: const Text('See all offerings'),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.onContinue,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                  label: Text(widget.blueprint.commitStyle == MarketplaceCommitStyle.material ? 'Continue' : 'Choose this service'),
                ),
              ),
            ],
          ),
        ),
        if (_selected != null) _detailOverlay(_selected!),
      ],
    );
  }

  Widget _detailOverlay(BusinessProduct product) {
    final duration = MotionTokens.accessibleDuration(context, MotionTokens.standard);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.96, end: 1),
        duration: duration,
        curve: MotionTokens.enter,
        builder: (_, value, child) => Transform.scale(scale: value, alignment: Alignment.topCenter, child: child),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: widget.colors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: widget.colors.accent.withValues(alpha: 0.45)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OfferingImage(product: product, colors: widget.colors, size: 82),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800))),
                        IconButton(onPressed: () => setState(() => _selected = null), icon: const Icon(Icons.close_rounded, size: 18), tooltip: 'Close'),
                      ],
                    ),
                    if (widget.blueprint.showSpecifications && product.description != null && product.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(product.description!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.colors.textSecondary, fontSize: 12, height: 1.35)),
                      ),
                    const SizedBox(height: 8),
                    Text('${product.priceUsdc.toStringAsFixed(2)} USDC', style: TextStyle(color: widget.colors.accent, fontSize: 14, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 9),
                    SizedBox(width: double.infinity, child: FilledButton(onPressed: widget.onContinue, child: Text(widget.blueprint.detailPresentation == MarketplaceDetailPresentation.serviceDossier ? 'Continue with this' : 'Continue'))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: widget.colors.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: widget.colors.divider)),
        child: Column(
          children: [
            Icon(Icons.auto_awesome_outlined, size: 34, color: widget.colors.accent),
            const SizedBox(height: 11),
            Text('Explore this business', style: TextStyle(color: widget.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text('The business has not published offerings for this experience yet.', textAlign: TextAlign.center, style: TextStyle(color: widget.colors.textSecondary, fontSize: 12, height: 1.35)),
          ],
        ),
      ),
    );
  }
}

class _OfferingCard extends StatelessWidget {
  final BusinessProduct product;
  final AzamanColors colors;
  final bool active;
  final VoidCallback onTap;

  const _OfferingCard({required this.product, required this.colors, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: AnimatedScale(
        duration: MotionTokens.accessibleDuration(context, MotionTokens.microInteraction),
        scale: active ? 1 : 0.965,
        child: Semantics(
          button: true,
          label: '${product.name}, ${product.priceUsdc.toStringAsFixed(2)} USDC',
          child: Material(
            color: colors.card,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _OfferingImage(product: product, colors: colors, size: double.infinity)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: Row(
                      children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text('${product.priceUsdc.toStringAsFixed(2)} USDC', style: TextStyle(color: colors.accent, fontSize: 11.5, fontWeight: FontWeight.w800))])),
                        Icon(Icons.open_in_full_rounded, size: 17, color: colors.textTertiary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OfferingImage extends StatelessWidget {
  final BusinessProduct product;
  final AzamanColors colors;
  final double size;

  const _OfferingImage({required this.product, required this.colors, required this.size});

  @override
  Widget build(BuildContext context) {
    final image = product.primaryImage;
    if (image == null || image.isEmpty) {
      return Container(width: size == double.infinity ? null : size, color: colors.softSurface, child: Center(child: Icon(Icons.auto_awesome_mosaic_outlined, color: colors.textTertiary, size: 26)));
    }
    return SizedBox(width: size == double.infinity ? null : size, height: size == double.infinity ? null : size, child: AzamanNetworkImage(imageUrl: image, width: size == double.infinity ? null : size, height: size == double.infinity ? null : size, fit: BoxFit.cover));
  }
}
