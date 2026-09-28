// TASK-008 follow-ups — Home entrance choreography (spec sections 2c, 3):
//
//   1. The entrance completes: every choreographed block is fully painted
//      by 550ms (last block: staggerDelay(6)=240ms + standard=220ms=460ms)
//      and sits at rest — no fade in flight, no slide offset left.
//   2. The camera move is correct: header from the LEFT, balance rail from
//      the RIGHT (the one block that travels opposite the others, so the
//      deck feels slid into view), pills from BELOW.
//   3. Reduced motion: with MediaQuery.disableAnimations, Home simply IS
//      there on the first frame — no fade, no slide, no avatar pop.
//
// Anchors are content widgets inside each block (flutter_animate renders
// slideX/slideY as SlideTransition, fadeIn as FadeTransition, scale as
// Transform.scale — all read at the widget layer, no private classes
// needed). The bell's own 300ms fade and the recent-activity row staggers
// belong to their widgets, not the entrance — they are covered by the
// F-050 holistic reduced-motion pass, so they are deliberately not
// asserted here.
//
// The host is minimal: an inert AuthProvider (no socket), a zeroed unread
// count (no badge, no notification fetch), and a stubbed balance/oracle
// pair so the hero card renders deterministically. The network-facing
// summary fetch fails fast in tests, so the sections below the rail render
// in their idle states — nothing to settle but the entrance.
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/widgets/flippable_balance_card.dart';
import 'package:azaman/widgets/live_market_section.dart';
import 'package:azaman/widgets/recent_activity_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _surfaceSize = Size(400, 900);

/// Seeds the first-time tap hint as seen (it pulses on a repeating
/// controller — real UX, but not part of the entrance) and pumps Home.
Future<void> _pumpHome(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  SharedPreferences.setMockInitialValues(
      {'has_seen_flippable_card_hint': true});
  await tester.binding.setSurfaceSize(_surfaceSize);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      // A derived Provider: overriding it keeps NotificationNotifier (and its
      // initial fetch) out of the tree entirely.
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
          (ref) => BalanceData(availableBalance: 100)),
      oracleRateProvider.overrideWith((ref) => 1.0),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: _surfaceSize)
              .copyWith(disableAnimations: reduceMotion),
          child: const Scaffold(body: AzamanHomePage()),
        ),
      ),
    ),
  );
  // First frame: flutter_animate schedules its start timer at mount, this
  // pump fires it — everything now sits at t=0 of the entrance.
  await tester.pump();
}

/// Walks up from [anchor] to the home page element — and no further. The
/// enclosing route's own transition (SlideTransitions at rest, a dismissed
/// FadeTransition at 0.0) is an ancestor of everything on the page; these
/// helpers must not reach past the page into it.
Iterable<Element> _ancestorsWithinHome(WidgetTester tester, Finder anchor) {
  final home = find.byType(AzamanHomePage).evaluate().first;
  final elements = <Element>[];
  Element? e = anchor.evaluate().first.parent;
  while (e != null && e != home) {
    elements.add(e);
    e = e.parent;
  }
  return elements;
}

/// The FadeTransition ancestors of [anchor] (the block's entrance fade —
/// plus any widget-internal ones the anchor nests in).
List<FadeTransition> _ancestorFades(WidgetTester tester, Finder anchor) {
  return _ancestorsWithinHome(tester, anchor)
      .where((e) => e.widget is FadeTransition)
      .map((e) => e.widget as FadeTransition)
      .toList();
}

/// The SlideTransition ancestors of [anchor] — the block's entrance slide.
List<SlideTransition> _ancestorSlides(WidgetTester tester, Finder anchor) {
  return _ancestorsWithinHome(tester, anchor)
      .where((e) => e.widget is SlideTransition)
      .map((e) => e.widget as SlideTransition)
      .toList();
}

/// Whether any Transform ancestor of [anchor] applies a non-identity scale
/// (flutter_animate's scale effect renders as Transform.scale; the avatar
/// pop-in would be a 0.8 scale on the first frames).
bool _hasNonIdentityScale(WidgetTester tester, Finder anchor) {
  return _ancestorsWithinHome(tester, anchor)
      .where((e) => e.widget is Transform)
      .any((e) =>
          ((e.widget as Transform).transform.getMaxScaleOnAxis() - 1).abs() >
          0.01);
}

