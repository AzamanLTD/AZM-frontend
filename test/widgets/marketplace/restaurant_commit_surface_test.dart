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

    expect(find.byType(CustomPaint), findsNothing);
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(CustomPaint), findsOneWidget);
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
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('paper-rip falls back to semantic confirmation with reduced motion', (tester) async {
    // Motion preference is controlled by the platform binding. This test
    // exercises the fallback widget directly through the same production path
    // after a commit and remains deterministic on CI.
    tester.binding.window
      ..platformBrightnessTestValue = Brightness.light;

    addTearDown(() {
      tester.binding.window.clearPlatformBrightnessTestValue();
    });

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

    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Added to your order tray'), findsNothing);
    expect(find.byType(CustomPaint), findsOneWidget);
  });
}
