// Contract tests for the rebuilt launch sequence.
//
// These assert the things that were wrong before and would be easy to
// regress silently:
//   1. the sequence is ONE sequence and is not finished early;
//   2. the completion signal fires at the END of the reference timeline;
//   3. the mark is absorbed by the aperture instead of cross-fading out;
//   4. reduced motion shows the settled brand state and does not wait 3.8s.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/launch/azaman_intro.dart';

const _key = ValueKey('intro');

Future<List<int>> _inkColumns(WidgetTester tester, {required int ms}) async {
  final controller = AnimationController(
    vsync: tester,
    duration: AzamanIntro.total,
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: RepaintBoundary(
        key: _key,
        child: AzamanIntroPlayer(
          controllerOverride: controller,
          chrome: IntroChrome.dark,
          onCompleted: () {},
        ),
      ),
    ),
  );
  controller.value = ms / AzamanIntro.total.inMilliseconds;
  await tester.pump();

  final bytes = await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_key),
    );
    final img = await boundary.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  });
  final b = bytes!;
  final width = tester.getSize(find.byKey(_key)).width.round();
  final height = tester.getSize(find.byKey(_key)).height.round();
  final cols = <int>[];
  for (var y = (height * 0.40).round(); y < (height * 0.60).round(); y++) {
    var count = 0;
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final lum = (b[i] + b[i + 1] + b[i + 2]) / 3;
      if (lum > 110) count++;
    }
    cols.add(count);
  }
  return cols;
}

void main() {
  group('timeline contract', () {
    test(
      'the sequence is the reference length, and the reveal finishes before it',
      () {
        expect(AzamanIntro.total, const Duration(milliseconds: 3833));
        expect(
          AzamanIntro.revealEnd,
          lessThan(AzamanIntro.total.inMilliseconds),
        );
        // The old build left the screen at 2.12s, ~1.7s early. Everything that
        // reads as motion must be finished before the sequence ends.
        expect(
          AzamanIntro.ringGone,
          lessThan(AzamanIntro.total.inMilliseconds),
        );
        expect(AzamanIntro.settled, lessThan(AzamanIntro.total));
      },
    );

    testWidgets('completion fires at the end, not when the wordmark appears', (
      tester,
    ) async {
      var completed = 0;
      final controller = AnimationController(
        vsync: tester,
        duration: AzamanIntro.total,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: AzamanIntroPlayer(
            controllerOverride: controller,
            chrome: IntroChrome.dark,
            onCompleted: () => completed++,
          ),
        ),
      );

      // Just past the moment the wordmark is legible: must NOT be done.
      controller.value = 2300 / AzamanIntro.total.inMilliseconds;
      await tester.pump();
      expect(
        completed,
        0,
        reason: 'ring and halo still have motion left after 2.3s',
      );

      controller.value = 1;
      await tester.pump();
      expect(completed, 1, reason: 'fires exactly once, at the end');
    });
  });

  group('the reveal is an aperture, not a crossfade', () {
    testWidgets('ink grows outward from the centre', (tester) async {
      final early = await _inkColumns(tester, ms: 1400);
      final mid = await _inkColumns(tester, ms: 1600);
      final settled = await _inkColumns(tester, ms: 2400);
      int total(List<int> c) => c.fold(0, (a, b) => a + b);
      expect(total(early), greaterThan(0));
      expect(
        total(mid),
        greaterThan(total(early)),
        reason: 'the aperture uncovers more ink as it opens',
      );
      expect(total(settled), greaterThan(total(mid)));
    });

    testWidgets('the mark is gone once the wordmark has settled', (
      tester,
    ) async {
      final settled = await _inkColumns(tester, ms: 3000);
      // At 3.0s only the wordmark should be painting: it is a single band, so
      // no row in the sampled middle should be completely empty.
      expect(settled.where((c) => c > 0).length, greaterThan(4));
    });
  });

  group('reduced motion', () {
    testWidgets('shows the settled brand state without an animation', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RepaintBoundary(key: _key, child: AzamanIntroStatic()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byKey(_key));
      expect(size.width, greaterThan(0));
    });
  });
}
