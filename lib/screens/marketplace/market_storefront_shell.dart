// =============================================================================
// MARKET STOREFRONT SHELL — Marketplace Storefront Redesign (2026-10-02)
//
// The canonical customer-facing market surface: ONE continuous motion from a
// full-bleed hero identity (arrival) into a locked shopping sheet, with the
// market's information living BEHIND the sheet.
//
// Interaction model (three deliberate snap states, one scroll owner):
//   • INFO     (extent 0.46) — sheet pulled down; "About this market" panel
//               (description / hours / location / contact / showcase) is
//               revealed behind the sheet; products stay visible below.
//   • OVERVIEW (extent 0.62) — arrival state: banner + logo + name + status
//               in the hero, grab handle + first products on the sheet.
//   • SHOPPING (extent 0.78) — sheet locked; products own vertical scrolling;
//               hero collapsed into the compact market pill (logo + name).
//
// Gesture ownership: the sheet's product ListView uses the controller the
// DraggableScrollableSheet hands the builder. At list offset 0 a downward
// drag hands control to the sheet (it recedes toward the info snap); an
// upward drag locks it back at shopping. There is exactly one vertical
// scrollable in the sheet, so the two systems can never fight.
//
// The collapse is ONE continuous transform: a normalized progress value is
// derived from the sheet extent and drives the hero crossfade/scale, the
// info panel reveal, and the compact pill fade/scale together — not two
// unrelated header widgets.
//
// Discovery: on first entry the sheet dips to the info snap and springs
// back to shopping (MotionTokens-timed, easeOutBack settle), teaching
// "there is something behind this sheet". Runs once per screen; skipped
// entirely (immediate settle) under reduced motion (AzMotion).
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/collapsible_business_bar.dart'
    show OpenStatus, currentOpenStatus;

/// Sheet extents as a fraction of the available height. Design-tunable;
/// the contract is that these are DELIBERATE locked states, not free float.
class MarketStorefrontSnaps {
  MarketStorefrontSnaps._();

  /// Info snap — sheet recedes, market information is revealed behind it.
  static const double info = 0.46;

  /// Overview snap — the arrival composition: full hero identity visible.
  static const double overview = 0.62;

  /// Shopping snap — sheet locked, products own the surface.
  static const double shopping = 0.78;
}

class MarketStorefrontShell extends StatefulWidget {
  final BusinessProfile business;
  final AzamanColors colors;

  /// Banner priority is resolved by the caller (showcase → coverImageUrl →
  /// logo → null for the accent-gradient fallback).
  final String? bannerUrl;

  final List<BusinessLocation> locations;
  final List<Map<String, dynamic>> showcaseSlides;
  final bool isFollowing;
  final int unpaidInvoices;

  /// Whether the market has catalog sections/products (gates the in-sheet
  /// catalog shortcut button).
  final bool hasCatalog;

  /// Vertical-aware label for the catalog shortcut ("Menu", "Products", ...).
  final String catalogLabel;

  /// The product/content surface, as ListView children. The shell owns the
  /// ListView and its scroll controller (the sheet's gesture handoff).
  final List<Widget> Function(BuildContext context) productsBuilder;

  // ── Delegates (all wired by BusinessProfileScreen) ─────────────────────────
  final VoidCallback? onBack;
  final VoidCallback? onToggleFollow;
  final VoidCallback? onShare;
  final VoidCallback? onPrimaryCta;
  final void Function(BusinessProduct product)? onOrderProduct;
  final VoidCallback? onOpenCatalog;
  final VoidCallback? onOpenStorefront;
  final VoidCallback? onOpenReviews;
  final VoidCallback? onOpenLocations;
  final VoidCallback? onPayInvoice;
  final void Function(String url)? onLaunch;

  const MarketStorefrontShell({
    super.key,
    required this.business,
    required this.colors,
    required this.bannerUrl,
    required this.locations,
    required this.showcaseSlides,
    required this.isFollowing,
    required this.unpaidInvoices,
    required this.hasCatalog,
    required this.catalogLabel,
    required this.productsBuilder,
    this.onBack,
    this.onToggleFollow,
    this.onShare,
    this.onPrimaryCta,
    this.onOrderProduct,
    this.onOpenCatalog,
    this.onOpenStorefront,
    this.onOpenReviews,
    this.onOpenLocations,
    this.onPayInvoice,
    this.onLaunch,
  });

  @override
  State<MarketStorefrontShell> createState() => _MarketStorefrontShellState();
}

