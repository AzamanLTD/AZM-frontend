import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/hotel_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/building_cross_section.dart';
import 'package:azaman/widgets/marketplace/hotel_arrival_sheet.dart';
import 'package:azaman/widgets/marketplace/stay_date_ribbon.dart';
import 'package:azaman/widgets/marketplace/stay_summary_bar.dart';

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

HotelRoom _room(
  String number, {
  int? floor,
  bool available = true,
  double price = 80,
}) =>
    HotelRoom(
      id: 'room-$number',
      businessProfileId: 'hotel-1',
      roomNumber: number,
      roomType: 'DELUXE',
      capacity: 2,
      status: available ? 'AVAILABLE' : 'BOOKED',
      basePriceUsdc: price,
      amenities: const ['Wi-Fi'],
      imageUrls: const [],
      floor: floor,
    );

void main() {
  group('hotelBandsFromRooms', () {
    test('sorts floors ascending and grounds rooms without a floor', () {
      final bands = hotelBandsFromRooms([
        _room('301', floor: 3),
        _room('101', floor: 1),
        _room('201', floor: 2),
        _room('L01'),
      ]);
      expect(bands.map((b) => b.floor).toList(), [1, 2, 3]);
      expect(
        bands.first.rooms.map((r) => r.roomNumber),
        containsAll(['101', 'L01']),
      );
    });

    test('single unlabelled band when no room declares a floor', () {
      final bands = hotelBandsFromRooms([_room('101'), _room('102')]);
      expect(bands, hasLength(1));
      expect(bands.first.floor, isNull);
      expect(bands.first.rooms, hasLength(2));
    });

    test('empty input yields no bands', () {
      expect(hotelBandsFromRooms(const []), isEmpty);
    });
  });

  group('ribbon math', () {
    test('ribbonNights counts cells between indices', () {
      expect(ribbonNights(2, 5), 3);
      expect(ribbonNights(5, 5), 1);
      expect(ribbonNights(7, 3), 1);
    });

    test('ribbonDateAt is day-granular', () {
      expect(
        ribbonDateAt(DateTime(2026, 9, 25, 14, 30), 3),
        DateTime(2026, 9, 28),
      );
    });

    test('stayTotalFor multiplies', () {
      expect(stayTotalFor(850, 3), 2550.0);
    });
  });

  testWidgets('StayDateRibbon drag extends the stay and ticks per night',
      (tester) async {
    final ranges = <DateTimeRange>[];
    var thresholds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: StayDateRibbon(
              firstDay: DateTime(2026, 9, 25),
              nightlyRate: 100,
              onRangeChanged: ranges.add,
              onNightAdded: () => thresholds++,
              colors: _colors,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Drag to choose your dates'), findsOneWidget);

    // Scaffold-body stretching makes the ribbon Column's centre miss the
    // 96px strip, so the drag anchors on cell 3's rendered day text instead
    // (its centre is the cell centre: Sep 28) and extends two cells right
    // (end-exclusive cell 6 = Oct 1).
    await tester.drag(find.text('28'), const Offset(112, 0));
    await tester.pump();

    expect(ranges, isNotEmpty);
    expect(ranges.last.start, DateTime(2026, 9, 28));
    expect(ranges.last.end, DateTime(2026, 10, 1));
    expect(thresholds, greaterThanOrEqualTo(1));
  });

  testWidgets('StayDateRibbon tap sets a one-night stay', (tester) async {
    final ranges = <DateTimeRange>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: StayDateRibbon(
              firstDay: DateTime(2026, 9, 25),
              nightlyRate: 100,
              onRangeChanged: ranges.add,
              colors: _colors,
            ),
          ),
        ),
      ),
    );

    // Cell 3's rendered day text (Sep 28) — see the drag test for why the
    // ribbon Column's centre cannot be the tap anchor.
    await tester.tap(find.text('28'));
    await tester.pump();

    expect(ranges, hasLength(1));
    expect(ranges.first.start, DateTime(2026, 9, 28));
    expect(ranges.first.end, DateTime(2026, 9, 29));
  });

  testWidgets('StayDateRibbon renders an externally-set range',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: StayDateRibbon(
              firstDay: DateTime(2026, 9, 25),
              checkIn: DateTime(2026, 10, 30),
              checkOut: DateTime(2026, 11, 2),
              nightlyRate: 100,
              onRangeChanged: (_) {},
              colors: _colors,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Oct 30 → Nov 2 · 3 nights'), findsOneWidget);
  });

  testWidgets('StaySummaryBar shows the live total and gates Reserve',
      (tester) async {
    var reserved = 0;
    final room = _room('203', floor: 2, price: 850);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox(),
          bottomNavigationBar: StaySummaryBar(
            room: room,
            checkIn: DateTime(2026, 9,25),
            checkOut: DateTime(2026, 9, 28),
            nights: 3,
            isBooking: false,
            onReserve: () => reserved++,
            colors: _colors,
          ),
        ),
      ),
    );

    expect(find.text('Deluxe · Room 203'), findsOneWidget);
    expect(find.text('\$2550.00 USDC · 3 nights'), findsOneWidget);

    await tester.tap(find.text('Reserve'));
    expect(reserved, 1);
  });

  testWidgets('StaySummaryBar disables Reserve without a room',
      (tester) async {
    var reserved = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox(),
          bottomNavigationBar: StaySummaryBar(
            room: null,
            checkIn: null,
            checkOut: null,
            nights: 0,
            isBooking: false,
            onReserve: () => reserved++,
            colors: _colors,
          ),
        ),
      ),
    );

    expect(find.text('Choose a room and dates'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    await tester.tap(find.text('Reserve'), warnIfMissed: false);
    expect(reserved, 0);
  });

  testWidgets('BuildingCrossSection pages floors and gates room taps',
      (tester) async {
    HotelRoom? tapped;
    final floors = <int?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BuildingCrossSection(
            rooms: [
              _room('101', floor: 1),
              _room('102', floor: 1),
              _room('201', floor: 2, available: false),
              _room('202', floor: 2),
            ],
            selectedRoomId: null,
            onRoomTap: (room) => tapped = room,
            onFloorChanged: floors.add,
            colors: _colors,
          ),
        ),
      ),
    );

    expect(find.text('Floor 1'), findsOneWidget);
    expect(find.text('101'), findsOneWidget);

    await tester.tap(find.text('101'));
    expect(tapped?.id, 'room-101');

    await tester.drag(
        find.byType(BuildingCrossSection), const Offset(0, -220));
    await tester.pumpAndSettle();

    expect(floors, [2]);
    expect(find.text('Floor 2'), findsOneWidget);

    // Unavailable rooms never fire onRoomTap.
    await tester.tap(find.text('201'), warnIfMissed: false);
    expect(tapped?.id, 'room-101');

    await tester.tap(find.text('202'));
    expect(tapped?.id, 'room-202');
  });

  testWidgets('HotelArrivalSheet plays the arrival and shows the stay facts',
      (tester) async {
    final room = _room('203', floor: 2, price: 850);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: HotelArrivalSheet(
              reservationRef: 'R-77',
              room: room,
              checkIn: DateTime(2026, 9, 25),
              nights: 3,
              totalUsdc: 2550,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('YOUR ROOM IS READY'), findsOneWidget);
    expect(find.text('Welcome to your stay'), findsOneWidget);
    expect(find.text('YOUR STAYS'), findsOneWidget);
    expect(find.text('ROOM 203'), findsOneWidget);
    expect(find.text('Deluxe · Room 203'), findsOneWidget);
    expect(find.text('\$2550.00 USDC'), findsOneWidget);
    expect(find.text('R-77'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  // Corrigendum §3A regression: a rendered cell's visual position and the
  // hit-test/index/reveal geometry must stay aligned across multiple cells —
  // not just cell 0 — so the rendered pitch (56dp cell + AzSpace.xs gap) and
  // the single `_cellPitch` constant used by `_cellAt`/`_reveal` can never
  // drift apart. Mutating `_cellPitch` away from the rendered sequence fails
  // the reveal leg; removing the gap or the margin fails the pitch leg.
  testWidgets(
      'rendered cell pitch stays aligned with hit-test and reveal geometry',
      (tester) async {
    final ranges = <DateTimeRange>[];
    final firstDay = DateTime(2026, 9, 25);

    Widget hosted(DateTime? checkIn, DateTime? checkOut) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: StayDateRibbon(
                firstDay: firstDay,
                checkIn: checkIn,
                checkOut: checkOut,
                nightlyRate: 100,
                onRangeChanged: ranges.add,
                colors: _colors,
              ),
            ),
          ),
        );

    await tester.pumpWidget(hosted(null, null));

    // 1. Measure the rendered pitch from two on-screen cells. The visible
    //    cell is 56dp wide; the tokenized gap must make the rendered pitch
    //    strictly wider than the cell itself.
    final cell0 = tester.getRect(find.text('25'));
    final cell3 = tester.getRect(find.text('28'));
    final pitch = (cell3.center.dx - cell0.center.dx) / 3;
    expect(pitch, greaterThan(56));

    // 2. Hit-test alignment: tapping the visual centre of a rendered cell
    //    selects exactly that day, across several cells — not just cell 0.
    for (final entry in {'0': '25', '3': '28', '5': '30'}.entries) {
      final index = int.parse(entry.key);
      final rect = tester.getRect(find.text(entry.value));
      ranges.clear();
      await tester.tapAt(rect.center);
      await tester.pump();
      expect(ranges, hasLength(1));
      expect(ranges.first.start, ribbonDateAt(firstDay, index));
      expect(
          ranges.first.end, ribbonDateAt(firstDay, index + 1));
    }

    // 3. Reveal alignment: an externally-set range far ahead (day 40 = Nov 4)
    //    scrolls the ribbon; the revealed cell's visual centre must still
    //    hit-test to its own day. This is the leg that breaks if reveal math
    //    uses a different pitch than the rendered cells.
    ranges.clear();
    await tester.pumpWidget(hosted(DateTime(2026, 11, 4), DateTime(2026, 11, 7)));
    await tester.pump();

    final revealed = tester.getRect(find.text('4')); // Nov 4's day cell
    expect(revealed.right, lessThanOrEqualTo(400));
    await tester.tapAt(revealed.center);
    await tester.pump();
    expect(ranges, hasLength(1));
    expect(ranges.first.start, DateTime(2026, 11, 4));
    expect(ranges.first.end, DateTime(2026, 11, 5));
  });
}
