// Visual record: the drawn vehicle on the seat-selection screen — a trotro
// (Sprinter, back bench across the walkway), a 2+2 coach and the portal's
// default grid — light and dark. Real fonts (FontLoader pattern;
// test/goldens/README.md).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/config.dart';
import 'package:azaman/marketplace/experiences/transit/transit_experience.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/transit_seat_selection_screen.dart';

bool _fontsLoaded = false;
Future<void> _loadFace(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(family)..addFont(
        Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
      ))
      .load();
}

Future<void> _loadAppFonts() async {
  if (_fontsLoaded) return;
  await _loadFace('Inter', 'assets/fonts/Inter-Variable.ttf');
  await _loadFace(
    'MaterialIcons',
    'test/goldens/fonts/MaterialIcons-Regular.otf',
  );
  await _loadFace('DejaVuSans', 'test/goldens/fonts/DejaVuSans.ttf');
  _fontsLoaded = true;
}

ThemeData _theme(bool dark) {
  final base = ThemeProvider.getThemeData(
    dark ? AzamanTheme.dark : AzamanTheme.light,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: const ['DejaVuSans']),
  );
}

TransitTrip _trip(String type, int seats) => TransitTrip(
  id: 'trip-$type',
  businessProfileId: 'b1',
  vehicleId: 'v-$type',
  routeName: 'Circle - Madina',
  origin: type == 'Coach' ? 'Accra' : 'Circle',
  destination: type == 'Coach' ? 'Kumasi' : 'Madina',
  departureAt: DateTime(2026, 12, 1, 7, 30),
  fareUsdc: type == 'Coach' ? 9 : 0.6,
  availableSeats: seats,
  status: TripStatus.scheduled,
  vehicleType: type,
);

TransitSeat _s(
  String id,
  int row,
  int col, {
  SeatStatus status = SeatStatus.available,
  SeatTier tier = SeatTier.economy,
  double fare = 0.6,
}) => TransitSeat(
  seatId: id,
  row: row,
  col: col,
  type: SeatType.window,
  status: status,
  tier: tier,
  fare: fare,
);

TransitSeat _none(int row, int col) => TransitSeat(
  seatId: '$row${String.fromCharCode(64 + col)}',
  row: row,
  col: col,
  type: SeatType.none,
  status: SeatStatus.available,
);

/// A Sprinter trotro: rows 1-3 have two seats, the walkway (col 3) and a
/// door-side seat; the back bench crosses the walkway.
List<TransitSeat> _trotro() {
  final out = <TransitSeat>[];
  for (var r = 1; r <= 3; r++) {
    out
      ..add(
        _s(
          '${r}A',
          r,
          1,
          status: r == 2 ? SeatStatus.occupied : SeatStatus.available,
        ),
      )
      ..add(
        _s(
          '${r}B',
          r,
          2,
          status: r == 1 ? SeatStatus.occupied : SeatStatus.available,
        ),
      )
      ..add(_none(r, 3))
      ..add(_s('${r}D', r, 4));
  }
  for (var c = 1; c <= 4; c++) {
    out.add(
      _s(
        '4${String.fromCharCode(64 + c)}',
        4,
        c,
        status: c == 4 ? SeatStatus.occupied : SeatStatus.available,
      ),
    );
  }
  return out;
}

/// A 2+2 coach, VIP up front, a five-seat back row.
List<TransitSeat> _coach() {
  final out = <TransitSeat>[];
  for (var r = 1; r <= 9; r++) {
    for (final c in [1, 2, 4, 5]) {
      final id = '$r${String.fromCharCode(64 + c)}';
      out.add(
        _s(
          id,
          r,
          c,
          tier: r <= 2 ? SeatTier.vip : SeatTier.economy,
          fare: r <= 2 ? 14 : 9,
          status: (r * c) % 7 == 0
              ? SeatStatus.occupied
              : (r == 6 && c == 5 ? SeatStatus.blocked : SeatStatus.available),
        ),
      );
    }
    out.add(_none(r, 3));
  }
  for (var c = 1; c <= 5; c++) {
    out.add(_s('10${String.fromCharCode(64 + c)}', 10, c, fare: 9));
  }
  return out;
}

/// The portal's default grid: 6 x 4, every cell a seat, no walkway drawn.
List<TransitSeat> _portalDefault() => [
  for (var r = 1; r <= 6; r++)
    for (var c = 1; c <= 4; c++)
      _s(
        '$r${String.fromCharCode(64 + c)}',
        r,
        c,
        status: (r + c) % 5 == 0 ? SeatStatus.occupied : SeatStatus.available,
        fare: 2,
      ),
];

SeatAvailability _availability(
  String trip,
  List<TransitSeat> seats,
  double fare,
) => SeatAvailability(
  tripId: trip,
  seats: seats,
  availableCount: seats
      .where((s) => !s.isSpace && s.status == SeatStatus.available)
      .length,
  totalSeats: seats.where((s) => !s.isSpace).length,
  tripStatus: 'SCHEDULED',
  fareUsdc: fare,
);

/// A fixed clock and a hold with 4:12 left, so the countdown is the same
/// on every run.
final _now = DateTime(2026, 12, 1, 7, 0);

class _FixedHoldGateway implements TransitHoldGateway {
  @override
  Future<TransitHoldResult> hold(TransitSeatSelection selection) async =>
      TransitHoldSuccess(
        holdId: 'capture',
        expiresAt: _now.add(const Duration(minutes: 4, seconds: 12)),
      );
}

void main() {
  AppConfig.enableDemoMode();

  final cases = <String, (String, List<TransitSeat>, String?)>{
    'trotro': ('Trotro', _trotro(), '2D'),
    'coach': ('Coach', _coach(), '3B'),
    'portal_default': ('Van', _portalDefault(), null),
  };

  for (final entry in cases.entries) {
    for (final dark in [false, true]) {
      if (entry.key == 'portal_default' && dark) continue;
      final name = '${entry.key}_${dark ? 'dark' : 'light'}';
      testWidgets('transit vehicle capture $name', (tester) async {
        SharedPreferences.setMockInitialValues({'azaman_theme': dark ? 1 : 0});
        final tp = ThemeProvider();
        tester.view
          ..physicalSize = const Size(360, 780) * 3.0
          ..devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);
        await tester.runAsync(_loadAppFonts);

        final (type, seats, pick) = entry.value;
        final trip = _trip(type, seats.length);
        final container = ProviderContainer(
          overrides: [
            themeProvider.overrideWith((ref) => tp),
            tripDetailProvider(trip.id).overrideWith((ref) async => trip),
            seatAvailabilityProvider(trip.id).overrideWith(
              (ref) async => _availability(trip.id, seats, trip.fareUsdc),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: _theme(dark),
                home: RepaintBoundary(
                  child: TransitSeatSelectionScreen(
                    tripId: trip.id,
                    holdGateway: _FixedHoldGateway(),
                    holdClock: () => _now,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        if (pick != null) {
          await tester.tap(find.bySemanticsLabel(RegExp('^Seat $pick,')));
          // Frame by frame: the dock arrives, the vehicle refits to the
          // smaller viewport, and the fit animates.
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('../../goldens/transit/vehicle_$name.png'),
        );
        // Unmount and let the dock's entrance and the sheet staggers finish,
        // so teardown sees no live timer.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
