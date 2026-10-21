// =============================================================================
// AZAMAN — COMPACT CARD TRANSFER: VISUAL CAPTURES (320 / 360 / 390 dp ×
// LIGHT / DARK, plus short viewports)
//
// Deliberate, reviewable goldens for the Workstream C compact surface, in
// BOTH stages (amount with a live preview, and the honest review pairing).
// 3 widths × 2 stages × 2 brightnesses = 12 rasters, plus a short-viewport
// (320×540) light/dark pair proving the stage scrolls instead of clipping.
//
// Same hard rules as the Send set (see test/goldens/README.md):
//   1. REAL FONTS — every face loaded through FontLoader before the first
//      pump; the cedi glyph falls through to DejaVuSans exactly as the
//      on-device OS fallback supplies it.
//   2. The rate is PINNED (fxRateOverride 15.38) so the preview equivalent
//      is deterministic: 5 GH₵ → 0.33 USDC on the rail.
//   3. disableAnimations: the entrance settles at its end state and the
//      flow lane rests — captures are deterministic.
//
// Generated with `flutter test --update-goldens`; any later regeneration
// must be a reviewable diff, never a green-maker.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/card_transfer_screen.dart';

const _storageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _sizes = {
  '320': Size(320, 692),
  '360': Size(360, 800),
  '390': Size(390, 844),
  '320short': Size(320, 540),
};

// ── Real fonts (FontLoader pattern; see test/goldens/README.md) ─────────────

bool _fontsLoaded = false;

Future<void> _loadFace(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(
      ByteData.view(Uint8List.fromList(bytes).buffer),
    ));
  await loader.load();
}

Future<void> _loadAppFonts() async {
  if (_fontsLoaded) return;
  await _loadFace('Inter', 'assets/fonts/Inter-Variable.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Regular.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Bold.ttf');
  await _loadFace(
      'MaterialIcons', 'test/goldens/fonts/MaterialIcons-Regular.otf');
  await _loadFace('DejaVuSans', 'test/goldens/fonts/DejaVuSans.ttf');
  _fontsLoaded = true;
}

ThemeData _harnessTheme(bool dark) {
  final base = ThemeProvider.getThemeData(
    dark ? AzamanTheme.dark : AzamanTheme.light,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: const ['DejaVuSans']),
  );
}

Future<void> _pump(WidgetTester tester, Size size, {required bool dark}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
    if (call.method == 'read') return 'mock-token';
    return null;
  });
  SharedPreferences.setMockInitialValues({'azaman_theme': dark ? 1 : 0});
  final tp = ThemeProvider();
  tester.view
    ..physicalSize = size * 3.0
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.runAsync(_loadAppFonts);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        themeProvider.overrideWith((ref) => tp),
        balanceDataProvider.overrideWith(
          (ref) => const BalanceData(availableBalance: 100),
        ),
      ],
      child: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _harnessTheme(dark),
          home: const RepaintBoundary(
            child: CardTransferScreen(fxRateOverride: 15.38),
          ),
        ),
      ),
    ),
  );
  // Fixed pumps: the surface carries live providers whose refresh pulses
  // would otherwise never "settle" — and the pinned rate means there is
  // nothing async left to await. disableAnimations lands the entrance
  // at its end state on the first frame.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _capture(
  WidgetTester tester, {
  required String width,
  required String stage,
  required bool dark,
}) async {
  final size = _sizes[width]!;
  await _pump(tester, size, dark: dark);

  if (stage == 'review') {
    // 5 GH₵ — the pinned rate makes the rail preview deterministic
    // (0.33 USDC), and the review pairing freezes it honestly.
    await tester.tap(find.text('5').first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('card-transfer-review-cta')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  await expectLater(
    find.byType(CardTransferScreen),
    matchesGoldenFile(
      '../goldens/card_transfer/${width}_${dark ? 'dark' : 'light'}_$stage.png',
    ),
  );
}

void main() {
  setUpAll(() {
    final goldenDir = Directory('test/goldens/card_transfer');
    if (!goldenDir.existsSync()) goldenDir.createSync(recursive: true);
  });

  for (final entry in _sizes.entries) {
    final isShort = entry.key.endsWith('short');
    for (final dark in [false, true]) {
      testWidgets(
        'capture ${entry.key} ${dark ? 'dark' : 'light'} '
        '${isShort ? 'amount (short viewport)' : 'amount + review'}',
        (tester) async {
          if (isShort) {
            await _capture(tester, width: entry.key, stage: 'amount', dark: dark);
          } else {
            await _capture(tester, width: entry.key, stage: 'amount', dark: dark);
            await _capture(tester, width: entry.key, stage: 'review', dark: dark);
          }
        },
      );
    }
  }
}
