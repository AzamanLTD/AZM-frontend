import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/widgets/marketplace/restaurant_commit_surface.dart';

void main() {
  testWidgets('paper-rip mode exposes the commit callback and starts its ritual', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: RestaurantCommitSurface(
            style: MarketplaceCommitStyle.paperRip,
            childBuilder: (onCommitted) => Center(
              child: FilledButton(
                onPressed: onCommitted,
                child: const Text('Add'),
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
  });

  testWidgets('non-paper commit styles do not add a tear overlay', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: RestaurantCommitSurface(
            style: MarketplaceCommitStyle.liftIntoTray,
            childBuilder: (onCommitted) => Center(
              child: FilledButton(
                onPressed: onCommitted,
                child: const Text('Add'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('paper-rip-animation')), findsNothing);
  });

  testWidgets('paper-rip uses semantic confirmation when reduced motion is enabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox.expand(
            child: RestaurantCommitSurface(
              style: MarketplaceCommitStyle.paperRip,
              childBuilder: (onCommitted) => Center(
                child: FilledButton(
                  onPressed: onCommitted,
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
    expect(find.text('Added to your order tray'), findsOneWidget);
    expect(find.byKey(const ValueKey('paper-rip-animation')), findsNothing);
  });
}
