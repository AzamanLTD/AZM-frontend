// =============================================================================
// AZAMAN — BALANCE CARD PREVIEW SECTION (WORKSTREAM E PREVIEW SUITE)
//
// The Home preview surface for the redesigned BalanceCardPair. The contracts
// pinned here are the HONESTY contracts, not the card's own internals (the
// pair's geometry/flip/gesture suite lives in balance_card_fx_test.dart):
//
//   1. INVISIBILITY — outside demo builds the section renders NOTHING.
//      Real-account Home behaviour is byte-for-byte the existing card.
//   2. EXPLICIT LABELLING — when visible it is never mistaken for a real
//      balance: the preview label, the DEMO tag and the "fixture data —
//      not real funds" caption are all present and semantically labelled.
//   3. FIXTURE HONESTY — the card pair renders the DEMO-kind rate
//      (explicitly identified, never presented as a live quote) and the
//      transaction gate stays CLOSED (fail-closed affordances).
//   4. LIVE INTERACTION — the previewed pair flips (the owner inspects
//      the breakdown face in the running app).
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart';
import 'package:azaman/widgets/home/balance_card_preview_section.dart';

bool _fontsLoaded = false;

/// The REAL font faces the card renders with (same loader contract as the
/// balance-card suites): without them every glyph substitutes as a wide
/// square and fixed-height cards overflow spuriously.
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  await (FontLoader('Inter')
        ..addFont(File('assets/fonts/Inter-Variable.ttf')
            .readAsBytes()
            .then((b) => ByteData.view(b.buffer))))
      .load();
  for (final f in ['ComicNeue-Regular.ttf', 'ComicNeue-Bold.ttf']) {
    await (FontLoader('ComicNeue')
          ..addFont(File('assets/fonts/$f')
              .readAsBytes()
              .then((b) => ByteData.view(b.buffer))))
        .load();
  }
  await (FontLoader('HugeIconsSolid')
        ..addFont(rootBundle.load(
          'packages/hugeicons_pro/fonts/hugeicons-solid.ttf',
        )))
      .load();
  _fontsLoaded = true;
}

Future<void> _pump(
  WidgetTester tester, {
  required bool visible,
  double width = 390,
}) async {
  await tester.runAsync(_loadFonts);
  final colors = ThemeProvider.getColors(AzamanTheme.dark).withAccent(
    AzAccent.gold,
  );
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeProvider.getThemeData(AzamanTheme.dark),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 844)),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    BalanceCardPreviewSection(
                      key: const ValueKey('bc-preview-section'),
                      colors: colors,
                      visible: visible,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('outside demo builds the section renders nothing', (tester) async {
    await _pump(tester, visible: false);
    expect(find.byType(BalanceCardPreviewSection), findsOneWidget);
    // No card, no label — the real Home card is the only balance surface.
    expect(find.byType(BalanceCardPair), findsNothing);
    expect(find.text(BalanceCardPreviewSection.previewLabel.toUpperCase()),
        findsNothing);
    expect(find.text(BalanceCardPreviewSection.demoTag), findsNothing);
    // SizedBox.shrink is the invisible branch.
    final section = tester.widget<BalanceCardPreviewSection>(
      find.byKey(const ValueKey('bc-preview-section')),
    );
    expect(section.visible, isFalse);
  });

  testWidgets('visible: the preview label, DEMO tag and fixture caption all render',
      (tester) async {
    await _pump(tester, visible: true);
    expect(find.byType(BalanceCardPair), findsOneWidget);
    expect(find.text(BalanceCardPreviewSection.previewLabel.toUpperCase()),
        findsOneWidget);
    expect(find.text(BalanceCardPreviewSection.demoTag), findsOneWidget);
    expect(find.text(BalanceCardPreviewSection.fixtureCaption), findsOneWidget);
    // The label is exposed to screen readers with its plain-case form.
    expect(
      find.bySemanticsLabel(BalanceCardPreviewSection.previewLabel),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('DEMO fixture data'),
      findsOneWidget,
    );
  });

  testWidgets('the card pair renders the demo-kind rate identification',
      (tester) async {
    await _pump(tester, visible: true);
    // The front face identifies the seeded DEMO rate explicitly — never a
    // live or guaranteed quote.
    expect(find.textContaining('Demo rate (seeded)'), findsOneWidget);
    // And it is NOT labelled a fresh or saved observation.
    expect(find.textContaining('Using saved rate'), findsNothing);
  });

  testWidgets('the previewed pair flips to the breakdown face and back',
      (tester) async {
    await _pump(tester, visible: true);
    // Deliberate tap in the middle of the card (never a boundary point —
    // exact-edge taps miss regions).
    final card = tester.getRect(find.byType(BalanceCardPair));
    await tester.tapAt(card.center);
    await tester.pumpAndSettle();
    expect(find.text('BALANCE BREAKDOWN'), findsOneWidget);
    // …and back.
    await tester.tapAt(card.center);
    await tester.pumpAndSettle();
    expect(find.text('BALANCE BREAKDOWN'), findsNothing);
  });

  testWidgets('fixture gate is fail-closed — no transaction affordance opens',
      (tester) async {
    await _pump(tester, visible: true);
    // The preview fixture keeps the USDC transaction gate closed; the front
    // face renders no open transaction affordance from the preview (the
    // gate state is owned by the model and pinned in the model suite —
    // here we pin the user-visible law: the preview never presents an
    // active send/convert entry point).
    final pair = tester.widget<BalanceCardPair>(
      find.byType(BalanceCardPair),
    );
    expect(pair.valuation.usdcTransactionGateOpen, isFalse);
    expect(pair.valuation.rate.kind, FxRateKind.demo);
    expect(pair.valuation.rate.isFallback, isTrue);
  });

  testWidgets('renders at 320dp width without overflow', (tester) async {
    await _pump(tester, visible: true, width: 320);
    expect(tester.takeException(), isNull);
    expect(find.byType(BalanceCardPair), findsOneWidget);
    expect(find.text(BalanceCardPreviewSection.previewLabel.toUpperCase()),
        findsOneWidget);
  });
}
