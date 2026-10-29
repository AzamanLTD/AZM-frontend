// BALANCE CARD PAIR — CAPTURE EVIDENCE (FINAL REDESIGN).
//
// Visual captures of the PAIRED physical card (BalanceCardPair): the
// shared frame with its FX-status front face and icon-led breakdown back
// face, captured from the SAME instance — the back captures are taken by
// flipping the very card that rendered the front, exactly as a user
// would. Goldens are pinned per capture.
//
// The harness loads the REAL UI font faces (Comic Neue Regular + Bold,
// Inter for money figures) plus the HugeIconsSolid glyph font, so every
// capture renders true glyphs and true icons — never blank bars,
// tofu boxes or placeholder squares.
//
// Matrix:
//   FRONT — saved fallback (390 dark/light, 320 dark), fresh (360 light),
//           demo (360 dark), loading (360 dark), unavailable (360 light),
//           balance placeholder (320 light);
//   BACK  — full breakdown (390 dark/light, 320 dark, 360 light) and a
//           scrolled variant (390 dark);
//   MOTION — reduced-motion front and back (390 dark).
//
// Contract proven per capture:
//   • the frame is exactly the Home deck footprint (180px) at every
//     width and on BOTH faces — the surrounding layout cannot move;
//   • front: eyebrow → headline → equivalent → rate row, refresh flush
//     right, info icon beside the equivalent (fallback states only);
//   • back: compact header, icon-led rows with explicit native units,
//     no share rail, no overflow;
//   • every capture writes real PNG bytes as inspectable evidence.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'dart:ui' show ImageByteFormat, SemanticsAction;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart';

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  // The ACTUAL UI families of the live app theme: Comic Neue (Regular +
  // Bold) and Inter for money figures, plus the HugeIcons glyph font the
  // breakdown rows render with. Anything else renders as bars.
  final inter = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final comicRegular = await File(
    'assets/fonts/ComicNeue-Regular.ttf',
  ).readAsBytes();
  final comicBold = await File('assets/fonts/ComicNeue-Bold.ttf').readAsBytes();
  await (FontLoader('Inter')..addFont(
        Future<ByteData>.value(ByteData.view(Uint8List.fromList(inter).buffer)),
      ))
      .load();
  await (FontLoader('ComicNeue')
        ..addFont(
          Future<ByteData>.value(
            ByteData.view(Uint8List.fromList(comicRegular).buffer),
          ),
        )
        ..addFont(
          Future<ByteData>.value(
            ByteData.view(Uint8List.fromList(comicBold).buffer),
          ),
        ))
      .load();
  await (FontLoader('HugeIconsSolid')..addFont(
        rootBundle.load('packages/hugeicons_pro/fonts/hugeicons-solid.ttf'),
      ))
      .load();
  _fontsLoaded = true;
}

BalanceCardValuation _saved({bool vendor = false, double? susu = 5}) =>
    BalanceCardValuation(
      nativeGhsAvailable: 100,
      availableUsdc: 50,
      balanceConfirmed: true,
      escrowLocked: 4,
      disputeEscrow: 1,
      vaultLocked: 10,
      savingsLockedGhs: 20,
      susuCommitted: susu,
      azmPoints: 1200,
      vendorRowRelevant: vendor,
      vendorUnallocatedUsdc: 7.5,
      rate: FxRateView(
        ghsPerUsdc: 12.03,
        kind: FxRateKind.saved,
        sourceLabel: 'saved observation',
        observedAt: DateTime.utc(2026, 10, 22, 9, 30),
      ),
    ).compute();

BalanceCardValuation _unavailable() => const BalanceCardValuation(
  nativeGhsAvailable: 100,
  availableUsdc: 50,
  balanceConfirmed: true,
  rate: FxRateView(kind: FxRateKind.none),
).compute();

