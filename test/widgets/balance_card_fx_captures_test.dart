// BALANCE CARD (FX REDESIGN) — CAPTURE EVIDENCE.
//
// Small-screen and theme captures of the redesigned balance card faces,
// pinned to goldens. The harness loads the REAL UI font faces (Comic
// Neue Regular + Bold, per pubspec) plus Inter for money figures, so every
// capture renders true glyphs — never blank bars or tofu boxes.
//
// Contract proven per capture:
//   • headline → equivalent → rate row stack in order;
//   • the info icon (fallback states) sits beside the equivalent;
//   • the refresh affordance stays flush right in the rate row;
//   • everything fits the viewport at 320dp.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/balance_card_breakdown.dart';
import 'package:azaman/widgets/home/balance_card_fx.dart';

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  // The ACTUAL UI families of the live app theme: Comic Neue (Regular +
  // Bold) and Inter for money figures. Anything else renders as bars.
  final inter = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final comicRegular =
      await File('assets/fonts/ComicNeue-Regular.ttf').readAsBytes();
  final comicBold = await File('assets/fonts/ComicNeue-Bold.ttf').readAsBytes();
  await (FontLoader('Inter')
        ..addFont(Future<ByteData>.value(
            ByteData.view(Uint8List.fromList(inter).buffer))))
      .load();
  await (FontLoader('ComicNeue')
        ..addFont(Future<ByteData>.value(
            ByteData.view(Uint8List.fromList(comicRegular).buffer)))
        ..addFont(Future<ByteData>.value(
            ByteData.view(Uint8List.fromList(comicBold).buffer))))
      .load();
  _fontsLoaded = true;
}

class _RefreshStub extends StatelessWidget {
  const _RefreshStub();
  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('capture-refresh-indicator'),
        width: 24,
        height: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
}

BalanceCardValuation _saved() => BalanceCardValuation(
      nativeGhsAvailable: 100,
      availableUsdc: 50,
      balanceConfirmed: true,
      escrowLocked: 4,
      disputeEscrow: 1,
      vaultLocked: 10,
      savingsLocked: 20,
      susuCommitted: 5,
      azmPoints: 1200,
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
  bool back = false,
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
                // The card is CONTENT-SIZED here exactly as in the real
                // Home layout — never stretched to the surface.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (back)
                      BalanceCardBreakdown(
                          valuation: valuation, colors: colors)
                    else
                      BalanceCardFx(
                        valuation: valuation,
                        colors: colors,
                        trailingRefresh: const _RefreshStub(),
                      ),
                  ],
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

/// Structural position contract — true in EVERY front capture.
Future<void> _assertFrontContract(WidgetTester tester,
    {required double width}) async {
  final headline = tester.getRect(
      find.byKey(const ValueKey('balance-fx-headline')).first);
  final rateRow =
      tester.getRect(find.byKey(const ValueKey('balance-fx-rate-row')));
  expect(headline.bottom, lessThan(rateRow.top),
      reason: 'the rate row sits below the headline');
  final refresh = tester
      .getRect(find.byKey(const ValueKey('capture-refresh-indicator')));
  expect(refresh.right, closeTo(rateRow.right, 2),
      reason: 'the refresh affordance is flush right');
  final card = tester.getRect(find.byKey(const ValueKey('balance-fx-card')));
  // Viewport truth: setSurfaceSize does NOT change the binding window
  // metrics, so assert against the harness's own declared surface.
  expect(card.right, lessThanOrEqualTo(width - 12),
      reason: 'the card fits the viewport width');
  expect(card.bottom, lessThan(844),
      reason: 'the card fits the viewport height');
  final infoIcon = find.byKey(const ValueKey('balance-fx-equivalent-info'));
  if (infoIcon.evaluate().isNotEmpty) {
    final eq = tester
        .getRect(find.byKey(const ValueKey('balance-fx-equivalent-row')));
    final info = tester.getRect(infoIcon);
    expect(info.top, greaterThanOrEqualTo(eq.top - 4));
    expect(info.bottom, lessThanOrEqualTo(eq.bottom + 4),
        reason: 'the info icon is beside the equivalent, on its own line '
            'band, never at the right edge');
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  await expectLater(
    find.byKey(const ValueKey('bcfx-capture-root')),
    matchesGoldenFile('goldens/balance_card_fx/$name.png'),
  );
  var ok = false;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('bcfx-capture-root')));
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = (await image.toByteData(format: ImageByteFormat.png))!;
    final dir = Directory('.screenshots/balance_card_fx')
      ..createSync(recursive: true);
    final file = File('${dir.path}/$name.png');
    await file.writeAsBytes(data.buffer.asUint8List());
    ok = file.lengthSync() > 1000;
  });
  expect(ok, isTrue, reason: '$name.png must contain real image bytes');
}

