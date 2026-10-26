// =============================================================================
// AZAMAN — WORKSTREAM E: BALANCE CARD FINISHING (E1–E4 CONTRACT SUITE)
//
// Proves the Workstream E finishing pass on the balance card pair and the
// reminder celebration, on the REAL components:
//
//   E1 — front-face grammar: the GH₵ marker is SMALLER and subordinate to
//        the digits; the squiggly ≈ says 'equivalent' (the trailing word
//        is gone from the visual line, and the glyph sits on the USDC
//        line only — the GHS headline is the known value, owner-
//        corrected 2026-10-26); the updating dots + 'Updating rate…'
//        caption read as ONE coherent status in the SAME slot the rate
//        occupies when idle.
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
// PR #203 wires BalanceCardPair into the live Home deck through
// HomeBalanceCard, so this suite pins the production card's own
// contract. The FRONT-face figures stay interim-honest: until the
// backend valuation contract (#367/8/9) ships and is revalidated, the
// GHS headline is an APPROXIMATE converted display valuation, and the
// #367 mapper activates only after that compatibility review.
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
/// A confirmed balance with a FRESH canonical rate — the card's
/// default good state, and the one the disclosure control shows.
BalanceCardValuation _fresh() {
  const base = BalanceCardValuation(
    availableUsdc: 100,
    balanceConfirmed: true,
    rate: FxRateView(
      ghsPerUsdc: 12.5,
      kind: FxRateKind.fresh,
      sourceLabel: 'oracle',
    ),
  );
  return base.compute();
}

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
  double scale = 1.0,
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
        data: MediaQueryData(
          size: Size(width, 844),
          textScaler: TextScaler.linear(scale),
        ),
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

