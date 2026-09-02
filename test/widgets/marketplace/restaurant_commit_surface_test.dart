import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/widgets/marketplace/restaurant_commit_surface.dart';

void main() {
  testWidgets('paper-rip defers the commit action until the paper leaves the menu', (tester) async {
    var committed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: SizedBox.expand(
            child: RestaurantCommitSurface(
              style: MarketplaceCommitStyle.paperRip,
              childBuilder: (onCommit) => Center(
                child: FilledButton(
                  onPressed: () => onCommit(() => committed = true),
                  child: const Text('Add'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('paper-rip-animation')), findsNothing);
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('paper-rip-animation')), findsOneWidget);
    expect(committed, isFalse);

    await tester.pump(const Duration(milliseconds: 240));
    expect(committed, isTrue);
    expect(find.byKey(const ValueKey('paper-rip-animation')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 420));
    expect(find.byKey(const ValueKey('paper-rip-animation')), findsNothing);
  });

  testWidgets('non-paper commit styles execute the action immediately without a tear', (tester) async {
    var committed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: RestaurantCommitSurface(
            style: MarketplaceCommitStyle.liftIntoTray,
            childBuilder: (onCommit) => Center(
              child: FilledButton(
                onPressed: () => onCommit(() => committed = true),
                child: const Text('Add'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(committed, isTrue);
    expect(find.byKey(const ValueKey('paper-rip-animation')), findsNothing);
  });

  testWidgets('paper-rip uses semantic confirmation when reduced motion is enabled', (tester) async {
    var committed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox.expand(
            child: RestaurantCommitSurface(
              style: MarketplaceCommitStyle.paperRip,
              childBuilder: (onCommit) => Center(
                child: FilledButton(
                  onPressed: () => onCommit(() => committed = true),
                  child: const Text('Add'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(committed, isTrue);
    expect(find.text('Added to your order tray'), findsOneWidget);
    expect(find.byKey(const ValueKey('paper-rip-animation')), findsNothing);
  });

  testWidgets('a second commit while the ritual is active is ignored', (tester) async {
    var commits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: RestaurantCommitSurface(
            style: MarketplaceCommitStyle.paperRip,
            childBuilder: (onCommit) => Center(
              child: FilledButton(
                onPressed: () => onCommit(() => commits++),
                child: const Text('Add'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(commits, 1);
  });
}
