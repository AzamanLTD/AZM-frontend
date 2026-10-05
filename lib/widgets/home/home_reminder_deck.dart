// =============================================================================
// AZAMAN — HOME REMINDER DECK  (experience pass §4 + §5, fill patch)
//
// §4 — REAL SIGNALS FIRST. A compact, premium reminder deck sitting
// immediately above Recent Activity. Cards are derived from existing
// providers (susuListProvider, marketplaceResumeProvider,
// marketplaceRelevanceProvider) — no new backend requests, no fabricated
// personalisation. Card copy never claims something the data does not say.
//
// THE SLOT IS NEVER BLANK. The deck FILLS the band Home measures for it:
//   * real signals  → up to three real cards fan behind the front card
//   * new user      → the placeholder card ("Your reminders will appear
//                     here") with dimmed ghost slots fanned behind it
//   * demo mode     → when no real signal exists, the deck seeds from the
//                     app's demo data (DemoGuard-gated, never in a real
//                     build) so the demo experience shows a lived-in Home
//   * empty slots   → dimmed ghost faces (no copy, no fake content) fill
//                     the fan so the deck always reads as a deck
//
// Geometry: the deck is given the BAND height (the measured space between
// the wallet modules and the activity doorway) and derives everything
// from it — peek depth grows with the band, cards get a taller "tall
// mode" (bigger icon chip, larger type, position dots) when the band
// allows, and both are clamped so cards never become absurd. Behind
// cards peek BELOW the front card's bottom edge with shallow alternating
// rotations (±1.5–2.5°) and slight sideways nudges, so the fan spans the
// whole band and reads as a spread hand of cards.
//
// §5 — SHUFFLE, NOT DELETE. The top card is horizontally swipeable; a
// committed swipe sends it along a curved (arc) trajectory with rising
// rotation and slightly reduced scale/opacity, and mid-flight it drops
// BEHIND the deck while the order rotates — the next card was already
// partially visible underneath. One coherent gesture-driven trajectory
// (finger-following drag + curved completion on release), animation
// controllers only, no Timer sequencing. The placeholder and ghost faces
// are inert: no swipe, no tap target.
//
// Reduced motion: no expressive travel — instant reorder/settle with the
// same information hierarchy. Accessibility: a custom semantics action
// advances the deck without a swipe; each card is its own tappable
// destination.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction, SemanticsProperties;
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

/// The deck. Always renders — the band it is given is never left blank.
class HomeReminderDeck extends ConsumerStatefulWidget {
  const HomeReminderDeck({super.key, this.band = _DeckGeometry.defaultBand});

