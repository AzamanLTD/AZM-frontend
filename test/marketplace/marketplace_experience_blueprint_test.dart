import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';

void main() {
  group('MarketplaceExperienceBlueprint', () {
    test('uses category defaults when no remote contract is present', () {
      final restaurant = MarketplaceExperienceBlueprint.fromJson(
        null,
        'FOOD_BEVERAGE',
      );
      final retail = MarketplaceExperienceBlueprint.fromJson(null, 'RETAIL');
      final hotel = MarketplaceExperienceBlueprint.fromJson(null, 'HOSPITALITY');
      final transit = MarketplaceExperienceBlueprint.fromJson(null, 'LOGISTICS');

      expect(restaurant.preset, 'DINING_JOURNEY');
      expect(restaurant.detailPresentation,
          MarketplaceDetailPresentation.dishDossier);
      expect(restaurant.commitStyle, MarketplaceCommitStyle.paperRip);
      expect(retail.preset, 'SHOP_FLOOR');
      expect(retail.navigationMode, MarketplaceNavigationMode.aisleTraverse);
      expect(retail.detailPresentation,
          MarketplaceDetailPresentation.productDossier);
      expect(hotel.preset, 'BUILDING_WALK');
      expect(hotel.navigationMode, MarketplaceNavigationMode.floorTraverse);
      expect(hotel.commitStyle, MarketplaceCommitStyle.material);
      expect(hotel.persistentTray, isFalse);
      expect(transit.preset, 'TRAVEL_JOURNEY');
      expect(transit.customerContext.passenger, isTrue);
      expect(transit.commitStyle, MarketplaceCommitStyle.material);
    });

    test('rejects a preset belonging to another category while preserving valid scalar options', () {
      final blueprint = MarketplaceExperienceBlueprint.fromJson(
        {
          'preset': 'SHOP_FLOOR',
          'navigation': {'mode': 'AISLE_TRAVERSE', 'showProgress': false},
        },
        'FOOD_BEVERAGE',
      );

      expect(blueprint.preset, 'DINING_JOURNEY');
      expect(blueprint.navigationMode,
          MarketplaceNavigationMode.contextual);
      expect(blueprint.showNavigationContext, isFalse);
    });

    test('rejects cross-vertical detail and commit styles', () {
      final blueprint = MarketplaceExperienceBlueprint.fromJson(
        {
          'detail': {'presentation': 'ROOM_DOSSIER'},
          'commit': {'style': 'LIFT_INTO_TRAY'},
          'customerContext': {'tableNumber': true, 'passenger': true},
        },
        'FOOD_BEVERAGE',
      );

      expect(blueprint.detailPresentation,
          MarketplaceDetailPresentation.dishDossier);
      expect(blueprint.commitStyle, MarketplaceCommitStyle.paperRip);
      expect(blueprint.customerContext.tableNumber, isTrue);
      expect(blueprint.customerContext.serviceMode, isTrue);
      expect(blueprint.customerContext.passenger, isFalse);
    });

    test('normalizes every supported behavior dimension', () {
      final blueprint = MarketplaceExperienceBlueprint.fromJson(
        {
          'preset': 'REJECTED',
          'navigation': {
            'mode': 'JOURNEY_TIMELINE',
            'showProgress': false,
          },
          'detail': {
            'presentation': 'SEAT_DOSSIER',
            'showGallery': false,
            'showSpecifications': false,
            'showOptions': false,
            'showQuantity': false,
          },
          'customerContext': {
            'enabled': false,
            'passenger': true,
          },
          'commit': {
            'style': 'MATERIAL',
            'persistentTray': false,
          },
          'motion': {'tempo': 'QUICK'},
        },
        'LOGISTICS',
      );

      expect(blueprint.preset, 'TRAVEL_JOURNEY');
      expect(blueprint.navigationMode,
          MarketplaceNavigationMode.journeyTimeline);
      expect(blueprint.showNavigationContext, isFalse);
      expect(blueprint.detailPresentation,
          MarketplaceDetailPresentation.seatDossier);
      expect(blueprint.showGallery, isFalse);
      expect(blueprint.showSpecifications, isFalse);
      expect(blueprint.showOptions, isFalse);
      expect(blueprint.showQuantity, isFalse);
      expect(blueprint.customerContext.enabled, isFalse);
      expect(blueprint.customerContext.passenger, isTrue);
      expect(blueprint.customerContext.tableNumber, isFalse);
      expect(blueprint.commitStyle, MarketplaceCommitStyle.material);
      expect(blueprint.persistentTray, isFalse);
      expect(blueprint.motionTempo, MarketplaceMotionTempo.quick);
      expect(blueprint.reducedMotionSafe, isTrue);
    });

    test('hospitality aliases retain hotel-safe grammar', () {
      final blueprint = MarketplaceExperienceBlueprint.fromJson(
        {
          'navigation': {'mode': 'FLOOR_TRAVERSE'},
          'detail': {'presentation': 'ROOM_DOSSIER'},
          'commit': {'style': 'LIFT_INTO_TRAY'},
          'customerContext': {'tableNumber': true, 'passenger': true},
        },
        'HOTEL',
      );

      expect(blueprint.preset, 'BUILDING_WALK');
      expect(blueprint.navigationMode, MarketplaceNavigationMode.floorTraverse);
      expect(blueprint.detailPresentation,
          MarketplaceDetailPresentation.roomDossier);
      expect(blueprint.commitStyle, MarketplaceCommitStyle.material);
      expect(blueprint.customerContext.tableNumber, isFalse);
      expect(blueprint.customerContext.passenger, isFalse);
    });

    test('unknown categories fall back to a restrained service journey', () {
      final blueprint = MarketplaceExperienceBlueprint.fromJson(
        {
          'navigation': {'mode': 'AISLE_TRAVERSE'},
          'detail': {'presentation': 'PRODUCT_DOSSIER'},
          'commit': {'style': 'PAPER_RIP'},
          'customerContext': {
            'tableNumber': true,
            'serviceMode': true,
            'passenger': true,
          },
        },
        'HEALTH_WELLNESS',
      );

      expect(blueprint.preset, 'SERVICE_JOURNEY');
      expect(blueprint.navigationMode,
          MarketplaceNavigationMode.contextual);
      expect(blueprint.detailPresentation,
          MarketplaceDetailPresentation.serviceDossier);
      expect(blueprint.commitStyle, MarketplaceCommitStyle.material);
      expect(blueprint.customerContext.tableNumber, isFalse);
      expect(blueprint.customerContext.serviceMode, isFalse);
      expect(blueprint.customerContext.passenger, isFalse);
    });

    testWidgets('maps tempo to MotionTokens and respects reduced motion',
        (tester) async {
      Duration? normal;
      Duration? reduced;
      final blueprint = MarketplaceExperienceBlueprint.fromJson(
        {'motion': {'tempo': 'RELAXED'}},
        'RETAIL',
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              normal = blueprint.motionDuration(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              reduced = blueprint.motionDuration(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(normal, const Duration(milliseconds: 450));
      expect(reduced, Duration.zero);
    });
  });
}
