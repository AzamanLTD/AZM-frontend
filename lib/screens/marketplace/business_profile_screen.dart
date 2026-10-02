// =============================================================================
// BUSINESS PROFILE SCREEN — Market Storefront Shell (2026-10-02)
//
// The customer-facing market surface. This screen is now the DATA +
// DELEGATION layer: it loads the business (by bizId, "BIX-XXXX"), its
// locations, menu/catalog, showcase, follow state and unpaid invoices,
// and hands everything to MarketStorefrontShell, which owns the storefront
// interaction model:
//   • arrival hero (banner + logo + name + status) overlapped by a white
//     draggable sheet showing the products,
//   • deliberate snap states (info / overview / shopping),
//   • the market's information living BEHIND the sheet (replacing the old
//     automatic ⓘ popover, pill tabs and floating bubbles),
//   • a compact market pill that crossfades in as the hero collapses.
//
// Everything the market can DO (order sheet, hotel/transit booking routes,
// full catalog experiences — restaurant flip-book, UberEats-style
// CatalogStorefrontScreen — SDUI storefront, invoices, reviews, locations,
// share, follow) is preserved here and wired into the shell as delegates.
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';
import 'package:animations/animations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/my_invoices_screen.dart';
import 'package:azaman/screens/marketplace/invoice_detail_screen.dart';
import 'package:azaman/screens/marketplace/market_storefront_shell.dart';
import 'package:azaman/screens/tickets/ticket_create_sheet.dart';
import 'package:azaman/screens/tickets/ticket_workspace_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/ticket_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/featured_products_section.dart';
import 'package:azaman/widgets/restaurant_menu_flip_book.dart';
import 'package:azaman/widgets/loyalty_stamp_card.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:azaman/widgets/scale_tap.dart';
import 'package:azaman/screens/marketplace/catalog_storefront_screen.dart';
import 'package:azaman/screens/marketplace/business_reviews_section.dart';

class BusinessProfileScreen extends ConsumerStatefulWidget {
  final String bizId;

  /// Injectable business-data seam. Production leaves this null (a real
  /// BusinessService is created); widget tests pass a counting fake so
  /// load-once invariants (e.g. invoices) can be proven.
  final BusinessService? service;

  const BusinessProfileScreen({super.key, required this.bizId, this.service});

