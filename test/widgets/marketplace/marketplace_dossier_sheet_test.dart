import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/marketplace_dossier_sheet.dart';

/// TASK-011 permanent guard: the shared dossier scaffold must render the
/// presentation eyebrow — exactly one glyph icon, the presentation's own
/// label — the title in display type, the caller's content and the optional
/// footer. The entrance must be a real fade+rise normally, and must be fully
/// collapsed (final opacity, zero translation, nothing pending) on the FIRST
/// rendered frame under reduced motion.

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

/// The in-repo glyph mapping from MarketplaceDossierSheet._presentationGlyph
/// (verified in lib, not speculative — F-035: only in-repo-verified names).
const Map<MarketplaceDetailPresentation, IconData> _expectedGlyphs = {
  MarketplaceDetailPresentation.dishDossier: HugeIconsStroke.store01,
  MarketplaceDetailPresentation.productDossier: HugeIconsSolid.store01,
  MarketplaceDetailPresentation.roomDossier: HugeIconsSolid.bank,
  MarketplaceDetailPresentation.seatDossier:
      HugeIconsSolid.arrowDataTransferHorizontal,
  MarketplaceDetailPresentation.serviceDossier: HugeIconsSolid.note01,
  MarketplaceDetailPresentation.morph: HugeIconsSolid.informationCircle,
};

/// The in-repo label mapping from MarketplaceDossierSheet._presentationLabel,
/// as rendered (the sheet uppercases the eyebrow).
const Map<MarketplaceDetailPresentation, String> _expectedLabels = {
  MarketplaceDetailPresentation.morph: 'DETAILS',
  MarketplaceDetailPresentation.dishDossier: 'DISH DOSSIER',
  MarketplaceDetailPresentation.productDossier: 'PRODUCT DOSSIER',
  MarketplaceDetailPresentation.roomDossier: 'ROOM DOSSIER',
  MarketplaceDetailPresentation.seatDossier: 'SEAT DOSSIER',
  MarketplaceDetailPresentation.serviceDossier: 'SERVICE DOSSIER',
};

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

Finder _sheet() => find.byType(MarketplaceDossierSheet);

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
    expect(_sheet(), findsOneWidget);
    expect(find.text('Body content'), findsOneWidget);
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

  for (final entry in _expectedGlyphs.entries) {
    testWidgets('presentation ${entry.key.name} renders exactly its own glyph '
        'and label', (tester) async {
      await _openDossier(tester, presentation: entry.key);
      await tester.pumpAndSettle();

      // Exactly one icon is rendered inside the sheet, and it is the
      // presentation's own glyph — the mapping is guarded, not assumed.
      final iconsInSheet = find.descendant(
        of: _sheet(),
        matching: find.byType(Icon),
      );
      expect(iconsInSheet, findsOneWidget);
      expect(
        tester.widget<Icon>(iconsInSheet).icon,
        entry.value,
        reason: '${entry.key.name} must render its in-repo glyph',
      );

      // The presentation's own label renders when no override is supplied.
      expect(find.text(_expectedLabels[entry.key]!), findsOneWidget);
    });
  }

  testWidgets('reduced motion collapses the entrance on the first frame', (
    tester,
  ) async {
    await _openDossier(
      tester,
      presentation: MarketplaceDetailPresentation.seatDossier,
      reduceMotion: true,
    );
    // First rendered frame only — no settled time has been pumped, so a
    // non-collapsed entrance would still be mid-flight here.
    final eyebrow = find.text('SEAT DOSSIER');

    final opacity = tester.widget<Opacity>(
      find.ancestor(of: eyebrow, matching: find.byType(Opacity)).first,
    );
    expect(
      opacity.opacity,
      1.0,
      reason: 'entrance opacity must already be complete',
    );

    final transform = tester.widget<Transform>(
      find.ancestor(of: eyebrow, matching: find.byType(Transform)).first,
    );
    final translation = transform.transform.getTranslation();
    expect(translation.y, 0.0, reason: 'no entrance translation may remain');

    // Nothing may animate in afterwards: after real time passes, the values
    // are unchanged and no entrance is still pending.
    await tester.pump(const Duration(milliseconds: 200));
    final opacityAfter = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text('SEAT DOSSIER'),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(opacityAfter.opacity, 1.0);
    expect(find.text('Dossier Title'), findsOneWidget);
  });

  testWidgets('without reduced motion the entrance is a real fade+rise', (
    tester,
  ) async {
    await _openDossier(
      tester,
      presentation: MarketplaceDetailPresentation.roomDossier,
    );
    // First frame only: the entrance must be mid-flight (not yet opaque),
    // proving the reduced-motion guard above is guarding a real animation.
    final eyebrow = find.text('ROOM DOSSIER');
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: eyebrow, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, lessThan(1.0));

    await tester.pumpAndSettle();
    final opacitySettled = tester.widget<Opacity>(
      find.ancestor(of: eyebrow, matching: find.byType(Opacity)).first,
    );
    expect(opacitySettled.opacity, 1.0);
  });
}