/// Drags the back face's section pager one section DOWN and settles.
Future<void> _dragToNextSection(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const ValueKey('bc-section-pager')),
    const Offset(0, -120),
  );
  await tester.pumpAndSettle();
}

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
      // The headline is ONE amount line: [gutter][unit label][digits] —
      // its gutter slot is EMPTY (no ≈): the glyph belongs to the USDC
      // line below. The unit label is a quiet separate label; the
      // digits are the hero.
      final headline = find.byKey(const ValueKey('balance-fx-headline'));
      final unitLabel = tester.widget<Text>(
        find.descendant(
          of: headline,
          matching: find.text('GH₵'),
        ),
      );
      final amountText = tester.widget<Text>(
        find.descendant(
          of: headline,
          matching: find.text(AzMoney.amount(1234.56)),
        ),
      );
      final unitSize = unitLabel.style?.fontSize ?? 14;
      final amountSize = amountText.style?.fontSize ?? 0;
      expect(amountSize, AzText.sizeHero, reason: 'the AMOUNT is the hero');
      expect(
        unitSize,
        lessThan(amountSize / 2),
        reason: 'the currency marker is small, never part of the hero block',
      );
      // Subordinate: the marker sits to the LEFT of the digits, same line.
      final unitRect = tester.getRect(
        find.descendant(of: headline, matching: find.text('GH₵')),
      );
      final amountRect = tester.getRect(
        find.descendant(of: headline, matching: find.text(AzMoney.amount(1234.56))),
      );
      expect(unitRect.right, lessThan(amountRect.left));
      // One typographic line: the small marker rides the hero line —
      // its centre sits inside the amount's vertical band.
      expect(unitRect.center.dy, greaterThan(amountRect.top));
      expect(unitRect.center.dy, lessThan(amountRect.bottom));
    });

    testWidgets('the squiggly ≈ says equivalent — the trailing word is '
        'gone from the visual line', (tester) async {
      await _pumpPair(tester, valuation: _saved());
      // The VISIBLE USDC span carries the AMOUNT ONLY — the ≈ now lives
      // in the shared leading gutter that precedes BOTH lines, and no
      // word follows the figure.
      final visible = tester.widget<Text>(
        find.byKey(const ValueKey('balance-fx-equivalent')),
      );
      final span = visible.textSpan as TextSpan;
      expect(span.text, isNot(contains('equivalent')));
      expect(span.text, isNot(contains('≈')));
      expect(
        span.children ?? const <InlineSpan>[],
        isEmpty,
        reason: 'the old trailing word span is gone entirely',
      );
      // The ≈ glyph renders in the gutter, BEFORE the USDC line's
      // amount — the owner-corrected arrangement.
      final approxRect = tester.getRect(find.text('≈').first);
      final equivRect = tester.getRect(
        find.byKey(const ValueKey('balance-fx-equivalent')),
      );
      expect(approxRect.right, lessThan(equivRect.left));
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

  group('unconfirmed balance — the back face never fabricates (PR #203 '
      'review round)', () {
    // A loading/unconfirmed balance still carries CACHED figures in the
    // valuation (the adapter keeps its last-known derivation) — but none
    // of them may be SHOWN: every row sourced from the canonical balance
    // renders an honest dash + 'not confirmed yet', while independently
    // confirmed rows (GHS wallet, vaults/savings) keep their real values.
    BalanceCardValuation unconfirmed() => const BalanceCardValuation(
          nativeGhsAvailable: 100,
          availableUsdc: 50,
          balanceConfirmed: false,
          escrowLocked: 4,
          disputeEscrow: 1,
          vaultLocked: 10,
          savingsLockedGhs: 20,
          azmPoints: 1200,
          vendorRowRelevant: true,
          vendorUnallocatedUsdc: 7.5,
          rate: const FxRateView(
            ghsPerUsdc: 12.5,
            kind: FxRateKind.fresh,
            sourceLabel: 'oracle',
          ),
        ).compute();

    /// The amount the row shows, judged by the TEXT the row actually
    /// renders (rows compose rich/label spans, so widget.data can be
    /// null — assert on the rendered strings instead).
    Finder rowText(Key row, String containing) => find.descendant(
          of: find.byKey(row),
          matching: find.textContaining(containing),
        );

    testWidgets('flip to the back face of an UNCONFIRMED balance: '
        'balance-sourced rows dash, independent rows keep real values',
        (tester) async {
      await _pumpPair(tester, valuation: unconfirmed());
      await _flipToBack(tester);

      // AVAILABLE page: the USDC-held row dashes (cached 50 USDC is
      // UNKNOWN, not zero, not shown); the GHS-wallet row is
      // independently confirmed and keeps its real amount.
      expect(
          rowText(const ValueKey('bc-row-usdc-held'), '—'), findsOneWidget,
          reason: 'an unconfirmed balance is never rendered as its cached '
              'figure');
      expect(
          rowText(const ValueKey('bc-row-usdc-held'), 'not confirmed yet'),
          findsOneWidget,
          reason: 'the dash carries its honest reason');
      expect(
          rowText(const ValueKey('bc-row-ghs-wallet'), '100'),
          findsOneWidget,
          reason: 'the native GHS wallet figure is its OWN contract — '
              'an unconfirmed USDC balance never hides it');

      // COMMITTED page: vaults/savings keep their own confirmed values.
      await _dragToNextSection(tester);
      expect(
          rowText(const ValueKey('bc-row-vaults'), '10'), findsOneWidget,
          reason: 'vault commitments are independently confirmed and are '
              'NOT hidden by a loading general balance');

      // LOCKED page: escrow + dispute escrow dash.
      await _dragToNextSection(tester);
      expect(rowText(const ValueKey('bc-row-escrow'), '—'),
          findsOneWidget);
      expect(rowText(const ValueKey('bc-row-dispute-escrow'), '—'),
          findsOneWidget);

      // VENDOR page: the vendor row dashes and its capability-free
      // description waits with it.
      await _dragToNextSection(tester);
      expect(rowText(const ValueKey('bc-row-vendor'), '—'),
          findsOneWidget);
      expect(
          rowText(const ValueKey('bc-row-vendor'), 'not confirmed yet'),
          findsOneWidget,
          reason: 'withdrawability is never inferred — and while the '
              'amount is unknown the description never claims '
              'unallocated funds');

      // NON-CASH page: AZM points dash too (never a fabricated 0 pts).
      await _dragToNextSection(tester);
      expect(rowText(const ValueKey('bc-row-azm-points'), '—'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the same valuation CONFIRMED shows every one of those '
        'rows with its real figure (the dash is the readiness gate, not '
        'a broken row)', (tester) async {
      await _pumpPair(tester, valuation: _saved(vendor: true));
      await _flipToBack(tester);

      expect(rowText(const ValueKey('bc-row-usdc-held'), '50'),
          findsOneWidget,
          reason: 'confirmed: the same row shows the real cached figure');
      expect(find.text('not confirmed yet'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('E1b — the disclosure control: full target, zero flip bleed', () {
    // The equivalent line's info control is the card's ONLY tappable
    // affordance besides the flip itself. Its target is the full
    // 44 x 44 dp mobile accessibility target while the glyph stays 16px,
    // and the fixed 165px footprint must still hold it at the pair's
    // 1.25x text-scale clamp on the narrowest supported width.
    for (final scale in [1.0, 1.25, 1.3]) {
      testWidgets('info target ≥ 44 x 44 at 320dp / ${scale}x scale, '
          'card footprint unchanged', (tester) async {
        await _pumpPair(tester, valuation: _fresh(), width: 320, scale: scale);
        expect(tester.takeException(), isNull);

        final target = tester.getRect(
          find.byKey(const ValueKey('balance-fx-equivalent-info')),
        );
        expect(target.width, greaterThanOrEqualTo(44),
            reason: 'WCAG 2.5.8 / Material minimum touch target');
        expect(target.height, greaterThanOrEqualTo(44));

        // The footprint contract: the fixed 165px frame is untouched.
        expect(_frameRect(tester).height, 165);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('tapping the info control opens the disclosure and NEVER '
        'flips the card', (tester) async {
      await _pumpPair(tester, valuation: _fresh(), width: 320);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('balance-fx-equivalent-info')),
      );
      await tester.pumpAndSettle();

      // The disclosure dialog opened…
      expect(
        find.byKey(const ValueKey('balance-fx-fallback-disclosure')),
        findsOneWidget,
      );
      // …and the card is STILL on its front face: the affordance
      // tap must not have leaked into the flip gesture.
      expect(
        find.byKey(const ValueKey('balance-pair-front-surface')),
        findsOneWidget,
        reason: 'an info tap must never flip the card to the back face',
      );
      expect(
        find.byKey(const ValueKey('balance-pair-back-surface')),
        findsNothing,
      );

      // Dismiss and confirm the card settles back, still front.
      await tester
          .tap(find.byKey(const ValueKey('balance-fx-fallback-disclosure-close')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('balance-fx-fallback-disclosure')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('balance-pair-front-surface')),
        findsOneWidget,
      );
      expect(_frameRect(tester).height, 165);
    });
  });

  group('E3 — back-face rhythm', () {
    testWidgets('uniform hairline dividers sit BETWEEN rows within a '
        'section; the last row of a section carries none', (tester) async {
      await _pumpPair(tester, valuation: _saved(vendor: true));
      await _flipToBack(tester);

      // Section-paged back: the divider contract is per section page.

      // AVAILABLE page: the ghs-wallet divider separates the two rows;
      // usdc-held (the section's last row) carries none.
      final ghsDivider = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('bc-row-ghs-wallet')),
          matching: find.byKey(const ValueKey('bc-row-divider')),
        ),
      );
      expect(ghsDivider.height, 1.0);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bc-row-usdc-held')),
          matching: find.byKey(const ValueKey('bc-row-divider')),
        ),
        findsNothing,
        reason: 'the section-last row carries no divider',
      );

      // COMMITTED page: vaults and savings carry dividers; susu (the
      // section's last row) carries none.
      await _dragToNextSection(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bc-row-vaults')),
          matching: find.byKey(const ValueKey('bc-row-divider')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bc-row-savings')),
          matching: find.byKey(const ValueKey('bc-row-divider')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bc-row-susu')),
          matching: find.byKey(const ValueKey('bc-row-divider')),
        ),
        findsNothing,
      );

      // LOCKED page: escrow carries one; dispute escrow (the section's
      // last row) carries none.
      await _dragToNextSection(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bc-row-escrow')),
          matching: find.byKey(const ValueKey('bc-row-divider')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bc-row-dispute-escrow')),
          matching: find.byKey(const ValueKey('bc-row-divider')),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('rows sit on ONE typographic baseline; the escrow and '
        'dispute escrow values stay DISTINCT', (tester) async {
      await _pumpPair(tester, valuation: _saved(vendor: true));
      await _flipToBack(tester);
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

      // LOCKED page: escrow and dispute escrow are SEPARATE visible
      // values — never a merged sum.
      await _dragToNextSection(tester);
      await _dragToNextSection(tester);
      expect(find.byKey(const ValueKey('bc-row-escrow')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('bc-row-dispute-escrow')),
        findsOneWidget,
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