// Content anchors, one per choreographed block (see the block map in
// home_screen.dart's _stage). Block 4 (susu) renders nothing under its
// stub-failure state and block 1 is the only text on the page.
Finder get _headerGift => find.byIcon(HugeIconsSolid.gift); // block 0
Finder get _title => find.text('Welcome back'); // block 1
Finder get _addMoneyPill => find.byIcon(HugeIconsSolid.plusSign); // block 2
Finder get _heroCard =>
    find.byType(FlippableBalanceCard); // block 3
Finder get _activity =>
    find.byType(RecentActivitySection); // block 5
Finder get _market => find.byType(LiveMarketSection); // block 6

List<Finder> get _anchors =>
    [_headerGift, _title, _addMoneyPill, _heroCard, _activity, _market];

void main() {
  testWidgets(
      'entrance completes: fully painted and at rest by 550ms',
      (tester) async {
    await _pumpHome(tester);

    // t=0: the choreography is real — the header block is still invisible.
    final headerFades = _ancestorFades(tester, _headerGift);
    expect(headerFades, isNotEmpty,
        reason: 'header block has no entrance fade');
    expect(headerFades.first.opacity.value, lessThan(0.99),
        reason: 'home should still be entering at the first frame');

    // t=550ms: the last block lands at 460ms. Every block must be fully
    // painted…
    await tester.pump(const Duration(milliseconds: 550));
    for (final anchor in _anchors) {
      for (final fade in _ancestorFades(tester, anchor)) {
        expect(fade.opacity.value, greaterThan(0.999),
            reason: 'a fade is still running on $anchor at 550ms');
      }
      // …and sitting at rest: no slide offset left anywhere in its chain.
      for (final slide in _ancestorSlides(tester, anchor)) {
        expect(slide.position.value, Offset.zero,
            reason: 'a slide is still running on $anchor at 550ms');
      }
    }

    // Clean teardown: let every in-flight widget animation (bell fade,
    // recent-activity row staggers) play out before the test ends.
    await tester.pumpAndSettle();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets(
      'entrance direction: header from the left, rail from the right, '
      'pills from below', (tester) async {
    await _pumpHome(tester);

    // First frame: every block sits exactly at its begin offset.
    // The header travels from the LEFT: negative x.
    final header = _ancestorSlides(tester, _headerGift);
    expect(header, isNotEmpty, reason: 'header block has no entrance slide');
    expect(header.first.position.value.dx, lessThan(0));

    // The rail travels from the RIGHT: positive x, opposite the header —
    // the deck is slid in, not dropped.
    final rail = _ancestorSlides(tester, _heroCard);
    expect(rail, isNotEmpty, reason: 'balance rail has no entrance slide');
    expect(rail.first.position.value.dx, greaterThan(0));

    // The action pills rise from BELOW: positive y (the nearest ancestor
    // is the per-pill slide, which shares the block's direction).
    final pill = _ancestorSlides(tester, _addMoneyPill);
    expect(pill, isNotEmpty, reason: 'action pill has no entrance slide');
    expect(pill.first.position.value.dy, greaterThan(0));

    await tester.pumpAndSettle();
  });

  testWidgets(
      'reduced motion: Home is fully painted on the first frame',
      (tester) async {
    await _pumpHome(tester, reduceMotion: true);

    // No fade in flight on any choreographed block…
    for (final anchor in _anchors) {
      for (final fade in _ancestorFades(tester, anchor)) {
        expect(fade.opacity.value, greaterThan(0.999),
            reason: 'a fade is still running on $anchor under reduced '
                'motion');
      }
      // …and no entrance slide: the gate must remove them outright.
      expect(_ancestorSlides(tester, anchor), isEmpty,
          reason: '$anchor still carries a slide under reduced motion');
    }

    // The avatar pop-in is gone too — no non-identity scale anywhere in
    // its transform chain.
    expect(_hasNonIdentityScale(tester, find.byType(Hero)), isFalse,
        reason: 'avatar is scale-popping in under reduced motion');

    await tester.pumpAndSettle();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });
}
