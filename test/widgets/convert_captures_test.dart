// =============================================================================
// AZAMAN — WORKSTREAM G: CONVERT SHELL VISUAL CAPTURES
//
// Reviewable goldens for the honest Convert shell (PR #177) in BOTH themes
// at 320 / 360 / 390 dp.
//
// What the captures must show, per the G work order:
//   • The NONBINDING estimate panel: '1 USDC ≈ 12.50 GHS' + the source
//     disclosure + the not-a-quote disclaimer.
//   • The execution gate rendered honestly: the CTA in its DISABLED state
//     (no capability implication — the backend has no conversion contract).
//
// Same hard rules as the Send / native_amount sets:
//   1. REAL FONTS — every face loaded through FontLoader before the first
//      pump (cedi glyph falls through to DejaVuSans, as on device).
//   2. The rate is PINNED (fxRateProvider → 12.50, fresh) so the estimate
//     is deterministic: 1 USDC ≈ 12.50 GHS.
//   3. disableAnimations lands via the INNER MediaQuery the widgets read.
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

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/providers/currency_provider.dart' show FxRateSnapshot, fxRateProvider;
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/wallet/convert_screen.dart';

bool _fontsLoaded = false;
const _storageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

Future<void> _loadFace(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  await loader.load();
}

Future<void> _loadAppFonts() async {
  if (_fontsLoaded) return;
  await _loadFace('Inter', 'assets/fonts/Inter-Variable.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Regular.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Bold.ttf');
  await _loadFace(
    'MaterialIcons',
    'test/goldens/fonts/MaterialIcons-Regular.otf',
  );
  await _loadFace('DejaVuSans', 'test/goldens/fonts/DejaVuSans.ttf');
  _fontsLoaded = true;
}

ThemeData _harnessTheme(bool dark) {
  return ThemeProvider.getThemeData(
    dark ? AzamanTheme.dark : AzamanTheme.light,
  );
}

FxRateSnapshot _pinnedRate() {
  final now = DateTime.now().toUtc();
  return FxRateSnapshot(
    ghsPerUsdc: 12.50,
    source: 'KOTANI',
    lastSync: now,
    fetchedAt: now,
    serverFresh: true,
    lastExternalSync: now,
    externalRateAgeSeconds: 0,
    rateFreshnessMaxAgeSeconds: 60,
  );
}

Future<void> _pumpSubject(
  WidgetTester tester, {
  required Size size,
  required bool dark,
}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
        if (call.method == 'read') return 'mock-token';
        return null;
      });
  SharedPreferences.setMockInitialValues({'azaman_theme': dark ? 1 : 0});
  tester.view
    ..physicalSize = size * 3.0
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.runAsync(_loadAppFonts);

  final container = ProviderContainer(
    overrides: [fxRateProvider.overrideWith((ref) async => _pinnedRate())],
  );
  addTearDown(container.dispose);
  container.read(currencyProvider.notifier).state = DisplayCurrency.ghs;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _harnessTheme(dark),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const RepaintBoundary(child: ConvertScreen()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() {
    final goldenDir = Directory('test/goldens/convert');
    if (!goldenDir.existsSync()) goldenDir.createSync(recursive: true);
  });

  const sizes = {
    '320': Size(320, 692),
    '360': Size(360, 800),
    '390': Size(390, 844),
  };

  for (final dark in [false, true]) {
    for (final entry in sizes.entries) {
      testWidgets(
        'convert shell — ${entry.key} — ${dark ? 'dark' : 'light'}',
        (tester) async {
          await _pumpSubject(
            tester,
            size: entry.value,
            dark: dark,
          );

          // The contract the goldens must visibly preserve: a labelled
          // NONBINDING estimate, a disclosed source, and a DISABLED CTA.
          expect(
            find.byKey(const Key('convert_estimate_rate')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('convert_estimate_source_disclosure')),
            findsOneWidget,
            reason: 'the source + freshness disclosure is part of the '
                'golden contract — it must be VISIBLE in every capture',
          );
          expect(
            find.byKey(const Key('convert_execution_unavailable')),
            findsOneWidget,
          );

          await expectLater(
            find.byType(RepaintBoundary).first,
            matchesGoldenFile(
              '../goldens/convert/shell_${entry.key}_${dark ? 'dark' : 'light'}.png',
            ),
          );
        },
        timeout: const Timeout(Duration(minutes: 4)),
      );
    }
  }
}
