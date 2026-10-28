import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/launch/azaman_intro.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: child),
      );

  testWidgets('plays the entrance and reports the settled lockup',
      (tester) async {
    var revealed = 0;
    await tester.pumpWidget(
      host(AzamanIntro(onRevealed: () => revealed++)),
    );
    await tester.pump();
    expect(find.byType(AzamanIntro), findsOneWidget);
    expect(revealed, 0, reason: 'the tile phase comes first');

    await tester.pump(const Duration(milliseconds: AzamanIntro.revealMs + 40));
    expect(revealed, 1, reason: 'the lockup has settled by revealMs');

    // The reveal is reported exactly once, even as the animation holds.
    await tester.pump(const Duration(milliseconds: 1400));
    expect(revealed, 1);

    // Drain the controller so no timer outlives the test.
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion shows the settled lockup immediately',
      (tester) async {
    var revealed = 0;
    await tester.pumpWidget(
      host(AzamanIntro(animate: false, onRevealed: () => revealed++)),
    );
    await tester.pump();
    expect(revealed, 1);
    await tester.pumpAndSettle();
    expect(revealed, 1);
  });

  testWidgets('renders in both brightnesses', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(body: AzamanIntro(animate: false)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$brightness');
    }
    await tester.pumpAndSettle();
  });
}
