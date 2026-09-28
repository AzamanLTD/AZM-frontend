// Shared harness for the premium-surface golden set.
//
// Every golden test MUST go through [pumpGoldenSurface] so that the four
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
//   4. typography     — the bundled `Inter` face is EXPLICITLY loaded with
//                       [loadGoldenFonts] and applied as the theme family.
//
// A fifth, external variable — the Flutter/engine version — cannot be pinned in
// Dart, so it is pinned in CI: `.github/workflows/flutter-ci.yml` pins the
// exact engine the project baseline records. `matchesGoldenFile` documents that
// a golden rendered under a different Flutter version may legitimately differ.
//
// Why 4 matters: `flutter_test` does NOT register the `pubspec.yaml` font
// bundle. A bare `ThemeData(...)` therefore resolves to the framework default
// (Roboto), NOT the app's declared family. Declaring `Inter` in `pubspec.yaml`
// is NOT evidence that a golden renders with it — this was measured, not
// assumed. See `test/goldens/README.md` for the full finding.
//
// Rule: goldens are added or *deliberately* regenerated only. Never run
// `--update-goldens` to make a suite green — a regeneration must be a
// reviewable diff in the commit.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pinned surface geometry. Changing these invalidates every golden.
const Size kGoldenSurfaceSize = Size(360, 200);

/// Pinned device pixel ratio for every golden raster.
const double kGoldenPixelRatio = 3.0;

/// How long to settle after the first frame so implicit animations and
/// infinite pumpers (shimmer, liquid) reach their rest state.
const Duration kGoldenSettle = Duration(milliseconds: 400);

/// The bundled face every golden is rasterised with. Declared in
/// `pubspec.yaml` AND loaded explicitly here — the declaration alone does not
/// register it with the test binding.
const String kGoldenFontFamily = 'Inter';

/// Where the bundled face lives, relative to the package root.
const String kGoldenFontPath = 'assets/fonts/Inter-Variable.ttf';

bool _fontsLoaded = false;

/// Loads the bundled golden face(s) exactly once per test process.
///
/// Uses the `FontLoader` pattern documented on `matchesGoldenFile`. This must
/// complete before the first `pumpWidget`, otherwise the engine rasterises text
/// with whatever fallback is registered and the golden bakes in that fallback.
Future<void> loadGoldenFonts() async {
  if (_fontsLoaded) return;
  // Read straight from disk: `rootBundle` in a unit-test binding does not
  // resolve package assets reliably and awaiting it can hang the test, so the
  // file is loaded directly from the package root instead.
  final bytes = await File(kGoldenFontPath).readAsBytes();
  final loader = FontLoader(kGoldenFontFamily)
    ..addFont(Future<ByteData>.value(
      ByteData.view(Uint8List.fromList(bytes).buffer),
    ));
  await loader.load();
  _fontsLoaded = true;
}

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

  // Deterministic typography BEFORE the first pump — see rule 4 in the header.
  // `runAsync` is required: reading the font file is real async I/O, which the
  // test's fake-async zone will never complete on its own (it hangs the test).
  await tester.runAsync(loadGoldenFonts);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: brightness,
        useMaterial3: true,
        fontFamily: kGoldenFontFamily,
      ),
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
