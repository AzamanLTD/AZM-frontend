import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/widgets/marketplace/restaurant_commit_surface.dart';

Widget _surface({
  required MarketplaceCommitStyle style,
  required String buttonKey,
}) {
  return RestaurantCommitSurface(
    style: style,
    childBuilder: (onCommitted) => Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 24, top: 48),
        child: SizedBox(
          width: 180,
          height: 64,
          child: FilledButton(
            key: ValueKey(buttonKey),
            onPressed: onCommitted,
            child: const Text('Add'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('paper-rip mode starts from the customer commit touch point', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: SizedBox.expand(
            child: _surface(
              style: MarketplaceCommitStyle.paperRip,
              buttonKey: 'paper-rip-add',
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('paper-rip-animation')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('paper-rip-add')));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('paper-rip-animation')), findsOneWidget);
  });

  testWidgets('non-paper commit styles do not add a tear overlay', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: _surface(
            style: MarketplaceCommitStyle.liftIntoTray,
            buttonKey: 'lift-add',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('lift-add')));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('paper-rip-animation')), findsNothing);
  });

  testWidgets('paper-rip uses semantic confirmation when reduced motion is enabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox.expand(
            child: _surface(
              style: MarketplaceCommitStyle.paperRip,
              buttonKey: 'reduced-motion-add',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('reduced-motion-add')));
    await tester.pump();
    expect(find.text('Added to your order tray'), findsOneWidget);
    expect(find.byKey(const ValueKey('paper-rip-animation')), findsNothing);
  });
}