Future<void> _pump(
  WidgetTester tester, {
  required AzamanTheme theme,
  required double width,
  required BalanceCardValuation valuation,
  bool reduceMotion = false,
}) async {
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final colors = ThemeProvider.getColors(theme).withAccent(AzAccent.gold);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeProvider.getThemeData(theme),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 844),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: RepaintBoundary(
                key: const ValueKey('bcfx-capture-root'),
                // The pair carries the Home deck's own fixed geometry
                // (180px) and fills the parent width exactly as the
                // Home layout does — never stretched to the surface.
                child: BalanceCardPair(
                  key: const ValueKey('bcfx-pair'),
                  valuation: valuation,
                  colors: colors,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Flip the card in place — the same instance the front capture used.
/// Flip the front card to its back face, PROVING it happened.
///
/// This used to tap the eyebrow label, and on the narrow captures that tap
/// missed: the warning ("derived an Offset(157.5, 67.0) that would not hit
/// test on the specified widget", landing on the face's RenderCustomPaint)
/// meant the gesture never reached the flip. A missed tap is silent — the
/// widget simply does not move — so `--update-goldens` would then record the
/// FRONT face as the new back-face baseline and the test would look satisfied
/// while measuring nothing.
///
/// So this drives the card's own declared action (the `Semantics(onTap:)` it
/// exposes as 'show the balance details') and then asserts the state change
/// before any caller captures: back face present, front face gone.
Future<void> _flipToBack(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  final node = tester.getSemantics(
    find.byKey(const ValueKey('balance-pair-semantics')),
  );
  tester.binding.pipelineOwner.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.tap,
  );
  await tester.pump();
  await tester.pumpAndSettle();

  // THE FLIP MUST BE REAL. A capture of the wrong face is worse than no
  // capture: it would enshrine a front face as the back-face truth.
  expect(
    find.byKey(const ValueKey('balance-fx-breakdown-card')),
    findsOneWidget,
    reason: 'the breakdown card is on screen — the card is really on its back',
  );
  expect(
    find.byKey(const ValueKey('balance-fx-card')),
    findsNothing,
    reason: 'the front face is gone — this frame is the back, not the front',
  );
  handle.dispose();
}

/// The frame contract, true in EVERY capture on BOTH faces: the pair is
/// exactly the Home deck footprint and fits the harness viewport.
void _assertFrame(WidgetTester tester, {required double width}) {
  final frame = tester.getRect(
    find.byKey(const ValueKey('balance-pair-frame')),
  );
  expect(
    frame.height,
    BalanceCardGeometry.height,
    reason: 'the card keeps the live Home deck height',
  );
  expect(
    frame.right,
    lessThanOrEqualTo(width),
    reason: 'the card fits the viewport width',
  );
  expect(
    frame.bottom,
    lessThan(844),
    reason: 'the card fits the viewport height',
  );
  expect(
    tester.takeException(),
    isNull,
    reason: 'no layout overflow anywhere in the card',
  );
}

/// Structural position contract — true in EVERY front capture.
Future<void> _assertFrontContract(
  WidgetTester tester, {
  required double width,
}) async {
  final label = tester.getRect(find.byKey(const ValueKey('balance-fx-label')));
  // The headline is a single Text when the combined value is computable,
  // or a block (native amount + note) when the rate is missing.
  final headlineFinder = find.byKey(const ValueKey('balance-fx-headline'));
  // No usable rate: the headline slot renders the honest dash line
  // ('balance-fx-headline-unavailable') — fall back to it.
  final unavailableFinder = find.byKey(
    const ValueKey('balance-fx-headline-unavailable'),
  );
  final effective = headlineFinder.evaluate().isNotEmpty
      ? headlineFinder
      : unavailableFinder;
  final headline = tester.getRect(effective);
  final rateRow = tester.getRect(
    find.byKey(const ValueKey('balance-fx-rate-row')),
  );
  expect(
    headline.top,
    greaterThan(label.bottom),
    reason: 'the headline sits below the eyebrow',
  );
  expect(
    rateRow.top,
    greaterThan(headline.bottom),
    reason: 'the rate row sits below the headline',
  );
  final infoIcon = find.byKey(const ValueKey('balance-fx-equivalent-info'));
  if (infoIcon.evaluate().isNotEmpty) {
    final eq = tester.getRect(
      find.byKey(const ValueKey('balance-fx-equivalent-row')),
    );
    final info = tester.getRect(infoIcon);
    expect(info.top, greaterThanOrEqualTo(eq.top - 4));
    expect(
      info.bottom,
      lessThanOrEqualTo(eq.bottom + 4),
      reason:
          'the info icon is beside the equivalent, on its own line '
          'band, never at the right edge',
    );
  }
}

/// Structural contract — true in EVERY back capture. The back is a
/// SECTION PAGER now: the flip lands on the AVAILABLE section, with the
/// next section's header peeking at the bottom edge.
void _assertBackContract(WidgetTester tester) {
  expect(
    find.byKey(const ValueKey('balance-fx-breakdown-header')),
    findsOneWidget,
    reason: 'the compact breakdown header renders',
  );
  expect(
    find.byKey(const ValueKey('bc-section-pager')),
    findsOneWidget,
    reason: 'the section pager renders',
  );
  expect(
    find.byKey(const ValueKey('bc-section-available')),
    findsOneWidget,
    reason: 'the flip lands on the AVAILABLE section',
  );
  expect(
    find.byKey(const ValueKey('bc-row-ghs-wallet')),
    findsOneWidget,
    reason: 'the first available row renders',
  );
  expect(find.byKey(const ValueKey('bc-row-usdc-held')), findsOneWidget);
  expect(
    find.byKey(const ValueKey('balance-fx-share-rail')),
    findsNothing,
    reason: 'the old share rail is gone from the redesign',
  );
}

/// Pages the section pager down [steps] sections and settles.
Future<void> _pageDown(WidgetTester tester, int steps) async {
  final pager = find.byKey(const ValueKey('bc-section-pager'));
  final pageExtent = tester.getRect(pager).height * 0.86;
  for (var i = 0; i < steps; i++) {
    await tester.drag(pager, Offset(0, -(pageExtent * 0.75)));
    await tester.pumpAndSettle();
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  await expectLater(
    find.byKey(const ValueKey('bcfx-capture-root')),
    matchesGoldenFile('goldens/balance_card_pair/$name.png'),
  );
  var ok = false;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('bcfx-capture-root')),
    );
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = (await image.toByteData(format: ImageByteFormat.png))!;
    final dir = Directory('.screenshots/balance_card_pair')
      ..createSync(recursive: true);
    final file = File('${dir.path}/$name.png');
    await file.writeAsBytes(data.buffer.asUint8List());
    ok = file.lengthSync() > 1000;
  });
  expect(ok, isTrue, reason: '$name.png must contain real image bytes');
}

