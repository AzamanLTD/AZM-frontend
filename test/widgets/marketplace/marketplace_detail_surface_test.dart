import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/widgets/marketplace/marketplace_detail_surface.dart';

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

Widget _harness(MarketplaceDetailPresentation presentation) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          MarketplaceDetailSurface(
            presentation: presentation,
            colors: _colors,
            duration: Duration.zero,
            onDismiss: () {},
            child: const ColoredBox(key: ValueKey('detail-content'), color: Colors.red),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('dish dossier is grounded at the lower edge', (tester) async {
    await tester.pumpWidget(_harness(MarketplaceDetailPresentation.dishDossier));
    await tester.pump();

    final content = tester.getRect(find.byKey(const ValueKey('detail-content')));
    final viewport = tester.binding.renderView.size;

    expect(content.bottom, closeTo(viewport.height - 8, 1));
    expect(content.center.dy, greaterThan(viewport.height * 0.55));
  });

  testWidgets('morph presentation is centered rather than bottom grounded', (tester) async {
    await tester.pumpWidget(_harness(MarketplaceDetailPresentation.morph));
    await tester.pump();

    final content = tester.getRect(find.byKey(const ValueKey('detail-content')));
    final viewport = tester.binding.renderView.size;

    expect(content.center.dx, closeTo(viewport.width / 2, 1));
    expect(content.center.dy, closeTo(viewport.height / 2, 1));
  });

  testWidgets('tap outside the detail surface dismisses it', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              MarketplaceDetailSurface(
                presentation: MarketplaceDetailPresentation.dishDossier,
                colors: _colors,
                duration: Duration.zero,
                onDismiss: () => dismissed = true,
                child: const SizedBox(width: 200, height: 200),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tapAt(const Offset(4, 4));
    expect(dismissed, isTrue);
  });
}
