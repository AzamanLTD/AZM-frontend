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

import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';
import 'package:azaman/widgets/parallax_header_delegate.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:animations/animations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/widgets/loyalty_stamp_card.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/business_products_screen.dart';
import 'package:azaman/screens/marketplace/my_invoices_screen.dart';
import 'package:azaman/screens/tickets/ticket_create_sheet.dart';
import 'package:azaman/screens/tickets/ticket_workspace_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/ticket_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/featured_products_section.dart';
import 'package:azaman/widgets/restaurant_menu_flip_book.dart';
import 'package:azaman/widgets/stacked_gallery_cards.dart';
import 'package:azaman/screens/storefront_screen.dart';
import 'package:azaman/screens/marketplace/catalog_storefront_screen.dart';
import 'package:azaman/screens/marketplace/business_reviews_section.dart';
import 'package:azaman/screens/marketplace/business_book_tab.dart';

class BusinessProfileScreen extends ConsumerStatefulWidget {
  final String bizId;
  const BusinessProfileScreen({super.key, required this.bizId});

  @override
  ConsumerState<BusinessProfileScreen> createState() =>
      _BusinessProfileScreenState();
}

class _BusinessProfileScreenState
    extends ConsumerState<BusinessProfileScreen> {
  final _scrollCtrl = ScrollController();
  final _reviewsKey = GlobalKey();

  // 2026-07-08 UI/UX sprint: tabs are now pill buttons + a SharedAxisTransition
  // switcher instead of a swipeable TabBar/TabBarView — swiping inside a tab's
  // content (e.g. the restaurant flip-book menu) no longer fights with
  // swiping between tabs, since there's no PageView-style gesture anymore.
  // Catalog/Menu is no longer a tab at all — it moved to a floating bubble.
  int _currentTab = 0; // 0=Overview 1=Locations 2=Reviews 3=Book

  // Info popover (replaces the old always-visible "About" section) —
  // auto-opens briefly right after the business loads, then auto-closes,
  // both via a container-transform-style scale+fade.
  bool _showAboutPopover = false;
  Timer? _aboutPopoverTimer;

  bool _loading = true;
  String? _error;
  BusinessProfile? _business;
  List<BusinessLocation> _locations = const [];
  int _unpaidInvoices = 0;

  // Marketplace v2: Follow state
  bool _isFollowing = false;
  bool _followLoading = false;
  int _followerCount = 0;

  // Marketplace v2: Showcase slides
  List<Map<String, dynamic>> _showcaseSlides = const [];

  List<CatalogSection> _menuSections = const [];
  List<BusinessProduct> _uncategorisedProducts = const [];
  bool _menuLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _aboutPopoverTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Auto-opens the About info popover ~500ms after the business finishes
  /// loading (long enough for the hero image to settle in), keeps it up for
  /// ~3.2s, then auto-closes it — a "container transform in, container
  /// transform out" intro instead of a permanent About section on the page.
  void _autoShowAboutPopover() {
    _aboutPopoverTimer?.cancel();
    _aboutPopoverTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _showAboutPopover = true);
      _aboutPopoverTimer = Timer(const Duration(milliseconds: 3200), () {
        if (!mounted) return;
        setState(() => _showAboutPopover = false);
      });
    });
  }

  void _toggleAboutPopover() {
    _aboutPopoverTimer?.cancel();
    AzamanHaptics.nav();
    setState(() => _showAboutPopover = !_showAboutPopover);
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
      _loadMenu(business.bizId);
      _loadFollowState(business.id);
      _loadShowcase(business.id);
      _autoShowAboutPopover();
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
          _followerCount = data['followerCount'] ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadShowcase(String businessId) async {
    try {
      final res = await apiClient.get('/showcases/$businessId');
      final data = jsonDecode(res.body);
      if (mounted) {
        final raw = data is List ? data : (data["items"] ?? data["slides"] ?? []);
        setState(() {
          _showcaseSlides = (raw as List).cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
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

  Future<void> _loadMenu(String bizId) async {
    setState(() => _menuLoading = true);
    try {
      final response = await apiClient.get('/business/$bizId/menu');
      final body = jsonDecode(response.body);
      final sections = body['sections'] as List<dynamic>? ?? [];
      final uncategorised = body['uncategorisedProducts'] as List<dynamic>? ?? [];
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

  void _scrollToReviews() {
    final ctx = _reviewsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  Future<void> _toggleFollow() async {
    if (_followLoading) return;
    setState(() => _followLoading = true);
    final wasFollowing = _isFollowing;
    setState(() {
      _isFollowing = !_isFollowing;
      _followerCount += _isFollowing ? 1 : -1;
    });
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
        setState(() {
          _isFollowing = wasFollowing;
          _followerCount += wasFollowing ? 1 : -1;
        });
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
  /// catalog (there's no dedicated backend flow for generic appointments
  /// yet, but ordering a listed service/package already works end-to-end).
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

  /// Label for the catalog tab (was hardcoded 'Menu' for every vertical).
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

  /// Empty-state icon + copy for the catalog tab, per vertical.
  static ({IconData icon, String text}) _catalogEmptyState(String? category) {
    switch (category) {
      case 'FOOD_BEVERAGE':
        return (icon: Icons.restaurant_outlined, text: 'Menu not yet available');
      case 'RETAIL':
      case 'TECHNOLOGY':
        return (icon: Icons.shopping_bag_outlined, text: 'No products listed yet');
      case 'HEALTH_WELLNESS':
      case 'FREELANCE_SERVICES':
      case 'FINANCIAL_SERVICES':
        return (icon: Icons.design_services_outlined, text: 'No services listed yet');
      case 'EDUCATION':
        return (icon: Icons.school_outlined, text: 'No courses listed yet');
      case 'ENTERTAINMENT':
        return (icon: Icons.confirmation_number_outlined, text: 'No experiences listed yet');
      case 'HOSPITALITY':
      case 'REAL_ESTATE':
        return (icon: Icons.holiday_village_outlined, text: 'No amenities listed yet');
      case 'LOGISTICS':
        return (icon: Icons.directions_bus_outlined, text: 'No add-ons listed yet');
      default:
        return (icon: Icons.storefront_outlined, text: 'Nothing listed yet');
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
                Icon(Icons.storefront_outlined,
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
          NestedScrollView(
            controller: _scrollCtrl,
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverOverlapAbsorber(
                handle:
                    NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                sliver: SliverPersistentHeader(
                  pinned: true,
                  delegate: ParallaxHeaderDelegate(
                    imageUrl: _showcaseSlides.isNotEmpty ? _showcaseSlides.first['mediaUrl'] : _business?.logoUrl,
                    title: _business?.businessName ?? 'Business',
                    subtitle: _business != null
                        ? '${BusinessCategories.labelFor(_business!.category)} · ${_business!.averageRating.toStringAsFixed(1)}★'
                        : null,
                    minExtent: 56 + MediaQuery.of(context).padding.top,
                    maxExtent: 280,
                    actions: [
                      // Info popover trigger — replaces the old permanent
                      // "About" section; shows the same content in a small
                      // container-transform popover anchored here.
                      GestureDetector(
                        onTap: _toggleAboutPopover,
                        child: Container(
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.only(right: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                          child: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 17),
                        ),
                      ),
                      // Follow button
                      Center(
                        child: GestureDetector(
                          onTap: _toggleFollow,
                          child: AnimatedContainer(
                            duration: 300.ms, curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _isFollowing ? colors.accentSurface : colors.accent,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _isFollowing ? colors.accent.withValues(alpha: 0.3) : Colors.transparent),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_isFollowing ? Icons.check_rounded : Icons.add_rounded, size: 16, color: _isFollowing ? colors.accent : colors.background)
                                  .animate(target: _isFollowing ? 1 : 0)
                                  .scale(begin: const Offset(0.5, 0.5), end: const Offset(1, 1), duration: 200.ms, curve: Curves.easeOutBack),
                                const SizedBox(width: 5),
                                AnimatedSwitcher(
                                  duration: 250.ms,
                                  child: Text(_isFollowing ? 'Following' : 'Follow', key: ValueKey(_isFollowing),
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _isFollowing ? colors.accent : colors.background)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.ios_share_rounded, color: Colors.white, size: 20),
                        onPressed: () => _launch(_business?.website ?? ''),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _quickInfoBar(business, colors),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyTabBarDelegate(
                  child: Container(
                    color: colors.background,
                    child: _pillTabBar(colors),
                  ),
                ),
              ),
            ],
            body: PageTransitionSwitcher(
              duration: const Duration(milliseconds: 280),
              reverse: _tabReverse,
              transitionBuilder: (child, primary, secondary) => SharedAxisTransition(
                animation: primary,
                secondaryAnimation: secondary,
                transitionType: SharedAxisTransitionType.horizontal,
                fillColor: colors.background,
                child: child,
              ),
              child: KeyedSubtree(
                key: ValueKey<int>(_currentTab),
                child: _tabBody(_currentTab, business, colors),
              ),
            ),
          ),
          // Info popover — container-transform-style scale+fade, anchored
          // under the header info icon. Auto-shows briefly on open, and can
          // be re-toggled any time by tapping the icon again.
          if (_showAboutPopover)
            Positioned(
              top: MediaQuery.of(context).padding.top + 48,
              right: 56,
              left: 16,
              child: _aboutPopover(business, colors),
            ),
          Positioned(
            right: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: _floatingActionBubbles(business, colors),
          ),
        ],
      ),
    );
  }

  bool _tabReverse = false;

  void _selectTab(int i) {
    if (i == _currentTab) return;
    AzamanHaptics.toggle();
    setState(() {
      _tabReverse = i < _currentTab;
      _currentTab = i;
    });
  }

  Widget _tabBody(int index, BusinessProfile business, AzamanColors colors) {
    switch (index) {
      case 1:
        return _locationsTab(colors);
      case 2:
        return _reviewsTab(business, colors);
      case 3:
        return BusinessBookTab(
              business: business,
              colors: colors,
              onNavigate: (route) => context.push(route),
              onOpenOrderSheet: _openOrderSheet,
              onOpenCatalogView: _openCatalogView,
            );
      case 0:
      default:
        return _overviewTab(business, colors);
    }
  }

  // ── Pill-shaped tab row ─────────────────────────────────────────────────
  // Replaces the old underline TabBar. No swipe gesture is attached to the
  // content area anymore (see PageTransitionSwitcher above), so swiping
  // inside a tab (e.g. the flip-book menu, or a horizontal gallery) never
  // accidentally flips to the next/previous tab.
  Widget _pillTabBar(AzamanColors colors) {
    final cat = _business?.category;
    final items = <({IconData icon, String emoji, String label})>[
      (icon: Icons.grid_view_rounded, emoji: '📋', label: 'Overview'),
      (icon: Icons.menu_book_rounded, emoji: '📖', label: _catalogTabLabel(cat)),
      (icon: Icons.place_rounded, emoji: '📍', label: 'Locations'),
      (icon: Icons.star_rounded, emoji: '⭐', label: 'Reviews'),
      if (cat == 'HOSPITALITY' || cat == 'REAL_ESTATE')
        (icon: Icons.calendar_month_rounded, emoji: '📅', label: 'Book'),
      if (cat == 'LOGISTICS')
        (icon: Icons.directions_bus_rounded, emoji: '🚌', label: 'Trips'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _pill(
                colors: colors,
                selected: _currentTab == i,
                emoji: items[i].emoji,
                label: items[i].label,
                onTap: () => _selectTab(i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill({
    required AzamanColors colors,
    required bool selected,
    required String emoji,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.softSurface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? Colors.white : colors.textSecondary,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }

  // ── About popover (was a permanent section, now a transient popover) ────
  Widget _aboutPopover(BusinessProfile business, AzamanColors colors) {
    final hasDescription = business.description != null && business.description!.trim().isNotEmpty;
    final contacts = <Widget>[];
    if (business.phoneNumber != null && business.phoneNumber!.isNotEmpty) {
      contacts.add(_contactRow(colors, Icons.call_outlined, business.phoneNumber!, () => _launch('tel:${business.phoneNumber}')));
    }
    if (business.contactEmail != null && business.contactEmail!.isNotEmpty) {
      contacts.add(_contactRow(colors, Icons.mail_outline, business.contactEmail!, () => _launch('mailto:${business.contactEmail}')));
    }
    if (business.website != null && business.website!.isNotEmpty) {
      contacts.add(_contactRow(colors, Icons.link_rounded, business.website!, () => _launch(business.website!)));
    }
    if (business.address != null && business.address!.isNotEmpty) {
      contacts.add(_contactRow(colors, Icons.location_on_outlined, business.address!, null));
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.divider),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: colors.accent),
                const SizedBox(width: 8),
                Text('About', style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
                const Spacer(),
                GestureDetector(
                  onTap: _toggleAboutPopover,
                  child: Icon(Icons.close_rounded, size: 18, color: colors.textTertiary),
                ),
              ],
            ),
            if (hasDescription) ...[
              const SizedBox(height: 8),
              Text(business.description!.trim(),
                  style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.4)),
            ],
            if (contacts.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...contacts,
            ],
          ],
        ),
      ),
    )
        .animate(target: 1)
        .scaleXY(begin: 0.85, end: 1, duration: 260.ms, curve: Curves.easeOutBack)
        .fadeIn(duration: 200.ms);
  }

  // ── Floating action bubbles (replaces the old bottom action bar) ────────
  // Stacked bottom-right, container-transform (OpenContainer) into their
  // respective full views. The primary bubble's emoji/label adapts per
  // business vertical (same mapping the old CTA button used); the catalog
  // bubble (book emoji) only appears when there's something to show and
  // opens the same catalog/menu content — including the restaurant
  // flip-book — full-screen via container transform.

  /// Builds the full-screen catalog/menu route.
  ///
  /// FOOD_BEVERAGE keeps the dedicated page-turning flip-book experience
  /// (a fixed full-bleed metaphor — you flip pages, you don't scroll a
  /// list, so a sliver hero doesn't fit it) wrapped in a plain app bar.
  ///
  /// Every other vertical (Retail, Technology, Services, ...) gets the new
  /// "UberEats-style" storefront: a CustomScrollView with a parallax hero
  /// (reusing ParallaxHeaderDelegate, same as the profile page itself), a
  /// pinned horizontally-scrolling category bar, and tap-a-category ->
  /// smooth-scroll-to-that-section. This replaces what used to be a single
  /// flat ListView with no way to jump around a long catalog.
  Widget _floatingActionBubbles(BusinessProfile business, AzamanColors colors) {
    final hasCatalog = _menuSections.isNotEmpty || _uncategorisedProducts.isNotEmpty;
    final hasUnpaidInvoices = _unpaidInvoices > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Quick actions (Call, Directions, Share)
        if (business.phoneNumber != null && business.phoneNumber!.isNotEmpty) ...[
          _bubble(
            colors: colors,
            emoji: '📞',
            tooltip: 'Call',
            onTap: () {
              AzamanHaptics.nav();
              _launch('tel:${business.phoneNumber}');
            },
          ),
          const SizedBox(height: 12),
        ],
        if (business.address != null && business.address!.isNotEmpty) ...[
          _bubble(
            colors: colors,
            emoji: '📍',
            tooltip: 'Directions',
            onTap: () {
              AzamanHaptics.nav();
              _launch('https://maps.google.com/?q=${Uri.encodeComponent(business.address!)}');
            },
          ),
          const SizedBox(height: 12),
        ],
        _bubble(
          colors: colors,
          emoji: '↗️',
          tooltip: 'Share',
          onTap: () {
            AzamanHaptics.nav();
            _shareBusiness(business);
          },
        ),
        const SizedBox(height: 12),
        if (hasUnpaidInvoices) ...[
          _bubble(
            colors: colors,
            emoji: '🧾',
            tooltip: 'Pay Invoice',
            onTap: () {
              AzamanHaptics.nav();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MyInvoicesScreen()));
            },
          ),
          const SizedBox(height: 12),
        ],
        // SDUI Storefront — opens the customizable widget-based storefront
        _bubble(
          colors: colors,
          emoji: '🏪',
          tooltip: 'Storefront',
          onTap: () {
            AzamanHaptics.nav();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StorefrontScreen(
                  businessProfileId: business.id,
                  businessName: business.businessName,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        if (hasCatalog) ...[
          OpenContainer(
            transitionType: ContainerTransitionType.fade,
            transitionDuration: const Duration(milliseconds: 420),
            closedElevation: 0,
            openElevation: 0,
            closedShape: const CircleBorder(),
            closedColor: Colors.transparent,
            openColor: colors.background,
            closedBuilder: (context, openAction) => _bubbleClosed(
              colors: colors,
              emoji: '📖',
              onTap: () {
                AzamanHaptics.nav();
                openAction();
              },
            ),
            openBuilder: (context, closeAction) => _catalogRouteScaffold(business, colors),
          ),
          const SizedBox(height: 12),
        ],
        _bubble(
          colors: colors,
          emoji: _ctaEmoji(business),
          tooltip: _ctaLabel(business),
          primary: true,
          onTap: () {
            AzamanHaptics.confirm();
            _primaryCtaAction();
          },
        ),
      ],
    );
  }

  /// Builds the full-screen catalog/menu route.
  ///
  /// FOOD_BEVERAGE keeps the dedicated page-turning flip-book experience
  /// (a fixed full-bleed metaphor — you flip pages, you don't scroll a
  /// list, so a sliver hero doesn't fit it) wrapped in a plain app bar.
  ///
  /// Every other vertical (Retail, Technology, Services, ...) gets the new
  /// "UberEats-style" storefront: a CustomScrollView with a parallax hero
  /// (reusing ParallaxHeaderDelegate, same as the profile page itself), a
  /// pinned horizontally-scrolling category bar, and tap-a-category ->
  /// smooth-scroll-to-that-section. This replaces what used to be a single
  /// flat ListView with no way to jump around a long catalog.

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
          title: Text(_catalogTabLabel(business.category),
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800)),
        ),
        body: _menuTab(business, colors),
      );
    }

    return CatalogStorefrontScreen(
      business: business,
      sections: _menuSections,
      uncategorisedProducts: _uncategorisedProducts,
      colors: colors,
      catalogLabel: _catalogTabLabel(business.category),
      productRowBuilder: (product) => _menuProductRow(product, business, colors),
    );
  }

  /// Programmatic entry point for jumping straight to the catalog view from
  /// elsewhere on the page (e.g. the Book tab's "Shop the Catalog" CTA) —
  /// the catalog is a floating bubble now, not a tab, so there's no
  /// TabController index to animate to anymore.
  void _openCatalogView() {
    final business = _business;
    if (business == null) return;
    final colors = ref.read(themeProvider).colors;
    AzamanHaptics.nav();
    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (_, animation, secondaryAnimation) => _catalogRouteScaffold(business, colors),
      transitionsBuilder: (_, animation, secondaryAnimation, child) => SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: SharedAxisTransitionType.scaled,
        child: child,
      ),
    ));
  }

  Widget _bubble({
    required AzamanColors colors,
    required String emoji,
    required String tooltip,
    bool primary = false,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: primary ? 58 : 46,
          height: primary ? 58 : 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary ? colors.accent : colors.card,
            border: primary ? null : Border.all(color: colors.divider),
            boxShadow: [
              BoxShadow(
                color: (primary ? colors.accent : Colors.black).withValues(alpha: primary ? 0.35 : 0.14),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: TextStyle(fontSize: primary ? 24 : 18)),
        ),
      ),
    ).animate().scale(begin: const Offset(0, 0), end: const Offset(1, 1), duration: 300.ms, curve: Curves.easeOutBack);
  }

  Widget _bubbleClosed({required AzamanColors colors, required String emoji, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.card,
          border: Border.all(color: colors.divider),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 18)),
      ),
    ).animate().scale(begin: const Offset(0, 0), end: const Offset(1, 1), duration: 300.ms, delay: 60.ms, curve: Curves.easeOutBack);
  }

  /// Emoji for the primary CTA bubble, adapted to the business vertical
  /// (mirrors _ctaIcon's mapping, just as an emoji for the bubble face).
  String _ctaEmoji(BusinessProfile business) {
    switch (business.category) {
      case 'FOOD_BEVERAGE':
        return '🍴';
      case 'REAL_ESTATE':
      case 'HOSPITALITY':
        return '🏨';
      case 'LOGISTICS':
        return '🚌';
      case 'RETAIL':
      case 'TECHNOLOGY':
        return '🛍️';
      case 'HEALTH_WELLNESS':
      case 'FREELANCE_SERVICES':
        return '💇';
      case 'EDUCATION':
        return '🎓';
      case 'ENTERTAINMENT':
        return '🎟️';
      case 'FINANCIAL_SERVICES':
        return '💼';
      default:
        return '🛒';
    }
  }

  // ── Hero header ────────────────────────────────────────────────────────────
  Widget _hero(BusinessProfile business, AzamanColors colors) {
    // Prefer showcase slide → logo → gradient fallback
    final showcaseUrl = _showcaseSlides.isNotEmpty
        ? (_showcaseSlides.first['mediaUrl'] as String?)
        : null;
    final heroUrl = showcaseUrl ??
        (business.logoUrl != null && business.logoUrl!.isNotEmpty
            ? business.logoUrl
            : null);

    return Hero(
      tag: 'biz-logo-${business.id}',
      child: SizedBox(
      height: 280,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (heroUrl != null)
            CachedNetworkImage(
              imageUrl: heroUrl,
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
                    Icons.arrow_back,
                    () => Navigator.maybePop(context),
                  ),
                  const Spacer(),
                  _circleButton(
                    _isFollowing
                        ? Icons.how_to_reg_outlined
                        : Icons.person_add_outlined,
                    _toggleFollow,
                    color: _isFollowing ? colors.success : null,
                  ),
                  const SizedBox(width: 8),
                  _circleButton(
                    Icons.ios_share_outlined,
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
                    child: Icon(Icons.check_circle_outline,
                        color: colors.success, size: 22),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
            colors.accent.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Center(
        child: Icon(Icons.storefront_outlined,
            size: 72, color: Colors.white.withValues(alpha: 0.35)),
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap, {Color? color}) {
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
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color ?? Colors.white, size: 20),
      ),
    );
  }

  // ── Quick info bar ───────────────────────────────────────────────────────
  Widget _quickInfoBar(BusinessProfile business, AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: PremiumGlassContainer(
        blur: 12, opacity: 0.04, borderRadius: 16,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _infoChip(icon: Icons.star_rounded, value: business.averageRating.toStringAsFixed(1), label: 'Rating', colors: colors, accent: business.averageRating >= 4.5),
              _divider(colors),
              _infoChip(icon: Icons.task_alt_rounded, value: '${business.completedEscrows}', label: 'Deals', colors: colors),
              _divider(colors),
              _infoChip(icon: Icons.people_outline_rounded, value: _followerCount.toString(), label: 'Followers', colors: colors),
              if (business.isVerified) ...[
                _divider(colors),
                _infoChip(icon: Icons.verified_rounded, value: 'KYB', label: 'Verified', colors: colors, accent: true),
              ],
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.1, end: 0, delay: 200.ms, duration: 400.ms, curve: Curves.easeOutCubic);
  }

  Widget _infoChip({required IconData icon, required String value, required String label, required AzamanColors colors, bool accent = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent ? colors.accent : colors.textSecondary),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: accent ? colors.accent : colors.textPrimary)),
          Text(label, style: TextStyle(fontSize: 10, color: colors.textTertiary)),
        ],
      ),
    );
  }

  Widget _divider(AzamanColors colors) {
    return Container(width: 0.5, height: 28, margin: const EdgeInsets.symmetric(horizontal: 4), color: colors.divider);
  }

  // ── About ────────────────────────────────────────────────────────────────
  Widget _about(BusinessProfile business, AzamanColors colors) {
    final hasDescription =
        business.description != null && business.description!.trim().isNotEmpty;
    final contacts = <Widget>[];
    if (business.phoneNumber != null && business.phoneNumber!.isNotEmpty) {
      contacts.add(_contactRow(colors, Icons.widgets_outlined,
          business.phoneNumber!, () => _launch('tel:${business.phoneNumber}')));
    }
    if (business.contactEmail != null && business.contactEmail!.isNotEmpty) {
      contacts.add(_contactRow(colors, Icons.mail_outline,
          business.contactEmail!, () => _launch('mailto:${business.contactEmail}')));
    }
    if (business.website != null && business.website!.isNotEmpty) {
      contacts.add(_contactRow(colors, Icons.widgets_outlined,
          business.website!, () => _launch(business.website!)));
    }
    if (business.address != null && business.address!.isNotEmpty) {
      contacts.add(_contactRow(
          colors, Icons.location_on_outlined, business.address!, null));
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
                  Icon(Icons.arrow_forward,
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
            StackedGalleryCards(urls: loc.galleryUrls, width: 110, height: 80),
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
                Icon(Icons.widgets_outlined,
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


  /// 5-star breakdown bar chart computed from the loaded review page.

  // ── Tab: Overview ──────────────────────────────────────────────────────────
  Widget _overviewTab(BusinessProfile business, AzamanColors colors) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        if (_showcaseSlides.isNotEmpty) ...[
          _buildShowcaseCarousel(colors),
          const SizedBox(height: 16),
        ],
        _categoryFacts(business, colors),
        const SizedBox(height: 16),
        _hoursOverview(colors),
        const SizedBox(height: 16),
        _products(business, colors),
        const SizedBox(height: 16),
        _loyaltySection(business, colors),
      ],
    );
  }

  // ── Loyalty Card Section ───────────────────────────────────────────────────
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

    return LoyaltyStampCard(
      card: card,
      onTap: () {
        // Future: open loyalty history screen
      },
    );
  }

  Widget _buildShowcaseCarousel(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Showcase',
          style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _showcaseSlides.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final slide = _showcaseSlides[index];
              return Container(
                width: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: colors.card,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: slide['mediaUrl'] ?? '',
                      fit: BoxFit.cover,
                      placeholder: (_, __) => ColoredBox(color: colors.divider),
                      errorWidget: (_, __, ___) =>
                          ColoredBox(color: colors.divider),
                    ),
                    if (slide['caption'] != null &&
                        slide['caption'].toString().isNotEmpty)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                          child: Text(
                            slide['caption'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _categoryFacts(BusinessProfile business, AzamanColors colors) {
    final chips = <Widget>[];
    if (business.priceRange != null) {
      chips.add(_factChip(colors, PriceRange.label(business.priceRange)));
    }
    for (final a in business.amenities.take(4)) {
      chips.add(_factChip(colors, a));
    }
    for (final c in business.cuisineTypes.take(3)) {
      chips.add(_factChip(colors, c));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  Widget _factChip(AzamanColors colors, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _hoursOverview(AzamanColors colors) {
    if (_locations.isEmpty) return const SizedBox.shrink();
    final primary = _locations.firstWhere(
      (l) => l.isPrimary,
      orElse: () => _locations.first,
    );
    final hours = primary.operatingHours;
    if (hours == null || hours.isEmpty) return const SizedBox.shrink();
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
          Text('Hours',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            _formatHours(hours),
            style: TextStyle(color: colors.textSecondary, fontSize: 12.5, height: 1.45),
          ),
        ],
      ),
    );
  }

  // ── Tab: Menu ──────────────────────────────────────────────────────────────
  Widget _menuTab(BusinessProfile business, AzamanColors colors) {
    if (_menuLoading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
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
              Text(empty.text,
                  style: TextStyle(color: colors.textSecondary, fontSize: 14)),
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
          ..._menuSections.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _menuSection(s, colors),
              )),
        if (hasUncat) ...[
          _sectionHeader('Other Items', colors),
          const SizedBox(height: 10),
          ..._uncategorisedProducts.map(
              (p) => _menuProductRow(p, business, colors)),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, AzamanColors colors) {
    return Text(title,
        style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800));
  }

  Widget _menuSection(CatalogSection section, AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(section.name, colors),
        if (section.description != null && section.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(section.description!,
                style:
                    TextStyle(color: colors.textTertiary, fontSize: 12.5)),
          ),
        const SizedBox(height: 10),
        ...section.products.map(
            (p) => _menuProductRow(p, _business!, colors)),
      ],
    );
  }

  Widget _menuProductRow(BusinessProduct product, BusinessProfile business,
      AzamanColors colors) {
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
                  Text(product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  if (product.description != null &&
                      product.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        product.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colors.textTertiary, fontSize: 12),
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
                  fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab: Locations ─────────────────────────────────────────────────────────
  Widget _locationsTab(AzamanColors colors) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        _locationsSection(colors),
      ],
    );
  }

  // ── Tab: Reviews ───────────────────────────────────────────────────────────
  Widget _reviewsTab(BusinessProfile business, AzamanColors colors) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        BusinessReviewsSection(business: business, colors: colors),
      ],
    );
  }

  // ── Tab: Book (placeholder) ────────────────────────────────────────────────


  // ── Sticky action bar ────────────────────────────────────────────────────
  
  /// Primary CTA label for the action bar, adapted to the business vertical.
  String _ctaLabel(BusinessProfile business) {
    switch (business.category) {
      case 'FOOD_BEVERAGE':
        return 'Order Now';
      case 'REAL_ESTATE':
      case 'HOSPITALITY':
        return 'Book a Room';
      case 'LOGISTICS':
        return 'Book a Seat';
      case 'RETAIL':
      case 'TECHNOLOGY':
        return 'Shop Now';
      case 'HEALTH_WELLNESS':
      case 'FREELANCE_SERVICES':
        return 'Book Service';
      case 'EDUCATION':
        return 'Enroll Now';
      case 'ENTERTAINMENT':
        return 'Get Tickets';
      case 'FINANCIAL_SERVICES':
        return 'View Plans';
      default:
        return 'Order Now';
    }
  }

  /// Icon for the primary CTA button, adapted to the business vertical.
  IconData _ctaIcon(BusinessProfile business) {
    switch (business.category) {
      case 'FOOD_BEVERAGE':
        return Icons.restaurant_outlined;
      case 'REAL_ESTATE':
      case 'HOSPITALITY':
        return Icons.hotel_outlined;
      case 'LOGISTICS':
        return Icons.directions_bus_outlined;
      case 'RETAIL':
      case 'TECHNOLOGY':
        return Icons.shopping_bag_outlined;
      case 'HEALTH_WELLNESS':
      case 'FREELANCE_SERVICES':
        return Icons.design_services_outlined;
      case 'EDUCATION':
        return Icons.school_outlined;
      case 'ENTERTAINMENT':
        return Icons.confirmation_number_outlined;
      case 'FINANCIAL_SERVICES':
        return Icons.account_balance_outlined;
      default:
        return Icons.local_mall_outlined;
    }
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// StickyTabBarDelegate — pinned header for the tab bar inside NestedScrollView.
// ─────────────────────────────────────────────────────────────────────────────

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyTabBarDelegate({required this.child});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  double get maxExtent => 42;

  @override
  double get minExtent => 42;

  @override
  bool shouldRebuild(covariant _StickyTabBarDelegate oldDelegate) => true;
}
