// Visual record: the Withdraw stage (harmattan sky), light and dark.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/withdrawal_screen.dart';
import 'package:azaman/widgets/amount_keypad.dart';


const _storage = MethodChannel('plugins.it_nomands.com/flutter_secure_storage');

class _FixedAuth extends AuthProvider {
  _FixedAuth(this.sessionUser);
  final User sessionUser;
  @override
  User? get user => sessionUser;
  @override
  Future<void> fetchUserDetails() async {}
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

void main() {
  for (final dark in [false, true]) {
    final name = '360dp_${dark ? 'dark' : 'light'}';
    testWidgets('withdraw capture $name', (tester) async {
      SharedPreferences.setMockInitialValues({'azaman_theme': dark ? 1 : 0, 'biometric_lock_enabled': false});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_storage, (call) async => call.method == 'read' ? 'mock-token' : null);
      final tp = ThemeProvider();
      tester.view
        ..physicalSize = const Size(360, 780) * 3.0
        ..devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(_loadAppFonts);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _FixedAuth(User(
                id: '7', username: 'me', email: 'me@example.com', token: 'tok', role: 'USER',
                azamanId: 'AZM-999999999', availableBalance: 50.0))),
          themeProvider.overrideWith((ref) => tp),
        ],
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _theme(dark),
            home: const RepaintBoundary(child: WithdrawalScreen(skyPhaseForCaptures: 0.3)),
          ),
        ),
      ));
      // The wallet fetch is real async I/O: let it complete.
      for (var i = 0; i < 10 && find.byType(AmountKeypad).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump(const Duration(milliseconds: 200));
      }
      for (final k in ['2', '5']) {
        await tester.tap(find.descendant(of: find.byType(AmountKeypad), matching: find.text(k)));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pump(const Duration(seconds: 2));
      await expectLater(find.byType(RepaintBoundary).first,
          matchesGoldenFile('../../goldens/money_stage/withdraw_$name.png'));
    });
  }
}
