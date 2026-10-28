// lib/screens/marketplace/marketplace_home_screen.dart
// =============================================================================
// AZAMAN — MARKETPLACE HOME SCREEN (Redesign, 2026-07-04)
//
// Structure (top → bottom):
//   _header()              — title + view toggle, morphs into an expandable
//                             search field (tap the search icon; tap the
//                             back arrow or elsewhere on the page to retract)
//   _activeCategoryChip()  — shown only when a category is active (clearable)
//   _resultsBar()          — slim row: count · Sort ▼ · Verified pill · Filter
//   Expanded(_listMode() or _mapMode())
//
// Category selection now lives entirely in the horizontal _categoryStrip()
// (the old side endDrawer was removed as redundant, 2026-07-06).
// All list items are BusinessResultCard (Workstream D): the body opens
// the business profile directly; the avatar opens the action panel. There
// is no inline accordion in the feed.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/theme/balance_card_brand.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/marketplace_nav_focus.dart';
import 'package:azaman/providers/marketplace_search_binding.dart';
import 'package:azaman/services/marketplace_booking_service.dart'
    show marketplaceBookingServiceProvider;
import 'package:azaman/providers/marketplace_search_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/nav_band_clearance.dart';
import 'package:azaman/widgets/stories/story_rail_collapse.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/screens/story_viewer_screen.dart';
import 'package:azaman/models/story_model.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/marketplace/business_result_card.dart';
import 'package:azaman/widgets/marketplace/follow_onboarding_sheet.dart';
import 'package:azaman/widgets/marketplace/follow_onboarding_spotlight.dart';
import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/marketplace_mix_provider.dart';
import 'package:azaman/widgets/liquid/category_speed_dial.dart';
import 'package:azaman/widgets/marketplace/discovery/mix_dice.dart';
import 'package:azaman/widgets/marketplace/discovery/mix_feed_surface.dart';
import 'package:azaman/widgets/marketplace/discovery/mix_local_first_rails.dart';
import 'package:azaman/widgets/marketplace/discovery/mix_taxonomy_bubble_rail.dart';
import 'package:azaman/widgets/marketplace/marketplace_status_rail.dart';
import 'package:azaman/widgets/marketplace/nearby_outcome.dart';
import 'package:azaman/widgets/marketplace/nearby_map_markers.dart';
import 'package:azaman/widgets/marketplace/nearby_business_row.dart';
import 'package:azaman/services/nearby_location_tracker.dart';
import 'package:azaman/services/nearby_location_resolver.dart';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart' hide Marker;
import 'package:shimmer/shimmer.dart';
import 'package:azaman/widgets/scale_tap.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum _ViewMode { list, map }

enum _SortMode { topRated, mostPopular, nearest, newest }

class MarketplaceHomeScreen extends ConsumerStatefulWidget {
  const MarketplaceHomeScreen({
    super.key,
    this.initialCategory,
    this.locationResolver = const PlatformNearbyLocationResolver(),
  });

  /// Wire value of the vertical to open with: `'RETAIL'`, `'FOOD_BEVERAGE'`,
  /// `'LOGISTICS'`, `'HOSPITALITY'` or `'REAL_ESTATE'` (the wire the in-app
  /// category dial itself sends for Hotels). `null` or an unknown value opens
  /// the marketplace unfiltered ("All").
  ///
  /// Added for the TASK-010b vertical launcher and future deep links.
  final String? initialCategory;

  /// One-shot location resolution (services check + permission dance +
  /// current position). Injectable so the resolve STATE MACHINE is
  /// widget-testable — the geolocator futures hang forever in tests.
  final NearbyLocationResolver locationResolver;

  @override
  ConsumerState<MarketplaceHomeScreen> createState() =>
      _MarketplaceHomeScreenState();
}

