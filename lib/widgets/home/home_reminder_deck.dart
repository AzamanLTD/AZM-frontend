// =============================================================================
// AZAMAN — HOME REMINDER DECK  (experience pass §4 + §5, fan/fill pass)
//
// §4 — REAL SIGNALS FIRST. A compact, premium reminder deck sitting
// immediately above Recent Activity. Cards are derived from existing
// providers (susuListProvider, marketplaceResumeProvider,
// marketplaceRelevanceProvider) — no new backend requests, no fabricated
// personalisation. Card copy never claims something the data does not say.
//
// FAN PASS (owner direction, 2026-10-05/06): the deck reads as an actual
// deck of cards, never a straight stack —
//   * the front card rests with a GENTLE tilt (~1.7°): readable, but the
//     stack never looks rigid ("I don't want it to look too straight")
//   * up to TWO cards peek out above it, each tilted AWAY from its
//     neighbour (alternating signs, deeper with depth) with a small
//     horizontal stagger and slight scale reduction — a spread hand
//   * the PAGINATION DOTS stay the honest card-count indicator: one dot
//     per real card, the active dot following the front
//
// FILL PASS (owner direction, 2026-10-05): Home measures the empty band
// between the wallet modules and the Recent Activity doorway and hands
// the deck a target [height]; the deck FILLS the band instead of a thin
// strip floating in dead space. Capped (bandCap 344) so tablets and
// rotations stay sane; without a height (tests, other hosts) the deck
// uses its natural geometry.
//
// PLACEHOLDER PASS (owner direction, 2026-10-05): the slot is never
// blank. With no real signal a new user sees the static placeholder —
// 'Your reminders will appear here', no chevron, nothing draggable —
// with the same fanned geometry dimmed behind it, so the deck's shape
// reads before the first signal arrives. Demo builds seed from the
// app's demo data instead (DemoGuard-gated, never in a real build).
//
// §5 — SHUFFLE, NOT DELETE. The front card is horizontally swipeable
// along ONE coherent controller-driven trajectory: it follows the
// finger, acquires a restrained directional rotation, arcs away on
// commit and drops BEHIND the deck mid-flight while the promoted card
// glides out of the fan into the front slot (straightening into the
// front's resting tilt, scale one, full opacity). No Timer sequencing.
//
// Reduced motion: no expressive travel — instant reorder/settle with
// the same information hierarchy. Accessibility: a custom semantics
// action advances the deck without a swipe; each card is its own
// tappable destination.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, SemanticsProperties;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/experience/demo/demo_guard.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/marketplace_relevance_provider.dart';
import 'package:azaman/providers/marketplace_resume_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/theme/az_elevation.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/scale_tap.dart';
import 'package:azaman/widgets/home/home_deck_separator.dart';

/// A single reminder card's honest content + its destination. `onTap` is
/// null for the placeholder — it is informational, not a destination.
class HomeReminderCardData {
  final String id;
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const HomeReminderCardData({
    required this.id,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });
}

/// The deck. Real signals render as the fanned, swipeable deck; a
/// signal-less production build renders the honest PLACEHOLDER (the
/// slot is never blank); a demo build seeds from the demo data.
class HomeReminderDeck extends ConsumerStatefulWidget {
  /// The measured FILL height (owner direction, 2026-10-05): Home hands
  /// the deck the empty band between the wallet modules and the Recent
  /// Activity doorway so the deck FILLS the composition. Null (tests,
  /// other hosts) = the natural geometry. Clamped to
  /// [naturalBand, bandCap] so nothing ever renders absurd.
  const HomeReminderDeck({super.key, this.height});

  final double? height;

  /// The deck's natural band height: a fully readable card + the fan
  /// peek above it + the pagination dots below. Exposed so Home can
  /// compute the fill from the same single source of truth.
  static const double naturalBand = 150;

  /// The fill ceiling (owner direction): beyond this the leftover band
  /// stays as breathing room — low in the composition IS the design
  /// there, and a spacer that grew unbounded would be the same
  /// fake-SizedBox mistake the contract forbids.
  static const double bandCap = 344;

