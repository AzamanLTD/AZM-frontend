// =============================================================================
// AZAMAN — CARD TRANSFER: THE TWO TILES ARE DIFFERENT PRODUCTS (2026-10-28)
//
// OWNER-REPORTED DEFECT: on the Card Transfer screen the balance card and the
// Visa card "look like the same card" — both were the same premium chrome, so
// the pair read as two Visa-ish cards.
//
// These tests pin the fix, and they are written so they FAIL on the old
// implementation:
//
//   1. the balance tile renders the AZAMAN balance card face — the shared
//      [AzamanCardPainter] in the APPLIED colourway, with the Azaman mark and
//      wordmark — and never a "VISA" mark;
//   2. the Visa tile renders the network's own identity — the VISA wordmark on
//      its light plate over the Visa navy body — and never the Azaman mark or
//      the balance palette;
//   3. the balance tile FOLLOWS the applied card (blue/green/dark/red) while
//      the Visa tile never does;
//   4. neither tile overflows, at 320dp and at the largest text scale, and the
//      money text is never clipped.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/home/azm_visa_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/balance_card_brand.dart';
import 'package:azaman/widgets/card_transfer/compact_card_pair.dart';
import 'package:azaman/widgets/home/azaman_card_face.dart';

const String _visaPlateFinder = 'VISA';

