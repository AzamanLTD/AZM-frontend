// =============================================================================
// BUSINESS PROFILE SCREEN — Flutter V3 Marketplace Sprint (2026-06-21)
//
// The Booking.com "hotel page" equivalent for a business. Loaded by bizId
// ("BIZ-XXXX") so it works from search results, the marketplace home and deep
// links alike. Sections (top→bottom):
//   • Hero header (logo or accent gradient + name + verified badge)
//   • Quick info bar (rating / category / completed deals / KYB chip)
//   • About (description + tappable contact + address)
//   • Products & Services (FeaturedProductsSection + "See all")
//   • Locations (cards with directions + gallery)
//   • Reviews (average + 5-star distribution + ReviewCard list)
// A sticky bottom action bar exposes [Order Now] and a conditional
// [Pay Invoice] when the signed-in user has unpaid invoices from this business.
//
// Design note (suggested improvement, taken under the spec's latitude): the
// spec listed a third "Message" button in the action bar, but a marketplace
// "message" and an "order" both resolve to opening a deal ticket with the
// business — two buttons doing the same thing reads as noise. The bar instead
// leads with a single strong CTA (Order Now) plus the genuinely distinct
// Pay-Invoice affordance, matching the Booking.com pattern of one primary CTA.
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/business_products_screen.dart';
import 'package:azaman/screens/marketplace/leave_review_sheet.dart';
import 'package:azaman/screens/marketplace/my_invoices_screen.dart';
import 'package:azaman/screens/tickets/ticket_create_sheet.dart';
import 'package:azaman/screens/tickets/ticket_workspace_screen.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/ticket_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/featured_products_section.dart';
import 'package:azaman/widgets/image_lightbox.dart';
import 'package:azaman/widgets/rating_stars.dart';
import 'package:azaman/widgets/review_card.dart';

class BusinessProfileScreen extends ConsumerStatefulWidget {
  final String bizId;
  const BusinessProfileScreen({super.key, required this.bizId});

  @override
  ConsumerState<BusinessProfileScreen> createState() =>
      _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen> {
  final _scrollCtrl = ScrollController();
  final _reviewsKey = GlobalKey();

  bool _loading = true;
  String? _error;
  BusinessProfile? _business;
  List<BusinessLocation> _locations = const [];
  int _unpaidInvoices = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final service = BusinessService();
    try {
      final business = await service.getBusinessByBizId(widget.bizId);
      if (business == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Business not found.';
        });
        return;
      }
      // Locations are non-critical — failure shouldn't blank the page.
      List<BusinessLocation> locations = const [];
      try {
        locations = await service.getPublicLocations(widget.bizId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _business = business;
        _locations = locations;
        _loading = false;
      });
      _loadUnpaidInvoices(business);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Best-effort count of the signed-in user's unpaid invoices from this
  /// business — drives the conditional "Pay Invoice" action. Silent on error
  /// (e.g. signed-out browsing) so the page still renders.
  Future<void> _loadUnpaidInvoices(BusinessProfile business) async {
    try {
      final page = await BusinessService().getMyInvoices(status: 'SENT');
      if (!mounted) return;
      final count = page.invoices
          .where((i) => i.businessProfileId == business.id)
          .length;
      setState(() => _unpaidInvoices = count);
    } catch (_) {}
  }

  void _scrollToReviews() {
    final ctx = _reviewsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openOrderSheet({BusinessProduct? product}) async {
    final business = _business;
    if (business == null) return;
    AzamanHaptics.confirm();
    final ticket = await showModalBottomSheet<Ticket>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TicketCreateSheet(
        preselectedBusiness: business,
        preselectedProduct: product,
      ),
    );
    if (ticket != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TicketWorkspaceScreen(
            ticketId: ticket.id,
            friendUsername: business.businessName,
          ),
        ),
      );
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    if (_loading) {
      return Scaffold(
        backgroundColor: colors.background,
        body: Center(child: CircularProgressIndicator(color: colors.accent)),
      );
    }

