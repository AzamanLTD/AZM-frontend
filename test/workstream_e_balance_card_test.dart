// =============================================================================
// AZAMAN — WORKSTREAM E: BALANCE CARD FINISHING (E1–E4 CONTRACT SUITE)
//
// Proves the Workstream E finishing pass on the balance card pair and the
// reminder celebration, on the REAL components:
//
//   E1 — front-face grammar: the GH₵ marker is SMALLER and subordinate to
//        the digits; the squiggly ≈ says 'equivalent' (the trailing word
//        is gone from the visual line); the updating dots + 'Updating
//        rate…' caption read as ONE coherent status in the SAME slot the
//        rate occupies when idle.
//   E2 — the documented 320dp 4-digit overflow (PR #190 known defect) is
//        fixed at the CAUSE: the headline is a single typographic line
//        that responsively fits at every width, the fixture is never
//        pre-shrunk, the 165px frame is preserved and the rate row never
//        fights the headline for space.
//   E3 — back-face rhythm: baseline-aligned rows, uniform hairline
//        dividers between rows within a section (never after a section's
//        last row), long detail text stays readable.
//   E4 — the celebration originates at the reminder section's HEADER and
//        sprays DOWN over the content below — never from the card.
//
// The pair is demo/contract-seam only (PR #190): nothing here touches the
// live production card, which stays unchanged until the backend valuation
// contract is verified end-to-end.
// =============================================================================

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart';
import 'package:azaman/widgets/home/home_reminder_deck.dart';

bool _fontsLoaded = false;

/// Loads the REAL font faces the card renders with (same rationale as the
/// fx suite: substituted tofu squares wrap unnaturally and overflow
/// fixed-height cards spuriously).
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  await (FontLoader('Inter')..addFont(
        File(
          'assets/fonts/Inter-Variable.ttf',
        ).readAsBytes().then((b) => ByteData.view(b.buffer)),
      ))
      .load();
  for (final f in ['ComicNeue-Regular.ttf', 'ComicNeue-Bold.ttf']) {
    await (FontLoader('ComicNeue')..addFont(
          File(
            'assets/fonts/$f',
          ).readAsBytes().then((b) => ByteData.view(b.buffer)),
        ))
        .load();
  }
  await (FontLoader('HugeIconsSolid')..addFont(
        rootBundle.load('packages/hugeicons_pro/fonts/hugeicons-solid.ttf'),
      ))
      .load();
  _fontsLoaded = true;
}

/// A confirmed balance with a FRESH rate over [ghs] — the headline fixture
/// for the E2 digit-length matrix. combined = native + usdc × rate.
BalanceCardValuation _freshGhs(double ghs) => BalanceCardValuation(
  nativeGhsAvailable: 0,
  availableUsdc: ghs / 12.5,
  balanceConfirmed: true,
  azmPoints: 0,
  rate: const FxRateView(
    ghsPerUsdc: 12.5,
    kind: FxRateKind.fresh,
    sourceLabel: 'oracle',
  ),
).compute();

