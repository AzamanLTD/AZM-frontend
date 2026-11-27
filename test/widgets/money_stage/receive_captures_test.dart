// Visual record: the Receive stage (lagoon) and its Request mode (blush).
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
import 'package:azaman/screens/receive_screen.dart';


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
    for (final request in [false, true]) {
      final name = '360dp_${dark ? 'dark' : 'light'}_${request ? 'request' : 'receive'}';
      testWidgets('receive capture $name', (tester) async {
        SharedPreferences.setMockInitialValues({'azaman_theme': dark ? 1 : 0});
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
                  id: '7', username: 'kofi', email: 'kofi@example.com', token: 'tok', role: 'USER',
                  azamanId: 'AZM-8273941', availableBalance: 50.0))),
            themeProvider.overrideWith((ref) => tp),
          ],
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _theme(dark),
              home: const RepaintBoundary(child: ReceiveScreen(skyPhaseForCaptures: 0.3)),
            ),
          ),
        ));
        await tester.pump(const Duration(seconds: 1));
        if (request) {
          await tester.tap(find.byKey(const ValueKey('receive-request-toggle')));
          await tester.pump(const Duration(seconds: 1));
        }
        await tester.pump(const Duration(seconds: 1));
        await expectLater(find.byType(RepaintBoundary).first,
            matchesGoldenFile('../../goldens/money_stage/receive_$name.png'));
      });
    }
  }
}