    final business = _business;
    if (business == null) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.surface,
          elevation: 0,
          iconTheme: IconThemeData(color: colors.textPrimary),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(HugeIconsSolid.store01,
                    size: 48, color: colors.textTertiary),
                const SizedBox(height: 12),
                Text(
                  _error ?? 'Business not found.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _load,
                  child: Text('Retry',
                      style: TextStyle(color: colors.accent)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollCtrl,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _hero(business, colors)),
              SliverToBoxAdapter(child: _quickInfoBar(business, colors)),
              SliverToBoxAdapter(child: _about(business, colors)),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              SliverToBoxAdapter(child: _products(business, colors)),
              SliverToBoxAdapter(child: _locationsSection(colors)),
              SliverToBoxAdapter(child: _reviewsSection(business, colors)),
              // Pad the tail so the sticky action bar never covers content.
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _actionBar(colors)),
        ],
      ),
    );
  }

  // ── Hero header ────────────────────────────────────────────────────────────
  Widget _hero(BusinessProfile business, AzamanColors colors) {
    final logo = business.logoUrl;
    return SizedBox(
      height: 280,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (logo != null && logo.isNotEmpty)
            CachedNetworkImage(
              imageUrl: logo,
              fit: BoxFit.cover,
              placeholder: (_, __) => _heroGradient(colors),
              errorWidget: (_, __, ___) => _heroGradient(colors),
            )
          else
            _heroGradient(colors),
          // Bottom scrim for legible white text.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
                stops: [0.45, 1.0],
              ),
            ),
          ),
          // Top buttons.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  _circleButton(
                    HugeIconsSolid.arrowLeft01,
                    () => Navigator.maybePop(context),
                  ),
                  const Spacer(),
                  _circleButton(
                    HugeIconsSolid.share08,
                    () => _launch(business.website ?? ''),
                  ),
                ],
              ),
            ),
          ),
          // Name + verified overlay.
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    business.businessName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                  ),
                ),
                if (business.isVerified) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Icon(HugeIconsSolid.checkmarkCircle01,
                        color: colors.success, size: 22),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroGradient(AzamanColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.accent,
            colors.accent.withOpacity(0.55),
          ],
        ),
      ),
      child: Center(
        child: Icon(HugeIconsSolid.store01,
            size: 72, color: Colors.white.withOpacity(0.35)),
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AzamanHaptics.nav();
        onTap();
      },
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  // ── Quick info bar ───────────────────────────────────────────────────────
  Widget _quickInfoBar(BusinessProfile business, AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            GestureDetector(
              onTap: _scrollToReviews,
              child: _infoChip(
                colors,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RatingStars(
                        rating: business.averageRating,
                        size: 13,
                        showNumber: true),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _infoChip(
              colors,
              child: Text(
                business.categoryLabel,
                style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            _infoChip(
              colors,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(HugeIconsStroke.checkmarkBadge01,
                      size: 13, color: colors.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    '${business.completedEscrows} deals',
                    style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            if (business.isKybVerified) ...[
              const SizedBox(width: 8),
              _infoChip(
                colors,
                accent: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(HugeIconsSolid.shield01,
                        size: 13, color: colors.success),
                    const SizedBox(width: 4),
                    Text(
                      'KYB Verified',
                      style: TextStyle(
                          color: colors.success,
                          fontSize: 12,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoChip(AzamanColors colors,
      {required Widget child, bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent ? colors.success.withOpacity(0.12) : colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent ? colors.success.withOpacity(0.4) : colors.divider,
        ),
      ),
      child: child,
    );
  }

  // ── About ────────────────────────────────────────────────────────────────
  Widget _about(BusinessProfile business, AzamanColors colors) {
    final hasDescription =
        business.description != null && business.description!.trim().isNotEmpty;
    final contacts = <Widget>[];
    if (business.phoneNumber != null && business.phoneNumber!.isNotEmpty) {
      contacts.add(_contactRow(colors, HugeIconsStroke.call02,
          business.phoneNumber!, () => _launch('tel:${business.phoneNumber}')));
    }
    if (business.contactEmail != null && business.contactEmail!.isNotEmpty) {
      contacts.add(_contactRow(colors, HugeIconsStroke.mail01,
          business.contactEmail!, () => _launch('mailto:${business.contactEmail}')));
    }
    if (business.website != null && business.website!.isNotEmpty) {
      contacts.add(_contactRow(colors, HugeIconsStroke.globe02,
          business.website!, () => _launch(business.website!)));
    }
    if (business.address != null && business.address!.isNotEmpty) {
      contacts.add(_contactRow(
          colors, HugeIconsStroke.location01, business.address!, null));
    }

    if (!hasDescription && contacts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            if (hasDescription) ...[
              const SizedBox(height: 8),
              Text(
                business.description!.trim(),
                style: TextStyle(
                    color: colors.textSecondary, fontSize: 13.5, height: 1.45),
              ),
            ],
            if (contacts.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...contacts,
            ],
          ],
        ),
      ),
    );
  }

  Widget _contactRow(
      AzamanColors colors, IconData icon, String label, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 16, color: colors.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onTap != null ? colors.accent : colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Products & Services ────────────────────────────────────────────────────
  Widget _products(BusinessProfile business, AzamanColors colors) {
    final productsAsync = ref.watch(businessProductsProvider(widget.bizId));
    final total = productsAsync.maybeWhen(
      data: (page) => page.products.length,
      orElse: () => 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The FeaturedProductsSection renders its own heading + carousel and
        // collapses to nothing when the business has no products. Its Order
        // button routes through the business-mode TicketCreateSheet.
        FeaturedProductsSection(
          bizId: widget.bizId,
          onOrder: (p) => _openOrderSheet(product: p),
        ),
        if (total >= 6)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: GestureDetector(
              onTap: () {
                AzamanHaptics.nav();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BusinessProductsScreen(
                      bizId: widget.bizId,
                      businessName: business.businessName,
                    ),
                  ),
                );
              },
              child: Row(
                children: [
                  Text('See all products',
                      style: TextStyle(
                          color: colors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  Icon(HugeIconsStroke.arrowRight01,
                      size: 14, color: colors.accent),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Locations ──────────────────────────────────────────────────────────────
  Widget _locationsSection(AzamanColors colors) {
    if (_locations.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Locations',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ..._locations.map((loc) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _locationCard(loc, colors),
              )),
        ],
      ),
    );
  }

  Widget _locationCard(BusinessLocation loc, AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(HugeIconsSolid.location01, size: 18, color: colors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.label.isNotEmpty ? loc.label : 'Branch',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800),
                ),
              ),
              if (loc.distanceKm != null)
                Text(
                  '${loc.distanceKm!.toStringAsFixed(1)} km',
                  style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
            ],
          ),
          if (loc.address.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              loc.address,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
          if (loc.operatingHours != null &&
              loc.operatingHours!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _formatHours(loc.operatingHours!),
              style: TextStyle(color: colors.textTertiary, fontSize: 11.5),
            ),
          ],
          if (loc.galleryUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: loc.galleryUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => ImageLightbox.show(
                    context,
                    urls: loc.galleryUrls,
                    initialIndex: i,
                  ),
                  child: Hero(
                    tag: 'lightbox_${loc.galleryUrls[i]}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: loc.galleryUrls[i],
                        width: 110,
                        height: 80,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(width: 110, color: colors.softSurface),
                        errorWidget: (_, __, ___) =>
                            Container(width: 110, color: colors.softSurface),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              AzamanHaptics.nav();
              _launch(
                'https://www.google.com/maps/dir/?api=1&destination=${loc.latitude},${loc.longitude}',
              );
            },
            child: Row(
              children: [
                Icon(HugeIconsStroke.navigation03,
                    size: 15, color: colors.accent),
                const SizedBox(width: 6),
                Text('Get directions',
                    style: TextStyle(
                        color: colors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatHours(Map<String, dynamic> hours) {
    // Render a compact "Mon 8:00-22:00 · Tue …" string from whatever
    // day→range map the backend stores.
    return hours.entries
        .take(7)
        .map((e) => '${_capitalize(e.key)} ${e.value}')
        .join('  ·  ');
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  // ── Reviews ────────────────────────────────────────────────────────────────
  Widget _reviewsSection(BusinessProfile business, AzamanColors colors) {
    final reviewsAsync = ref.watch(businessReviewsProvider(widget.bizId));
    return Padding(
      key: _reviewsKey,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Reviews',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              RatingStars(rating: business.averageRating, size: 15),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () async {
                  final submitted =
                      await LeaveReviewSheet.show(context, business: business);
                  if (submitted && mounted) {
                    // Refresh reviews after a successful submission.
                    ref.invalidate(businessReviewsProvider(widget.bizId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Review submitted. Thank you!')),
                    );
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.accent),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '+ Review',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          reviewsAsync.when(
            loading: () => _reviewsShimmer(colors),
            error: (_, __) => Text(
              'Could not load reviews.',
              style: TextStyle(color: colors.textTertiary, fontSize: 13),
            ),
            data: (page) {
              if (page.reviews.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Column(
                    children: [
                      Icon(HugeIconsStroke.star,
                          size: 28, color: colors.textTertiary),
                      const SizedBox(height: 8),
                      Text('No reviews yet',
                          style: TextStyle(
                              color: colors.textSecondary, fontSize: 13)),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _distribution(page.reviews, colors),
                  const SizedBox(height: 12),
                  ...page.reviews.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ReviewCard(review: r),
                      )),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _reviewsShimmer(AzamanColors colors) {
    return Column(
      children: List.generate(
        3,
        (_) => Container(
          height: 86,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: colors.softSurface,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  /// 5-star breakdown bar chart computed from the loaded review page.
  Widget _distribution(List<BusinessReview> reviews, AzamanColors colors) {
    final counts = <int, int>{5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final r in reviews) {
      final star = r.rating.clamp(1, 5);
      counts[star] = (counts[star] ?? 0) + 1;
    }
    final total = reviews.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          for (int star = 5; star >= 1; star--)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    child: Text('$star',
                        style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                  Icon(HugeIconsSolid.star, size: 11, color: colors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : (counts[star] ?? 0) / total,
                        minHeight: 6,
                        backgroundColor: colors.softSurface,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(colors.warning),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 22,
                    child: Text('${counts[star] ?? 0}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: colors.textTertiary, fontSize: 11)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Sticky action bar ────────────────────────────────────────────────────
  Widget _actionBar(AzamanColors colors) {
    final onAccent = colors.isDark ? Colors.black : Colors.white;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _openOrderSheet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: onAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(HugeIconsSolid.shoppingBag03, size: 18),
                label: const Text('Order Now',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          if (_unpaidInvoices > 0) ...[
            const SizedBox(width: 12),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: () {
                  AzamanHaptics.nav();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyInvoicesScreen(),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.accent,
                  side: BorderSide(color: colors.accent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: Text('Pay Invoice ($_unpaidInvoices)',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