BalanceCardValuation _saved({bool vendor = false}) => BalanceCardValuation(
  nativeGhsAvailable: 100,
  availableUsdc: 50,
  balanceConfirmed: true,
  escrowLocked: 4,
  disputeEscrow: 1,
  vaultLocked: 10,
  savingsLockedGhs: 20,
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

/// Confirmed balance while the rate is still loading with NO fallback
/// shown — the state whose rate slot must read as ONE updating status.
BalanceCardValuation _loadingRate() => BalanceCardValuation(
  nativeGhsAvailable: 100,
  availableUsdc: 50,
  balanceConfirmed: true,
  azmPoints: 1200,
  rate: const FxRateView(kind: FxRateKind.none, loading: true),
).compute();

Future<void> _pumpPair(
  WidgetTester tester, {
  required BalanceCardValuation valuation,
  double width = 390,
}) async {
  await tester.runAsync(_loadFonts);
  final colors = ThemeProvider.getColors(
    AzamanTheme.dark,
  ).withAccent(AzAccent.gold);
  await tester.binding.setSurfaceSize(Size(width, 844));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeProvider.getThemeData(AzamanTheme.dark),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 844)),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: RepaintBoundary(
                key: const ValueKey('we-pair-root'),
                child: SizedBox(
                  width: double.infinity,
                  child: BalanceCardPair(valuation: valuation, colors: colors),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Rect _frameRect(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('balance-pair-frame')));

/// The headline Text under the fitted headline widget (the key sits on
/// the widget's root; the rich text is its descendant).
Text _headlineText(WidgetTester tester, {required Key key}) => tester.widget(
  find.descendant(of: find.byKey(key), matching: find.byType(Text)).first,
);

Future<void> _flipToBack(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('balance-pair-flip-listener')));
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  group('E1 — front-face grammar', () {
    testWidgets('the GH₵ marker is SMALLER + subordinate to the digits', (
      tester,
    ) async {
      await _pumpPair(tester, valuation: _freshGhs(1234.56));
      final text = _headlineText(
        tester,
        key: const ValueKey('balance-fx-headline'),
      );
      final span = text.textSpan as TextSpan;
      // One marker span + one digits span — a single typographic line.
      expect(span.children, hasLength(1));
      expect(span.text, '${AzMoney.ghsSymbol}${AzMoney.nbsp}');
      expect(
        span.style?.fontSize,
        16,
        reason:
            'the currency marker is small, never part of the hero '
            'block',
      );
      final digits = span.children!.single as TextSpan;
      expect(digits.text, AzMoney.amount(1234.56));
      expect(
        digits.style?.fontSize,
        AzText.sizeHero,
        reason: 'the AMOUNT is the hero',
      );
    });

    testWidgets('the squiggly ≈ says equivalent — the trailing word is '
        'gone from the visual line', (tester) async {
      await _pumpPair(tester, valuation: _saved());
      // The VISIBLE span (not the screen-reader label, which keeps the
      // honest full explanation): '≈ 58.31 USDC' and nothing after.
      final visible = tester.widget<Text>(
        find.byKey(const ValueKey('balance-fx-equivalent')),
      );
      final span = visible.textSpan as TextSpan;
      expect(span.text, startsWith('≈ '));
      expect(span.text, endsWith(' USDC'));
      expect(
        span.text!.contains('equivalent'),
        isFalse,
        reason:
            "the word 'Equivalent' is dropped — the ≈ already says "
            'it',
      );
      expect(
        span.children ?? const <InlineSpan>[],
        isEmpty,
        reason: 'the old trailing word span is gone entirely',
      );
      // The info icon is retained beside the figure.
      expect(
        find.byKey(const ValueKey('balance-fx-equivalent-info')),
        findsOneWidget,
      );
    });

    testWidgets('updating dots + caption read as ONE status in the SAME '
        'slot as the idle rate', (tester) async {
      // Idle: the saved-rate caption occupies the rate row.
      await _pumpPair(tester, valuation: _saved());
      final idleRow = tester.getRect(
        find.byKey(const ValueKey('balance-fx-rate-row')),
      );
      final idleRate = tester.getRect(
        find.byKey(const ValueKey('balance-fx-rate-saved')),
      );

      // Loading without a fallback: dots + 'Updating rate…' in one row.
      await _pumpPair(tester, valuation: _loadingRate());
      final updatingRow = tester.getRect(
        find.byKey(const ValueKey('balance-fx-rate-updating')),
      );
      final dots = tester.getRect(
        find.byKey(const ValueKey('balance-fx-rate-dots')),
      );
      final label = tester.getRect(
        find.byKey(const ValueKey('balance-fx-rate-updating-label')),
      );
      expect(find.text('Updating rate…', findRichText: true), findsOneWidget);
      // Dots and caption share the updating row's band.
      expect(dots.top, greaterThanOrEqualTo(updatingRow.top));
      expect(dots.bottom, lessThanOrEqualTo(updatingRow.bottom + 1));
      expect(label.top, greaterThanOrEqualTo(updatingRow.top));
      expect(label.bottom, lessThanOrEqualTo(updatingRow.bottom + 1));
      expect(
        label.left,
        greaterThan(dots.right),
        reason: 'the caption reads AFTER the dots, one coherent status',
      );
      // SAME slot: the rate row itself is PINNED at the bottom of the
      // fixed 165px card — identical whether the slot shows the idle
      // rate or the updating status. The updating row is its leading
      // content.
      final loadRow = tester.getRect(
        find.byKey(const ValueKey('balance-fx-rate-row')),
      );
      // The slot's invariant is its PINNED BOTTOM (the card's fixed
      // footprint): its height may differ by a pixel of caption metric,
      // but the slot hugs the same bottom edge in both states.
      expect(
        loadRow.bottom,
        closeTo(idleRow.bottom, 0.5),
        reason: 'the rate slot never moves between loading and idle',
      );
      expect(updatingRow.top, greaterThanOrEqualTo(loadRow.top));
      expect(updatingRow.bottom, lessThanOrEqualTo(loadRow.bottom + 1));
      expect(updatingRow.left, closeTo(idleRate.left, 2.0));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('E2 — the documented 320dp overflow, fixed at the cause', () {
    testWidgets('the PR #190 repro figure fits on ONE line at 320dp: '
        'no overflow, no pre-shrunk fixture, 165px frame', (tester) async {
      // ~GH₵ 5,234.50 — the documented 4-digit repro scale.
      await _pumpPair(tester, valuation: _freshGhs(5234.50), width: 320);
      expect(tester.takeException(), isNull);
      expect(
        _frameRect(tester).height,
        BalanceCardGeometry.height,
        reason: 'the 165px geometry is preserved',
      );
      final headline = tester.getRect(
        find.byKey(const ValueKey('balance-fx-headline')),
      );
      final frame = _frameRect(tester);
      expect(
        headline.width,
        lessThanOrEqualTo(frame.width - 32),
        reason: 'the fitted headline stays inside the card interior',
      );
      expect(
        headline.height,
        lessThan(56),
        reason: 'a SINGLE line — never a wrapped two-line figure',
      );
      // The rate row is pinned at the bottom, never fighting the headline.
      final rateRow = tester.getRect(
        find.byKey(const ValueKey('balance-fx-rate-row')),
      );
      expect(rateRow.top, greaterThan(headline.bottom));
      expect(rateRow.bottom, closeTo(frame.bottom - 16, 6));
      await tester.pumpWidget(const SizedBox());
    });

    for (final width in [320.0, 360.0, 390.0]) {
      testWidgets('digit-length range at ${width.toInt()}dp: single-line '
          'headline at every realistic scale', (tester) async {
        const amounts = [
          9.99,
          99.99,
          999.50,
          5234.50, // the documented repro
          49342.10, // 5-digit
          123456.78, // 6-digit
        ];
        for (final a in amounts) {
          await _pumpPair(tester, valuation: _freshGhs(a), width: width);
          expect(
            tester.takeException(),
            isNull,
            reason:
                'no overflow rendering ${AzMoney.ghs(a)} at '
                '${width.toInt()}dp',
          );
          expect(_frameRect(tester).height, BalanceCardGeometry.height);
          final headline = tester.getRect(
            find.byKey(const ValueKey('balance-fx-headline')),
          );
          final frame = _frameRect(tester);
          expect(headline.right, lessThanOrEqualTo(frame.right - 12));
          expect(
            headline.height,
            lessThan(56),
            reason: 'always one line for ${AzMoney.ghs(a)}',
          );
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('E3 — back-face rhythm', () {
    testWidgets('uniform hairline dividers sit BETWEEN rows within a '
        'section; the last row of a section carries none', (tester) async {
      await _pumpPair(tester, valuation: _saved(vendor: true));
      await _flipToBack(tester);

      // Lazy ListView (fixed 165px card, rows disposed when they scroll
      // far off): the divider contract is asserted PER ROW, on whichever
      // rows are built, rather than by a global count.

      // Between-rows contract on the visible AVAILABLE section: the
      // ghs-wallet divider separates the two rows.
      final ghsRow = tester.getRect(
        find.byKey(const ValueKey('bc-row-ghs-wallet')),
      );
      final usdcRow = tester.getRect(
        find.byKey(const ValueKey('bc-row-usdc-held')),
      );
      final ghsDivider = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('bc-row-ghs-wallet')),
          matching: find.byKey(const ValueKey('bc-row-divider')),
        ),
      );
      expect(ghsDivider.top, greaterThan(ghsRow.top));
      expect(ghsDivider.bottom, lessThan(usdcRow.bottom));
      expect(ghsDivider.height, 1.0);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bc-row-usdc-held')),
          matching: find.byKey(const ValueKey('bc-row-divider')),
        ),
        findsNothing,
        reason: 'the section-last row carries no divider',
      );

      // Scroll to the tail: susu (a vendor row follows) carries one;
      // vendor and azm points (section lasts) carry none.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('bc-row-azm-points')),
        80,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('bc-breakdown-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bc-row-susu')),
          matching: find.byKey(const ValueKey('bc-row-divider')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bc-row-vendor')),
          matching: find.byKey(const ValueKey('bc-row-divider')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bc-row-azm-points')),
          matching: find.byKey(const ValueKey('bc-row-divider')),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('rows sit on ONE typographic baseline; long detail text '
        'stays readable', (tester) async {
      await _pumpPair(tester, valuation: _saved(vendor: true));
      await _flipToBack(tester);
      // The escrow row's detail is below the fold of the fixed frame —
      // bring it into the built region first.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('bc-row-escrow')),
        80,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('bc-breakdown-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      final row = find
          .descendant(
            of: find.byKey(const ValueKey('bc-row-ghs-wallet')),
            matching: find.byType(Row),
          )
          .first;
      final rowWidget = tester.widget<Row>(row);
      expect(
        rowWidget.crossAxisAlignment,
        CrossAxisAlignment.baseline,
        reason: 'label, amount and unit share one baseline line',
      );

      final escrowDetail = find.descendant(
        of: find.byKey(const ValueKey('bc-row-escrow')),
        matching: find.textContaining('Disputes'),
      );
      final detailText = tester.widget<Text>(escrowDetail);
      expect(
        detailText.maxLines,
        2,
        reason:
            'long detail wraps to a second line instead of '
            'truncating mid-fact',
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('E4 — the celebration originates at the section header', () {
    test('the emitter origin is the HEADER band, centred', () {
      final o = reminderConfettiHeaderOrigin(const Size(400, 300));
      expect(o.dx, 200);
      expect(
        o.dy,
        10,
        reason:
            'the burst leaves the header band at the top of the '
            'section, never the deck card',
      );
    });

    test('every trajectory sprays DOWN over the content below', () {
      final particles = ConfettiSystem.generate(seed: 7341, count: 26);
      expect(particles, hasLength(26));
      for (final p in particles) {
        expect(
          math.sin(p.angle),
          greaterThan(0),
          reason: 'no particle may fly upward, out of the section',
        );
      }
    });
  });
}
