// =============================================================================
// NEARBY OUTCOME — honest failure vs. legitimate empty (Workstream E).
//
// A FAILED nearby search used to render as "No businesses nearby" — the user
// was told a lie about a dead request. These tests pin the retired contract:
//   • failure (error non-null) shows the failure text + Retry, never the
//     empty-state text; tapping Retry fires the callback
//   • success-with-zero-results shows ONLY the empty-state text, no Retry
//   • the Retry touch target meets the 44dp minimum
//   • the two states can never swap — each is keyed and findable in exactly
//     one of the two states
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/marketplace/nearby_outcome.dart';

void _nop() {}

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets('failure: error non-null renders the failure state, not empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const NearbyOutcome(
          error: 'FormatException: bad payload',
          onRetry: _nop,
        ),
      ),
    );

    expect(find.byKey(const Key('nearby-outcome-failure')), findsOneWidget);
    expect(find.byKey(const Key('nearby-outcome-empty')), findsNothing);
    expect(find.text("Couldn't load nearby businesses"), findsOneWidget);
    expect(find.text('No businesses nearby'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('failure: Retry fires the retry callback exactly once', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _wrap(NearbyOutcome(error: 'SocketException', onRetry: () => retries++)),
    );

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(retries, 1);
  });

  testWidgets('failure: the Retry target meets the 44dp touch minimum', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(NearbyOutcome(error: 'timeout', onRetry: () {})),
    );

    final size = tester.getSize(find.byType(TextButton));
    expect(
      size.height,
      greaterThanOrEqualTo(44),
      reason: 'Retry is a primary map control — 44dp touch target rule',
    );
  });

  testWidgets('empty: success with zero results renders ONLY the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const NearbyOutcome(error: null)));

    expect(find.byKey(const Key('nearby-outcome-empty')), findsOneWidget);
    expect(find.byKey(const Key('nearby-outcome-failure')), findsNothing);
    expect(find.text('No businesses nearby'), findsOneWidget);
    expect(find.text("Couldn't load nearby businesses"), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });
}