class _MarketStorefrontShellState extends State<MarketStorefrontShell> {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  static const double _infoSnap = MarketStorefrontSnaps.info;
  static const double _overviewSnap = MarketStorefrontSnaps.overview;
  static const double _shoppingSnap = MarketStorefrontSnaps.shopping;

  /// The info panel has fully faded in by this extent (between info and
  /// overview) so the identity block and the info panel never fight.
  static const double _infoVisibleBelow = 0.56;

  bool _discoveryStarted = false;
  double _lastExtent = MarketStorefrontSnaps.overview;
  Timer? _discoveryTimer;

  @override
  void initState() {
    super.initState();
    _sheetController.addListener(_onExtentChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runDiscoveryAnimation();
    });
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  double get _extent =>
      _sheetController.isAttached ? _sheetController.size : _overviewSnap;

  // ── Sheet extent → normalized transition progress ───────────────────────────
  // ONE continuous mapping drives every animated piece.

  /// 0 at/below overview → 1 at shopping. Drives the hero collapse and the
  /// compact pill appearance.
  double get _pillProgress {
    final t = (_extent - _overviewSnap) / (_shoppingSnap - _overviewSnap);
    return t.clamp(0.0, 1.0);
  }

  /// 1 at/below the info-visible line → 0 at overview. Drives the info
  /// panel reveal.
  double get _infoProgress {
    final t = (_extent - _infoSnap) / (_infoVisibleBelow - _infoSnap);
    return (1.0 - t).clamp(0.0, 1.0);
  }

  /// The large hero identity: full at overview, faded out toward the pill
  /// (shopping) AND toward the info panel (info snap).
  double get _identityOpacity {
    return (1.0 - _pillProgress) * _infoProgress;
  }

  void _onExtentChanged() {
    if (!mounted) return;
    final e = _extent;
    // Subtle crossing tick when a drag sweeps past the overview snap.
    if ((_lastExtent - _overviewSnap) * (e - _overviewSnap) < 0) {
      AzamanHaptics.selection();
    }
    _lastExtent = e;
    setState(() {});
  }

  // ── Initial discovery animation ────────────────────────────────────────────
  // A single physical dip-and-settle, once per screen. Under reduced motion
  // the sheet simply settles at the shopping snap with no choreography.
  void _runDiscoveryAnimation() {
    if (_discoveryStarted || !_sheetController.isAttached) return;
    _discoveryStarted = true;
    final travel = AzMotion.of(context).travel;
    try {
      if (!travel) {
        // Reduced motion: no choreography — settle immediately.
        _sheetController.animateTo(
          _shoppingSnap,
          duration: const Duration(milliseconds: 1),
          curve: Curves.linear,
        );
        return;
      }
    } catch (_) {
      return;
    }
    // Small entrance beat so the arrival composition registers first.
    _discoveryTimer = Timer(MotionTokens.control, () {
      if (!mounted) return;
      // Reveal: dip to the info snap — "there is something behind me".
      _animateSheetTo(
        _infoSnap,
        duration: MotionTokens.standard,
        curve: MotionTokens.enter,
        onDone: () {
          _discoveryTimer = Timer(const Duration(milliseconds: 220), () {
            if (!mounted) return;
            // Settle into shopping with a soft spring.
            _animateSheetTo(
              _shoppingSnap,
              duration: MotionTokens.emphasized,
              curve: MotionTokens.spring,
            );
          });
        },
      );
    });
  }

  void _animateSheetTo(
    double target, {
    required Duration duration,
    required Curve curve,
    VoidCallback? onDone,
  }) {
    Future(() async {
      try {
        await _sheetController.animateTo(target, duration: duration, curve: curve);
      } catch (_) {
        // The sheet can be disposed mid-flight; never crash the entrance.
      }
      if (mounted) onDone?.call();
    });
  }

