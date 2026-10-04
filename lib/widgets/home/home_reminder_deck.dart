// =============================================================================
// AZAMAN — HOME REMINDER DECK  (experience pass §4 + §5)
//
// §4 — REAL SIGNALS ONLY. A compact, premium reminder deck sitting
// immediately above Recent Activity. Cards are derived from existing
// providers (susuListProvider, marketplaceResumeProvider) — no new
// backend requests, no fabricated personalisation. If there is no
// legitimate signal, the deck does not render; card copy never claims
// something the data does not say.
//
// Geometry: small elevated cards, ~92dp tall, 2–4 max, the cards behind
// the front one peek out with shallow rotations (±1.5–3°), slight
// vertical offsets and slight scale reduction backward.
//
// §5 — SHUFFLE, NOT DELETE. The top card is horizontally swipeable; a
// committed swipe sends it along a curved (arc) trajectory with rising
// rotation and slightly reduced scale/opacity, and mid-flight it drops
// BEHIND the deck while the order rotates — the next card was already
// partially visible underneath. One coherent gesture-driven trajectory
// (finger-following drag + curved completion on release), animation
// controllers only, no Timer sequencing.
//
// Reduced motion: no expressive travel — instant reorder/settle with the
// same information hierarchy. Accessibility: a custom semantics action
// advances the deck without a swipe; each card is its own tappable
// destination.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction, SemanticsProperties;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

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

/// A single reminder card's honest content + its destination.
class HomeReminderCardData {
  final String id;
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const HomeReminderCardData({
    required this.id,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
}

/// The deck. Renders nothing when there is nothing real to say (§4).
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

  List<HomeReminderCardData> _cards() {
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
    //    No fresh memory or no real match → no card (§4 honesty).
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

  // ignore: unused_field — used via _month() below.

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
          _advanceOrder(_count);
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

  int get _count => _cards().length;

  void _advanceOrder(int n) {
    if (n > 0) _front = (_front + 1) % n;
  }

  /// Accessibility: the semantic equivalent of a committed swipe.
  void _advance() {
    AzamanHaptics.confirm();
    setState(() => _advanceOrder(_count));
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards();
    if (cards.isEmpty) return const SizedBox.shrink();
    _travelAllowed = AzMotion.of(context).travel;

    // Keep the front index honest across data changes.
    final idHash = Object.hashAll(cards.map((c) => c.id));
    if (_frontIdHash != idHash) {
      _frontIdHash = idHash;
      _front = _front % cards.length;
    }

    // fromProperties keeps the custom action readable at the widget level
    // (the plain Semantics constructor folds it into a private config).
    return Semantics.fromProperties(
      properties: SemanticsProperties(
        label: 'Reminders',
        customSemanticsActions: cards.length > 1
            ? {const CustomSemanticsAction(label: 'Next reminder'): _advance}
            : null,
      ),
      child: SizedBox(
        height: _DeckGeometry.deckHeight,
        child: AnimatedBuilder(
          animation: _travel,
          builder: (context, _) => _buildStack(context, cards, _travel.value),
        ),
      ),
    );
  }

  Widget _buildStack(
      BuildContext context, List<HomeReminderCardData> cards, double t) {
    final colors = ref.watch(themeProvider).colors;
    final n = cards.length;
    final children = <Widget>[];

    // Behind cards peek from the top edge: scale down, offset up, shallow
    // alternating rotations (§4 resting geometry).
    for (var depth = math.min(n - 1, 2); depth >= 1; depth--) {
      final g = _DeckGeometry.back(depth);
      children.add(Positioned(
        top: g.top,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..scaleByDouble(g.scale, 1, 1, 1)
              ..rotateZ(g.rotate),
            child: Opacity(
              opacity: 0.92,
              child: _ReminderCardFace(
                card: cards[(_front + depth) % n],
                colors: colors,
                height: _DeckGeometry.cardHeight,
              ),
            ),
          ),
        ),
      ));
    }

    final front = Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: n > 1 ? _onDragUpdate : null,
        onHorizontalDragEnd: n > 1 ? _onDragEnd : null,
        child: _frontTransformed(
          _ReminderCardFace(
            card: cards[_front],
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

/// §4 resting + §5 flight geometry, in one place.
class _DeckGeometry {
  static const cardHeight = 92.0; // the 80–100dp band
  static const peek = 22.0; // visible portion of the card behind
  static const deckHeight = cardHeight + peek;

  static const frontRestRotate = 0.035; // ~2° — the deck always reads tilted

  /// depth 1 (just behind): −1.5°, up 10, scale .97
  /// depth 2 (furthest):  +2.3°, up 20, scale .94
  static ({double rotate, double top, double scale}) back(int depth) {
    final rotate = depth == 1 ? -0.026 : 0.040;
    final top = -depth * 10.0;
    final scale = 1.0 - depth * 0.03;
    return (rotate: rotate, top: top, scale: scale);
  }

  // §5 flight coefficients.
  static const arcK = 0.00035; // upward arc: dy = −k·dx²
  static const rotatePerPx = 0.0006; // radians/px (≈3.4° per 100px)
  static const scalePerPx = 0.0004;
  static const opacityPerPx = 0.0022;
  static const behindSwapT = 0.45; // when the card passes behind the deck
}

/// One elevated reminder card face. Tapping navigates to the real
/// destination behind the signal.
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
    return SizedBox(
      height: height,
      child: ScaleTap(
        onTap: card.onTap,
        child: Container(
          key: ValueKey('reminder-card-${card.id}'),
          padding: const EdgeInsets.symmetric(
              horizontal: AzSpace.lg, vertical: AzSpace.sm),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AzRadius.lg),
            border: Border.all(color: colors.border),
            boxShadow: AzElevation.level1(colors.isDark),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AzRadius.md),
              ),
              child: Icon(card.icon, color: colors.accent, size: 20),
            ),
            const SizedBox(width: AzSpace.md),
            Expanded(
              child: Column(
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
                      style:
                          AzText.title.copyWith(color: colors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(card.subtitle,
                      style:
                          AzText.bodyS.copyWith(color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
          ]),
        ),
      ),
    );
  }
}
