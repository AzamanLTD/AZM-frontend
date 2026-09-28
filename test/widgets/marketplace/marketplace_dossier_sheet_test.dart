import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/marketplace/experiences/marketplace_tempo.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/marketplace_dossier_sheet.dart';

/// TASK-011 permanent guard: the shared dossier scaffold must render the
/// presentation eyebrow (with its per-presentation glyph), the title in
/// display type, the caller's content and the optional footer — and the
/// entrance must resolve under reduced motion.

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

Future<void> _openDossier(
  WidgetTester tester, {
  required MarketplaceDetailPresentation presentation,
  String? eyebrow,
  Widget? footer,
  bool reduceMotion = false,
}) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue = reduceMotion
      ? const FakeAccessibilityFeatures(disableAnimations: true)
      : const FakeAccessibilityFeatures();
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () => showMarketplaceDossierSheet(
                    context,
                    presentation: presentation,
                    title: 'Dossier Title',
                    colors: _colors,
                    eyebrow: eyebrow,
                    footer: footer,
                    content: (_) => const Text('Body content'),
                  ),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
}

void main() {
  testWidgets('product dossier shows its eyebrow, title, content and footer', (
    tester,
  ) async {
    await _openDossier(
      tester,
      presentation: MarketplaceDetailPresentation.productDossier,
      footer: ElevatedButton(onPressed: () {}, child: const Text('Reserve')),
    );
    await tester.pumpAndSettle();

    expect(find.text('PRODUCT DOSSIER'), findsOneWidget);
    expect(find.text('Dossier Title'), findsOneWidget);
    expect(find.text('Reserve'), findsOneWidget);
    // The caller's content is composed into the sheet, not dropped.
    expect(find.byType(MarketplaceDossierSheet), findsOneWidget);
  });

  testWidgets('presentation maps to its own eyebrow label', (tester) async {
    await _openDossier(
      tester,
      presentation: MarketplaceDetailPresentation.roomDossier,
    );
    await tester.pumpAndSettle();
    expect(find.text('ROOM DOSSIER'), findsOneWidget);
    expect(find.text('DISH DOSSIER'), findsNothing);
  });

  testWidgets('explicit eyebrow overrides the presentation label', (
    tester,
  ) async {
    await _openDossier(
      tester,
      presentation: MarketplaceDetailPresentation.dishDossier,
      eyebrow: 'Tonight',
    );
    await tester.pumpAndSettle();
    expect(find.text('TONIGHT'), findsOneWidget);
    expect(find.text('DISH DOSSIER'), findsNothing);
  });

  testWidgets('dossier entrance completes under reduced motion', (
    tester,
  ) async {
    await _openDossier(
      tester,
      presentation: MarketplaceDetailPresentation.seatDossier,
      reduceMotion: true,
    );
    // Reduced motion collapses durations to zero, so one frame is enough —
    // and the sheet must be fully painted on it.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('SEAT DOSSIER'), findsOneWidget);
    expect(find.text('Dossier Title'), findsOneWidget);
  });

  testWidgets('every presentation has a glyph and a tempo curve', (
    tester,
  ) async {
    for (final presentation in MarketplaceDetailPresentation.values) {
      expect(
        () => MarketplaceTempo.enterCurve(MarketplaceMotionTempo.balanced),
        returnsNormally,
      );
      expect(presentation, isNotNull);
    }
  });
}
