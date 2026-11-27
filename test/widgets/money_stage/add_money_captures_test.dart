// Visual record: the Add money (Add Cash) stage, light and dark, empty and
// with an amount typed. Real fonts (FontLoader pattern; test/goldens/README.md)
// with DejaVuSans as the glyph fallback so the cedi symbol renders.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/widgets/amount_keypad.dart';

class _FakeSavedMomo extends SavedMomoNotifier {
  @override
  Future<List<SavedMomoAccount>> build() async => [
        SavedMomoAccount(
          id: 'a1',
          nickname: 'Kwame',
          provider: 'MTN',
          phoneNumber: '0244123456',
          accountName: 'Kwame Mensah',
          isVerified: true,
          isPrimary: true,
          createdAt: DateTime.utc(2026, 9, 1),
        ),
      ];
}

bool _fontsLoaded = false;
Future<void> _loadFace(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer))))
      .load();
}

Future<void> _loadAppFonts() async {
  if (_fontsLoaded) return;
  await _loadFace('Inter', 'assets/fonts/Inter-Variable.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Regular.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Bold.ttf');
  await _loadFace('MaterialIcons', 'test/goldens/fonts/MaterialIcons-Regular.otf');
  await _loadFace('DejaVuSans', 'test/goldens/fonts/DejaVuSans.ttf');
  _fontsLoaded = true;
}

ThemeData _theme(bool dark) {
  final base = ThemeProvider.getThemeData(dark ? AzamanTheme.dark : AzamanTheme.light);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: const ['DejaVuSans']),
  );
}

Future<void> _tapKey(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(AmountKeypad), matching: find.text(label)));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  AppConfig.enableDemoMode();

  for (final dark in [false, true]) {
    for (final typed in [false, true]) {
      final name = '360dp_${dark ? 'dark' : 'light'}_${typed ? 'amount' : 'empty'}';
      testWidgets('add money capture $name', (tester) async {
        SharedPreferences.setMockInitialValues({'azaman_theme': dark ? 1 : 0});
        final tp = ThemeProvider();
        tester.view
          ..physicalSize = const Size(360, 780) * 3.0
          ..devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);
        await tester.runAsync(_loadAppFonts);

        await tester.pumpWidget(ProviderScope(
          overrides: [
            savedMomoProvider.overrideWith(() => _FakeSavedMomo()),
            themeProvider.overrideWith((ref) => tp),
          ],
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _theme(dark),
              home: const RepaintBoundary(child: DepositScreen(skyPhaseForCaptures: 0.3)),
            ),
          ),
        ));
        await tester.pump(const Duration(seconds: 1));
        if (typed) {
          for (final k in ['2', '5', '0']) {
            await _tapKey(tester, k);
          }
        }
        await tester.pump(const Duration(seconds: 1));
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('../../goldens/money_stage/add_money_$name.png'),
        );
      });
    }
  }
}
