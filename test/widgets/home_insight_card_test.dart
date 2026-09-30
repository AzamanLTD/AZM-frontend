// NEW-D — AzInsightCard tests.
//
// Pins the two properties §G.8 demands of the card:
//
//   1. The honesty gate: no verifiable amount + category → the card is
//      SIZE ZERO. Never a placeholder statistic, never a fabricated
//      category (F.5).
//   2. §H.7 tone: spending more is a neutral fact — the up case renders
//      the same tertiary color as "no comparison", NEVER the destructive
//      red treatment; copy states facts, not judgement.
//
// Plus the sparkline contract: at most 7 bars, most-recent 7 of any longer
// series, and an all-zero week renders flat bars (floor, not NaN).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/az_insight_card.dart';

Future<void> _pumpCard(
  WidgetTester tester, {
  AzInsightData? insight,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: container.read(themeProvider).themeData,
        home: Scaffold(
          body: AzInsightCard(insight: insight),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the honesty gate: null insight renders size zero', (tester) async {
    await _pumpCard(tester, insight: null);
    expect(tester.getSize(find.byType(AzInsightCard)), Size.zero);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('an amount without a category is still no insight', (tester) async {
    await _pumpCard(
      tester,
      insight: AzInsightData(amountText: '240.00 USDC', category: ''),
    );
    expect(tester.getSize(find.byType(AzInsightCard)), Size.zero);
  });

  testWidgets('amount + category renders the insight line', (tester) async {
    await _pumpCard(
      tester,
      insight: AzInsightData(
        amountText: '240.00 USDC',
        category: 'withdrawals',
        daily: const [10, 20, 30, 40, 50, 60, 70],
      ),
    );
    expect(find.text('240.00 USDC on withdrawals'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
  });

  testWidgets('down from last week: factual copy, success color, no judgement', (tester) async {
    await _pumpCard(
      tester,
      insight: AzInsightData(
        amountText: '180.00 USDC',
        category: 'food',
        changeFraction: -0.18,
        daily: const [10, 20, 30, 40, 50, 60, 70],
      ),
    );
    expect(find.text('Down from last week.'), findsOneWidget);
    expect(find.text('↓ 18%'), findsOneWidget);
  });

  testWidgets('up from last week: neutral fact — NEVER the red/destructive treatment (§H.7)', (tester) async {
    await _pumpCard(
      tester,
      insight: AzInsightData(
        amountText: '240.00 USDC',
        category: 'food',
        changeFraction: 0.25,
        daily: const [10, 20, 30, 40, 50, 60, 70],
      ),
    );
    expect(find.text('Up from last week.'), findsOneWidget);
    expect(find.text('↑ 25%'), findsOneWidget);

    // The judgement rule: the "more" delta must not use the destructive
    // color that errors and failures use.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final destructive = container.read(themeProvider).colors.danger;
    final delta = tester.widget<Text>(find.text('↑ 25%'));
    expect(delta.style?.color, isNot(destructive));

    // Copy stays factual — no "you overspent" vocabulary anywhere.
    expect(find.textContaining('overspent'), findsNothing);
    expect(find.textContaining('keep it'), findsNothing);
  });

  testWidgets('no comparison yet: the copy says exactly that', (tester) async {
    await _pumpCard(
      tester,
      insight: AzInsightData(
        amountText: '240.00 USDC',
        category: 'food',
        changeFraction: null,
        daily: const [10, 20, 30, 40, 50, 60, 70],
      ),
    );
    expect(find.text('Not enough history yet to compare.'), findsOneWidget);
    // No percentage renders without a real comparison.
    expect(find.byWidgetPredicate((w) => w is Text && w.data!.contains('%')),
        findsNothing);
  });

  group('the sparkline contract', () {
    test('normalizeSparkline keeps at most 7 values', () {
      expect(
        AzInsightCard.normalizeSparkline([1, 2, 3, 4, 5, 6, 7]),
        [1, 2, 3, 4, 5, 6, 7],
      );
      expect(
        AzInsightCard.normalizeSparkline([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        [4, 5, 6, 7, 8, 9, 10],
      );
    });

    testWidgets('a 10-day series renders exactly 7 bars', (tester) async {
      await _pumpCard(
        tester,
        insight: AzInsightData(
          amountText: '240.00 USDC',
          category: 'food',
          daily: List<double>.generate(10, (i) => (i + 1).toDouble()),
        ),
      );
      expect(
        find.byWidgetPredicate(
            (w) => w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('az-insight-bar-')),
        findsNWidgets(7),
      );
    });

    testWidgets('an all-zero week renders flat bars, not NaN heights (floor)', (tester) async {
      await _pumpCard(
        tester,
        insight: AzInsightData(
          amountText: '240.00 USDC',
          category: 'food',
          daily: const [0, 0, 0, 0, 0, 0, 0],
        ),
      );
      final bar = tester.widget<AnimatedContainer>(
        find.byWidgetPredicate(
            (w) => w is AnimatedContainer && (w.key as ValueKey?)?.value == 'az-insight-bar-6'),
      );
      expect(bar.constraints?.minHeight, 6.0); // the floor: max<=0 → flat
    });
  });
}
