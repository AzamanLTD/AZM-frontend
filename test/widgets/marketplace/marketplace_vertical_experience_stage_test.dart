    );

    expect(find.text('Explore the property'), findsOneWidget);
    expect(find.byType(HotelFloorPlanPreview), findsOneWidget);
    expect(find.text('Continue to rooms'), findsOneWidget);

    await tester.tap(find.text('Continue to rooms'));
    expect(route, '/business-market/BIZ-1/hotel-booking');
  });

  testWidgets('restaurant businesses use the native menu journey', (tester) async {
    await _pump(
      tester,
      business: _business('FOOD_BEVERAGE'),
      menuSections: [
        _section('Mains', [_product('Jollof Rice')]),
      ],
      onOrder: () {},
    );

    expect(find.byType(RestaurantNativeMenuJourneyClean), findsOneWidget);
    expect(find.text('MENU'), findsOneWidget);
    expect(find.text('Turn from the edge to browse'), findsOneWidget);
  });

  testWidgets('transit businesses expose schedule fallback when no trips exist', (tester) async {
    await _pump(
      tester,
      business: _business('LOGISTICS'),
    );

    expect(find.text('No upcoming trips yet'), findsOneWidget);
  });

  testWidgets('unknown categories use the native service journey', (tester) async {
    var opened = false;
    await _pump(
      tester,
      business: _business('TECHNOLOGY', products: [_product('Strategy session', price: 65)]),
      onOrder: () => opened = true,
    );

    expect(find.byType(ServiceExperienceStage), findsOneWidget);
    expect(find.text('Explore Test Business'), findsOneWidget);
    expect(find.text('Strategy session'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('service-offering-${_strategyId}')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Strategy session description'), findsOneWidget);

    await tester.tap(find.text('Continue with this'));
    expect(opened, isTrue);
  });

  testWidgets('unknown categories with no offerings show an intentional empty state', (tester) async {
    await _pump(
      tester,
      business: _business('TECHNOLOGY'),
    );

    expect(find.byType(ServiceExperienceStage), findsOneWidget);
    expect(find.text('Explore this business'), findsOneWidget);
    expect(find.text('The business has not published offerings for this experience yet.'), findsOneWidget);
  });
}