  /// Tap on the grab handle: at shopping → reveal information; anywhere
  /// else → lift into shopping.
  void _onHandleTap() {
    if (!_sheetController.isAttached) return;
    AzamanHaptics.nav();
    final target =
        _extent >= (_overviewSnap + _shoppingSnap) / 2 ? _infoSnap : _shoppingSnap;
    _sheetController.animateTo(
      target,
      duration: MotionTokens.emphasized,
      curve: MotionTokens.spring,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final pillT = _pillProgress;
    final infoT = _infoProgress;
    final identityT = _identityOpacity;

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Back layer: banner + identity + information (behind sheet) ──
          _backLayer(colors, pillT, infoT, identityT),
          // ── The sheet ────────────────────────────────────────────────────
          Positioned.fill(
            child: DraggableScrollableSheet(
              expand: false,
              controller: _sheetController,
              minChildSize: _infoSnap,
              maxChildSize: _shoppingSnap,
              snapSizes: const [_overviewSnap],
              snap: true,
              initialChildSize: _overviewSnap,
              builder: (context, scrollController) => _sheet(
                colors,
                scrollController,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Back layer ────────────────────────────────────────────────────────────
  Widget _backLayer(
    AzamanColors colors,
    double pillT,
    double infoT,
    double identityT,
  ) {
    final media = MediaQuery.of(context);
    final safeTop = media.padding.top;
    final business = widget.business;

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Banner, with a subtle parallax lift as it collapses.
          Transform.translate(
            offset: Offset(0, -18 * pillT),
            child: Transform.scale(
              scale: 1.0 + (0.05 * pillT),
              child: _banner(colors),
            ),
          ),
          // Top action row — always available over the banner strip.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AzSpace.md,
                vertical: AzSpace.xs,
              ),
              child: Row(
                children: [
                  _circleButton(
                    colors,
                    Icons.arrow_back_rounded,
                    widget.onBack ?? () => Navigator.maybePop(context),
                  ),
                  const Spacer(),
                  _circleButton(
                    colors,
                    widget.isFollowing
                        ? Icons.check_circle_outline_rounded
                        : Icons.person_add_outlined,
                    widget.onToggleFollow,
                    tint: widget.isFollowing ? colors.success : null,
                  ),
                  const SizedBox(width: AzSpace.sm),
                  _circleButton(colors, Icons.ios_share_rounded, widget.onShare),
                ],
              ),
            ),
          ),
          // Large hero identity block (arrival composition).
          Positioned(
            top: safeTop + 72,
            left: AzSpace.lg,
            right: AzSpace.lg,
            child: IgnorePointer(
              ignoring: identityT < 0.05,
              child: Opacity(
                opacity: identityT,
                child: Transform.scale(
                  scale: 1.0 - (0.18 * pillT),
                  child: _identityBlock(business, colors),
                ),
              ),
            ),
          ),
          // Compact market pill — crossfades in as the hero collapses.
          Positioned(
            top: safeTop + AzSpace.xs,
            left: AzSpace.md,
            right: AzSpace.md,
            child: IgnorePointer(
              ignoring: pillT < 0.95,
              child: Opacity(
                opacity: Curves.easeOutCubic.transform(pillT),
                child: Transform.scale(
                  scale: 0.96 + (0.04 * pillT),
                  child: Center(
                    child: _compactPill(business, colors),
                  ),
                ),
              ),
            ),
          ),
          // Information panel — revealed behind the sheet at the info snap.
          Positioned(
            left: AzSpace.lg,
            right: AzSpace.lg,
            top: safeTop + 64,
            bottom: 0,
            child: IgnorePointer(
              ignoring: infoT < 0.95,
              child: Opacity(
                opacity: Curves.easeOutCubic.transform(infoT),
                child: _infoPanel(business, colors),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(AzamanColors colors) {
    final bannerUrl = widget.bannerUrl;
    if (bannerUrl == null || bannerUrl.isEmpty) {
      // No real banner: the accent gradient + storefront mark. A coherent
      // hero that never looks broken (and never invents fake imagery).
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.accent, colors.accent.withValues(alpha: 0.55)],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.storefront_outlined,
            size: 72,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        AzamanNetworkImage(
          imageUrl: bannerUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => _bannerGradientFallback(colors),
          errorWidget: (_, __, ___) => _bannerGradientFallback(colors),
        ),
        // Legibility scrim for the identity/pill overlays.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black54, Colors.transparent, Colors.black38],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bannerGradientFallback(AzamanColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.accent, colors.accent.withValues(alpha: 0.55)],
        ),
      ),
    );
  }

  Widget _identityBlock(BusinessProfile business, AzamanColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Logo / profile image, straddling the banner.
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: _logoAvatar(business, colors, radius: 36),
        ),
        const SizedBox(height: AzSpace.md),
        // Market name — the strongest element on the page.
        Text(
          business.businessName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            height: 1.1,
            shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
          ),
        ),
        const SizedBox(height: AzSpace.xs + 2),
        // One minimal meta line — the current screen's metadata dump is
        // deliberately NOT carried into the hero.
        _identityMeta(business, colors),
      ],
    );
  }

  Widget _identityMeta(BusinessProfile business, AzamanColors colors) {
    final parts = <String>[BusinessCategories.labelFor(business.category)];
    final status = _openStatusLabel();
    if (status != null) parts.add(status);
    if (business.reviewCount > 0) {
      parts.add('★ ${business.averageRating.toStringAsFixed(1)}');
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AzSpace.md,
        vertical: AzSpace.xs + 1,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: AzRadius.brXl,
      ),
      child: Text(
        parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.92),
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String? _openStatusLabel() {
    final primary = _primaryLocation;
    final hours = primary?.operatingHours;
    if (hours == null || hours.isEmpty) return null;
    switch (currentOpenStatus(hours)) {
      case OpenStatus.open:
        return 'Open now';
      case OpenStatus.closingSoon:
        return 'Closing soon';
      case OpenStatus.closed:
        return 'Closed';
      case OpenStatus.unknown:
        return null;
    }
  }

  BusinessLocation? get _primaryLocation {
    if (widget.locations.isEmpty) return null;
    return widget.locations.firstWhere(
      (l) => l.isPrimary,
      orElse: () => widget.locations.first,
    );
  }

  Widget _logoAvatar(
    BusinessProfile business,
    AzamanColors colors, {
    required double radius,
  }) {
    final logoUrl = business.logoUrl;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: colors.card,
        foregroundColor: colors.textPrimary,
        child: ClipOval(
          child: SizedBox(
            width: radius * 2,
            height: radius * 2,
            child: AzamanNetworkImage(imageUrl: logoUrl, fit: BoxFit.cover),
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.card,
      child: Icon(
        Icons.storefront_outlined,
        size: radius,
        color: colors.accent,
      ),
    );
  }

  Widget _compactPill(BusinessProfile business, AzamanColors colors) {
    return Container(
      key: const Key('market-compact-pill'),
      padding: const EdgeInsets.symmetric(
        horizontal: AzSpace.xs + 6,
        vertical: AzSpace.xs + 1,
      ),
      decoration: BoxDecoration(
        color: colors.card.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AzRadius.pill),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 5),
            color: Colors.black.withValues(alpha: 0.10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _logoAvatar(business, colors, radius: 15),
          const SizedBox(width: AzSpace.sm),
          Flexible(
            child: Text(
              business.businessName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Information panel (behind the sheet) ───────────────────────────────────
  // Reuses BusinessProfile fields only — no second data model. Sections
  // render only when their data exists; a market with no public information
  // renders no panel at all (never an empty shell).
  Widget _infoPanel(BusinessProfile business, AzamanColors colors) {
    final children = <Widget>[];

    final description = business.description?.trim() ?? '';
    if (description.isNotEmpty) {
      children.add(_infoTitle(colors, 'About this market'));
      children.add(const SizedBox(height: AzSpace.sm));
      children.add(
        Text(
          description,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      );
      children.add(const SizedBox(height: AzSpace.lg));
    }

    final primary = _primaryLocation;
    final hours = primary?.operatingHours;
    if (hours != null && hours.isNotEmpty) {
      children.add(_infoTitle(colors, 'Hours'));
      children.add(const SizedBox(height: AzSpace.sm));
      children.add(
        Text(
          _formatHours(hours),
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
      );
      children.add(const SizedBox(height: AzSpace.lg));
    }

    if (primary != null && primary.address.isNotEmpty) {
      children.add(_infoTitle(colors, 'Location'));
      children.add(const SizedBox(height: AzSpace.sm));
      children.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on_outlined, size: 16, color: colors.textTertiary),
            const SizedBox(width: AzSpace.sm),
            Expanded(
              child: Text(
                primary.address,
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      );
      if (widget.locations.length > 1) {
        children.add(const SizedBox(height: AzSpace.xs));
        children.add(
          _infoActionRow(
            colors,
            Icons.place_rounded,
            'All locations (${widget.locations.length})',
            widget.onOpenLocations,
          ),
        );
      }
      children.add(const SizedBox(height: AzSpace.lg));
    }

    final contacts = <Widget>[];
    if ((business.phoneNumber ?? '').isNotEmpty) {
      contacts.add(
        _infoActionRow(
          colors,
          Icons.call_outlined,
          business.phoneNumber!,
          () => widget.onLaunch?.call('tel:${business.phoneNumber}'),
        ),
      );
    }
    if ((business.contactEmail ?? '').isNotEmpty) {
      contacts.add(
        _infoActionRow(
          colors,
          Icons.mail_outline,
          business.contactEmail!,
          () => widget.onLaunch?.call('mailto:${business.contactEmail}'),
        ),
      );
    }
    if ((business.website ?? '').isNotEmpty) {
      contacts.add(
        _infoActionRow(
          colors,
          Icons.link_rounded,
          business.website!,
          () => widget.onLaunch?.call(business.website!),
        ),
      );
    }
    if (contacts.isNotEmpty) {
      children.add(_infoTitle(colors, 'Contact'));
      children.add(const SizedBox(height: AzSpace.xs));
      children.addAll(contacts);
      children.add(const SizedBox(height: AzSpace.lg));
    }

    if (business.reviewCount > 0) {
      children.add(
        _infoActionRow(
          colors,
          Icons.star_rounded,
          '★ ${business.averageRating.toStringAsFixed(1)} · '
          '${business.reviewCount} reviews',
          widget.onOpenReviews,
        ),
      );
      children.add(const SizedBox(height: AzSpace.lg));
    }

    if (widget.showcaseSlides.isNotEmpty) {
      children.add(_infoTitle(colors, 'Showcase'));
      children.add(const SizedBox(height: AzSpace.sm));
      children.add(_showcaseGallery(colors));
      children.add(const SizedBox(height: AzSpace.lg));
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      key: const Key('market-info-panel'),
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(AzSpace.lg),
      child: Container(
        padding: const EdgeInsets.all(AzSpace.lg),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: AzRadius.brXl,
          border: Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _infoTitle(AzamanColors colors, String title) {
    return Text(
      title,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 14.5,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _infoActionRow(
    AzamanColors colors,
    IconData icon,
    String label,
    VoidCallback? onTap,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              AzamanHaptics.nav();
              onTap();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AzSpace.xs + 1),
        child: Row(
          children: [
            Icon(icon, size: 16, color: colors.textTertiary),
            const SizedBox(width: AzSpace.xs + 4),
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

  Widget _showcaseGallery(AzamanColors colors) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        itemCount: widget.showcaseSlides.length,
        separatorBuilder: (_, __) => const SizedBox(width: AzSpace.sm),
        itemBuilder: (context, index) {
          final slide = widget.showcaseSlides[index];
          return Container(
            width: 180,
            decoration: BoxDecoration(
              borderRadius: AzRadius.brLg,
              color: colors.softSurface,
            ),
            clipBehavior: Clip.antiAlias,
            child: AzamanNetworkImage(
              imageUrl: slide['mediaUrl'] ?? '',
              fit: BoxFit.cover,
              placeholder: (_, __) => ColoredBox(color: colors.divider),
              errorWidget: (_, __, ___) => ColoredBox(color: colors.divider),
            ),
          );
        },
      ),
    );
  }

  String _formatHours(Map<String, dynamic> hours) {
    return hours.entries
        .take(7)
        .map((e) => '${_capitalize(e.key)} ${e.value}')
        .join('  ·  ');
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  // ── The sheet ──────────────────────────────────────────────────────────────
  Widget _sheet(AzamanColors colors, ScrollController scrollController) {
    final business = widget.business;
    return Container(
      key: const Key('market-storefront-sheet'),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Grab handle — physical but extremely subtle. Tap cycles the
          // sheet between its locked states; the ride of the discovery
          // dip gives it its only "lift".
          GestureDetector(
            key: const Key('market-storefront-handle'),
            behavior: HitTestBehavior.opaque,
            onTap: _onHandleTap,
            child: Container(
              width: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                vertical: AzSpace.sm,
                horizontal: AzSpace.lg,
              ),
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(AzRadius.pill),
                ),
              ),
            ),
          ),
          // Action row: primary market CTA + the vertical content
          // shortcuts + rare utilities.
          _sheetActions(business, colors),
          // Product/content surface — the sheet's one and only scrollable.
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.only(
                top: AzSpace.md,
                bottom: MediaQuery.of(context).padding.bottom + AzSpace.xxl,
              ),
              children: widget.productsBuilder(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetActions(BusinessProfile business, AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AzSpace.lg,
        AzSpace.xs,
        AzSpace.lg,
        AzSpace.sm,
      ),
      child: Row(
        children: [
          Expanded(child: _primaryCta(business, colors)),
          if (widget.hasCatalog) ...[
            const SizedBox(width: AzSpace.sm),
            _iconAction(
              colors,
              Icons.menu_book_rounded,
              widget.catalogLabel,
              widget.onOpenCatalog,
            ),
          ],
          if (widget.onOpenStorefront != null) ...[
            const SizedBox(width: AzSpace.sm),
            _iconAction(
              colors,
              Icons.storefront_outlined,
              'Storefront',
              widget.onOpenStorefront,
            ),
          ],
          const SizedBox(width: AzSpace.sm),
          _iconAction(
            colors,
            Icons.more_horiz_rounded,
            'More',
            _openMoreSheet,
          ),
        ],
      ),
    );
  }

  Widget _primaryCta(BusinessProfile business, AzamanColors colors) {
    return GestureDetector(
      key: const Key('market-primary-cta'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AzamanHaptics.confirm();
        widget.onPrimaryCta?.call();
      },
      child: Container(
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
        decoration: BoxDecoration(
          color: colors.accent,
          borderRadius: BorderRadius.circular(AzRadius.pill),
          boxShadow: [
            BoxShadow(
              color: colors.accent.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _ctaIcon(business),
              size: 17,
              color: colors.isDark ? Colors.white : Colors.white,
            ),
            const SizedBox(width: AzSpace.xs + 2),
            Flexible(
              child: Text(
                _ctaLabel(business),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconAction(
    AzamanColors colors,
    IconData icon,
    String tooltip,
    VoidCallback? onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AzamanHaptics.nav();
          onTap?.call();
        },
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.softSurface,
            borderRadius: BorderRadius.circular(AzRadius.pill),
            border: Border.all(color: colors.divider),
          ),
          child: Icon(icon, size: 19, color: colors.textSecondary),
        ),
      ),
    );
  }

  // Rare utilities live in the "More" sheet, not on the storefront.
  Future<void> _openMoreSheet() async {
    final colors = widget.colors;
    final business = widget.business;
    final rows = <Widget>[];

    if ((business.phoneNumber ?? '').isNotEmpty) {
      rows.add(_moreRow(colors, Icons.call_outlined, 'Call', () {
        Navigator.pop(context);
        widget.onLaunch?.call('tel:${business.phoneNumber}');
      }));
    }
    if ((business.address ?? '').isNotEmpty) {
      rows.add(_moreRow(colors, Icons.directions_outlined, 'Directions', () {
        Navigator.pop(context);
        widget.onLaunch?.call(
          'https://maps.google.com/?q=${Uri.encodeComponent(business.address!)}',
        );
      }));
    }
    rows.add(_moreRow(colors, Icons.share_rounded, 'Share', () {
      Navigator.pop(context);
      widget.onShare?.call();
    }));
    if (widget.onOpenReviews != null) {
      rows.add(_moreRow(colors, Icons.star_rounded, 'Reviews', () {
        Navigator.pop(context);
        widget.onOpenReviews!();
      }));
    }
    if (widget.locations.length > 1 && widget.onOpenLocations != null) {
      rows.add(_moreRow(
        colors,
        Icons.place_rounded,
        'All locations (${widget.locations.length})',
        () {
          Navigator.pop(context);
          widget.onOpenLocations!();
        },
      ));
    }
    if (widget.unpaidInvoices > 0 && widget.onPayInvoice != null) {
      rows.add(_moreRow(
        colors,
        Icons.receipt_long_rounded,
        'Pay invoice (${widget.unpaidInvoices})',
        () {
          Navigator.pop(context);
          widget.onPayInvoice!();
        },
      ));
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AzSpace.md),
            ...rows,
            const SizedBox(height: AzSpace.md),
          ],
        ),
      ),
    );
  }

  Widget _moreRow(
    AzamanColors colors,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: colors.accent, size: 20),
      title: Text(
        label,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () {
        AzamanHaptics.nav();
        onTap();
      },
    );
  }

  Widget _circleButton(
    AzamanColors colors,
    IconData icon,
    VoidCallback? onTap, {
    Color? tint,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AzamanHaptics.nav();
        onTap?.call();
      },
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: tint ?? Colors.white, size: 19),
      ),
    );
  }

  // ── Vertical-aware CTA labels (moved from BusinessProfileScreen) ───────────
  static String _ctaLabel(BusinessProfile business) {
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

  static IconData _ctaIcon(BusinessProfile business) {
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