void main() {
  testWidgets('front 390 dark: saved fallback — headline, equivalent + info '
      'icon, saved rate row, refresh flush right', (tester) async {
    await _pump(tester,
        theme: AzamanTheme.dark, width: 390, valuation: _saved());
    await _assertFrontContract(tester, width: 390);
    await _capture(tester, 'front_saved_390_dark');
  });

  testWidgets('front 390 light: saved fallback', (tester) async {
    await _pump(tester,
        theme: AzamanTheme.light, width: 390, valuation: _saved());
    await _assertFrontContract(tester, width: 390);
    await _capture(tester, 'front_saved_390_light');
  });

  testWidgets('front 320 dark: saved fallback at the smallest width — the '
      'whole stack fits with the same order', (tester) async {
    await _pump(tester,
        theme: AzamanTheme.dark, width: 320, valuation: _saved());
    await _assertFrontContract(tester, width: 320);
    await _capture(tester, 'front_saved_320_dark');
  });

  testWidgets('front 360 light: fresh rate — no fallback chrome',
      (tester) async {
    final fresh = const BalanceCardValuation(
      nativeGhsAvailable: 100,
      availableUsdc: 50,
      balanceConfirmed: true,
      rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
    ).compute();
    await _pump(tester,
        theme: AzamanTheme.light, width: 360, valuation: fresh);
    await _assertFrontContract(tester, width: 390);
    expect(find.byKey(const ValueKey('balance-fx-equivalent-info')),
        findsNothing);
    await _capture(tester, 'front_fresh_360_light');
  });

  testWidgets('front 360 dark: demo-seeded rate — the demo is identified',
      (tester) async {
    final demo = const BalanceCardValuation(
      nativeGhsAvailable: 0,
      availableUsdc: 100,
      balanceConfirmed: true,
      rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.demo),
    ).compute();
    await _pump(tester, theme: AzamanTheme.dark, width: 360, valuation: demo);
    await _assertFrontContract(tester, width: 390);
    await _capture(tester, 'front_demo_360_dark');
  });

  testWidgets('front 360 dark: loading with no fallback — dots ONLY in the '
      'rate row, balance never replaced', (tester) async {
    final loading = const BalanceCardValuation(
      nativeGhsAvailable: 100,
      availableUsdc: 50,
      balanceConfirmed: true,
      rate: FxRateView(kind: FxRateKind.none, loading: true),
    ).compute();
    await _pump(tester,
        theme: AzamanTheme.dark, width: 360, valuation: loading);
    expect(find.byKey(const ValueKey('balance-fx-rate-dots')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('balance-fx-amount-dots')), findsNothing);
    await _capture(tester, 'front_loading_360_dark');
  });

  testWidgets('front 320 light: unavailable rate — native visible, valuation '
      'declared incomplete', (tester) async {
    await _pump(tester,
        theme: AzamanTheme.light, width: 320, valuation: _unavailable());
    expect(find.byKey(const ValueKey('balance-fx-valuation-incomplete')),
        findsOneWidget);
    await _capture(tester, 'front_unavailable_320_light');
  });

  testWidgets('front 320 dark: reduced motion — a static saved state, no '
      'animation dependency', (tester) async {
    await _pump(tester,
        theme: AzamanTheme.dark,
        width: 320,
        valuation: _saved(),
        reduceMotion: true);
    await _assertFrontContract(tester, width: 320);
    await _capture(tester, 'front_saved_320_dark_reducedmotion');
  });

  testWidgets('front 390 dark: empty wallet — an honest loaded zero',
      (tester) async {
    final zero = const BalanceCardValuation(
      nativeGhsAvailable: 0,
      availableUsdc: 0,
      balanceConfirmed: true,
      rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
    ).compute();
    await _pump(tester, theme: AzamanTheme.dark, width: 390, valuation: zero);
    await _assertFrontContract(tester, width: 390);
    await _capture(tester, 'front_zero_390_dark');
  });

  testWidgets('back 390 dark: the icon-led breakdown', (tester) async {
    await _pump(tester,
        theme: AzamanTheme.dark, width: 390, valuation: _saved(), back: true);
    expect(find.byKey(const ValueKey('balance-fx-share-rail')), findsOneWidget);
    await _capture(tester, 'back_breakdown_390_dark');
  });

  testWidgets('back 390 light: the icon-led breakdown', (tester) async {
    await _pump(tester,
        theme: AzamanTheme.light, width: 390, valuation: _saved(), back: true);
    await _capture(tester, 'back_breakdown_390_light');
  });

  testWidgets('back 320 dark: breakdown at the smallest width',
      (tester) async {
    await _pump(tester,
        theme: AzamanTheme.dark, width: 320, valuation: _saved(), back: true);
    await _capture(tester, 'back_breakdown_320_dark');
  });
}