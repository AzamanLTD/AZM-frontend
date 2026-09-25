import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experience/marketplace_experience_capabilities.dart';

void main() {
  group('MarketplaceExperienceCatalog', () {
    test('maps restaurants to menu and reservation capabilities', () {
      final profile =
          MarketplaceExperienceCatalog.fromCategory('FOOD_BEVERAGE');

      expect(profile, same(MarketplaceExperienceCatalog.restaurant));
      expect(profile.label, 'Restaurants');
      expect(profile.primaryActionLabel, 'View menu');
      expect(
        profile.supports(MarketplaceExperienceCapability.menuFlipbook),
        isTrue,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.reservation),
        isTrue,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.hotelFloorMap),
        isFalse,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.transitSeatMap),
        isFalse,
      );
    });

    test('maps retail to collection, variants and fulfilment capabilities', () {
      final profile = MarketplaceExperienceCatalog.fromCategory('RETAIL');

      expect(profile, same(MarketplaceExperienceCatalog.retail));
      expect(profile.label, 'Retail');
      expect(profile.primaryActionLabel, 'View store');
      expect(
        profile.supports(MarketplaceExperienceCapability.retailCollection),
        isTrue,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.productVariants),
        isTrue,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.pickup),
        isTrue,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.delivery),
        isTrue,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.menuFlipbook),
        isFalse,
      );
    });

    test('maps hotels to spatial room capabilities', () {
      final profile =
          MarketplaceExperienceCatalog.fromCategory('HOSPITALITY');

      expect(profile, same(MarketplaceExperienceCatalog.hotel));
      expect(profile.label, 'Hotels');
      expect(profile.primaryActionLabel, 'See rooms');
      expect(
        profile.supports(MarketplaceExperienceCapability.hotelFloorMap),
        isTrue,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.roomExplorer),
        isTrue,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.reservation),
        isTrue,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.retailCollection),
        isFalse,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.transitSeatMap),
        isFalse,
      );
    });

    test('maps transit to seat map and boarding capabilities', () {
      final profile = MarketplaceExperienceCatalog.fromCategory('LOGISTICS');

      expect(profile, same(MarketplaceExperienceCatalog.transit));
      expect(profile.label, 'Transit');
      expect(profile.primaryActionLabel, 'Book a seat');
      expect(
        profile.supports(MarketplaceExperienceCapability.transitSeatMap),
        isTrue,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.boardingPass),
        isTrue,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.roomExplorer),
        isFalse,
      );
      expect(
        profile.supports(MarketplaceExperienceCapability.menuFlipbook),
        isFalse,
      );
    });

    test('unknown categories get an empty safe profile', () {
      final profile = MarketplaceExperienceCatalog.fromCategory('NOT_REAL');

      expect(profile.capabilities, isEmpty);
      expect(profile.primaryActionLabel, 'View business');
      expect(profile.categoryWire, 'OTHER');
    });

    test('null category also resolves safely without capabilities', () {
      final profile = MarketplaceExperienceCatalog.fromCategory(null);

      expect(profile.capabilities, isEmpty);
      expect(profile.label, 'All');
      expect(profile.primaryActionLabel, 'View business');
    });
  });
}
