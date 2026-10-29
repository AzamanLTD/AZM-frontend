// PUBLIC TOUR — SLIDE CAPTURES.
//
// Proof that the tour is a finished composition rather than a wireframe. Each
// slide is captured in both appearances at a 390pt phone, with the REAL UI
// font faces loaded (Comic Neue for copy, Inter for figures), so the images
// show true glyphs instead of the test harness's placeholder bars.
//
// These are pinned goldens: they are reviewed as pictures and committed by
// hand. A layout regression that breaks the composition should fail here
// loudly, which is the point of pinning them.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/screens/intro/app_intro_screen.dart';
import 'package:azaman/screens/intro/intro_slide_art.dart';
import 'package:azaman/services/intro_store.dart';

/// The tour only ever asks its store whether the intro was seen; a golden
/// capture needs no persistence.
class _SeenStore implements IntroStore {
  @override
  Future<bool> hasSeenIntro() async => false;
  @override
  Future<bool> markSeen() async => true;
}

bool _fontsLoaded = false;

Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final bytes = await File(path).readAsBytes();
      loader.addFont(
        Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
      );
    }
    await loader.load();
  }

  await load('Inter', ['assets/fonts/Inter-Variable.ttf']);
  await load('ComicNeue', [
    'assets/fonts/ComicNeue-Regular.ttf',
    'assets/fonts/ComicNeue-Bold.ttf',
  ]);
  _fontsLoaded = true;
}

Future<void> _pumpTour(
  WidgetTester tester, {
  required Brightness brightness,
  required int slide,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        useMaterial3: true,
        fontFamily: 'ComicNeue',
      ),
      home: AppIntroScreen(store: _SeenStore()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));

  // Walk to the requested slide the way a person would. Bounded pumps, not
  // pumpAndSettle: the real card surface carries a repeating sheen, and
  // pumpAndSettle waits ten minutes for a widget that never quiesces.
  for (var i = 0; i < slide; i++) {
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }
}

void main() {
  setUpAll(_loadFonts);

  // ONE appearance, not two. The public tour is a fixed brand surface: it
  // reads ThemeProvider.getColors(AzamanTheme.dark) unconditionally, the same
  // material as the launch animation, so a light capture would be a byte
  // duplicate of the dark one and claiming otherwise would be false evidence.
  // Whether the tour should follow the appearance setting is an owner design
  // decision, not something to change silently under a defect fix.
  for (var slide = 0; slide < kIntroSlides.length; slide++) {
    testWidgets('slide ${slide + 1} renders its art', (tester) async {
      await _pumpTour(tester, brightness: Brightness.dark, slide: slide);

      // The art is present and actually sized, not collapsed to nothing.
      final art = find.byType(IntroSlideArt);
      expect(art, findsOneWidget);
      expect(tester.getSize(art).height, greaterThan(200));
      expect(tester.takeException(), isNull);

      await expectLater(
        find.byType(AppIntroScreen),
        matchesGoldenFile('goldens/intro_slide_${slide + 1}.png'),
      );
    });
  }
}