  /// The vertical band the deck must occupy: the measured space between
  /// the wallet modules and the activity doorway.
  final double band;

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
      list.add(HomeReminderCardData(
        id: 'susu-${dueGroup.id}',
        eyebrow: 'SUSU',
        title: cycle.isMe
            ? 'Your payout cycle runs $when'
            : 'Susu contribution due $when',
        subtitle: dueGroup.name,
        icon: HugeIconsSolid.wallet01,
        onTap: () => context.push('/susu/${dueGroup.id}'),
      ));
    }

    // 2. The marketplace resume intent — a live cart, or a fresh world
    //    memory of what they were browsing. Both are real signals; the
    //    intent provider already guarantees freshness and honesty.
    final intent = ref.watch(marketplaceResumeProvider);
    if (intent != null) {
      final isCart = intent.kind == ResumeKind.cart;
      list.add(HomeReminderCardData(
        id: 'resume-${intent.worldWire ?? intent.businessProfileId ?? 'cart'}',
        eyebrow: 'MARKETPLACE',
        title: intent.title,
        subtitle: intent.subtitle,
        icon: isCart ? HugeIconsSolid.shoppingCart01 : HugeIconsSolid.store01,
        onTap: () => context.push(
            intent.kind == ResumeKind.cart ? AzRoutes.cart : AzRoutes.marketplace),
      ));
    }

    // 3. Marketplace relevance — a REAL store in the category they most
    //    recently visited (world memory + existing discovery data, both
    //    already real). Suppressed when the resume card above already
    //    speaks for the same world: one memory, one card, never two.
    final relevance = ref.watch(marketplaceRelevanceProvider);
    if (relevance != null && intent?.worldWire != relevance.worldWire) {
      list.add(HomeReminderCardData(
        id: 'relevance-${relevance.business.id}',
        eyebrow: 'MARKETPLACE',
        title: relevance.business.businessName,
        subtitle: 'Relevant in ${relevance.categoryLabel}',
        icon: HugeIconsSolid.store01,
        onTap: () => context.push(AzRoutes.storefront(
            relevance.business.id, name: relevance.business.businessName)),
      ));
    }
    return list;
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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

  /// The placeholder card: the deck's honest empty state for a new user.
  HomeReminderCardData get _placeholderCard => const HomeReminderCardData(
        id: 'placeholder',
        eyebrow: 'REMINDERS',
        title: 'Your reminders will appear here',
        subtitle: 'Susu schedules, saved carts and store picks land here.',
        icon: HugeIconsSolid.notification01,
      );

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
    final isPlaceholder = cards.isEmpty;
    _travelAllowed = AzMotion.of(context).travel;

    // Keep the front index honest across data changes.
    final idHash = Object.hashAll(cards.map((c) => c.id));
    if (_frontIdHash != idHash) {
      _frontIdHash = idHash;
      _front = cards.isEmpty ? 0 : _front % cards.length;
    }

    final geo = _DeckGeometry.forBand(widget.band);
    final swipable = cards.length > 1 && !isPlaceholder;

    // fromProperties keeps the custom action readable at the widget level
    // (the plain Semantics constructor folds it into a private config).
    return Semantics.fromProperties(
      properties: SemanticsProperties(
        label: 'Reminders',
        customSemanticsActions: swipable
            ? {const CustomSemanticsAction(label: 'Next reminder'): _advance}
            : null,
      ),
      child: SizedBox(
        height: geo.bandHeight,
        child: AnimatedBuilder(
          animation: _travel,
          builder: (context, _) => _buildStack(
              context, cards, isPlaceholder, swipable, geo, _travel.value),
        ),
      ),
    );
  }

  Widget _buildStack(
    BuildContext context,
    List<HomeReminderCardData> cards,
    bool isPlaceholder,
    bool swipable,
    _BandGeometry geo,
    double t,
  ) {
    final colors = ref.watch(themeProvider).colors;
    final n = cards.length;
    final children = <Widget>[];

    // Behind cards peek BELOW the front card's bottom edge: they sit
    // lower in the band, scale down slightly and carry the alternating
    // fan rotations. Ghost faces (no copy, no shadow, dimmed) fill the
    // fan when there are fewer real cards — the slot is never blank and
    // no ghost ever claims content.
    for (var depth = 2; depth >= 1; depth--) {
      final g = _DeckGeometry.back(depth);
      final card = n > depth ? cards[(_front + depth) % n] : null;
      children.add(Positioned(
        top: geo.peek * depth,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Opacity(
            opacity: card == null ? _DeckGeometry.ghostOpacity : 0.92,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translateByDouble(g.dx, 0, 0, 1.0)
                ..scaleByDouble(g.scale, 1, 1, 1)
                ..rotateZ(g.rotate),
              child: card == null
                  ? _GhostCardFace(colors: colors, height: geo.cardHeight)
                  : _ReminderCardFace(
                      card: card,
                      colors: colors,
                      height: geo.cardHeight,
                    ),
            ),
          ),
        ),
      ));
    }

    final frontData = isPlaceholder ? _placeholderCard : cards[_front];
    final front = Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: swipable ? _onDragUpdate : null,
        onHorizontalDragEnd: swipable ? _onDragEnd : null,
        child: _frontTransformed(
          _ReminderCardFace(
            card: frontData,
            colors: colors,
            height: geo.cardHeight,
            tall: geo.tall,
            positionDots: swipable && geo.tall ? (index: _front, count: n) : null,
          ),
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
    return Stack(clipBehavior: Clip.none, children: children);
  }

  /// The front card's live drag + flight/settle transform. Everything is
  /// derived from the ONE dx parameter so the trajectory reads as a
  /// single coherent motion (§5), never a collection of unrelated tweens.
  Widget _frontTransformed(Widget child, double t, int n) {
    var dx = _dragDx;
    var dy = 0.0;
    var rotate = _DeckGeometry.frontRestRotate;
    var scale = 1.0;
    var opacity = 1.0;

    if (n > 1 && _travelAllowed) {
      // Finger-following drag: rising rotation, slight upward arc,
      // slightly reduced scale/opacity.
      final drag = _dragDx.abs();
      dy = -drag * drag * _DeckGeometry.arcK;
      rotate += _dragDx * _DeckGeometry.rotatePerPx;
      scale = (1.0 - drag * _DeckGeometry.scalePerPx).clamp(0.85, 1.0);
      opacity = (1.0 - drag * _DeckGeometry.opacityPerPx).clamp(0.4, 1.0);
    }

    if (t > 0 && _travelKind != _TravelKind.none) {
      if (_travelKind == _TravelKind.flight) {
        // Curved completion: continue the gesture's direction outward
        // along the arc; rotation keeps rising, scale/opacity ease away.
        final eased = Curves.easeInCubic.transform(t);
        final width = MediaQuery.sizeOf(context).width;
        dx = _flightFromDx +
            _flightDirection * (width * 0.85 - _flightFromDx.abs()) * eased;
        final d = dx.abs();
        dy = -d * d * _DeckGeometry.arcK;
        rotate += dx * _DeckGeometry.rotatePerPx * (1 + eased * 2.2);
        scale = (1.0 - d * _DeckGeometry.scalePerPx * (1 + eased)).clamp(
            0.6, 1.0);
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
}

enum _TravelKind { none, flight, settle }

/// The deck's derived band geometry (see [_DeckGeometry.forBand]).
typedef _BandGeometry =
    ({double bandHeight, double peek, double cardHeight, bool tall});

/// §4 resting + §5 flight geometry, in one place. The deck is BAND-DRIVEN:
/// Home measures the empty space and hands it over; every dimension below
/// derives from that band, clamped so the cards never get absurd.
class _DeckGeometry {
  /// The compact strip used when no band is supplied (tests, previews).
  static const defaultBand = 134.0;

  /// The card's 88–100dp comfort band, preserved from the §4 contract.
  static const minCard = 88.0;
  static const maxCard = 264.0;
  static const minPeek = 20.0;
  static const maxPeek = 40.0;

  /// Tall mode kicks in when the band affords a taller card: bigger icon
  /// chip, larger type, position dots.
  static const tallCardThreshold = 150.0;

  static const ghostOpacity = 0.45;

  static const frontRestRotate = 0.035; // ~2° — the deck always reads tilted

  static _BandGeometry forBand(double band) {
    final peek = (band * 0.16).clamp(minPeek, maxPeek);
    final cardHeight = (band - 2 * peek).clamp(minCard, maxCard);
    // The laid-out band: exactly what the fan spans. When the clamps bite
    // (absurdly tall tablet band) the deck keeps its geometry and simply
    // does not stretch the last pixels — never a mis-measured overflow.
    final bandHeight = cardHeight + 2 * peek;
    return (
      bandHeight: bandHeight,
      peek: peek,
      cardHeight: cardHeight,
      tall: cardHeight >= tallCardThreshold,
    );
  }

  /// depth 1 (just behind): −1.4°, nudge left, scale .985
  /// depth 2 (furthest):   +2.4°, nudge right, scale .97
  static ({double rotate, double dx, double scale}) back(int depth) {
    final rotate = depth == 1 ? -0.024 : 0.042;
    final dx = depth == 1 ? -7.0 : 11.0;
    final scale = 1.0 - depth * 0.015;
    return (rotate: rotate, dx: dx, scale: scale);
  }

  // §5 flight coefficients.
  static const arcK = 0.00035; // upward arc: dy = −k·dx²
  static const rotatePerPx = 0.0006; // radians/px (≈3.4° per 100px)
  static const scalePerPx = 0.0004;
  static const opacityPerPx = 0.0022;
  static const behindSwapT = 0.45; // when the card passes behind the deck
}

/// One elevated reminder card face. Tapping navigates to the real
/// destination behind the signal. In tall mode the face grows its icon
/// chip and type; with multiple cards a quiet position-dot rail shows
/// where the front card sits in the deck.
class _ReminderCardFace extends StatelessWidget {
  const _ReminderCardFace({
    required this.card,
    required this.colors,
    required this.height,
    this.tall = false,
    this.positionDots,
  });

  final HomeReminderCardData card;
  final AzamanColors colors;
  final double height;
  final bool tall;

  /// Quiet position rail: which card is front, of how many. Null on the
  /// compact band (no room) and behind cards (only the front shows it).
  final ({int index, int count})? positionDots;

  @override
  Widget build(BuildContext context) {
    final chipSize = tall ? 52.0 : 40.0;
    final body = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(card.eyebrow,
            style: AzText.caption.copyWith(
                color: colors.textTertiary,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(card.title,
            style: (tall ? AzText.titleL : AzText.title)
                .copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(card.subtitle,
            style: (tall ? AzText.body : AzText.bodyS)
                .copyWith(color: colors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        if (positionDots != null) ...[
          const SizedBox(height: AzSpace.sm),
          _PositionDots(
              index: positionDots!.index,
              count: positionDots!.count,
              colors: colors),
        ],
      ],
    );

    final content = Row(children: [
      Container(
        width: chipSize,
        height: chipSize,
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AzRadius.md),
        ),
        child:
            Icon(card.icon, color: colors.accent, size: tall ? 26.0 : 20.0),
      ),
      const SizedBox(width: AzSpace.md),
      Expanded(child: body),
      if (card.onTap != null)
        Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
    ]);

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
        padding: const EdgeInsets.symmetric(
            horizontal: AzSpace.lg, vertical: AzSpace.sm),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(AzRadius.lg),
          border: Border.all(color: colors.border),
          boxShadow: AzElevation.level1(colors.isDark),
        ),
        child: child,
      );
}

/// A ghost slot: the deck's honest "nothing here yet" filler. Same shape
/// and rhythm as a real card, but transparent, dimmed, no copy, no
/// shadow, no tap — it never claims content.
class _GhostCardFace extends StatelessWidget {
  const _GhostCardFace({required this.colors, required this.height});

  final AzamanColors colors;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Container(
        key: const ValueKey('reminder-ghost'),
        padding: const EdgeInsets.symmetric(
            horizontal: AzSpace.lg, vertical: AzSpace.sm),
        decoration: BoxDecoration(
          color: colors.card.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AzRadius.lg),
          border: Border.all(color: colors.divider),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AzRadius.md),
            ),
          ),
          const SizedBox(width: AzSpace.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 8,
                  width: 72,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(AzRadius.pill),
                  ),
                ),
                const SizedBox(height: AzSpace.sm),
                Container(
                  height: 8,
                  width: 120,
                  decoration: BoxDecoration(
                    color: colors.divider.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AzRadius.pill),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// The quiet position rail on the front card in tall mode: one dot per
/// card, the front one accented.
class _PositionDots extends StatelessWidget {
  const _PositionDots(
      {required this.index, required this.count, required this.colors});

  final int index;
  final int count;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: EdgeInsets.only(right: i == count - 1 ? 0 : 5),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == index
                    ? colors.accent
                    : colors.textTertiary.withValues(alpha: 0.4),
              ),
            ),
          ),
      ],
    );
  }
}
