// Visual record: Your trips and the boarding pass, light and dark, with real
// fonts (FontLoader pattern; test/goldens/README.md).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/my_transit_trips_screen.dart';
import 'package:azaman/screens/marketplace/transit_boarding_qr_screen.dart';
import 'package:azaman/services/marketplace_booking_service.dart';

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  for (final (family, path) in [
    ('Inter', 'assets/fonts/Inter-Variable.ttf'),
    ('MaterialIcons', 'test/goldens/fonts/MaterialIcons-Regular.otf'),
  ]) {
    final bytes = await File(path).readAsBytes();
    await (FontLoader(family)..addFont(
          Future<ByteData>.value(
            ByteData.view(Uint8List.fromList(bytes).buffer),
          ),
        ))
        .load();
  }
  _fontsLoaded = true;
}

class _Fake extends MarketplaceBookingService {
  @override
  Future<List<TransitBookingSummary>> myTransitBookings() async => [
    TransitBookingSummary(
      id: 'a',
      bookingRef: 'TRN-4F2A',
      status: 'CONFIRMED',
      origin: 'Circle',
      destination: 'Madina',
      amountUsdc: 0.6,
      departureAt: DateTime(2026, 12, 1, 7, 30),
      operatorName: 'Madina Line',
    ),
    TransitBookingSummary(
      id: 'b',
      bookingRef: 'TRN-91C0',
      status: 'COMPLETED',
      origin: 'Accra',
      destination: 'Kumasi',
      amountUsdc: 9,
      departureAt: DateTime(2026, 11, 20, 6, 0),
      operatorName: 'VIP Jeoun',
    ),
  ];

  @override
  Future<TransitBoardingCode> transitBoardingCode(
    String bookingId,
  ) async => TransitBoardingCode(
    qrPayload:
        '{"token":"eyJ0eXAiOiJUUkFOU0lUX0NIRUNLSU4iLCJiaWQiOiJhIn0.${'c' * 64}","type":"AZAMAN_TRANSIT_CHECKIN"}',
    expiresAt: DateTime(2026, 12, 1, 7, 20),
  );
}

void main() {
  for (final screen in ['trips', 'pass']) {
    for (final dark in [false, true]) {
      final name = '${screen}_${dark ? 'dark' : 'light'}';
      testWidgets('transit $name capture', (tester) async {
        SharedPreferences.setMockInitialValues({'azaman_theme': dark ? 1 : 0});
        final tp = ThemeProvider();
        tester.view
          ..physicalSize = const Size(360, 780) * 3.0
          ..devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);
        await tester.runAsync(_loadFonts);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              themeProvider.overrideWith((ref) => tp),
              marketplaceBookingServiceProvider.overrideWithValue(_Fake()),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeProvider.getThemeData(
                dark ? AzamanTheme.dark : AzamanTheme.light,
              ),
              home: RepaintBoundary(
                child: screen == 'trips'
                    ? const MyTransitTripsScreen()
                    : const TransitBoardingQrScreen(bookingId: 'a'),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('../../goldens/transit/$name.png'),
        );
      });
    }
  }
}
