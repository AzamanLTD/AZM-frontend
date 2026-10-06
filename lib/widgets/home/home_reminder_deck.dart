// =============================================================================
// AZAMAN — HOME REMINDER DECK  (experience pass §4 + §5, pass B/C/D)
//
// §4 — REAL SIGNALS FIRST. A compact, premium reminder deck sitting
// immediately above Recent Activity. Cards are derived from existing
// providers (susuListProvider, marketplaceResumeProvider,
// marketplaceRelevanceProvider) — no new backend requests, no fabricated
// personalisation. Card copy never claims something the data does not say.
//
// PASS B — SIMPLIFIED VISUAL GRAMMAR. The deck is a clean stack:
//   * ONE fully readable, completely STRAIGHT front card (no resting
//     tilt — the hero card never looks like it is being thrown)
//   * ONE shallow next-card peek below it (no rotated fan, no ghost
//     layers — the stack shows at most two faces)
//   * the PAGINATION DOTS are the card-count indicator: they count the
//     real cards in the deck, and the active dot follows the front
//
// PASS B5 — STABLE GEOMETRY. The deck's dimensions are fixed constants
// from the first settled render: no band measurement, no placeholder
// that grows after the screen loads. The same geometry every frame.
//
// PASS D — TRUTHFULNESS. Production Home never fabricates content: with
// no real signal the deck collapses out of the layout cleanly (no
// reserved blank band, no ghost fan). Demo builds may seed from the
// app's demo data (DemoGuard-gated, never in a real build).
//
// §5 + PASS C — SHUFFLE, NOT DELETE. The front card is horizontally
// swipeable along ONE coherent controller-driven trajectory: it follows
// the finger, acquires a restrained directional rotation, arcs away on
// commit and drops BEHIND the deck mid-flight while the promoted next
// card settles into the exact straight front position (rotation zero,
// scale one, full opacity, fully readable). No Timer sequencing.
//
// Reduced motion: no expressive travel — instant reorder/settle with
// the same information hierarchy. Accessibility: a custom semantics
// action advances the deck without a swipe; each card is its own
// tappable destination.
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

/// The deck. Renders only when there is REAL card content (pass D): in
/// production a signal-less deck collapses out of the layout cleanly
/// instead of fabricating a fan; demo builds seed from the demo data.
class HomeReminderDeck extends ConsumerStatefulWidget {
  const HomeReminderDeck({super.key});

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

    // Keep the front index honest across data changes.
    final idHash = Object.hashAll(cards.map((c) => c.id));
    if (_frontIdHash != idHash) {
      _frontIdHash = idHash;
      _front = cards.isEmpty ? 0 : _front % cards.length;
    }

    // PASS D — truthfulness: production Home never fabricates reminder
    // content. A signal-less deck collapses out of the layout cleanly
    // (no reserved blank band, no ghost fan). Demo builds always carry
    // their seeds, so a demo never lands here.
    if (cards.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('reminder-deck-empty'));
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
          // PR #142 VISUAL PASS (2026-10-06) — the small premium section
          // separator immediately above the compact deck: centered, small
          // gray text, hairlines fading toward the outer ends. It lives
          // INSIDE the deck so it collapses with the deck when production
          // Home has no reminder signals — never a stranded label. The
          // cards themselves are untouched.
          HomeDeckSeparator(colors: ref.watch(themeProvider).colors),
          SizedBox(
            height: _DeckGeometry.bandHeight,
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

    // PASS B2/B4 — exactly ONE next-card peek: no rotated fan, no ghost
    // layers. The next card sits a shallow step below the hero, slightly
    /// inset. During the committed flight it blends into the EXACT front
    // position (the promoted card straightens: rotation stays zero,
    // scale reaches 1.0, opacity becomes full — pass B4), so the new
    // hero is fully readable the moment the old one leaves.
    if (n > 1) {
      final next = cards[(_front + 1) % n];
      final settle = _travelKind == _TravelKind.flight
          ? Curves.easeOutCubic.transform(t.clamp(0.0, 1.0))
          : 0.0;
      children.add(Positioned(
        top: _DeckGeometry.peek * (1 - settle),
        left: _DeckGeometry.peekInset * (1 - settle),
        right: _DeckGeometry.peekInset * (1 - settle),
        child: IgnorePointer(
          child: Opacity(
            opacity: _DeckGeometry.peekOpacity +
                (1 - _DeckGeometry.peekOpacity) * settle,
            child: _ReminderCardFace(
              card: next,
              colors: colors,
              height: _DeckGeometry.cardHeight,
            ),
          ),
        ),
      ));
    }

    final frontData = cards[_front];
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
            height: _DeckGeometry.cardHeight,
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

    // PASS B3 — the pagination dots ARE the card-count indicator: one
    // dot per real card, the active dot following the front. The visual
    // stack never pretends extra pages exist.
    children.add(Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Center(
        child: _PositionDots(index: _front, count: n, colors: colors),
      ),
    ));

