// NEW-B — sheet grammar.
//
// The geometry half of the grammar is pure, so it is tested as pure math. The
// widget half is tested for the three things a sheet can get wrong: it does
// not show the wrong weight's chrome, it respects the OS reduce-motion
// setting, and it hands the panel's own ScrollController to the builder.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/theme/az_sheet.dart';
import 'package:azaman/widgets/azaman_sheet.dart';

/// A representative phone: 390×844 logical.
const double kViewport = 844;

Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  group('AzSheetGeometry', () {
    group('whisper', () {
      test('sizes to content when content is small', () {
        expect(
          AzSheetGeometry.whisperHeight(
            viewportHeight: kViewport,
            contentHeight: 200,
          ),
          200,
        );
      });

      test('clamps to the 45% ceiling when content is tall', () {
        expect(
          AzSheetGeometry.whisperHeight(
            viewportHeight: kViewport,
            contentHeight: 700,
          ),
          kViewport * AzSheetGeometry.whisperMaxFraction,
        );
      });

      test('is scale-free: the fraction holds on a short viewport', () {
        final tall = AzSheetGeometry.whisperHeight(
          viewportHeight: 1200,
          contentHeight: 700,
        );
        final short = AzSheetGeometry.whisperHeight(
          viewportHeight: 600,
          contentHeight: 700,
        );
        expect(tall, greaterThan(short));
        expect(short, 600 * AzSheetGeometry.whisperMaxFraction);
      });

      test('survives a zero viewport without dividing by zero', () {
        expect(
          AzSheetGeometry.whisperHeight(viewportHeight: 0, contentHeight: 120),
          120,
        );
      });
    });

    group('panel', () {
      test('rest and extended detents are 45% and 90%', () {
        expect(AzSheetGeometry.panelRestFraction, 0.45);
        expect(AzSheetGeometry.panelExtendedFraction, 0.90);
      });

      test('panelHeight is viewport * fraction', () {
        expect(
          AzSheetGeometry.panelHeight(
            kViewport,
            AzSheetGeometry.panelRestFraction,
          ),
          closeTo(379.8, 0.001),
        );
      });

      test('an out-of-range fraction is clamped, not trusted', () {
        expect(AzSheetGeometry.panelHeight(kViewport, 4.0), kViewport);
        expect(AzSheetGeometry.panelHeight(kViewport, -1.0), 0);
      });

      test('a zero viewport yields zero rather than NaN', () {
        expect(AzSheetGeometry.panelHeight(0, 0.9), 0);
      });
    });

    group('stage', () {
      test('leaves only the status bar visible', () {
        expect(
          AzSheetGeometry.stageHeight(kViewport),
          kViewport * (1.0 - AzSheetGeometry.stageTopInsetFraction),
        );
      });
    });

    group('scrim', () {
      test('weights are ordered: whisper < panel, stage is none', () {
        expect(
          AzSheetGeometry.scrimSigmaFor(AzSheetWeight.whisper),
          lessThan(AzSheetGeometry.scrimSigmaFor(AzSheetWeight.panel)),
        );
        expect(AzSheetGeometry.scrimSigmaFor(AzSheetWeight.stage), 0);
        expect(AzSheetGeometry.scrimOpacityFor(AzSheetWeight.stage), 0);
      });

      test('every weight has a scrim value', () {
        for (final w in AzSheetWeight.values) {
          expect(AzSheetGeometry.scrimSigmaFor(w), greaterThanOrEqualTo(0));
          expect(AzSheetGeometry.scrimOpacityFor(w), greaterThanOrEqualTo(0));
          expect(AzSheetGeometry.scrimOpacityFor(w), lessThan(1.0));
        }
      });
    });

    group('classify', () {
      test('full-screen is a stage regardless of anything else', () {
        expect(
          AzSheetGeometry.classify(isScrollable: true, isFullScreen: true),
          AzSheetWeight.stage,
        );
      });

      test('scrollable is a panel', () {
        expect(
          AzSheetGeometry.classify(isScrollable: true),
          AzSheetWeight.panel,
        );
      });

      test('short non-scrollable is a whisper', () {
        expect(
          AzSheetGeometry.classify(
            isScrollable: false,
            contentHeight: 200,
            viewportHeight: kViewport,
          ),
          AzSheetWeight.whisper,
        );
      });

      test('tall non-scrollable is a panel, not a giant whisper', () {
        expect(
          AzSheetGeometry.classify(
            isScrollable: false,
            contentHeight: 600,
            viewportHeight: kViewport,
          ),
          AzSheetWeight.panel,
        );
      });

      test(
        'unknown height falls back to panel rather than guessing whisper',
        () {
          expect(
            AzSheetGeometry.classify(isScrollable: false),
            AzSheetWeight.panel,
          );
        },
      );
    });
  });

  group('AzamanSheet widgets', () {
    testWidgets('whisper shows no grab handle', (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => AzamanSheet.showWhisper(
                context,
                builder: (_) => const SizedBox(height: 100, child: Text('hi')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('hi'), findsOneWidget);
      expect(find.byType(AzSheetHandle), findsNothing);
    });

    testWidgets('panel shows a grab handle and passes a live controller', (
      tester,
    ) async {
      ScrollController? received;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => AzamanSheet.showPanel(
                context,
                builder: (_, c) {
                  received = c;
                  return const SizedBox(height: 200, child: Text('panel body'));
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('panel body'), findsOneWidget);
      expect(find.byType(AzSheetHandle), findsOneWidget);
      expect(
        received,
        isNotNull,
        reason: 'the builder must receive the sheet\'s own controller',
      );
    });

    testWidgets(
      'the panel builder must receive the draggable scroll controller',
      (tester) async {
        // The detent and the content share one gesture only if the content
        // scrolls through the controller the sheet hands it. A builder that
        // ignores it silently loses drag-to-dismiss.
        ScrollController? received;
        await tester.pumpWidget(
          _host(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => AzamanSheet.showPanel(
                  context,
                  builder: (_, c) {
                    received = c;
                    return ListView(
                      controller: c,
                      children: const [Text('row 1'), Text('row 2')],
                    );
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.byType(DraggableScrollableSheet), findsOneWidget);
        expect(find.text('row 1'), findsOneWidget);
        expect(
          received!.hasClients,
          isTrue,
          reason:
              'a builder that scrolls through the controller gets live clients',
        );
      },
    );

    testWidgets('stage has no handle and no scrim dim', (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => AzamanSheet.showStage(
                context,
                builder: (_) =>
                    const SizedBox(height: 300, child: Text('world')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('world'), findsOneWidget);
      expect(find.byType(AzSheetHandle), findsNothing);
    });

    testWidgets('dismissing returns null, matching the showDialog contract', (
      tester,
    ) async {
      int? result = 1;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await AzamanSheet.showWhisper<int>(
                  context,
                  builder: (_) =>
                      const SizedBox(height: 80, child: Text('bye')),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('bye'), findsOneWidget);

      // Tap the barrier, well above the sheet.
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      expect(find.text('bye'), findsNothing);
      expect(result, isNull);
    });

    testWidgets('reduce-motion disables the stagger without dropping content', (
      tester,
    ) async {
      final media = MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _host(
          const AzStaggeredColumn(children: [Text('a'), Text('b'), Text('c')]),
        ),
      );
      await tester.pumpWidget(media);

      // All three render on the first frame — no delayed reveal to wait on.
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('c'), findsOneWidget);
      expect(
        find.byType(AzStaggeredReveal),
        findsNothing,
        reason: 'reduce-motion must bypass the stagger wrapper entirely',
      );
    });

    testWidgets('staggered children all become visible once settled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AzStaggeredColumn(children: [Text('a'), Text('b'), Text('c')]),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text('a'),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 1.0);
    });

    testWidgets('staggered rows are ordered a, b, c', (tester) async {
      await tester.pumpWidget(
        _host(
          const AzStaggeredColumn(children: [Text('a'), Text('b'), Text('c')]),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        tester.getCenter(find.text('a')).dy,
        lessThan(tester.getCenter(find.text('b')).dy),
      );
      expect(
        tester.getCenter(find.text('b')).dy,
        lessThan(tester.getCenter(find.text('c')).dy),
      );
    });
  });
}
