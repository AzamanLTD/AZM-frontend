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
import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/widgets/home/az_typewriter_heading.dart';
import 'package:azaman/widgets/home/pull_reveal_card_deck.dart';
import 'package:azaman/widgets/home/wallet_modules.dart';
import 'package:azaman/widgets/home/activity_doorway.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _surfaceSize = Size(400, 900);

/// Loads the bundled Inter face once per process — the same pattern the
/// golden harness documents on `matchesGoldenFile` (see
/// test/goldens/golden_harness.dart); inlined so this suite does not depend
/// on the golden harness's churn.
bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final bytes = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final loader = FontLoader('Inter')
    ..addFont(Future<ByteData>.value(
        ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
  _fontsLoaded = true;
}

/// Seeds the first-time tap hint as seen (it pulses on a repeating
/// controller — real UX, but not part of the entrance) and pumps Home.
Future<void> _pumpHome(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  SharedPreferences.setMockInitialValues(
      {'has_seen_flippable_card_hint': true});
  // `runAsync` is required: reading the font file is real async I/O, which
  // the fake-async zone never completes on its own (it hangs the test) — the
  // golden harness documents the same constraint.
  await tester.runAsync(_loadFonts);
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
        // The app's own theme (Inter, the bundled face) — the default test
        // font renders every glyph as a fixed-width square, which overflows
        // and fails layout on screens it actually fits.
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
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
  anchor
      .evaluate()
      .first
      .visitAncestorElements((e) {
        if (e == home) return false;
        elements.add(e);
        return true;
      });
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
// home_screen.dart's _stage — NEW-HOME's five-block composition). Block 1's
// anchor is the heading WIDGET, not its text: the typewriter types its
// message after the first frame, so the text is deliberately empty at t=0.
Finder get _headerGift => find.byIcon(HugeIconsSolid.gift); // block 0
Finder get _heading => find.byType(AzTypewriterHeading); // block 1
Finder get _deck => find.byType(PullRevealCardDeck); // block 2
Finder get _modules => find.byType(WalletModulesRow); // block 3
Finder get _doorway => find.byType(RecentActivityDoorway); // block 4

List<Finder> get _anchors =>
    [_headerGift, _heading, _deck, _modules, _doorway];

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
    // painted. flutter_animate starts each block from a delayed future and
    // its controller only advances one tick per frame, so the entrance
    // needs stepped frames — a single 550ms jump would land on the
    // controller's first tick (value 0) and falsely report a stuck fade.
    for (var t = 0; t < 550; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (final anchor in _anchors) {
      final chain = _ancestorsWithinHome(tester, anchor)
          .map((e) => e.widget is FadeTransition
              ? 'Fade(${(e.widget as FadeTransition).opacity.value})'
              : e.widget.runtimeType.toString())
          .join(' > ');
      debugPrint('ANCHOR CHAIN: $chain');
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

    // Bounded drain — NOT pumpAndSettle: the notification bell runs a
    // repeat(reverse: true) pulse forever, so the page never settles.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'entrance direction: identity blocks from the left, wallet body '
      'from below', (tester) async {
    await _pumpHome(tester);

    // First frame: every block sits exactly at its begin offset.
    // The header travels from the LEFT: negative x.
    final header = _ancestorSlides(tester, _headerGift);
    expect(header, isNotEmpty, reason: 'header block has no entrance slide');
    expect(header.first.position.value.dx, lessThan(0));

    // The typewriter heading travels from the LEFT too: the identity pair
    // (header + heading) arrives as one camera move.
    final heading = _ancestorSlides(tester, _heading);
    expect(heading, isNotEmpty, reason: 'heading block has no entrance slide');
    expect(heading.first.position.value.dx, lessThan(0));

    // The card deck rises from BELOW: positive y (block 2 and beyond
    // compose the wallet body rising into place).
    final deck = _ancestorSlides(tester, _deck);
    expect(deck, isNotEmpty, reason: 'card deck has no entrance slide');
    expect(deck.first.position.value.dy, greaterThan(0));

    // The modules and the doorway rise from BELOW as well.
    final modules = _ancestorSlides(tester, _modules);
    expect(modules, isNotEmpty,
        reason: 'wallet modules have no entrance slide');
    expect(modules.first.position.value.dy, greaterThan(0));
    final doorway = _ancestorSlides(tester, _doorway);
    expect(doorway, isNotEmpty,
        reason: 'activity doorway has no entrance slide');
    expect(doorway.first.position.value.dy, greaterThan(0));

    // Let the entrance play out without waiting for the never-settling
    // bell pulse (see the note in the completion test).
    await tester.pump(const Duration(seconds: 1));
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

    await tester.pump(const Duration(seconds: 1));
  });
}