    return Stack(clipBehavior: Clip.none, children: children);
  }

  /// The front card's live drag + flight transform. Everything is
  /// derived from the ONE dx parameter so the trajectory reads as a
  /// single coherent motion (§5 + pass C), never a collection of
  /// unrelated tweens. At REST the front card is completely straight
  /// (pass B1): zero resting rotation, scale 1.0, fully readable.
  Widget _frontTransformed(Widget child, double t, int n) {
    var dx = _dragDx;
    var dy = 0.0;
    var rotate = 0.0;
    var scale = 1.0;
    var opacity = 1.0;

    if (n > 1 && _travelAllowed) {
      // Finger-following drag: a restrained rising rotation, a slight
      // upward arc, a slightly reduced scale/opacity (pass C).
      final drag = _dragDx.abs();
      dy = -drag * drag * _DeckGeometry.arcK;
      rotate += _dragDx * _DeckGeometry.rotatePerPx;
      scale = (1.0 - drag * _DeckGeometry.scalePerPx).clamp(0.85, 1.0);
      opacity = (1.0 - drag * _DeckGeometry.opacityPerPx).clamp(0.4, 1.0);
    }

    if (t > 0 && _travelKind != _TravelKind.none) {
      if (_travelKind == _TravelKind.flight) {
        // PASS C — the curved committed trajectory: continue the
        // gesture's direction outward along the arc; rotation keeps
        // rising, scale/opacity ease away, and the card disappears
        // behind/out of the deck.
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

/// PASS B5 — the deck's FIXED geometry: identical constants from the
/// first settled render. No band measurement, no tall-mode expansion, no
/// post-load growth — the same card every frame.
class _DeckGeometry {
  /// The fully readable hero card (pass B1): straight, scale 1.0.
  static const double cardHeight = 96;

  /// PASS B2 — ONE shallow next-card peek: the next card's top step
  /// below the hero's bottom edge, the only visible "there is more"
  /// edge in the stack.
  static const double peek = 16;

  /// The peek card's horizontal inset — the next edge reads slightly
  /// narrower than the hero, never a fan.
  static const double peekInset = 14;

  static const double peekOpacity = 0.9;

  /// PASS B3 — the pagination-dot rail's slot and the gap above it.
  static const double dotsHeight = 12;
  static const double dotsGap = 8;

  /// The deck's stable band: hero + peek + dot rail. FIXED (pass B5).
  static const double bandHeight = cardHeight + peek + dotsGap + dotsHeight;

  // §5 + PASS C flight coefficients.
  static const arcK = 0.00035; // upward arc: dy = −k·dx²
  static const rotatePerPx = 0.0006; // radians/px (≈3.4° per 100px)
  static const scalePerPx = 0.0004;
  static const opacityPerPx = 0.0022;
  static const behindSwapT = 0.45; // when the card passes behind the deck
}

/// One elevated reminder card face. Tapping navigates to the real
/// destination behind the signal. The icon chip is a MUTED accent
/// (pass E: supporting feature icons are muted gold — bright gold is
/// reserved for primary actions and selected navigation) and the corners
/// use the AzRadius system's larger token (pass B7).
class _ReminderCardFace extends StatelessWidget {
  const _ReminderCardFace({
    required this.card,
    required this.colors,
    required this.height,
  });

  final HomeReminderCardData card;
  final AzamanColors colors;
  final double height;

  @override
  Widget build(BuildContext context) {
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
            style: AzText.title.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(card.subtitle,
            style: AzText.bodyS.copyWith(color: colors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );

    final content = Row(children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AzRadius.md),
        ),
        child: Icon(card.icon, color: colors.mutedAccent, size: 20),
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
          // PASS B7 — the existing AzRadius system's larger token: soft
          // and premium, never a new custom constant.
          borderRadius: BorderRadius.circular(AzRadius.xl),
          border: Border.all(color: colors.border),
          boxShadow: AzElevation.level1(colors.isDark),
        ),
        child: child,
      );
}

/// PASS B3 — the pagination dots: the deck's card-count indicator. One
/// dot per REAL card, the active dot following the front card. The dots
/// are a restrained detail (pass E): the active dot is the muted accent,
/// the rest neutral.
class _PositionDots extends StatelessWidget {
  const _PositionDots(
      {required this.index, required this.count, required this.colors});

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
