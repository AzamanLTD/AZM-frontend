import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/marketplace_experience_scope.dart';

final AzamanColors _testColors = ThemeProvider.getColors(AzamanTheme.dark);

void main() {
  testWidgets('maybeOf() is null outside a scope', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    expect(MarketplaceExperienceScope.maybeOf(context), isNull);
  });

  testWidgets('of() exposes the blueprint and colors to descendants',
      (tester) async {
    final blueprint =
        MarketplaceExperienceBlueprint.fromJson(const <String, dynamic>{}, 'RETAIL');
    await tester.pumpWidget(MarketplaceExperienceScope(
      blueprint: blueprint,
      colors: _testColors,
      child: Builder(
        builder: (context) {
          final scope = MarketplaceExperienceScope.of(context);
          expect(scope.blueprint.preset, 'SHOP_FLOOR');
          expect(scope.blueprint.commitStyle, MarketplaceCommitStyle.liftIntoTray);
          expect(scope.blueprint.navigationMode,
              MarketplaceNavigationMode.aisleTraverse);
          expect(identical(scope.colors, _testColors), isTrue);
          return const SizedBox();
        },
      ),
    ));
  });

  testWidgets('descendants rebuild when the blueprint changes', (tester) async {
    var builds = 0;
    Widget buildScope(String category) => MarketplaceExperienceScope(
          blueprint: MarketplaceExperienceBlueprint.fromJson(
              const <String, dynamic>{}, category),
          colors: _testColors,
          child: Builder(
            builder: (context) {
              MarketplaceExperienceScope.of(context);
              builds++;
              return const SizedBox();
            },
          ),
        );

    await tester.pumpWidget(buildScope('RETAIL'));
    expect(builds, 1);

    await tester.pumpWidget(buildScope('HOTEL'));
    expect(builds, 2);
  });
}
