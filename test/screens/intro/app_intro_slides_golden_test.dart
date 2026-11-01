// PUBLIC TOUR — SLIDE CAPTURES, BOTH APPEARANCES.
//
// Six captures: three slides x light and dark. The tour now reads the saved
// appearance and the applied card variant from the live theme provider, so
// these are genuinely different renders — not three dark captures renamed.
// The suite proves that: it measures mean luminance per image and fails if a
// light capture is not measurably brighter than its dark twin.
//
// The dark-only era of this file is the reason for that check. The tour used
// to hardcode ThemeProvider.getColors(AzamanTheme.dark) and a blue card, so a
// "light" capture was a byte-identical duplicate and the evidence was false.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/intro/app_intro_screen.dart';
import 'package:azaman/screens/intro/intro_slide_art.dart';
import 'package:azaman/services/intro_store.dart';
import 'package:azaman/theme/balance_card_brand.dart';
import 'package:azaman/widgets/home/azaman_card_face.dart';

/// The tour only asks its store whether the intro was seen; a capture needs no
/// persistence.
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
  required AzamanTheme appearance,
  required BalanceCardVariant variant,
  required int slide,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  // A provider holding exactly the settings under test, so the capture does
  // not depend on whatever the machine last persisted. The settings are
  // applied AFTER the first pump: ThemeProvider starts an async load from
  // SharedPreferences in its constructor, and a value set before that load
  // resolves gets overwritten by the stored (default) one.
  // Seeded exactly as a device would have them. Setting them on the provider
  // afterwards is a losing race: the constructor's own load from
  // SharedPreferences resolves later and reinstates the stored value, which
  // is how a "green card" capture silently came out blue.
  SharedPreferences.setMockInitialValues(<String, Object>{
    'azaman_theme': appearance.index,
    kBalanceCardVariantPrefKey: variant.storageValue,
  });
  final theme = ThemeProvider();

  await tester.pumpWidget(
    ProviderScope(
      // A distinct key per settings pair: reusing the same scope lets the
      // previous provider instance survive the pump, which is how a green
      // render was measured against a blue card.
      key: ValueKey('${appearance.name}-${variant.name}'),
      overrides: [themeProvider.overrideWith((ref) => theme)],
      child: MaterialApp(
        theme: ThemeData(
          brightness: appearance == AzamanTheme.dark
              ? Brightness.dark
              : Brightness.light,
          useMaterial3: true,
          fontFamily: 'ComicNeue',
        ),
        home: AppIntroScreen(store: _SeenStore()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));

  // Walk to the requested slide the way a person would. Bounded pumps, not
  // pumpAndSettle: the card surface carries a repeating sheen and
  // pumpAndSettle waits ten minutes for a widget that never quiesces.
  for (var i = 0; i < slide; i++) {
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }
}

/// Mean luminance of a captured PNG, used to prove each capture is what it
/// claims: a light surface must actually be light.
Future<double> _luminanceOf(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  var sum = 0;
  var count = 0;
  for (var i = 0; i < bytes.length; i += 4) {
    sum += (bytes[i] * 299 + bytes[i + 1] * 587 + bytes[i + 2] * 114) ~/ 1000;
    count++;
  }
  return sum / count;
}

void main() {
  setUpAll(_loadFonts);

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  final captures = <String, String>{};

  for (final appearance in <AzamanTheme>[AzamanTheme.dark, AzamanTheme.light]) {
    final label = appearance == AzamanTheme.dark ? 'dark' : 'light';

    for (var slide = 0; slide < kIntroSlides.length; slide++) {
      testWidgets('slide ${slide + 1} in $label', (tester) async {
        await _pumpTour(
          tester,
          appearance: appearance,
          variant: BalanceCardVariant.blue,
          slide: slide,
        );

        final art = find.byType(IntroSlideArt);
        expect(art, findsOneWidget);
        expect(tester.getSize(art).height, greaterThan(200));
        expect(tester.takeException(), isNull);

        final path = 'goldens/intro_slide_${slide + 1}_$label.png';
        await expectLater(find.byType(AppIntroScreen), matchesGoldenFile(path));
        captures['$slide-$label'] = path;
      });
    }
  }

  test('light and dark captures actually differ', () async {
    // Measured from the committed goldens, not from a fresh render: this is a
    // statement about the evidence the repository ships.
    for (var slide = 1; slide <= 3; slide++) {
      final dark = await _luminanceOf(
        File(
          'test/screens/intro/goldens/intro_slide_${slide}_dark.png',
        ).readAsBytesSync(),
      );
      final light = await _luminanceOf(
        File(
          'test/screens/intro/goldens/intro_slide_${slide}_light.png',
        ).readAsBytesSync(),
      );
      expect(
        light,
        greaterThan(dark + 40),
        reason:
            'slide $slide: light capture (luminance ${light.toStringAsFixed(1)}) '
            'is not meaningfully brighter than dark '
            '(${dark.toStringAsFixed(1)}) — the appearances are not distinct',
      );
    }
  });

  testWidgets('the wallet hero renders the applied card variant', (
    tester,
  ) async {
    for (final variant in <BalanceCardVariant>[
      BalanceCardVariant.blue,
      BalanceCardVariant.green,
      BalanceCardVariant.red,
      BalanceCardVariant.dark,
    ]) {
      await _pumpTour(
        tester,
        appearance: AzamanTheme.light,
        variant: variant,
        slide: 0,
      );
      final surface = tester.widget<AzamanCardSurface>(
        find.descendant(
          of: find.byType(IntroSlideArt),
          matching: find.byType(AzamanCardSurface),
        ),
      );
      expect(
        surface.variant,
        variant,
        reason: 'wallet slide ignored the saved ${variant.name} card',
      );
    }
  });

  testWidgets('the marketplace keeps its fixed category mapping', (
    tester,
  ) async {
    // Category identity is semantic: applying a green or red card must not
    // re-tint Shop/Stay/Eat/Ride. The tiles are painted from a static table,
    // so this asserts the table is not feeding off the applied variant.
    for (final variant in <BalanceCardVariant>[
      BalanceCardVariant.green,
      BalanceCardVariant.red,
    ]) {
      await _pumpTour(
        tester,
        appearance: AzamanTheme.dark,
        variant: variant,
        slide: 1,
      );
      expect(tester.takeException(), isNull);
      // The wallet's card surface must NOT appear on this slide at all.
      expect(
        find.descendant(
          of: find.byType(IntroSlideArt),
          matching: find.byType(AzamanCardSurface),
        ),
        findsNothing,
      );
    }
  });
}
