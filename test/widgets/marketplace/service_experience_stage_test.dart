import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/service_experience_stage.dart';

BusinessProduct _product(String id, String name, double price, {bool active = true}) => BusinessProduct(
      id: id,
      businessProfileId: 'business-1',
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      description: '$name description',
      priceUsdc: price,
      totalRevenue: 0,
      imageUrls: const [],
      tags: const [],
      totalOrders: 0,
      isActive: active,
    );

MarketplaceExperienceBlueprint _blueprint() => MarketplaceExperienceBlueprint.fromJson({
      'preset': 'SERVICE_JOURNEY',
      'navigation': {'mode': 'CONTEXTUAL', 'showProgress': true},
      'detail': {
        'presentation': 'SERVICE_DOSSIER',
        'showGallery': true,
        'showSpecifications': true,
        'showOptions': false,
        'showQuantity': false,
      },
      'customerContext': {'enabled': true},
      'commit': {'style': 'MATERIAL', 'persistentTray': false},
      'motion': {'tempo': 'BALANCED'},
    }, 'TECHNOLOGY');

Future<void> _pump(WidgetTester tester, {required List<BusinessProduct> offerings}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: ServiceExperienceStage(
          business: BusinessProfile(
            id: 'business-1',
            bizId: 'BIZ-1',
            businessName: 'Apex Studio',
            category: 'TECHNOLOGY',
            isVerified: true,
            isSuspended: false,
            kybStatus: 'VERIFIED',
            totalEscrows: 0,
            completedEscrows: 0,
            userId: 1,
            totalVolume: 0,
            averageRating: 4.8,
            username: 'apex-studio',
            products: offerings,
          ),
          colors: ThemeProvider.getColors(AzamanTheme.dark),
          offerings: offerings,
          blueprint: _blueprint(),
          onContinue: () {},
          onOpenCatalog: () {},
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('shows real active service offerings in a peeking rail', (tester) async {
    await _pump(tester, offerings: [_product('1', 'Consulting', 50), _product('2', 'Audit', 80)]);

    expect(find.text('Explore Apex Studio'), findsOneWidget);
    expect(find.text('Consulting'), findsOneWidget);
    expect(find.text('Audit'), findsOneWidget);
    expect(find.text('See all offerings'), findsOneWidget);
  });

  testWidgets('focuses an offering into a detail surface', (tester) async {
    await _pump(tester, offerings: [_product('1', 'Consulting', 50)]);

    await tester.tap(find.byKey(const ValueKey('service-offering-1')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Consulting description'), findsOneWidget);
    expect(find.text('50.00 USDC'), findsAtLeastNWidgets(1));
    expect(find.text('Continue with this'), findsOneWidget);
  });

  testWidgets('does not display inactive offerings as customer choices', (tester) async {
    await _pump(tester, offerings: [
      _product('1', 'Live service', 50),
      _product('2', 'Retired service', 80, active: false),
    ]);

    expect(find.text('Live service'), findsOneWidget);
    expect(find.text('Retired service'), findsNothing);
  });

  testWidgets('shows an intentional empty state when no offerings exist', (tester) async {
    await _pump(tester, offerings: const []);

    expect(find.text('Explore this business'), findsOneWidget);
    expect(find.text('The business has not published offerings for this experience yet.'), findsOneWidget);
  });
}