  @override
  ConsumerState<HomeReminderDeck> createState() => _HomeReminderDeckState();
}

class _HomeReminderDeckState extends ConsumerState<HomeReminderDeck>
    with SingleTickerProviderStateMixin {
  // Deck order: [_front] is the list index currently at the front. A
  // committed swipe rotates the order by one.
  int _front = 0;
  int? _frontIdHash;

  // §5 — one coherent trajectory. The SAME controller drives either the
  // committed flight (card arcs out behind the deck) or the settle (drag
  // under threshold returns home). Never Timer-based sequencing.
  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: MotionTokens.spatial,
  );
  _TravelKind _travelKind = _TravelKind.none;

  // Drag + flight snapshot state.
  double _dragDx = 0;
  double _flightFromDx = 0;
  double _flightDirection = 1;

  // Cached per build (inherited lookups stay inside build).
  bool _travelAllowed = true;

  static const _commitDx = 92.0;
  static const _commitVelocity = 700.0;

  // ── FILL geometry (one source of truth: _DeckGeometry) ───────────────

  /// The whole deck band this build renders: the measured fill clamped
  /// to the honest range, or the natural height.
  double get _bandH => (widget.height ?? _DeckGeometry.naturalBand).clamp(
    _DeckGeometry.naturalBand,
    HomeReminderDeck.bandCap,
  );

  /// The fanned cards rise this far above the front card's top edge —
  /// and deepen a little when the deck fills, so the spread reads at
  /// the taller scale.
  double get _fan => _DeckGeometry.fanFor(_bandH);

  /// The card face height: the band minus the fan peek above and the
  /// dot rail below.
  double get _cardH =>
      _bandH - _fan - _DeckGeometry.dotsGap - _DeckGeometry.dotsHeight;

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  // ── §4 data: existing signals only ──────────────────────────────────────

  List<HomeReminderCardData> _realCards() {
    final list = <HomeReminderCardData>[];

    // 1. The soonest pending Susu cycle across the caller's ACTIVE Susus.
    final mine =
        ref.watch(susuListProvider).valueOrNull ?? const <SusuSummary>[];
    SusuSummary? due;
    for (final s in mine) {
      if (s.status != SusuStatus.active) continue;
      final c = s.nextCycle;
      if (c == null) continue;
      final best = due?.nextCycle?.scheduledRunAt;
      if (best == null || best.isAfter(c.scheduledRunAt)) due = s;
    }
    if (due != null) {
      final cycle = due.nextCycle!;
      final dueGroup = due;
      final when =
          '${_months[cycle.scheduledRunAt.month - 1]} ${cycle.scheduledRunAt.day}';
      list.add(
        HomeReminderCardData(
          id: 'susu-${dueGroup.id}',
          eyebrow: 'SUSU',
          title: cycle.isMe
              ? 'Your payout cycle runs $when'
              : 'Susu contribution due $when',
          subtitle: dueGroup.name,
          icon: HugeIconsSolid.wallet01,
          onTap: () => context.push('/susu/${dueGroup.id}'),
        ),
      );
    }

    // 2. The marketplace resume intent — a live cart, or a fresh world
    //    memory of what they were browsing. Both are real signals; the
    //    intent provider already guarantees freshness and honesty.
    final intent = ref.watch(marketplaceResumeProvider);
    if (intent != null) {
      final isCart = intent.kind == ResumeKind.cart;
      list.add(
        HomeReminderCardData(
          id: 'resume-${intent.worldWire ?? intent.businessProfileId ?? 'cart'}',
          eyebrow: 'MARKETPLACE',
          title: intent.title,
          subtitle: intent.subtitle,
          icon: isCart ? HugeIconsSolid.shoppingCart01 : HugeIconsSolid.store01,
          onTap: () => context.push(
            intent.kind == ResumeKind.cart
                ? AzRoutes.cart
                : AzRoutes.marketplace,
          ),
        ),
      );
    }

    // 3. Marketplace relevance — a REAL store in the category they most
    //    recently visited (world memory + existing discovery data, both
    //    already real). Suppressed when the resume card above already
    //    speaks for the same world: one memory, one card, never two.
    final relevance = ref.watch(marketplaceRelevanceProvider);
    if (relevance != null && intent?.worldWire != relevance.worldWire) {
      list.add(
        HomeReminderCardData(
          id: 'relevance-${relevance.business.id}',
          eyebrow: 'MARKETPLACE',
          title: relevance.business.businessName,
          subtitle: 'Relevant in ${relevance.categoryLabel}',
          icon: HugeIconsSolid.store01,
          onTap: () => context.push(
            AzRoutes.storefront(
              relevance.business.id,
              name: relevance.business.businessName,
            ),
          ),
        ),
      );
    }
    return list;
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  // ── DEMO SEEDS (§4 honesty preserved: DemoGuard-gated) ──────────────────
  //
  // Demo mode exists to demo. When the demo build carries no live signal
  // (no susu cycle in the seed, nothing browsed yet), the deck seeds from
  // the SAME demo data the rest of the app serves — the seeded susu group
  // and the seeded marketplace businesses — so the Home reads lived-in.
  // DemoGuard.enabled is false in every real build, so a real user can
  // never see a seeded card.
  List<HomeReminderCardData> _demoCards() => [
    HomeReminderCardData(
      id: 'demo-susu-susu-1',
      eyebrow: 'SUSU',
      title: 'Susu Circle - August',
      subtitle: 'Monthly rotation · Next payout in 7 days',
      icon: HugeIconsSolid.userGroup,
      onTap: () => context.push('/susu/susu-1'),
    ),
    HomeReminderCardData(
      id: 'demo-store-chef-abby',
      eyebrow: 'MARKETPLACE',
      title: "Chef Abby's",
      subtitle: 'Restaurants in the Marketplace',
      icon: HugeIconsSolid.store01,
      onTap: () => context.push(AzRoutes.marketplace),
    ),
    HomeReminderCardData(
      id: 'demo-store-coastline',
      eyebrow: 'MARKETPLACE',
      title: 'Coastline Suites',
      subtitle: 'Hotels in the Marketplace',
      icon: HugeIconsSolid.building01,
      onTap: () => context.push(AzRoutes.marketplace),
    ),
  ];

  // ── §5 trajectory ───────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails d) {
    if (_travel.isAnimating) return;
    setState(() => _dragDx += d.delta.dx);
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final committed =
        _dragDx.abs() > _commitDx || velocity.abs() > _commitVelocity;
    if (committed) {
      AzamanHaptics.confirm();
      if (!_travelAllowed) {
        // Reduced motion: instant reorder/settle, same hierarchy.
        setState(() {
          _advanceOrder(_cards().length);
          _dragDx = 0;
        });
        return;
      }
      setState(() {
        _flightFromDx = _dragDx;
        _flightDirection = _dragDx != 0
            ? _dragDx.sign.toDouble()
            : (velocity != 0 ? velocity.sign.toDouble() : 1.0);
        _travelKind = _TravelKind.flight;
        _travel.forward(from: 0);
      });
    } else {
      if (!_travelAllowed) {
        setState(() => _dragDx = 0);
        return;
      }
      setState(() {
        _travelKind = _TravelKind.settle;
        _travel.forward(from: 0);
      });
    }
  }

  void _advanceOrder(int n) {
    if (n > 0) _front = (_front + 1) % n;
  }

  /// Accessibility: the semantic equivalent of a committed swipe.
  void _advance() {
    AzamanHaptics.confirm();
    setState(() => _advanceOrder(_cards().length));
  }

  /// The deck's card list: real signals, demo seeds in a demo build with
  /// none, or empty (front becomes the placeholder).
  List<HomeReminderCardData> _cards() {
    final real = _realCards();
    if (real.isNotEmpty) return real;
    if (DemoGuard.enabled) return _demoCards();
    return const <HomeReminderCardData>[];
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards();
    _travelAllowed = AzMotion.of(context).travel;

    // PLACEHOLDER PASS — the slot is never blank (owner direction,
    // 2026-10-05): with no signal and no demo seeds the deck renders
    // the honest static placeholder at the same geometry, never a
    // collapse-to-nothing and never fabricated content. Nothing drags,
    // nothing shuffles — a new user has nothing to shuffle yet.
    if (cards.isEmpty) {
      final colors = ref.watch(themeProvider).colors;
      return Semantics.fromProperties(
        properties: const SemanticsProperties(label: 'Reminders'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HomeDeckSeparator(colors: colors),
            SizedBox(
              key: const ValueKey('reminder-deck-placeholder'),
              height: _bandH,
              child: _PlaceholderDeck(colors: colors, cardH: _cardH, fan: _fan),
            ),
          ],
        ),
      );
    }

    // Keep the front index honest across data changes.
    final idHash = Object.hashAll(cards.map((c) => c.id));
    if (_frontIdHash != idHash) {
      _frontIdHash = idHash;
      _front = cards.isEmpty ? 0 : _front % cards.length;
    }

    final swipable = cards.length > 1;

    // fromProperties keeps the custom action readable at the widget level
    // (the plain Semantics constructor folds it into a private config).
    return Semantics.fromProperties(
      properties: SemanticsProperties(
        label: 'Reminders',
        customSemanticsActions: swipable
            ? {const CustomSemanticsAction(label: 'Next reminder'): _advance}
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The small premium section separator immediately above the
          // deck — kept from the PR #142 visual pass (review-protected).
          HomeDeckSeparator(colors: ref.watch(themeProvider).colors),
          SizedBox(
            height: _bandH,
            child: AnimatedBuilder(
              animation: _travel,
              builder: (context, _) =>
                  _buildStack(context, cards, swipable, _travel.value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStack(
    BuildContext context,
    List<HomeReminderCardData> cards,
    bool swipable,
    double t,
  ) {
    final colors = ref.watch(themeProvider).colors;
    final n = cards.length;
    final children = <Widget>[];

    // FAN PASS — the cards behind the front peek out above it, each
    // tilted AWAY from its neighbour, so the stack reads as a spread
    // hand of cards. At most two peek: the rest of the order stays
    // virtual (never a fan of stale ghosts). During a committed flight
    // the whole visible fan CHAIN-PROMOTES: each card glides into the
    // slot in front of it, straightening as it arrives, so the promoted
    // card is fully readable the moment the old front leaves.
    final maxDepth = math.min(n - 1, 2);
    final settle = _travelKind == _TravelKind.flight
        ? Curves.easeOutCubic.transform(t.clamp(0.0, 1.0))
        : 0.0;
    for (var depth = maxDepth; depth >= 1; depth--) {
      final from = _DeckGeometry.fan(depth, _fan);
      final to = _DeckGeometry.fan(depth - 1, _fan);
      final g = _DeckGeometry.lerp(from, to, settle);
      final card = cards[(_front + depth) % n];
      children.add(
        Positioned(
          top: g.top,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: _lerp(from.opacity, to.opacity, settle),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translateByDouble(g.dx, 0, 0, 1.0)
                  ..scaleByDouble(g.scale, 1, 1, 1)
                  ..rotateZ(g.rotate),
                child: _ReminderCardFace(
                  card: card,
                  colors: colors,
                  height: _cardH,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final frontData = cards[_front];
    final front = Positioned(
      top: _fan,
      left: 0,
      right: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: swipable ? _onDragUpdate : null,
        onHorizontalDragEnd: swipable ? _onDragEnd : null,
        child: _frontTransformed(
          _ReminderCardFace(card: frontData, colors: colors, height: _cardH),
          t,
          n,
        ),
      ),
    );

    // §5: mid-flight the card drops BEHIND the deck — paint-order swap.
    final flying = _travelKind == _TravelKind.flight && t > 0 && t < 1;
    if (flying && t >= _DeckGeometry.behindSwapT) {
      children.insert(0, front);
    } else {
      children.add(front);
    }

    // The pagination dots ARE the card-count indicator: one dot per
    // real card, the active dot following the front. The visual stack
    // never pretends extra pages exist.
    children.add(
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Center(
          child: _PositionDots(index: _front, count: n, colors: colors),
        ),
      ),
    );

    return Stack(clipBehavior: Clip.none, children: children);
  }

  /// The front card's live drag + flight transform. Everything is
  /// derived from the ONE dx parameter so the trajectory reads as a
  /// single coherent motion (§5), never a collection of unrelated
  /// tweens. At REST the front card carries the fan pass's gentle
  /// resting tilt (owner direction: the deck must never look straight),
  /// with scale 1.0 and full readability.
  Widget _frontTransformed(Widget child, double t, int n) {
    var dx = _dragDx;
    var dy = 0.0;
    var rotate = _DeckGeometry.frontRestRotate;
    var scale = 1.0;
    var opacity = 1.0;

    if (n > 1 && _travelAllowed) {
      // Finger-following drag: a restrained rising rotation, a slight
      // upward arc, a slightly reduced scale/opacity.
      final drag = _dragDx.abs();
      dy = -drag * drag * _DeckGeometry.arcK;
      rotate += _dragDx * _DeckGeometry.rotatePerPx;
      scale = (1.0 - drag * _DeckGeometry.scalePerPx).clamp(0.85, 1.0);
      opacity = (1.0 - drag * _DeckGeometry.opacityPerPx).clamp(0.4, 1.0);
    }

    if (t > 0 && _travelKind != _TravelKind.none) {
      if (_travelKind == _TravelKind.flight) {
        // The curved committed trajectory: continue the gesture's
        // direction outward along the arc; rotation keeps rising,
        // scale/opacity ease away, and the card disappears
        // behind/out of the deck.
        final eased = Curves.easeInCubic.transform(t);
        final width = MediaQuery.sizeOf(context).width;
        dx =
            _flightFromDx +
            _flightDirection * (width * 0.85 - _flightFromDx.abs()) * eased;
        final d = dx.abs();
        dy = -d * d * _DeckGeometry.arcK;
        rotate += dx * _DeckGeometry.rotatePerPx * (1 + eased * 2.2);
        scale = (1.0 - d * _DeckGeometry.scalePerPx * (1 + eased)).clamp(
          0.6,
          1.0,
        );
        opacity = (1.0 - eased * 0.55).clamp(0.0, 1.0);
        if (t >= 1.0) {
          // Flight complete: rotate the order; the flown card reappears
          // at the back (shuffle, not delete).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _travelKind == _TravelKind.flight) {
              setState(() {
                _advanceOrder(n);
                _dragDx = 0;
                _travelKind = _TravelKind.none;
                _travel.value = 0;
              });
            }
          });
        }
      } else {
        // Elastic settle back to rest.
        dx = _dragDx * (1 - Curves.elasticOut.transform(t));
        if (t >= 1.0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _travelKind == _TravelKind.settle) {
              setState(() {
                _dragDx = 0;
                _travelKind = _TravelKind.none;
                _travel.value = 0;
              });
            }
          });
        }
      }
    }

    return Opacity(
      opacity: opacity,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translateByDouble(dx, dy, 0, 1.0)
          ..scaleByDouble(scale, 1, 1, 1)
          ..rotateZ(rotate),
        child: child,
      ),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

enum _TravelKind { none, flight, settle }

/// The deck's geometry: the fan pass's resting slots, the fill-driven
/// dimensions, and the §5 flight coefficients. One source of truth.
class _DeckGeometry {
  /// The natural band: card + fan peek + dot rail (no fill).
  static const double naturalBand = HomeReminderDeck.naturalBand; // 150

  /// The natural fan peek — how far the fanned cards rise above the
  /// front card's top edge at the natural band.
  static const double naturalFan = 14;

  /// The fan peek ceiling on filled decks.
  static const double fanCap = 40;

  /// The fan deepens with the fill so the spread stays readable at the
  /// taller scale.
  static double fanFor(double bandH) {
    final grown = naturalFan + (bandH - naturalBand) * 0.12;
    return grown.clamp(naturalFan, fanCap);
  }

  /// The dot rail's slot and the gap above it (from the pass B layout).
  static const double dotsHeight = 12;
  static const double dotsGap = 8;

  /// The front card's GENTLE resting tilt (~1.7°): readable, but the
  /// deck never looks rigid (owner direction: "not too straight").
  static const double frontRestRotate = 0.03;

  /// A visible fan slot. depth 0 is the FRONT slot itself — straight
  /// into the resting tilt, scale 1, full opacity, so a promoted card
  /// has a real destination to glide to. Deeper slots tilt AWAY from
  /// their neighbours (alternating signs), stagger horizontally, and
  /// dim slightly with depth so the stack reads as a spread hand of
  /// physical cards, never a straight stack.
  static _FanSlot fan(int depth, double fanPeek) {
    assert(depth >= 0 && depth <= 2);
    const rotateBy = [frontRestRotate, -0.05, 0.075]; // +1.7°, −2.9°, +4.3°
    const dxBy = [0.0, -7.0, 11.0];
    const scaleBy = [1.0, 0.97, 0.94];
    const opacityBy = [1.0, 0.95, 0.85];
    final top = fanPeek * (1 - depth * 0.5); // front at the peek, back above
    return _FanSlot(
      rotate: rotateBy[depth],
      top: top,
      scale: scaleBy[depth],
      dx: dxBy[depth],
      opacity: opacityBy[depth],
    );
  }

  static _FanSlot lerp(_FanSlot a, _FanSlot b, double t) => _FanSlot(
    rotate: a.rotate + (b.rotate - a.rotate) * t,
    top: a.top + (b.top - a.top) * t,
    scale: a.scale + (b.scale - a.scale) * t,
    dx: a.dx + (b.dx - a.dx) * t,
    opacity: a.opacity + (b.opacity - a.opacity) * t,
  );

  // §5 + flight coefficients.
  static const arcK = 0.00035; // upward arc: dy = −k·dx²
  static const rotatePerPx = 0.0006; // radians/px (≈3.4° per 100px)
  static const scalePerPx = 0.0004;
  static const opacityPerPx = 0.0022;
  static const behindSwapT = 0.45; // when the card passes behind the deck
}

/// One slot in the visible fan — pure geometry, so the chain promotion
/// can lerp between slots without touching the card widgets.
class _FanSlot {
  final double rotate;
  final double top;
  final double scale;
  final double dx;
  final double opacity;

  const _FanSlot({
    required this.rotate,
    required this.top,
    required this.scale,
    required this.dx,
    required this.opacity,
  });
}

/// One elevated reminder card face. Tapping navigates to the real
/// destination behind the signal. The icon chip is a MUTED accent
/// (bright gold is reserved for primary actions and the balance/visa
/// cards — the deck must never out-shout them) and the corners use the
/// AzRadius system's larger token. At FILL heights the face goes TALL —
/// a bigger chip, larger type, roomier padding — so a filled deck never
/// reads as a thin strip stretched.
class _ReminderCardFace extends StatelessWidget {
  const _ReminderCardFace({
    required this.card,
    required this.colors,
    required this.height,
  });

  final HomeReminderCardData card;
  final AzamanColors colors;

  /// The face's height: drives the tall-mode typography.
  final double height;

  @override
  Widget build(BuildContext context) {
    final tall = height >= 150;
    final chip = tall ? 56.0 : 40.0;
    final iconSize = tall ? 26.0 : 20.0;
    final body = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          card.eyebrow,
          style: AzText.caption.copyWith(
            color: colors.textTertiary,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: tall ? 4 : 2),
        Text(
          card.title,
          style: (tall ? AzText.titleL : AzText.title).copyWith(
            color: colors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: tall ? 4 : 2),
        Text(
          card.subtitle,
          style: (tall ? AzText.bodyL : AzText.bodyS).copyWith(
            color: colors.textSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    final content = Row(
      children: [
        Container(
          width: chip,
          height: chip,
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AzRadius.md),
          ),
          child: Icon(card.icon, color: colors.mutedAccent, size: iconSize),
        ),
        SizedBox(width: tall ? AzSpace.lg : AzSpace.md),
        Expanded(child: body),
        if (card.onTap != null)
          Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
      ],
    );

    return SizedBox(
      height: height,
      child: card.onTap != null
          ? ScaleTap(
              onTap: card.onTap,
              child: _surface(child: content),
            )
          : _surface(child: content),
    );
  }

  Widget _surface({required Widget child}) => Container(
    key: ValueKey('reminder-card-${card.id}'),
    padding: EdgeInsets.symmetric(
      horizontal: AzSpace.lg,
      vertical: height >= 150 ? AzSpace.lg : AzSpace.sm,
    ),
    decoration: BoxDecoration(
      color: colors.card,
      borderRadius: BorderRadius.circular(AzRadius.lg),
      border: Border.all(color: colors.border),
      boxShadow: AzElevation.level1(colors.isDark),
    ),
    child: child,
  );
}

/// The resting placeholder — a new user's deck slot, never blank (owner
/// direction, 2026-10-05). The front card says, honestly, what will
/// live here; the same fanned cards peek dimmed behind it so the deck's
/// geometry reads before the first real signal arrives. Nothing drags,
/// nothing shuffles, no chevron: there is nothing to open yet.
class _PlaceholderDeck extends StatelessWidget {
  const _PlaceholderDeck({
    required this.colors,
    required this.cardH,
    required this.fan,
  });

  final AzamanColors colors;
  final double cardH;
  final double fan;

  static const _placeholder = HomeReminderCardData(
    id: 'placeholder',
    eyebrow: 'REMINDERS',
    title: 'Your reminders will appear here',
    subtitle: 'Join a susu or browse the marketplace to get started',
    icon: Icons.notifications_none_rounded,
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The stacked deck behind: the same fan slots the real deck
        // uses, dimmed so the placeholder reads as a ghost of the
        // living thing.
        for (final depth in const [2, 1])
          Positioned(
            top: _DeckGeometry.fan(depth, fan).top,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: _DeckGeometry.fan(depth, fan).opacity * 0.5,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translateByDouble(
                      _DeckGeometry.fan(depth, fan).dx,
                      0,
                      0,
                      1.0,
                    )
                    ..scaleByDouble(
                      _DeckGeometry.fan(depth, fan).scale,
                      1,
                      1,
                      1,
                    )
                    ..rotateZ(_DeckGeometry.fan(depth, fan).rotate),
                  child: _ReminderCardFace(
                    card: _placeholder,
                    colors: colors,
                    height: cardH,
                  ),
                ),
              ),
            ),
          ),
        // The front face: full height, gently dimmed, honest copy. No
        // chevron, no tap — information, not a destination.
        Positioned(
          top: fan,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.9,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..rotateZ(_DeckGeometry.frontRestRotate),
                child: _ReminderCardFace(
                  card: _placeholder,
                  colors: colors,
                  height: cardH,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The pagination dots — the honest card-count indicator (unchanged
/// from the reviewed PR #142 visual pass): one dot per real card, the
/// active dot tracking the front.
class _PositionDots extends StatelessWidget {
  const _PositionDots({
    required this.index,
    required this.count,
    required this.colors,
  });

  final int index;
  final int count;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('reminder-deck-dots'),
      height: _DeckGeometry.dotsHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: EdgeInsets.only(right: i == count - 1 ? 0 : 5),
              child: Container(
                key: ValueKey('reminder-deck-dot-$i'),
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == index
                      ? colors.mutedAccent
                      : colors.textTertiary.withValues(alpha: 0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