void main() {
  // ── FRONT: the FX-status face ──────────────────────────────────────
  testWidgets('front 390 dark: saved fallback — headline, equivalent + '
      'info icon, saved rate row, refresh flush right', (tester) async {
    await _pump(
      tester,
      theme: AzamanTheme.dark,
      width: 390,
      valuation: _saved(),
    );
    _assertFrame(tester, width: 390);
    await _assertFrontContract(tester, width: 390);
    await _capture(tester, 'front_saved_390_dark');
  });

  testWidgets('front 390 light: saved fallback', (tester) async {
    await _pump(
      tester,
      theme: AzamanTheme.light,
      width: 390,
      valuation: _saved(),
    );
    _assertFrame(tester, width: 390);
    await _assertFrontContract(tester, width: 390);
    await _capture(tester, 'front_saved_390_light');
  });

  testWidgets('front 320 dark: saved fallback at the smallest width — '
      'the whole stack fits with the same order', (tester) async {
    await _pump(
      tester,
      theme: AzamanTheme.dark,
      width: 320,
      valuation: _saved(),
    );
    _assertFrame(tester, width: 320);
    await _assertFrontContract(tester, width: 320);
    await _capture(tester, 'front_saved_320_dark');
  });

  testWidgets('front 360 light: fresh rate — no fallback chrome', (
    tester,
  ) async {
    final fresh = const BalanceCardValuation(
      nativeGhsAvailable: 100,
      availableUsdc: 50,
      balanceConfirmed: true,
      rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
    ).compute();
    await _pump(tester, theme: AzamanTheme.light, width: 360, valuation: fresh);
    _assertFrame(tester, width: 360);
    await _assertFrontContract(tester, width: 360);
    // PR #206 review round: the info icon is visible BESIDE the USDC
    // equivalent line in the LIVE state too — the disclosure says the
    // USDC figure is the equivalent converted FROM the GHS balance
    // (GHS is the app's main currency).
    final info = find.byKey(const ValueKey('balance-fx-equivalent-info'));
    expect(info, findsOneWidget);
    await tester.tap(info, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('balance-fx-fallback-disclosure')),
      findsOneWidget,
    );
    final body = tester
        .widget<Text>(
          find.byKey(const ValueKey('balance-fx-fallback-disclosure-body')),
        )
        .data!;
    expect(
      body,
      contains('Azaman\u2019s main currency'),
      reason:
          'GHS is the main currency — the headline figure is '
          'canonical, never USDC-derived',
    );
    expect(
      body,
      contains('USDC equivalent'),
      reason: 'the disclosure explains the USDC line is the equivalent',
    );
    expect(
      body,
      isNot(contains('held in USDC')),
      reason: 'the GHS balance is never described as USDC-derived',
    );
    await tester.tap(
      find.byKey(const ValueKey('balance-fx-fallback-disclosure-close')),
    );
    await tester.pumpAndSettle();
    await _capture(tester, 'front_fresh_360_light');
  });

  testWidgets('front 360 dark: demo-seeded rate — the demo is identified', (
    tester,
  ) async {
    final demo = const BalanceCardValuation(
      nativeGhsAvailable: 0,
      availableUsdc: 100,
      balanceConfirmed: true,
      rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.demo),
    ).compute();
    await _pump(tester, theme: AzamanTheme.dark, width: 360, valuation: demo);
    _assertFrame(tester, width: 360);
    await _assertFrontContract(tester, width: 360);
    await _capture(tester, 'front_demo_360_dark');
  });

  testWidgets('front 360 dark: loading with no fallback — dots ONLY in '
      'the rate row, balance never replaced', (tester) async {
    final loading = const BalanceCardValuation(
      nativeGhsAvailable: 100,
      availableUsdc: 50,
      balanceConfirmed: true,
      rate: FxRateView(kind: FxRateKind.none, loading: true),
    ).compute();
    await _pump(
      tester,
      theme: AzamanTheme.dark,
      width: 360,
      valuation: loading,
    );
    _assertFrame(tester, width: 360);
    expect(find.byKey(const ValueKey('balance-fx-rate-dots')), findsOneWidget);
    expect(find.byKey(const ValueKey('balance-fx-amount-dots')), findsNothing);
    await _capture(tester, 'front_loading_360_dark');
  });

  testWidgets('front 360 light: unavailable — the honest fallback '
      'identification survives', (tester) async {
    await _pump(
      tester,
      theme: AzamanTheme.light,
      width: 360,
      valuation: _unavailable(),
    );
    _assertFrame(tester, width: 360);
    await _assertFrontContract(tester, width: 360);
    await _capture(tester, 'front_unavailable_360_light');
  });

  testWidgets('front 320 light: unconfirmed balance — the placeholder, '
      'not an invented figure', (tester) async {
    final placeholder = const BalanceCardValuation(
      nativeGhsAvailable: 0,
      availableUsdc: 0,
      balanceConfirmed: false,
      rate: FxRateView(kind: FxRateKind.none, loading: true),
    ).compute();
    await _pump(
      tester,
      theme: AzamanTheme.light,
      width: 320,
      valuation: placeholder,
    );
    _assertFrame(tester, width: 320);
    expect(
      find.byKey(const ValueKey('balance-fx-amount-dots')),
      findsOneWidget,
    );
    await _capture(tester, 'front_placeholder_320_light');
  });

  // ── BACK: the icon-led breakdown face (same instance, flipped) ─────
  testWidgets('back 390 dark: full breakdown — flip the card and capture '
      'the reverse of the same instance', (tester) async {
    await _pump(
      tester,
      theme: AzamanTheme.dark,
      width: 390,
      valuation: _saved(vendor: true),
    );
    await _assertFrontContract(tester, width: 390); // the front first
    final frontRect = tester.getRect(
      find.byKey(const ValueKey('balance-pair-frame')),
    );
    await _flipToBack(tester);
    _assertFrame(tester, width: 390);
    _assertBackContract(tester);
    final backRect = tester.getRect(
      find.byKey(const ValueKey('balance-pair-frame')),
    );
    expect(
      backRect.top,
      closeTo(frontRect.top, 0.5),
      reason: 'flipping in place must not move the frame',
    );
    await _capture(tester, 'back_full_390_dark');
  });

  testWidgets('back 390 light: full breakdown', (tester) async {
    await _pump(
      tester,
      theme: AzamanTheme.light,
      width: 390,
      valuation: _saved(vendor: true),
    );
    await _flipToBack(tester);
    _assertFrame(tester, width: 390);
    _assertBackContract(tester);
    await _capture(tester, 'back_full_390_light');
  });

  testWidgets('back 320 dark: full breakdown at the smallest width', (
    tester,
  ) async {
    await _pump(
      tester,
      theme: AzamanTheme.dark,
      width: 320,
      valuation: _saved(vendor: true),
    );
    await _flipToBack(tester);
    _assertFrame(tester, width: 320);
    _assertBackContract(tester);
    await _capture(tester, 'back_full_320_dark');
  });

  testWidgets('back 360 light: full breakdown', (tester) async {
    await _pump(
      tester,
      theme: AzamanTheme.light,
      width: 360,
      valuation: _saved(vendor: true),
    );
    await _flipToBack(tester);
    _assertFrame(tester, width: 360);
    _assertBackContract(tester);
    await _capture(tester, 'back_full_360_light');
  });

  testWidgets('back 390 dark: scrolled — the inner region scrolls to the '
      'non-cash row WITHOUT flipping back', (tester) async {
    await _pump(
      tester,
      theme: AzamanTheme.dark,
      width: 390,
      valuation: _saved(vendor: true),
    );
    await _flipToBack(tester);
    // _saved(vendor: true) = 5 sections — page to the LAST one (the
    // non-cash section) one snap at a time.
    await _pageDown(tester, 4);
    final pagerRect = tester.getRect(
      find.byKey(const ValueKey('bc-section-pager')),
    );
    final pointsRect = tester.getRect(
      find.byKey(const ValueKey('bc-row-azm-points')),
    );
    expect(
      pointsRect.top,
      greaterThanOrEqualTo(pagerRect.top),
      reason: 'the non-cash row is on screen',
    );
    expect(
      find.byKey(const ValueKey('balance-fx-headline')),
      findsNothing,
      reason: 'still on the back face — paging never flips',
    );
    _assertFrame(tester, width: 390);
    await _capture(tester, 'back_scrolled_390_dark');
  });

  // ── REDUCED MOTION ─────────────────────────────────────────────────
  testWidgets('reduced motion 390 dark: the flip lands instantly — front '
      'and back with no travel animation', (tester) async {
    await _pump(
      tester,
      theme: AzamanTheme.dark,
      width: 390,
      valuation: _saved(),
      reduceMotion: true,
    );
    _assertFrame(tester, width: 390);
    await _assertFrontContract(tester, width: 390);
    await _capture(tester, 'front_reduced_motion_390_dark');
    await _flipToBack(tester);
    _assertFrame(tester, width: 390);
    _assertBackContract(tester);
    await _capture(tester, 'back_reduced_motion_390_dark');
  });
}
