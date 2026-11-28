// The hotel check-in code is a real QR of the backend's signed payload — the
// same JSON BusinessCheckInScreen parses — not the decorative grid it was.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/checkin_qr_screen.dart';

const _payload =
    '{"token":"eyJyZXNlcnZhdGlvbklkIjoiUkVTLTEiLCJleHAiOjE3OTU4MjQwMDB9.c2lnbmF0dXJl","type":"AZAMAN_CHECKIN"}';

CheckInToken _token({String payload = _payload}) => CheckInToken(
      token: 'eyJ.sig',
      qrPayload: payload,
      azamanId: 'AZM-7Q2K',
      reservationRef: 'RES-2041',
      expiresAt: DateTime(2026, 12, 1, 14, 30),
      businessName: 'Labadi Beach Hotel',
    );

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  for (final (family, path) in [
    ('Inter', 'assets/fonts/Inter-Variable.ttf'),
    ('MaterialIcons', 'test/goldens/fonts/MaterialIcons-Regular.otf'),
  ]) {
    final bytes = await File(path).readAsBytes();
    await (FontLoader(family)
          ..addFont(Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer))))
        .load();
  }
  _fontsLoaded = true;
}

Future<void> _pump(WidgetTester tester, CheckInToken token, {bool dark = false}) async {
  SharedPreferences.setMockInitialValues({'azaman_theme': dark ? 1 : 0});
  final tp = ThemeProvider();
  tester.view
    ..physicalSize = const Size(360, 780) * 3.0
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.runAsync(_loadFonts);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      themeProvider.overrideWith((ref) => tp),
      checkInTokenProvider('RES-1').overrideWith((ref) async => token),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeProvider.getThemeData(dark ? AzamanTheme.dark : AzamanTheme.light),
      home: const RepaintBoundary(child: CheckInQrScreen(reservationId: 'RES-1')),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('encodes the signed payload as a real, valid QR code', (tester) async {
    await _pump(tester, _token());
    expect(find.byKey(const ValueKey('checkin-qr-code')), findsOneWidget);
    expect(tester.widget<CheckInCode>(find.byType(CheckInCode)).payload, _payload);
    expect(QrValidator.validate(data: _payload).isValid, isTrue);
    // The old decorative grid is gone.
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('the expiry comes from the token, not a fixed "30 minutes"', (tester) async {
    await _pump(tester, _token());
    expect(find.text('Valid until 2:30 PM'), findsOneWidget);
    expect(find.text('Valid for 30 minutes'), findsNothing);
  });

  testWidgets('an empty payload shows a message, not an unreadable code', (tester) async {
    await _pump(tester, _token(payload: ''));
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('This code could not be created. Try again.'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('check-in code capture ${dark ? 'dark' : 'light'}', (tester) async {
      await _pump(tester, _token(), dark: dark);
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('../../goldens/hotel/checkin_qr_${dark ? 'dark' : 'light'}.png'),
      );
    });
  }
}
