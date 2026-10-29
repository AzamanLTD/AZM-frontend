// Ported to the rebuilt launch API.
//
// The old version asserted that the entrance "settled" at `AzamanIntro.revealMs`
// (2.12s) — which is exactly the behaviour that was wrong: the route changed
// while the ring and halo still had motion left. These tests now assert the
// opposite: nothing is reported until the full reference sequence has played.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/launch/azaman_intro.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: child),
  );

  testWidgets('plays the entrance and reports only when it has finished', (
    tester,
  ) async {
    var completed = 0;
    await tester.pumpWidget(
      host(AzamanIntroPlayer(onCompleted: () => completed++)),
    );
    await tester.pump();
    expect(find.byType(AzamanIntroPlayer), findsOneWidget);
    expect(completed, 0, reason: 'the tile phase comes first');

    // Past the moment the wordmark is legible, the sequence is still moving.
    await tester.pump(const Duration(milliseconds: 2500));
    expect(
      completed,
      0,
      reason: 'the ring and halo still have motion after 2.5s',
    );

    // Finish the reference timeline.
    await tester.pump(AzamanIntro.total);
    expect(completed, 1, reason: 'reported at the end of the sequence');

    // Reported exactly once, even if pumped further.
    await tester.pump(const Duration(seconds: 2));
    expect(completed, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion shows the settled brand state immediately', (
    tester,
  ) async {
    await tester.pumpWidget(host(const AzamanIntroStatic()));
    await tester.pump();
    expect(find.byType(AzamanIntroStatic), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('renders in both brightnesses', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(body: AzamanIntroStatic()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$brightness');
    }
    await tester.pumpAndSettle();
  });
}
