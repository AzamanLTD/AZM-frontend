// Shared harness for the premium-surface golden set.
//
// Every golden test MUST go through [pumpGoldenSurface] so that the three
// sources of flakiness are pinned in one place:
//
//   1. surface size   — fixed logical box, so layout cannot drift with the
//                       host window.
//   2. pixel ratio    — fixed DPR, so rasterisation is identical everywhere.
//   3. animations     — `MediaQueryData.disableAnimations: true` on the INNER
//                       MediaQuery (inside `MaterialApp.home`), which is the one
//                       the widgets actually read. Setting it outside
//                       MaterialApp lets MaterialApp overwrite it, and the frame
//                       is then captured mid-transition.
//
// Rule: goldens are added or *deliberately* regenerated only. Never run
// `--update-goldens` to make a suite green — a regeneration must be a
// reviewable diff in the commit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pinned surface geometry. Changing these invalidates every golden.
const Size kGoldenSurfaceSize = Size(360, 200);

/// Pinned device pixel ratio for every golden raster.
const double kGoldenPixelRatio = 3.0;

/// How long to settle after the first frame so implicit animations and
/// infinite pumpers (shimmer, liquid) reach their rest state.
const Duration kGoldenSettle = Duration(milliseconds: 400);

/// Pumps [child] inside a fully pinned golden surface.
///
/// [brightness] selects the light or dark ThemeData, [home] overrides the
/// default centred `Scaffold` when a surface needs a bespoke background (e.g.
/// a light/dark scrim behind glass), and [child] is what the default
/// `Scaffold` centres. Supply [home] and [child], or neither.
Future<void> pumpGoldenSurface(
  WidgetTester tester, {
  required Brightness brightness,
  Widget? child,
  Widget? home,
  Size surfaceSize = kGoldenSurfaceSize,
  double pixelRatio = kGoldenPixelRatio,
}) async {
  tester.view
    ..physicalSize = surfaceSize * pixelRatio
    ..devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      home: home ??
          Scaffold(
            body: Center(
              child: RepaintBoundary(child: child ?? const SizedBox.shrink()),
            ),
          ),
    ),
  );

  await tester.pump(kGoldenSettle);
}

/// Wraps [child] in the deterministic reduced-motion MediaQuery required by
/// the golden rules. Must be used *inside* `MaterialApp.home`.
Widget goldenNoMotion(Widget child) {
  return MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: child,
  );
}
