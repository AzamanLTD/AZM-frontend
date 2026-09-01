import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/hotel_floor_plan_preview.dart';

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

BusinessProduct _room(
  String name, {
  bool active = true,
  double price = 80,
}) => BusinessProduct(
      id: name.toLowerCase().replaceAll(' ', '-'),
      businessProfileId: 'hotel-1',
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      description: null,
      priceUsdc: price,
      totalRevenue: 0,
      imageUrls: const [],
      isActive: active,
      totalOrders: 0,
      tags: const [],
    );

void main() {
  testWidgets('shows building floors and selects a floor', (tester) async {
    String? selected;
    final products = [
      _room('Room 201'),
      _room('Room 202'),
      _room('Room 301', price: 120),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HotelFloorPlanPreview(
            products: products,
            selectedRoomId: null,
            onRoomSelected: (id) => selected = id,
            colors: _colors,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Building overview'), findsOneWidget);
    expect(find.text('2 floors'), findsOneWidget);
    expect(find.text('Floor 3'), findsOneWidget);
    expect(find.text('Floor 2'), findsOneWidget);

    await tester.tap(find.text('Floor 3'));
    await tester.pump();

    expect(find.text('301'), findsOneWidget);
    expect(find.text('202'), findsNothing);
    expect(selected, isNull);
  });

  testWidgets('marks inactive rooms unavailable and prevents selection',
      (tester) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HotelFloorPlanPreview(
            products: [
              _room('Room 101'),
              _room('Room 102', active: false),
            ],
            selectedRoomId: null,
            onRoomSelected: (id) => selected = id,
            colors: _colors,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Unavailable'), findsOneWidget);

    await tester.tap(find.text('102'));
    await tester.pump();
    expect(selected, isNull);

    await tester.tap(find.text('101'));
    await tester.pump();
    expect(selected, 'room-101');
  });
}