class _MarketplaceHomeScreenState extends ConsumerState<MarketplaceHomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _scrollCtrl = ScrollController();
  double _scrollOffset = 0;

  // ── WORKSTREAM F1 — the EXPLICIT story-rail expansion state ──────────────
  //
  // The collapsed affordance used to `_scrollCtrl.animateTo(0)`: tapping the
  // stories strip while scrolled down DRAGGED THE FEED BACK TO THE TOP,
  // destroying the scroll anchor. The pin is the fix: tapping expands the
  // rail IN PLACE (explicit expansion state) while the list scrolls DOWN by
  // exactly the rail's growth, so the first visible results stay visually
  // stationary while the rail slides in over them. The scroll-driven
  // collapse keeps all its authority whenever the pin is not held; the pin
  // hands back seamlessly when the user scrolls the feed to its top (the
  // scroll ratio there is already 1 — no height jump, no opacity pop).
  late final AnimationController _storyPinCtrl;
  late final CurvedAnimation _storyPinCurve;
  bool _storyPinHeld = false;
  // Live results while typing: debounce the already-updated provider text
  // into the existing search plumbing.
  Timer? _debounce;

  // Category filter — wire value string (null = All)
  String? _selectedCategory;

  // Story height is driven by scroll offset — no manual toggle needed.
  // At offset 0: fully expanded (96px). At offset 96: fully collapsed (0px).

  // ── NEAR YOU / MAP SPLIT (Programme G2/G3) ────────────────────────────────
  // Near You and Map are SEPARATE controls with SEPARATE state:
  //   • `_nearYouActive` governs the proximity FEED — the list renders the
  //     distance-ordered nearby results while it is on, and returns to the
  //     untouched normal search list when it goes off (the plain list keeps
  //     its provider state: nothing re-fires, nothing is lost).
  //   • `_viewMode` (list/map, the view segmented control) governs the
  //     GEOGRAPHIC surface. The pill no longer switches the view.
  bool _nearYouActive = false;

  /// True when the proximity feed was co-activated BY MIX (Workstream H):
  /// exiting Mix then restores the pre-Mix near-you state exactly — a
  /// user who explicitly enabled Near You first keeps it on exit.
  bool _nearYouFromMix = false;

  /// Foreground-only position stream (started only while a proximity
  /// consumer is active and the app is foregrounded; stopped on exit,
  /// toggle-off and app pause — late events are dropped by the tracker's
  /// generation guard).
  NearbyLocationTracker? _nearbyTracker;

  /// The position the last nearby request was fired from — the
  /// significant-move re-fire baseline.
  Position? _lastFiredPosition;

  // View / sort / filter state
  _ViewMode _viewMode = _ViewMode.list;
  // 2026-10-20 discovery refinement: the DEFAULT sort is Newest — a
  // transparent, data-grounded ordering (the backend's createdAt). The
  // old default (topRated) ranked by averageRating while the star
  // widgets were being removed from the cards — ranking by a signal
  // the surface no longer shows was silently dishonest. Top rated
  // (Audit note: there is NO sort menu on this surface — the stale
  // "_resultsBar: Sort ▼" comment predates its removal — so topRated
  // was a hidden hard-wired ranking, which is exactly what the
  // refinement forbids. mostPopular (completedEscrows) and nearest
  // (map mode) are the other real, data-grounded modes.)
  _SortMode _sort = _SortMode.newest;

  // MARKETPLACE MIX — the in-place cross-store mode. Toggled by the Mix
  // button INSIDE this screen; NO route is pushed. While active the feed
  // below the category selector is the cross-store discovery feed.
  bool _mixActive = false;

  /// Whole-button press cue for the Mix entry pill (visual only — the
  /// mode still toggles on a completed tap).
  bool _mixEntryPressed = false;

  /// The dial's selection before Mix was entered — restored on exit so
  /// the normal marketplace view returns exactly as it was (the list
  /// beneath never changed, so no re-fire is needed).
  String? _preMixDialWire;

  // Location
  Position? _position;
  bool _resolvingLocation = false;
  String? _locationError;

  // §1: Google Map controller
  GoogleMapController? _mapController;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Seed the category BEFORE the first post-frame search, so a launcher or a
    // deep link lands on an already-filtered marketplace rather than flashing
    // "All" and then filtering a frame later.
    _selectedCategory = _validatedInitialCategory();
    _scrollCtrl.addListener(_onScroll);
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.hasClients) {
        // WORKSTREAM F1 — the pin hands back to the scroll-driven grammar
        // exactly when the feed returns to its top; there the scroll ratio
        // is already 1, so this is a seamless handoff, never a jump.
        if (_storyPinHeld &&
            _scrollCtrl.offset <= 0.5 &&
            _storyPinCtrl.value >= 1) {
          _storyPinHeld = false;
          _storyPinCtrl.value = 0;
        }
        setState(() => _scrollOffset = _scrollCtrl.offset);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(businessSearchProvider.notifier)
          .search('', category: _selectedCategory);
      // Prefetch the signed-in user's own business profile so the
      // Register/Your-Business FAB shows the correct state immediately
      // instead of waiting on whatever triggered it before (opening the
      // settings drawer, which the user may never do on this screen).
      final biz = ref.read(myBusinessProvider);
      if (!biz.hasLoaded && !biz.isLoading) {
        ref.read(myBusinessProvider.notifier).load();
      }
    });
    // FOREGROUND-ONLY LOCATION (G3): no location permission is requested at
    // Marketplace open. The permission ask happens in context — when the
    // user engages Near You (or the map resolves its camera) — and the
    // position stream that follows runs only while the consuming surface is
    // active and the app is foregrounded.
    WidgetsBinding.instance.addObserver(this);
    _storyPinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    // The rail's growth and the list's compensation scroll run on the SAME
    // curve and duration, so the visible content stays anchored.
    _storyPinCurve = CurvedAnimation(
      parent: _storyPinCtrl,
      curve: Curves.easeOut,
    );
    _storyPinCtrl.addListener(() => setState(() {}));
  }

  // ── App lifecycle: the location stream is FOREGROUND-ONLY ────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final streamConsumerActive = _nearYouActive || _viewMode == _ViewMode.map;
    if (state == AppLifecycleState.resumed) {
      if (streamConsumerActive) _startNearbyUpdates();
    } else if (state != AppLifecycleState.inactive) {
      // paused / hidden / detached — never keep a location stream alive
      // outside the foreground.
      _nearbyTracker?.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nearbyTracker?.dispose();
    _debounce?.cancel();
    _storyPinCurve.dispose();
    _storyPinCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Unified search state (Overhaul 02 §4) ─────────────────────────────────

  MarketplaceSearchBinding get _binding => MarketplaceSearchBinding(ref);

  /// The committed query text — read from the provider, never from the
  /// controller, so the in-pill search (when it lands) and this screen agree.
  String get _query => ref.read(marketplaceSearchProvider).text.trim();

  bool get _searchActive => ref.read(marketplaceSearchProvider).isActive;

  /// Wire values a launcher or deep link may use to open the marketplace with a
  /// vertical already selected. Includes `REAL_ESTATE` because that is the wire
  /// the in-app category dial itself sends for Hotels (`_controlRow`).
  static const Set<String> _launchableCategoryWires = <String>{
    'FOOD_BEVERAGE',
    'RETAIL',
    'LOGISTICS',
    'HOSPITALITY',
    'REAL_ESTATE',
  };

  /// Normalises [MarketplaceHomeScreen.initialCategory] into a wire the dial
  /// already understands, or `null` for "open unfiltered".
  ///
  /// Why an allowlist rather than `BusinessCategories.fromWire`: `fromWire`
  /// does not model `REAL_ESTATE` and falls back to `OTHER` (see F-029), so
  /// round-tripping a hotel launch through it would mislabel the result. The
  /// allowlist accepts exactly what the app itself can send today, and nothing
  /// else — an unrecognised value is a caller bug, not a licence to guess.
  String? _validatedInitialCategory() {
    final wire = widget.initialCategory;
    if (wire == null || wire.trim().isEmpty) return null;
    final normalised = wire.trim().toUpperCase();
    return _launchableCategoryWires.contains(normalised) ? normalised : null;
  }

  // ── Query plumbing ─────────────────────────────────────────────────────────

  void _onScroll() {
    if (_viewMode == _ViewMode.list &&
        _scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 320) {
      if (_nearYouActive) {
        ref.read(nearbySearchProvider.notifier).loadMore();
      } else {
        ref.read(businessSearchProvider.notifier).loadMore();
      }
    }

    // Story expand/collapse is now handled via NotificationListener
    // (UserScrollNotification) in the build method — see _handleScrollNotification.
  }

  // Story expand/collapse is now driven directly by _scrollOffset.
  // No manual toggle or direction detection needed — the height
  // interpolates smoothly with scroll position, just like Telegram.

  /// CORRECTION I: the search field lives in the focused Marketplace nav
  /// band and writes to the AUTHORITATIVE provider through the SAME
  /// [MarketplaceSearchBinding] seam this screen always used — no second
  /// search provider exists. The screen reacts to committed text changes
  /// with its existing debounced plumbing. Called from build via
  /// `ref.listen` so the response is part of the normal build cycle.
  void _onProviderTextChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _fireSearch);
  }

  void _fireSearch() {
    // The proximity feed follows the SAME committed query + category —
    // a typed search inside Near You re-fires the nearby search, it does
    // not silently drop the user back to the plain list.
    if (_nearYouActive || _viewMode == _ViewMode.map) {
      _fireNearby();
      return;
    }
    ref
        .read(businessSearchProvider.notifier)
        .search(_query, category: _selectedCategory);
  }

  Future<void> _fireNearby() async {
    final pos = _position;
    if (pos == null) {
      await _resolveLocation();
      return;
    }
    _lastFiredPosition = pos;
    ref
        .read(nearbySearchProvider.notifier)
        .searchNearby(
          lat: pos.latitude,
          lng: pos.longitude,
          q: _query.isEmpty ? null : _query,
          category: _selectedCategory,
        );
  }

  Future<void> _resolveLocation() async {
    setState(() {
      _resolvingLocation = true;
      _locationError = null;
    });
    try {
      final pos = await widget.locationResolver.resolve();
      if (!mounted) return;
      setState(() {
        _position = pos;
        _resolvingLocation = false;
      });
      _lastFiredPosition = pos;
      ref
          .read(nearbySearchProvider.notifier)
          .searchNearby(
            lat: pos.latitude,
            lng: pos.longitude,
            q: _query.isEmpty ? null : _query,
            category: _selectedCategory,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolvingLocation = false;
        _locationError = e.toString();
      });
    }
  }

  // ── Near You control (G2): a SEPARATE toggle from the map ──────────────────

  /// Toggles the proximity feed. ON: resolves location (asking permission
  /// in context if needed), starts the foreground-only significant-move
  /// stream and fires the nearby search with the CURRENT query + category.
  /// OFF: stops the stream and returns to the normal search list, which
  /// kept its own provider state the whole time — no re-fetch, no lost
  /// scroll, no lost filters.
  void _toggleNearYou() {
    AzamanHaptics.toggle();
    final enabling = !_nearYouActive;
    setState(() => _nearYouActive = enabling);
    if (enabling) {
      _startNearbyUpdates();
      _fireNearby();
    } else {
      _stopNearbyUpdates();
    }
  }

  /// Starts the foreground-only position stream. Idempotent.
  void _startNearbyUpdates() {
    _nearbyTracker ??= NearbyLocationTracker(
      onPosition: _onNearbyPositionUpdate,
    );
    _nearbyTracker!.start();
  }

  /// Stops the stream unless the map (a still-active position consumer)
  /// is on screen.
  void _stopNearbyUpdates() {
    if (_viewMode == _ViewMode.map) return;
    _nearbyTracker?.stop();
  }

  /// Significant-move handler: each event the tracker delivers already
  /// passed its 100 m distanceFilter — re-fire the nearby search from the
  /// NEW position. The provider's generation guard makes the in-flight
  /// response of the previous position irrelevant.
  void _onNearbyPositionUpdate(Position position) {
    if (!mounted) return;
    if (!_nearYouActive && _viewMode != _ViewMode.map) return;
    if (_lastFiredPosition != null) {
      final moved = Geolocator.distanceBetween(
        _lastFiredPosition!.latitude,
        _lastFiredPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      if (moved < 100) return; // not a significant move
    }
    setState(() => _position = position);
    _fireNearby();
  }

  void _setViewMode(_ViewMode mode) {
    if (_viewMode == mode) return;
    AzamanHaptics.toggle();
    setState(() {
      _viewMode = mode;
      if (mode == _ViewMode.map) _sort = _SortMode.nearest;
    });
    if (mode == _ViewMode.map) {
      // The map is the geographic surface — it keeps the nearby
      // machinery (position + radius-bounded markers) and now also holds
      // the position stream while it is on screen.
      _startNearbyUpdates();
      _fireNearby();
    } else {
      _stopNearbyUpdates();
    }
  }

  // ── Sort + filter (client-side) ─────────────────────────────────────────────

  /// Client-side category match that tolerates the historical hotel launcher
  /// wire value REAL_ESTATE: the backend/demo search already normalizes it to
  /// HOSPITALITY, but a literal equality here would empty the result list.
  bool _categoryMatchesBusiness(
    String businessCategory,
    String selectedCategory,
  ) {
    final actual = businessCategory.trim().toUpperCase();
    final wanted = selectedCategory.trim().toUpperCase();
    if (wanted == 'REAL_ESTATE') {
      return actual == 'HOSPITALITY' || actual == 'REAL_ESTATE';
    }
    return actual == wanted;
  }

  List<BusinessProfile> _applySortFilter(List<BusinessProfile> input) {
    var list = input.where((b) {
      if (_selectedCategory != null &&
          !_categoryMatchesBusiness(b.category, _selectedCategory!)) {
        return false;
      }
      return true;
    }).toList();

    switch (_sort) {
      case _SortMode.topRated:
        list.sort((a, b) => b.averageRating.compareTo(a.averageRating));
        break;
      case _SortMode.mostPopular:
        list.sort((a, b) => b.completedEscrows.compareTo(a.completedEscrows));
        break;
      case _SortMode.newest:
        // Real createdAt ordering — the previous `break` silently left
        // the list in fetch order while the UI labelled it "Newest".
        list.sort((a, b) => b.createdOrEpoch.compareTo(a.createdOrEpoch));
        break;
      case _SortMode.nearest:
        break;
    }
    return list;
  }

  Future<void> _refresh() {
    return ref
        .read(businessSearchProvider.notifier)
        .search(_query, category: _selectedCategory);
  }

  // ── Back + search clear (correction H/I) ────────────────────────────────────
  //
  // Back semantics: a committed search clears first; otherwise the bare
  // marketplace root lets the system back do its thing.

  void _handleBack() {
    // In-place modes unwind from the inside out: Mix first, then the
    // committed search, then the system default.
    if (_mixActive) {
      _toggleMixMode();
      return;
    }
    if (_searchActive) _clearSearch();
  }

  /// Toggles the in-place Mix mode. Entering: the dial renders ALL and the
  /// unfiltered discovery feed loads (the provider's null category). No
  /// navigation happens — the mode lives inside this screen.
  void _toggleMixMode() {
    AzamanHaptics.toggle();
    if (!_mixActive) {
      _preMixDialWire = _selectedCategory;
      setState(() {
        _mixActive = true;
        _selectedCategory = null; // the dial renders All — Mix's default
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Entering Mix defaults to ALL: the UNFILTERED discovery feed (the
        // gateway omits the category parameter entirely).
        await ref.read(marketplaceMixProvider.notifier).selectCategory(null);
        // WORKSTREAM H — pressing Mix co-activates Near You when a valid
        // foreground location is ALREADY available. The resolve is SILENT:
        // it never asks for permission, so pressing Mix can't surprise
        // the user with a system prompt. No position → the honest off
        // state; the Near You control remains the explicit ask/retry
        // route. No coordinates are invented and no fake feed loads.
        try {
          final pos = await widget.locationResolver.resolveSilently();
          if (!mounted || !_mixActive) return;
          setState(() {
            _position = pos;
            if (!_nearYouActive) {
              _nearYouActive = true;
              _nearYouFromMix = true;
            }
          });
          _startNearbyUpdates();
          _lastFiredPosition = pos;
          ref
              .read(nearbySearchProvider.notifier)
              .searchNearby(
                lat: pos.latitude,
                lng: pos.longitude,
                q: _query.isEmpty ? null : _query,
                category: _selectedCategory,
              );
        } catch (_) {
          // Silent by design: Mix stays a pure discovery surface. No
          // prompt, no retry loop, no error banner on this path.
        }
      });
    } else {
      final mixOwnedNearYou = _nearYouFromMix;
      setState(() {
        _mixActive = false;
        // Restore the pre-Mix dial selection — the marketplace list
        // underneath never changed, so the view returns exactly as left.
        _selectedCategory = _preMixDialWire;
        // WORKSTREAM H exit restoration: if MIX was what turned the
        // proximity feed on, it turns it back off — the user returns to
        // the exact marketplace they left. An explicitly-enabled Near You
        // survives the Mix round trip.
        if (mixOwnedNearYou) {
          _nearYouActive = false;
          _nearYouFromMix = false;
        }
      });
      if (mixOwnedNearYou) _stopNearbyUpdates();
    }
  }

  /// Opens the OFFERING store from the Mix feed — the only navigation Mix
  /// triggers, and it is the same storefront route the old Mix screen
  /// used (offer identity travels through the real events contract).
  void _openMixStore(MixOffer offer) {
    ref.read(marketplaceMixProvider.notifier).trackOfferTap(offer);
    context.push('/business/${offer.bizId}');
  }

  /// Clears the AUTHORITATIVE provider — the focused-nav search field
  /// mirrors the committed text out of it, and the provider listener
  /// re-fires the results.
  void _clearSearch() {
    AzamanHaptics.toggle();
    _debounce?.cancel();
    _binding.clear();
    _fireSearch();
  }

  // ── Root build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    // CORRECTION I: the focused-nav search field writes to the AUTHORITATIVE
    // provider through the SAME [MarketplaceSearchBinding] seam this screen
    // always used — no second search provider exists. The screen reacts to
    // committed text changes with its existing debounced plumbing.
    ref.listen(marketplaceSearchProvider.select((s) => s.text), (_, text) {
      _onProviderTextChanged(text);
    });

    // Scroll-driven gradient (0 at top → full when scrolled 120px)
    final expandRatio = (_scrollOffset / 120).clamp(0.0, 1.0);
    // §16 — the story rail's collapse speaks the SAME grammar as chat's
    // story rail; WORKSTREAM F1 layers the explicit pin on top (the pin
    // only ever OPENS — scroll keeps its authority everywhere else).
    final storyExpandRatio = _storyRailRatio(context);

    final searchActive = ref.watch(
      marketplaceSearchProvider.select((s) => s.isActive),
    );
    // Back semantics (correction H): the marketplace root is ONE result
    // screen. A committed search clears first; otherwise the system back
    // does its normal thing.
    final canPop = !searchActive;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        // FAB removed — store management moved to the storefront button (item 9)
        body: SafeArea(
          bottom: false,
          child: AzPullToRefresh(
            onRefresh: () async {
              // WORKSTREAM H: with Mix and the co-activated proximity
              // feed both live, one deliberate pull refreshes BOTH —
              // never a silent stale half.
              if (_mixActive && _nearYouActive) {
                await Future.wait([
                  ref.read(marketplaceMixProvider.notifier).retry(),
                  _fireNearby(),
                ]);
              } else if (_mixActive) {
                await ref.read(marketplaceMixProvider.notifier).retry();
              } else if (_viewMode == _ViewMode.list) {
                await (_nearYouActive ? _fireNearby() : _refresh());
              } else {
                await _fireNearby();
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Phase 3.4: Collapsible gradient behind header ───────────────
                Stack(
                  children: [
                    // Gradient that fades in as user scrolls
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: expandRatio,
                          duration: const Duration(milliseconds: 100),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  colors.accent.withValues(alpha: 0.08),
                                  colors.background,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _header(colors),
                  ],
                ),
                const SizedBox(height: 10),
                // CORRECTION I: tapping anywhere on Marketplace content (while
                // the user is on this root screen) restores the focused
                // Marketplace nav — the "…" exit is a presentation change of
                // the SAME tab, and content interaction brings it back. The
                // Listener is observational: it never consumes or blocks the
                // child's own taps and gestures.
                Expanded(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) {
                      if (!ref.read(marketplaceNavFocusProvider)) {
                        ref.read(marketplaceNavFocusProvider.notifier).state =
                            true;
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Stories: smooth scroll-driven height (Telegram-style).
                        //    2026-10-20: Stories stay in their normal position
                        //    ABOVE the selectors/feed while Mix is active — Mix
                        //    is an in-place mode of THIS page, not a separate
                        //    page; the story rail keeps its browse role and its
                        //    scroll-collapse behavior in both modes.
                        SizedBox(
                          // Testable seam: this box's height IS the rail's
                          // collapsed extent — the child inside the
                          // OverflowBox always lays out at full height and
                          // is clipped away, so assertions must read HERE.
                          key: const ValueKey('marketplace_story_rail_extent'),
                          height: StoryRailCollapse.extentPx * storyExpandRatio,
                          width: double.infinity,
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: StoryRailCollapse.extentPx,
                              maxHeight: StoryRailCollapse.extentPx,
                              child: Opacity(
                                opacity: storyExpandRatio.clamp(0.0, 1.0),
                                child: MarketplaceExpandedStories(
                                  onOpenBusiness: (bizId) {
                                    _openBusinessStories(context, bizId);
                                  },
                                  onBrowsePressed: () {
                                    setState(() => _selectedCategory = null);
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        // ── §11: the category SPEED DIAL is the category
                        // system (radial fan grammar) + Near You as the only
                        // additional control. §12: no star/featured surface.
                        // ── I1: the follow-onboarding spotlight card.
                        //    Renders itself ONLY in the proven-eligible
                        //    state (authoritative empty follow list,
                        //    authenticated, not previously dismissed) —
                        //    every other state is an honest SizedBox
                        //    that takes no layout space. Non-modal by
                        //    construction: the marketplace above and
                        //    below it stays fully interactive.
                        FollowOnboardingSpotlight(
                          userId: ref.watch(authProvider).user?.id,
                          onStart: () => FollowOnboardingSheet.open(context),
                        ),
                        _controlRow(colors),
                        Expanded(
                          child: _mixActive
                              ? _mixMode(colors)
                              : (_viewMode == _ViewMode.list
                                    ? _listMode(colors)
                                    : _mapMode(colors)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── The in-place MIX MODE surface ──────────────────────────────────────

  /// Mix active: the server-canonical subcategory BUBBLES for the selected
  /// category sit immediately below the category selector (the dial), and
  /// the shared state-honest discovery feed fills the rest. The bottom
  /// clearance is the shell tab's live nav-band inset — never a guess.
  Widget _mixMode(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // WORKSTREAM H — the proximity strip: the one-glance answer to
        // "why am I seeing these results?" Rendered ONLY while the
        // proximity feed is live, showing REAL states only (resolving,
        // nearby results, nearby failure) and NEVER coordinates.
        if (_nearYouActive)
          const MixProximityStrip(key: ValueKey('mix_proximity_strip')),
        const MixTaxonomyBubbleRail(),
        // WORKSTREAM H — local-first rails: "Nearby for you" (real
        // distance-ordered results) ABOVE "From your network" (offers
        // from businesses the user actually follows on the server).
        // Real-data-only: a rail with nothing honest to show renders
        // nothing at all — no fabricated popularity, no guessed rows.
        if (_nearYouActive)
          MixLocalFirstRails(
            key: const ValueKey('mix_local_first_rails'),
            onOpenStore: _openMixStore,
          ),
        Expanded(
          key: const ValueKey('mix_inplace_feed'),
          child: MixFeedSurface(
            onOpenStore: _openMixStore,
            bottomPadding: navBandClearance(context) + kNavBandGap,
          ),
        ),
      ],
    );
  }

  // ── Store management sheet (replaces old FAB) ──────────────────────────────
  // The FAB was removed — store management now lives in the storefront
  // button in the header. See _showStoreManagementSheet().
  void _showStoreManagementSheet(AzamanColors colors) {
    final bizState = ref.read(myBusinessProvider);
    final isRegistered = bizState.profile != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Your Stores',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              if (isRegistered) ...[
                // Show existing store
                GestureDetector(
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    AzamanHaptics.nav();
                    // NEW-A: canonical business dashboard route.
                    context.push(AzRoutes.businessMarketDashboard);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.softSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.divider, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.accentSurface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: bizState.profile?.logoUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: AzamanNetworkImage(
                                    imageUrl: bizState.profile!.logoUrl!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(
                                  Icons.store_rounded,
                                  color: colors.accent,
                                  size: 22,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bizState.profile?.businessName ?? 'My Store',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tap to manage',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colors.textTertiary,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Add store button (always visible)
              GestureDetector(
                onTap: () {
                  Navigator.pop(sheetCtx);
                  AzamanHaptics.nav();
                  // NEW-A: canonical /business/register route.
                  context.push(AzRoutes.businessRegister);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.accentSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colors.accent.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: colors.isDark ? Colors.black : Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isRegistered
                            ? 'Add another store'
                            : 'Register your business',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── WORKSTREAM F1 — explicit story expansion (pin) ──────────────────────────

  /// The rail's EFFECTIVE open ratio: the scroll-driven shared collapse
  /// grammar, layered with the explicit pinned-open animation. The pin
  /// only ever OPENS the rail (max) — the scroll keeps its authority for
  /// every collapse that is not an explicit expansion.
  double _storyRailRatio(BuildContext context) {
    final scrollRatio = StoryRailCollapse.ratio(
      scrollOffset: _scrollOffset,
      reducedMotion: !AzMotion.of(context).travel,
    );
    return _storyPinCurve.value > scrollRatio
        ? _storyPinCurve.value
        : scrollRatio;
  }

  /// Expands the stories rail IN PLACE from the collapsed affordance.
  ///
  /// F1 contract: the page is NEVER scrolled to the top. The rail opens
  /// (explicit expansion state) and the results list scrolls DOWN by
  /// exactly the rail's growth on the same curve/duration, so the first
  /// visible results stay visually stationary while the rail slides in.
  /// Reduced motion lands directly, per the shared rail grammar.
  void _pinStoriesOpen(BuildContext context) {
    if (_storyPinHeld || _storyPinCtrl.value >= 1) return;
    _storyPinHeld = true;
    final reduced = !AzMotion.of(context).travel;
    if (!reduced) {
      _storyPinCtrl.forward(from: 0);
    }
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    // Compensate only the rail's REMAINING growth: tapping mid-collapse
    // (partial ratio) grows the rail by the unfilled part, and the list
    // scrolls by exactly that — the anchor is preserved at every tap
    // point, not just from fully collapsed.
    final growth = StoryRailCollapse.extentPx * (1 - _storyRailRatio(context));
    final target = (pos.pixels + growth).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if (reduced) {
      _storyPinCtrl.value = 1.0;
      pos.jumpTo(target);
    } else {
      _scrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Header (title + actions) ────────────────────────────────────────────────

  Widget _header(AzamanColors colors) {
    // CORRECTION I: the search affordance no longer lives in this screen —
    // the focused Marketplace nav band owns the search field, bound to the
    // AUTHORITATIVE provider. The header keeps the story avatars slot, the
    // storefront management, order history, and the list/map view toggle.
    final storyExpandRatio = _storyRailRatio(context);
    final storyCollapsedOpacity = (1.0 - storyExpandRatio).clamp(0.0, 1.0);

    // Review A1 — the collapsed story affordance now renders with the
    // CompactStoryRail's OWN AzSpace.xl (20) horizontal padding, exactly
    // like the chat strip. The header row therefore contributes NO
    // leading padding: 0 (parent) + 20 (component) = 20, the same
    // effective ring offset as chat's full-width strip. The trailing 12
    // stays for the action icons; the rail's own trailing padding keeps
    // the chevron 20dp inside the affordance's right edge, mirroring
    // chat's chevron geometry.
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Collapsed avatars fade in as stories section collapses.
          if (storyCollapsedOpacity > 0.5)
            Expanded(
              child: MarketplaceCollapsedAvatars(
                // WORKSTREAM F1 — expand IN PLACE; the feed NEVER gets
                // dragged back to the top.
                onTap: () => _pinStoriesOpen(context),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 8),

          // Store management — shows your stores + add button
          _iconAction(
            icon: Icons.storefront_rounded,
            onTap: () => _showStoreManagementSheet(colors),
            colors: colors,
            activeColor: colors.accent,
          ),
          const SizedBox(width: 8),

          // My Orders
          _iconAction(
            icon: Icons.receipt_long_rounded,
            // NEW-A: canonical /my-orders location.
            onTap: () => context.push(AzRoutes.storefrontOrderHistory),
            colors: colors,
            activeColor: colors.accent,
          ),
          const SizedBox(width: 8),

          // View mode toggle (list / map)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: colors.divider, width: 0.5),
            ),
            child: Row(
              children: [
                _viewSeg(Icons.view_agenda_outlined, _ViewMode.list, colors),
                _viewSeg(Icons.location_on_outlined, _ViewMode.map, colors),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewSeg(IconData icon, _ViewMode mode, AzamanColors colors) {
    final active = _viewMode == mode;
    return ScaleTap(
      onTap: () => _setViewMode(mode),
      child: Container(
        width: 34,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? colors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 16,
          color: active
              ? (colors.isDark ? Colors.black : Colors.white)
              : colors.textSecondary,
        ),
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required VoidCallback onTap,
    required AzamanColors colors,
    Color? activeColor,
  }) {
    return ScaleTap(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.divider, width: 0.5),
        ),
        child: Icon(icon, size: 20, color: activeColor ?? colors.textSecondary),
      ),
    );
  }

  // UX-CORRECTION §1 — the category set is EXACTLY All / Shop / Ride /
  // Stay / Eat (All is a REAL selectable state, wire null, and the
  // default). Services and Wellness are removed: no other user-facing
  // satellite exists.
  /// The category dial. Colour comes from the SHARED card palettes through
  /// the fixed vertical mapping (Shop->azadark, Stay->azablue, Eat->azagreen,
  /// Ride->azared) in lib/theme/balance_card_brand.dart — one palette system
  /// for the card and the Marketplace, never two disconnected colour tables.
  ///
  /// Resolved per brightness because a solid pill has to read on both the
  /// light canvas and the near-black one; the mapping itself is fixed and
  /// never consults the user's applied balance card.
  List<CategoryDialItem> _dialCategoriesFor(bool isDark) {
    Color accentFor(MarketplaceVertical v) =>
        verticalAccentFor(v, isDark).accent;
    return [
      // "All" stays the quiet neutral pill — it is a real selectable state.
      const CategoryDialItem(
        wire: null,
        icon: Icons.apps_rounded,
        label: 'All',
      ),
      CategoryDialItem(
        wire: 'FOOD_BEVERAGE',
        icon: Icons.restaurant_rounded,
        label: 'Eat',
        accent: accentFor(MarketplaceVertical.eat),
      ),
      CategoryDialItem(
        wire: 'RETAIL',
        icon: Icons.shopping_bag_rounded,
        label: 'Shop',
        accent: accentFor(MarketplaceVertical.shop),
      ),
      CategoryDialItem(
        wire: 'LOGISTICS',
        icon: Icons.directions_bus_rounded,
        label: 'Ride',
        accent: accentFor(MarketplaceVertical.ride),
      ),
      CategoryDialItem(
        wire: 'REAL_ESTATE',
        icon: Icons.apartment_rounded,
        label: 'Stay',
        accent: accentFor(MarketplaceVertical.stay),
      ),
    ];
  }

  // EXPERIENCE PASS §11 — the category SPEED DIAL is THE category system.
  // The radial fan / goo-morph arms remain the visual grammar; the old row
  // of standalone category buttons (correction H) is gone — the spec
  // explicitly rejects a second flat control row. Near You stays as the
  // ONLY additional control, with a location icon in the same visual
  // language, driving the existing near-you map machinery.
  Widget _controlRow(AzamanColors colors) {
    // G2 — the pill reads the PROXIMITY FEED state, never the view mode.
    final nearYou = _nearYouActive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      // MARKETPLACE MIX overflow fix (rebase audit): the Mix entry pill made
      // the row's natural width exceed phone content widths (16px over at
      // 360dp). The strip stays PIXEL-IDENTICAL whenever the row fits —
      // ConstrainedBox minWidth stretches the row to the full available
      // width, so the dial/Mix/Near-You grammar is unchanged — and only
      // when the controls would overflow does it become horizontally
      // scrollable (every control stays reachable; nothing is dropped or
      // shrunk).
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              // spaceBetween (NOT a flex Spacer — a Spacer is illegal in a
              // horizontal scrollable's unbounded width) keeps the dial+Mix
              // cluster at the left edge and Near You pinned to the right
              // edge exactly as the old Spacer did whenever the strip fits.
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // UX-CORRECTION: the dial is COMPACT — intrinsic pill width, no
                  // Expanded stretch. The radial fan anchors to the pill's real
                  // box; a stretched slot made the whole empty row-width part of
                  // the anchor (and the fan fanned off a rect the eye doesn't
                  // see). The dial and the Mix pill form the LEFT cluster that
                  // spaceBetween pins to the row's leading edge.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CategorySpeedDial(
                        key: const ValueKey('marketplace-category-dial'),
                        categories: _dialCategoriesFor(colors.isDark),
                        selectedWire: _selectedCategory,
                        colors: colors,
                        onSelected: (wire) async {
                          AzamanHaptics.toggle();
                          setState(() => _selectedCategory = wire);
                          if (_mixActive) {
                            // Inside Mix the dial is the CATEGORY SELECTOR: translate
                            // through the ONE dial↔discovery boundary (the dial's
                            // REAL_ESTATE "Stay" is the discovery endpoint's
                            // HOSPITALITY; the mismatch can never build an invalid
                            // query and never silently defaults to Eat).
                            await ref
                                .read(marketplaceMixProvider.notifier)
                                .selectCategory(
                                  MixDialCategoryBoundary.dialToMix(wire),
                                );
                            // WORKSTREAM H: while Mix co-activated the
                            // proximity feed, the dial is BOTH feeds'
                            // category selector — the nearby search
                            // re-fires with the same wire, so the rails
                            // and the discovery feed never disagree.
                            if (_nearYouActive) _fireNearby();
                          } else {
                            _fireSearch();
                          }
                        },
                      ),
                      // 2026-10-20: the faint vertical divider separates the
                      // CATEGORY DIAL from the MIX CONTROL — it no longer
                      // lives inside the Mix pill between its die and label.
                      // One 1px rule + 8px breathing space on each side:
                      // the cluster stays usable at 320dp without clipping.
                      const SizedBox(width: 8),
                      Container(
                        key: const ValueKey('marketplace-dial-mix-divider'),
                        width: 1,
                        height: 18,
                        color: colors.divider.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 8),
                      // MARKETPLACE MIX — the in-place cross-store mode. The button
                      // TOGGLES the mode inside this screen (no route is pushed); the
                      // custom-painted isometric die is its mark, separated from the
                      // label by a faint vertical divider with breathing space around
                      // it. Same control-row grammar as Near You — additive slot, no
                      // other control moves.
                      GestureDetector(
                        key: const ValueKey('marketplace-mix-entry'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleMixMode,
                        // Whole-button pressed feedback: the entire pill
                        // (die + label together) dips on pointer-down and
                        // springs back — visual only; nothing commits
                        // before the completed tap.
                        onTapDown: (_) =>
                            setState(() => _mixEntryPressed = true),
                        onTapUp: (_) =>
                            setState(() => _mixEntryPressed = false),
                        onTapCancel: () =>
                            setState(() => _mixEntryPressed = false),
                        child: AnimatedScale(
                          scale: _mixEntryPressed ? 0.96 : 1.0,
                          duration: const Duration(milliseconds: 110),
                          curve: Curves.easeOutCubic,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: _mixActive
                                  ? colors.accent.withValues(alpha: 0.12)
                                  : colors.card,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _mixActive
                                    ? colors.accent
                                    : colors.divider,
                                width: _mixActive ? 1.2 : 0.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // The die: breathing space around it, then
                                // the label. (The vertical divider used to
                                // sit here, inside the pill — it now separates
                                // the dial from this control.)
                                Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: MixDie(active: _mixActive),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  'Mix',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _mixActive
                                        ? colors.accent
                                        : colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 2026-10-06 VISUAL PASS — Near You moves to the FAR END of the
                  // control row: it reads as the secondary location/filter
                  // utility, visually belonging to the row's end rather than to the
                  // category fan. The dial is NOT stretched to force the
                  // alignment; spaceBetween takes the free row width between the
                  // clusters (a flex Spacer is illegal inside a horizontal
                  // scrollable, where the strip can exceed the viewport).
                  // Near You — the ONLY control outside the category selector
                  // (location icon, same pill language). Toggling off returns to
                  // the list view.
                  GestureDetector(
                    key: const ValueKey('marketplace-near-you'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleNearYou,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: nearYou
                            ? colors.accent.withValues(alpha: 0.12)
                            : colors.card,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: nearYou ? colors.accent : colors.divider,
                          width: nearYou ? 1.2 : 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.near_me_rounded,
                            size: 14,
                            color: nearYou
                                ? colors.accent
                                : colors.textTertiary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Near You',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: nearYou
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: nearYou
                                  ? colors.accent
                                  : colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Opens the story viewer for a business's stories (not their profile).
  ///
  /// Real rail: GET /api/marketplace/business/:id/stories (the only backend
  /// route that serves business stories). The former stories fetch used a
  /// dead path — that route never existed on the backend, so every
  /// production tap silently fell back to the profile. Demo mode serves the
  /// same production shape from the seeded marketplace stories.
  Future<void> _openBusinessStories(BuildContext context, String bizId) async {
    try {
      final stories = await ref
          .read(marketplaceBookingServiceProvider)
          .getBusinessStories(bizId);
      final groups = stories.isEmpty
          ? <StoryGroup>[]
          : [storyGroupFromBusinessStories(stories)];
      if (groups.isNotEmpty && context.mounted) {
        await StoryViewerScreen.open(
          context,
          groups: groups,
          initialGroupIndex: 0,
          heroTag: 'marketplace-story-ring-$bizId',
        );
      } else if (context.mounted) {
        context.push('/business/$bizId');
      }
    } catch (_) {
      if (context.mounted) {
        context.push('/business/$bizId');
      }
    }
  }

  String _categoryLabel(String? cat) {
    switch (cat) {
      case 'FOOD_BEVERAGE':
        return 'restaurants';
      case 'REAL_ESTATE':
        return 'hotels & stays';
      case 'LOGISTICS':
        return 'transit services';
      case 'RETAIL':
        return 'retail shops';
      case 'FREELANCE_SERVICES':
        return 'service providers';
      case 'HEALTH_WELLNESS':
        return 'beauty & wellness';
      default:
        return 'businesses';
    }
  }

  // ── Results bar (slim control row) ─────────────────────────────────────────

  // ── Real map mode (§1) ─────────────────────────────────────────────────────

  void _showBusinessPreviewSheet(BusinessLocation loc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => FutureBuilder(
        future: BusinessService().getBusinessByBizId(
          loc.bizId ?? loc.businessProfileId,
        ),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final business = snap.data;
          if (business == null) {
            return Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text('Business not found'),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Consumer(
              builder: (ctx2, ref, _) {
                final colors = ref.watch(themeProvider).colors;
                return Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: BusinessResultCard(
                    key: const ValueKey('map-preview-\${loc.id}'),
                    business: business,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _recenterButton(AzamanColors colors) {
    return GestureDetector(
      onTap: () {
        if (_position != null && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(_position!.latitude, _position!.longitude),
            ),
          );
        }
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(Icons.my_location_rounded, color: colors.accent, size: 22),
      ),
    );
  }

  static const _darkMapStyleJson = r'''
  [
    {"elementType":"geometry","stylers":[{"color":"#1a1a2e"}]},
    {"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
    {"elementType":"labels.text.stroke","stylers":[{"color":"#000000"}]},
    {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2a2a3e"}]},
    {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9a9a9a"}]},
    {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0d1b2a"}]},
    {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#1e1e30"}]},
    {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2a2a3e"}]}
  ]
  ''';

  // ── Near You proximity feed (G2) ───────────────────────────────────────────

  /// The distance-ordered proximity list. Server-ordered by distance
  /// (haversine, 0.1 km rounding) — the client NEVER re-sorts it, so the
  /// list and the map markers can never disagree. Failure and emptiness
  /// are distinct truthful states, exactly like the search list.
  Widget _nearYouList(AzamanColors colors) {
    final state = ref.watch(nearbySearchProvider);

    if (state.isLoading && state.locations.isEmpty) {
      return _listShimmer(colors);
    }

    if (state.error != null && state.locations.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 60),
          AzamanEmptyState(
            key: const Key('marketplace-nearby-failure'),
            icon: Icons.wifi_off_outlined,
            title: 'Couldn\'t load nearby businesses',
            subtitle: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: _fireNearby,
          ),
        ],
      );
    }

    if (state.locations.isEmpty) {
      // A failed location resolve is its OWN truthful state — not "no
      // businesses" and not a search failure. The neighborhood was never
      // queried because there is no origin to measure from.
      if (_locationError != null && !_resolvingLocation) {
        return ListView(
          children: [
            const SizedBox(height: 60),
            AzamanEmptyState(
              key: const Key('marketplace-nearby-location-error'),
              icon: Icons.location_disabled_outlined,
              title: 'Location unavailable',
              subtitle:
                  'Turn on location services or grant permission to see '
                  'what\'s around you.',
              actionLabel: 'Retry',
              onAction: _resolveLocation,
            ),
          ],
        );
      }
      if (_resolvingLocation) return _listShimmer(colors);
      return ListView(
        children: [
          const SizedBox(height: 60),
          AzamanEmptyState(
            key: const Key('marketplace-nearby-empty'),
            icon: Icons.near_me_outlined,
            title: 'No businesses nearby yet',
            subtitle: _selectedCategory != null
                ? 'No ${_categoryLabel(_selectedCategory)} within range — '
                      'try another category or clear filters.'
                : 'Nothing within your range right now. Try again later.',
          ),
        ],
      );
    }

    return ListView.builder(
      key: const ValueKey('marketplace_nearby_results_list'),
      controller: _scrollCtrl,
      padding: EdgeInsets.fromLTRB(
        8,
        6,
        8,
        navBandClearance(context) + kNavBandGap,
      ),
      itemCount: state.locations.length + (state.hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i >= state.locations.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final loc = state.locations[i];
        return NearbyBusinessRow(
              location: loc,
              onTap: () {
                final bizId = loc.bizId ?? loc.businessProfileId;
                if (bizId.isEmpty) return; // nothing to open — never guess
                context.push(AzRoutes.businessProfile(bizId));
              },
            )
            .animate()
            .fadeIn(delay: (i * 50).ms, duration: 250.ms)
            .move(
              begin: const Offset(0, 8),
              end: const Offset(0, 0),
              duration: 220.ms,
            );
      },
    );
  }

  // ── List mode ──────────────────────────────────────────────────────────────

  Widget _listMode(AzamanColors colors) {
    // G2 — Near You owns the LIST while active: the distance-ordered
    // proximity feed, an entirely separate provider from the search list.
    if (_nearYouActive) return _nearYouList(colors);

    final state = ref.watch(businessSearchProvider);

    if (state.isLoading) return _listShimmer(colors);

    // TRUTHFUL FAILURE (Workstream F): a DEAD search request is never
    // "No businesses found" — an empty result and a failed request are
    // different facts; the failure gets its own state and a real retry.
    if (state.error != null && state.results.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 60),
          AzamanEmptyState(
            key: const Key('marketplace-search-failure'),
            icon: Icons.wifi_off_outlined,
            title: 'Couldn\'t load businesses',
            subtitle: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: _fireSearch,
          ),
        ],
      );
    }

    final results = _applySortFilter(state.results);

    if (results.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  child: LottieBuilder.asset(
                    'assets/animations/success.json',
                    width: 120,
                    height: 120,
                    repeat: false,
                  ),
                ).animate().scale(
                  begin: const Offset(0.8, 0.8),
                  end: const Offset(1, 1),
                  duration: 400.ms,
                  curve: Curves.easeOutBack,
                ),
                const SizedBox(height: 12),
                Text(
                  'No businesses found',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _query.isNotEmpty
                      ? 'Try a different search term or category'
                      : _selectedCategory != null
                      ? 'No ${_categoryLabel(_selectedCategory)} yet — be the first!'
                      : 'Be the first to register here',
                  style: TextStyle(fontSize: 13, color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      key: const ValueKey('marketplace_results_list'),
      controller: _scrollCtrl,
      // Persistent-nav occlusion fix: the bottom inset is the LIVE band
      // height the shell publishes (navBandClearance) — not a magic 120
      // that could under/over-pad per device — plus breathing room.
      padding: EdgeInsets.fromLTRB(
        8,
        6,
        8,
        navBandClearance(context) + kNavBandGap,
      ),
      // REVIEW §5 — the tail sentinel renders while more pages exist OR a
      // later-page fetch failed (the inline retry replaces the spinner).
      itemCount:
          results.length +
          ((state.hasMore || state.loadMoreError != null) ? 1 : 0),
      itemBuilder: (ctx, i) {
        // Tail sentinel: inline accessible retry when a later-page fetch
        // failed; the infinite-scroll spinner while a page is in flight.
        if (i >= results.length) {
          if (state.loadMoreError != null) {
            return Semantics(
              label: 'Couldn\'t load more businesses. Retry.',
              button: true,
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: TextButton.icon(
                    key: const Key('marketplace-load-more-retry'),
                    onPressed: () =>
                        ref.read(businessSearchProvider.notifier).loadMore(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Couldn\'t load more — retry'),
                  ),
                ),
              ),
            );
          }
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final b = results[i];
        return BusinessResultCard(
              key: ValueKey(b.bizId),
              business: b,
              distanceKm: b.locations.isNotEmpty
                  ? b.locations.first.distanceKm
                  : null,
            )
            .animate()
            .fadeIn(
              delay: (i * 50).ms,
              duration: 300.ms,
              curve: Curves.easeOutCubic,
            )
            .slideY(
              begin: 0.15,
              end: 0,
              delay: (i * 50).ms,
              duration: 300.ms,
              curve: Curves.easeOutCubic,
            );
      },
    );
  }

  // ── LIST shimmer ────────────────────────────────────────────────────────────

  Widget _listShimmer(AzamanColors colors) {
    return Shimmer.fromColors(
      baseColor: colors.card,
      highlightColor: colors.softSurface,
      child: ListView.builder(
        key: const ValueKey('marketplace_shimmer_list'),
        // Occlusion fix: the loading list is a scrollable under the
        // persistent band too — the old hardcoded 60 left the last
        // skeleton rows painting behind the pill on devices where the
        // band's published inset is larger. Same live clearance as the
        // results list, plus the same breathing room.
        padding: EdgeInsets.fromLTRB(
          8,
          6,
          8,
          navBandClearance(context) + kNavBandGap,
        ),
        itemCount: 8,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          height: 68,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.divider, width: 0.5),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 13, width: 160, color: colors.divider),
                    const SizedBox(height: 7),
                    Container(height: 10, width: 100, color: colors.divider),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── MAP mode (unchanged from previous version) ─────────────────────────────

  Widget _mapMode(AzamanColors colors) {
    final state = ref.watch(nearbySearchProvider);

    if (_position == null) return _locationPrompt(colors);

    if (state.isLoading) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SkeletonBlock(
              width: double.infinity,
              height: 120,
              borderRadius: BorderRadius.circular(16),
            ),
            const SizedBox(height: 12),
            SkeletonBlock(
              width: double.infinity,
              height: 80,
              borderRadius: BorderRadius.circular(12),
            ),
            const SizedBox(height: 12),
            ...List.generate(
              3,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SkeletonBlock(
                  width: double.infinity,
                  height: 56,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final locations = state.locations;
    // TRUTHFUL FAILURE (Workstream E): a failed nearby search is a FAILURE,
    // never "No businesses nearby" — an empty result and a dead request are
    // different facts; NearbyOutcome decides the two in ONE place.
    if (locations.isEmpty) {
      return NearbyOutcome(error: state.error, onRetry: _fireNearby);
    }

    // §1: Real embedded GoogleMap instead of a list view
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(_position!.latitude, _position!.longitude),
            zoom: 14,
          ),
          markers: markersFromSpecs(
            buildNearbyMarkerSpecs(locations),
            onTap: (spec) {
              final loc = locations.firstWhere(
                (l) => l.id == spec.id,
                orElse: () => locations.first,
              );
              _showBusinessPreviewSheet(loc);
            },
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          onMapCreated: (controller) => _mapController = controller,
          style: colors.isDark ? _darkMapStyleJson : null,
        ),
        Positioned(
          right: 16,
          // Occlusion fix: this Expanded area ends BEHIND the persistent
          // band (the page is the Marketplace root tab under extendBody),
          // so a fixed 16 sat the button under the pill. Anchor it to the
          // live band clearance instead.
          bottom: navBandClearance(context) + kNavBandGap,
          child: _recenterButton(colors),
        ),
      ],
    );
  }

  Widget _locationPrompt(AzamanColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_on_outlined,
                size: 36,
                color: colors.accent,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Find businesses near you',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _locationError ??
                  'Share your location to see nearby businesses with distances.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _resolveLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.isDark ? Colors.black : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _resolvingLocation
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.isDark ? Colors.black : Colors.white,
                      ),
                    )
                  : const Icon(Icons.location_on_outlined, size: 18),
              label: Text(
                _resolvingLocation ? 'Locating...' : 'Use my location',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ── Portal world card (2026-09-30) ───────────────────────────────────────────

/// Immutable view-model for one portal world: the category identity plus a
/// truthful count and preview derived from the loaded search state.
