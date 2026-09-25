import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/widgets/marketplace/restaurant_commit_surface.dart';

void main() {
  testWidgets('paper-rip starts from the customer commit touch point', (tester) async {
    var committed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: SizedBox.expand(
            child: RestaurantCommitSurface(
              style: MarketplaceCommitStyle.paperRip,
              childBuilder: (onCommit) => Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24, top: 48),
                  child: SizedBox(
                    width: 180,
                    height: 64,
                    child: FilledButton(
                      key: const ValueKey('paper-rip-origin-add'),
                      onPressed: () => onCommit(() => committed = true),
                      child: const Text('Add'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('paper-rip-origin-add')));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('paper-rip-animation')), findsOneWidget);
    expect(committed, isFalse);
    await tester.pump(const Duration(milliseconds: 240));
    expect(committed, isTrue);
  });
}