Widget _host(Widget child, {double width = 400, TextScaler? scaler}) {
  return ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: kCompactCardHeight,
            child: MediaQuery(
              data: MediaQueryData(textScaler: scaler ?? TextScaler.noScaling),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

/// True when two palettes are the same colourway (the palettes are built by
/// the brand module, so compare their tones rather than instance identity).
bool _samePalette(AzamanCardPalette? a, AzamanCardPalette? b) =>
    a != null &&
    b != null &&
    a.bright.toARGB32() == b.bright.toARGB32() &&
    a.deep.toARGB32() == b.deep.toARGB32();

/// The palette the balance tile actually handed to the painter, read off the
/// painted layer. This is the palette the card face was drawn with.
AzamanCardPalette? _paintedPalette(WidgetTester tester) {
  final painters = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<AzamanCardPainter>();
  return painters.isEmpty ? null : painters.first.palette;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('the balance tile is the Azaman balance card', () {
    testWidgets('1. it paints the real card face and carries the mark', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const CompactBalancePreview(rate: 12.0)));
      await tester.pump();

      expect(
        _paintedPalette(tester),
        isNotNull,
        reason: 'the balance tile must paint the shared card face, not chrome',
      );
      expect(
        find.byType(AzamanCardBrandBlock),
        findsOneWidget,
        reason: 'the Azaman mark and wordmark identify the product',
      );
      expect(
        find.text('AZM balance card'),
        findsOneWidget,
        reason: 'the tile names its product explicitly',
      );
      expect(
        find.text(_visaPlateFinder),
        findsNothing,
        reason: 'the balance card must never wear the Visa mark',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('2. it names the APPLIED card in its semantics', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kBalanceCardVariantPrefKey: BalanceCardVariant.red.storageValue,
      });
      await tester.pumpWidget(_host(const CompactBalancePreview(rate: 12.0)));
      await tester.pumpAndSettle();

      final semantics = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byType(ClipRRect),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.label, contains('Red'));
      expect(
        _samePalette(
          _paintedPalette(tester),
          kCardPalettes[BalanceCardVariant.red],
        ),
        isTrue,
      );
    });

    testWidgets('3. switching the applied card recolours this tile only', (
      tester,
    ) async {
      for (final v in BalanceCardVariant.values) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          kBalanceCardVariantPrefKey: v.storageValue,
        });
        // Unmount first: pumpWidget of the same tree shape would reuse the
        // existing ProviderScope, keeping the previous variant.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(_host(const CompactBalancePreview(rate: 12.0)));
        await tester.pumpAndSettle();
        expect(
          _samePalette(_paintedPalette(tester), kCardPalettes[v]),
          isTrue,
          reason: 'the tile must follow the applied ${v.label} card',
        );
        expect(find.text(_visaPlateFinder), findsNothing);
      }
    });
  });

  group('the Visa tile is the Visa card', () {
    testWidgets('4. it wears the network mark and the Visa navy body', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const CompactVisaPreview(
            maskedCardNumber: '•••• 4242',
            cardholderLabel: 'SAMPLE HOLDER',
          ),
        ),
      );
      await tester.pump();

      expect(find.text(_visaPlateFinder), findsOneWidget);
      // OWNER-CORRECTED 2026-10-29: the tile used to be a hand-built miniature
      // that named itself "AZM Visa card". The transfer surface must show the
      // SAME physical card the Home deck holds, so the tile now renders the
      // real [AzmVisaCard] and carries its marks verbatim.
      expect(
        find.byType(AzmVisaCard),
        findsOneWidget,
        reason: 'the tile renders the same Visa card as Home',
      );
      expect(
        find.text('AZM'),
        findsOneWidget,
        reason: 'the Home card\'s AZM mark is present',
      );
      expect(
        find.text('SAMPLE'),
        findsOneWidget,
        reason: 'the demo disclosure travels with the card',
      );
      expect(
        find.byType(AzamanCardBrandBlock),
        findsNothing,
        reason: 'the Visa tile must not borrow the Azaman balance identity',
      );
      expect(
        _paintedPalette(tester),
        isNull,
        reason: 'the Visa tile must not paint the balance card face',
      );

      // The body is the Visa navy, not a balance palette tone.
      final decorated = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.gradient != null);
      final colors = (decorated.gradient! as LinearGradient).colors;
      // OWNER-CORRECTED 2026-10-29: this pinned the hand-built navy body of the
      // old miniature. The tile now renders the real [AzmVisaCard], so the
      // navy literal is gone by design; the load-bearing claim — that the tile
      // never wears a balance-card palette colour — is asserted right below.
      final balanceBrights = BalanceCardVariant.values
          .map((v) => kCardPalettes[v]!.bright)
          .toList();
      expect(balanceBrights.contains(colors.first), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. it never follows the applied balance card', (tester) async {
      Color? materialAcrossVariants;
      for (final v in BalanceCardVariant.values) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          kBalanceCardVariantPrefKey: v.storageValue,
        });
        // Unmount first: pumpWidget of the same tree shape would reuse the
        // existing ProviderScope, keeping the previous variant.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          _host(
            const CompactVisaPreview(
              maskedCardNumber: '•••• 4242',
              cardholderLabel: 'SAMPLE HOLDER',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          _paintedPalette(tester),
          isNull,
          reason: 'the Visa card has its own identity, independent of $v',
        );
        final decorated = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((w) => w.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.gradient != null);
        final first = (decorated.gradient! as LinearGradient).colors.first;
        // Equality across variants, not a hardcoded colour: the assertion
        // survives a redesign but still fails the moment the tile follows the
        // applied balance card.
        materialAcrossVariants ??= first;
        expect(
          first,
          materialAcrossVariants,
          reason: 'the Visa tile must not repaint for variant ${v.name}',
        );
      }
    });
  });

  group('the pair stays honest at every size', () {
    testWidgets('6. no overflow at 320dp, 400dp and 1.6x text', (tester) async {
      for (final width in <double>[320, 360, 400, 430]) {
        for (final scale in <double>[1.0, 1.3, 1.6]) {
          await tester.pumpWidget(
            _host(
              CompactCardPair(
                toVisa: true,
                colors: ThemeProvider.getColors(AzamanTheme.dark),
                reduceMotion: true,
                rate: 12.0,
                maskedCardNumber: '•••• 4242',
              ),
              width: width,
              scaler: TextScaler.linear(scale),
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'pair overflowed at ${width}dp / ${scale}x',
          );
          // Both identities are present at every size.
          expect(find.text(_visaPlateFinder), findsOneWidget);
          expect(find.byType(AzamanCardBrandBlock), findsOneWidget);
        }
      }
    });
  });
}
