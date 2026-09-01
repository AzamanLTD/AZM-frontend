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
      expect(hotel.preset, 'BUILDING_WALK');
      expect(hotel.navigationMode, MarketplaceNavigationMode.floorTraverse);
      expect(transit.preset, 'TRAVEL_JOURNEY');
      expect(transit.customerContext.passenger, isTrue);
    });

    test('rejects a preset belonging to another category', () {
      final blueprint = MarketplaceExperienceBlueprint.fromJson(
        {
          'preset': 'SHOP_FLOOR',
          'navigation': {'mode': 'AISLE_TRAVERSE', 'showProgress': false},
        },
        'FOOD_BEVERAGE',
      );

      expect(blueprint.preset, 'DINING_JOURNEY');
      expect(blueprint.navigationMode,
          MarketplaceNavigationMode.aisleTraverse);
      expect(blueprint.showNavigationContext, isFalse);
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
            'style': 'LIFT_INTO_TRAY',
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
      expect(blueprint.commitStyle, MarketplaceCommitStyle.liftIntoTray);
      expect(blueprint.persistentTray, isFalse);
      expect(blueprint.motionTempo, MarketplaceMotionTempo.quick);
      expect(blueprint.reducedMotionSafe, isTrue);
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