  @override
  ConsumerState<BusinessProfileScreen> createState() =>
      _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen> {
  bool _loading = true;
  String? _error;
  BusinessProfile? _business;
  List<BusinessLocation> _locations = const [];

  // Marketplace v2: Follow state
  bool _isFollowing = false;
  bool _followLoading = false;

  // Marketplace showcase slides (banner priority #1).
  List<Map<String, dynamic>> _showcaseSlides = const [];

  // Catalog data for the in-sheet product surface + the full catalog routes.
  List<CatalogSection> _menuSections = const [];
  List<BusinessProduct> _uncategorisedProducts = const [];
  bool _menuLoading = false;

  // Signed-in user's unpaid invoices from this business (Pay invoice action).
  // The DETAILS are cached in stable parent state by _loadUnpaidInvoices()
  // exactly once per load: the storefront shell rebuilds its product subtree
  // on every draggable-sheet extent tick, so no widget below the screen may
  // ever create a Future / start network work during a rebuild. The section
  // renders purely from this state.
  int _unpaidInvoices = 0;
  List<BusinessInvoice> _unpaidInvoiceDetails = const [];
  BusinessService get _service => widget.service ?? BusinessService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final service = _service;
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
      _loadMenu(business.bizId);
      _loadFollowState(business.id);
      _loadShowcase(business.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadFollowState(String businessId) async {
    try {
      final res = await apiClient.get('/follows/check/$businessId');
      final data = jsonDecode(res.body);
      if (mounted) {
        setState(() {
          _isFollowing = data['isFollowing'] ?? false;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadShowcase(String businessId) async {
    try {
      final res = await apiClient.get('/showcases/$businessId');
      final data = jsonDecode(res.body);
      if (mounted) {
        // Handle multiple response shapes: {'data': [...]}, {'items': [...]},
        // {'slides': [...]}, or a bare List. Also handle URL-string lists
        // (demo seed returns ['url1', 'url2', ...]) by wrapping them as maps.
        final List rawList;
        if (data is List) {
          rawList = data;
        } else if (data['data'] is List) {
          rawList = data['data'] as List;
        } else if (data['items'] is List) {
          rawList = data['items'] as List;
        } else if (data['slides'] is List) {
          rawList = data['slides'] as List;
        } else {
          rawList = [];
        }
        final slides = <Map<String, dynamic>>[];
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            slides.add(item);
          } else if (item is String) {
            slides.add({'mediaUrl': item});
          }
        }
        setState(() => _showcaseSlides = slides);
      }
    } catch (_) {}
  }

  /// Best-effort load of the signed-in user's unpaid invoices from this
  /// business — drives the "Outstanding Bills" section and the conditional
  /// "Pay Invoice" action. Runs ONCE per screen load and caches the details
  /// in parent state: sheet-extent rebuilds must never initiate network work.
  /// Silent on error (e.g. signed-out browsing) so the page still renders.
  Future<void> _loadUnpaidInvoices(BusinessProfile business) async {
    try {
      final page = await _service.getMyInvoices(status: 'SENT');
      if (!mounted) return;
      final invoices = page.invoices
          .where((i) => i.businessProfileId == business.id)
          .toList(growable: false);
      setState(() {
        _unpaidInvoiceDetails = invoices;
        _unpaidInvoices = invoices.length;
      });
    } catch (_) {}
  }

  Future<void> _loadMenu(String bizId) async {
    setState(() => _menuLoading = true);
    try {
      final response = await apiClient.get('/business/$bizId/menu');
      final body = jsonDecode(response.body);
      final sections = body['sections'] as List<dynamic>? ?? [];
      final uncategorised =
          body['uncategorisedProducts'] as List<dynamic>? ?? [];
      if (!mounted) return;
      setState(() {
        _menuSections = sections
            .map((e) => CatalogSection.fromJson(e as Map<String, dynamic>))
            .toList();
        _uncategorisedProducts = uncategorised
            .map((e) => BusinessProduct.fromJson(e as Map<String, dynamic>))
            .toList();
        _menuLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _menuLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_followLoading) return;
    setState(() => _followLoading = true);
    final wasFollowing = _isFollowing;
    setState(() => _isFollowing = !_isFollowing);
    try {
      final client = ref.read(apiClientProvider);
      final bizId = _business?.id ?? widget.bizId;
      if (wasFollowing) {
        await client.delete('/follows/$bizId');
      } else {
        await client.post('/follows', {'businessProfileId': bizId});
      }
    } catch (e) {
      // Revert on failure
      if (mounted) {
        setState(() => _isFollowing = wasFollowing);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
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

  /// Routes the primary CTA to the right flow for the business's vertical:
  /// FOOD_BEVERAGE opens the order sheet inline; HOSPITALITY/REAL_ESTATE and
  /// LOGISTICS push to their dedicated booking screens; every other vertical
  /// opens the order sheet against that business's own product/service
  /// catalog.
  void _primaryCtaAction() {
    final business = _business;
    if (business == null) return;
    switch (business.category) {
      case 'HOSPITALITY':
      case 'REAL_ESTATE':
        context.push('/business-market/${business.id}/hotel-booking');
        return;
      case 'LOGISTICS':
        context.push('/business-market/${business.id}/transit');
        return;
      case 'FOOD_BEVERAGE':
      default:
        _openOrderSheet();
    }
  }

  void _shareBusiness(BusinessProfile business) {
    final shareUrl = 'https://azaman.app/business/${business.bizId}';
    Share.share(
      'Check out ${business.businessName} on AZAMAN! $shareUrl',
      subject: '${business.businessName} on AZAMAN',
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Label for the catalog shortcut, adapted to the business vertical.
  static String _catalogTabLabel(String? category) {
    switch (category) {
      case 'FOOD_BEVERAGE':
        return 'Menu';
      case 'RETAIL':
      case 'TECHNOLOGY':
        return 'Products';
      case 'HEALTH_WELLNESS':
      case 'FREELANCE_SERVICES':
      case 'FINANCIAL_SERVICES':
        return 'Services';
      case 'EDUCATION':
        return 'Courses';
      case 'ENTERTAINMENT':
        return 'Experiences';
      case 'HOSPITALITY':
      case 'REAL_ESTATE':
        return 'Amenities';
      case 'LOGISTICS':
        return 'Add-ons';
      default:
        return 'Catalog';
    }
  }

  /// Empty-state icon + copy for the catalog, per vertical.
  static ({IconData icon, String text}) _catalogEmptyState(String? category) {
    switch (category) {
      case 'FOOD_BEVERAGE':
        return (
          icon: Icons.restaurant_outlined,
          text: 'Menu not yet available',
        );
      case 'RETAIL':
      case 'TECHNOLOGY':
        return (
          icon: Icons.shopping_bag_outlined,
          text: 'No products listed yet',
        );
      case 'HEALTH_WELLNESS':
      case 'FREELANCE_SERVICES':
      case 'FINANCIAL_SERVICES':
        return (
          icon: Icons.design_services_outlined,
          text: 'No services listed yet',
        );
      case 'EDUCATION':
        return (icon: Icons.school_outlined, text: 'No courses listed yet');
      case 'ENTERTAINMENT':
        return (
          icon: Icons.confirmation_number_outlined,
          text: 'No experiences listed yet',
        );
      case 'HOSPITALITY':
      case 'REAL_ESTATE':
        return (
          icon: Icons.holiday_village_outlined,
          text: 'No amenities listed yet',
        );
      case 'LOGISTICS':
        return (
          icon: Icons.directions_bus_outlined,
          text: 'No add-ons listed yet',
        );
      default:
        return (icon: Icons.storefront_outlined, text: 'Nothing listed yet');
    }
  }

  // ── Banner priority: showcase → coverImageUrl → logo → gradient ────────────
  String? get _bannerUrl {
    final business = _business;
    if (business == null) return null;
    String? clean(String? url) => (url != null && url.isNotEmpty) ? url : null;
    final showcase = _showcaseSlides.isNotEmpty
        ? clean(_showcaseSlides.first['mediaUrl'] as String?)
        : null;
    return showcase ?? clean(business.coverImageUrl) ?? clean(business.logoUrl);
  }

  bool get _hasCatalog =>
      _menuSections.isNotEmpty || _uncategorisedProducts.isNotEmpty;

  // ── The in-sheet product/content surface ───────────────────────────────────
  // Vertical-aware: restaurants feel like a menu, hotels expose amenities,
  // retail feels like a store — while the SHELL stays recognizably AZM.
  List<Widget> _storefrontProducts(BuildContext context) {
    final business = _business;
    if (business == null) return const [];
    final colors = ref.read(themeProvider).colors;
    final children = <Widget>[];

    // Featured products carousel (self-collapses when the market has none).
    children.add(
      FeaturedProductsSection(
        bizId: widget.bizId,
        onOrder: (p) => _openOrderSheet(product: p),
      ),
    );

    if (_menuLoading && !_hasCatalog) {
      children.add(const SizedBox(height: 12));
      children.addAll(
        List.generate(
          3,
          (i) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: SkeletonBlock(height: 64),
          ),
        ),
      );
    }

    // Catalog sections inline for quick browsing.
    if (_hasCatalog) {
      if (business.category == 'FOOD_BEVERAGE' && _menuSections.isEmpty) {
        children.add(_sectionHeader('Menu', colors));
      } else {
        children.addAll(
          _menuSections.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _menuSection(s, colors),
            ),
          ),
        );
      }
      if (_uncategorisedProducts.isNotEmpty) {
        children.add(_sectionHeader('Other Items', colors));
        children.add(const SizedBox(height: 4));
        children.addAll(
          _uncategorisedProducts.map(
            (p) => _menuProductRow(p, business, colors),
          ),
        );
      }
      children.add(const SizedBox(height: 12));
      // Shortcut into the vertical's full catalog experience.
      children.add(_fullCatalogCard(business, colors));
    } else if (!_menuLoading) {
      // No catalog at all — vertical-aware empty state, never a blank sheet.
      children.add(_catalogEmptyCard(business, colors));
    }

    // Outstanding bills (only when the signed-in user owes this market).
    children.add(_unpaidInvoicesSection(business, colors));

    // Loyalty stamp card.
    children.add(_loyaltySection(business, colors));

    return children;
  }

  Widget _sectionHeader(String title, AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _menuSection(CatalogSection section, AzamanColors colors) {
    final business = _business;
    if (business == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(section.name, colors),
        if (section.description != null && section.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              section.description!,
              style: TextStyle(color: colors.textTertiary, fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 10),
        ...section.products.map((p) => _menuProductRow(p, business, colors)),
      ],
    );
  }

  Widget _menuProductRow(
    BusinessProduct product,
    BusinessProfile business,
    AzamanColors colors,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openOrderSheet(product: product),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (product.description != null &&
                      product.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        product.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${product.priceUsdc.toStringAsFixed(2)} USDC',
              style: TextStyle(
                color: colors.accent,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Wide shortcut card into the vertical's full-screen catalog experience
  /// (restaurant flip-book for FOOD_BEVERAGE, CatalogStorefrontScreen
  /// otherwise).
  Widget _fullCatalogCard(BusinessProfile business, AzamanColors colors) {
    return ScaleTap(
      onTap: () {
        AzamanHaptics.nav();
        _openCatalogView();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.menu_book_rounded, size: 18, color: colors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Open the full ${_catalogTabLabel(business.category).toLowerCase()}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: colors.accent),
          ],
        ),
      ),
    );
  }

  Widget _catalogEmptyCard(BusinessProfile business, AzamanColors colors) {
    final empty = _catalogEmptyState(business.category);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(empty.icon, size: 40, color: colors.textTertiary),
          const SizedBox(height: 10),
          Text(
            empty.text,
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Unpaid invoices / receipt cards ──────────────────────────────────────
  Widget _unpaidInvoicesSection(BusinessProfile business, AzamanColors colors) {
    // Pure render projection of state cached by _loadUnpaidInvoices() — a
    // NEW Future is NEVER created here, so sheet-drag rebuilds of this
    // subtree cannot re-fire the invoice request.
    final invoices = _unpaidInvoiceDetails;
    if (invoices.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.receipt_long_rounded, size: 18, color: colors.accent),
            const SizedBox(width: 6),
            Text(
              'Outstanding Bills',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${invoices.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colors.danger,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...invoices.map((inv) => _receiptCard(inv, colors)),
      ],
    );
  }

  Widget _receiptCard(BusinessInvoice invoice, AzamanColors colors) {
    final isPaid = invoice.status == InvoiceStatus.paid;
    final statusColor = isPaid ? Colors.green : colors.danger;
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InvoiceDetailScreen(invoiceId: invoice.id),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPaid ? colors.divider : statusColor.withValues(alpha: 0.3),
            width: isPaid ? 0.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (invoice.businessLogoUrl != null &&
                    invoice.businessLogoUrl!.isNotEmpty)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.receipt_outlined,
                      size: 16,
                      color: colors.accent,
                    ),
                  )
                else
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.receipt_outlined,
                      size: 16,
                      color: colors.accent,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoice.invoiceRef,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (invoice.locationLabel != null &&
                          invoice.locationLabel!.isNotEmpty)
                        Text(
                          invoice.locationLabel!,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isPaid ? 'Paid' : 'Unpaid',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _loyaltySection(BusinessProfile business, AzamanColors colors) {
    // Sample loyalty card — in production, this would be fetched from the API
    final card = UserLoyaltyCard(
      programId: business.bizId,
      businessName: business.businessName,
      type: LoyaltyType.stampCard,
      stampsCollected: 7,
      stampsRequired: 10,
      rewardDescription: 'Free coffee',
    );

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: LoyaltyStampCard(
        card: card,
        onTap: () {
          // Future: open loyalty history screen
        },
      ),
    );
  }

  // ── Full-screen catalog experiences (preserved vertical behavior) ─────────
  /// FOOD_BEVERAGE keeps the dedicated page-turning flip-book experience
  /// (a fixed full-bleed metaphor — you flip pages, you don't scroll a
  /// list). Every other vertical gets the "UberEats-style" storefront with
  /// the parallax hero + pinned category bar.
  Widget _catalogRouteScaffold(BusinessProfile business, AzamanColors colors) {
    final hasSections = _menuSections.isNotEmpty;
    final hasUncat = _uncategorisedProducts.isNotEmpty;

    if (business.category == 'FOOD_BEVERAGE' || (!hasSections && !hasUncat)) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.surface,
          elevation: 0,
          iconTheme: IconThemeData(color: colors.textPrimary),
          title: Text(
            _catalogTabLabel(business.category),
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: _menuTabBody(business, colors),
      );
    }

    return CatalogStorefrontScreen(
      business: business,
      sections: _menuSections,
      uncategorisedProducts: _uncategorisedProducts,
      colors: colors,
      catalogLabel: _catalogTabLabel(business.category),
      productRowBuilder: (product) =>
          _menuProductRow(product, business, colors),
    );
  }

  Widget _menuTabBody(BusinessProfile business, AzamanColors colors) {
    final hasSections = _menuSections.isNotEmpty;
    final hasUncat = _uncategorisedProducts.isNotEmpty;
    if (!hasSections && !hasUncat) {
      final empty = _catalogEmptyState(business.category);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(empty.icon, size: 40, color: colors.textTertiary),
              const SizedBox(height: 10),
              Text(
                empty.text,
                style: TextStyle(color: colors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // Restaurants get the real page-turning flip-book menu experience.
    if (business.category == 'FOOD_BEVERAGE') {
      return RestaurantMenuFlipBook(
        businessName: business.businessName,
        logoUrl: business.logoUrl,
        sections: _menuSections,
        uncategorisedProducts: _uncategorisedProducts,
        colors: colors,
        onOrder: (p) => _openOrderSheet(product: p),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        if (hasSections)
          ..._menuSections.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _menuSection(s, colors),
            ),
          ),
        if (hasUncat) ...[
          _sectionHeader('Other Items', colors),
          const SizedBox(height: 10),
          ..._uncategorisedProducts.map(
            (p) => _menuProductRow(p, business, colors),
          ),
        ],
      ],
    );
  }

  void _openCatalogView() {
    final business = _business;
    if (business == null) return;
    final colors = ref.read(themeProvider).colors;
    AzamanHaptics.nav();
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, animation, secondaryAnimation) =>
            _catalogRouteScaffold(business, colors),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            SharedAxisTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              transitionType: SharedAxisTransitionType.scaled,
              child: child,
            ),
      ),
    );
  }

  void _openReviews() {
    final business = _business;
    if (business == null) return;
    final colors = ref.read(themeProvider).colors;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: colors.surface,
            elevation: 0,
            iconTheme: IconThemeData(color: colors.textPrimary),
            title: Text(
              'Reviews',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
            children: [
              BusinessReviewsSection(business: business, colors: colors),
            ],
          ),
        ),
      ),
    );
  }

  void _openLocations() {
    final colors = ref.read(themeProvider).colors;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: colors.surface,
            elevation: 0,
            iconTheme: IconThemeData(color: colors.textPrimary),
            title: Text(
              'Locations',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
            children: [
              ..._locations.map(
                (loc) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _locationCard(loc, colors),
                ),
              ),
            ],
          ),
        ),
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
              Icon(Icons.location_on_outlined, size: 18, color: colors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.label.isNotEmpty ? loc.label : 'Branch',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (loc.distanceKm != null)
                Text(
                  '${loc.distanceKm!.toStringAsFixed(1)} km',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
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
          if (loc.operatingHours != null && loc.operatingHours!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _formatHours(loc.operatingHours!),
              style: TextStyle(color: colors.textTertiary, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 10),
          ScaleTap(
            onTap: () {
              AzamanHaptics.nav();
              _launch(
                'https://www.google.com/maps/dir/?api=1&destination=${loc.latitude},${loc.longitude}',
              );
            },
            child: Row(
              children: [
                Icon(Icons.widgets_outlined, size: 15, color: colors.accent),
                const SizedBox(width: 6),
                Text(
                  'Get directions',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    if (_loading) {
      return Scaffold(
        backgroundColor: colors.background,
        body: Column(
          children: [
            SkeletonBlock(
              height: 320,
              width: double.infinity,
              borderRadius: BorderRadius.zero,
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SizedBox(height: 8),
                    SkeletonBlock(
                      height: 44,
                      width: 200,
                      borderRadius: BorderRadius.all(Radius.circular(22)),
                    ),
                    SizedBox(height: 20),
                    SkeletonBlock(height: 120),
                    SizedBox(height: 16),
                    SkeletonBlock(height: 64),
                    SizedBox(height: 12),
                    SkeletonBlock(height: 64),
                  ],
                ),
              ),
            ),
          ],
        ),
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
                Icon(
                  Icons.storefront_outlined,
                  size: 48,
                  color: colors.textTertiary,
                ),
                const SizedBox(height: 12),
                Text(
                  _error ?? 'Business not found.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _load,
                  child: Text('Retry', style: TextStyle(color: colors.accent)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MarketStorefrontShell(
      business: business,
      colors: colors,
      bannerUrl: _bannerUrl,
      locations: _locations,
      showcaseSlides: _showcaseSlides,
      isFollowing: _isFollowing,
      unpaidInvoices: _unpaidInvoices,
      hasCatalog: _hasCatalog,
      catalogLabel: _catalogTabLabel(business.category),
      productsBuilder: _storefrontProducts,
      onBack: () => Navigator.maybePop(context),
      onToggleFollow: _toggleFollow,
      onShare: () => _shareBusiness(business),
      onPrimaryCta: _primaryCtaAction,
      onOpenCatalog: _openCatalogView,
      onOpenReviews: _openReviews,
      onOpenLocations: _locations.length > 1 ? _openLocations : null,
      onPayInvoice: _unpaidInvoices > 0
          ? () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyInvoicesScreen()),
            )
          : null,
      onLaunch: _launch,
    );
  }
}
