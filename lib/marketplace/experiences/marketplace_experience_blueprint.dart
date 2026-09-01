import 'package:flutter/widgets.dart';

import 'package:azaman/theme/motion_tokens.dart';

enum MarketplaceNavigationMode {
  contextual,
  floorTraverse,
  aisleTraverse,
  journeyTimeline,
}

enum MarketplaceDetailPresentation {
  morph,
  dishDossier,
  productDossier,
  roomDossier,
  seatDossier,
  serviceDossier,
}

enum MarketplaceMotionTempo { relaxed, balanced, quick }

enum MarketplaceCommitStyle { material, paperRip, liftIntoTray }

class MarketplaceCustomerContextPolicy {
  final bool enabled;
  final bool tableNumber;
  final bool serviceMode;
  final bool passenger;

  const MarketplaceCustomerContextPolicy({
    this.enabled = true,
    this.tableNumber = false,
    this.serviceMode = false,
    this.passenger = false,
  });
}

class MarketplaceExperienceBlueprint {
  final String preset;
  final MarketplaceNavigationMode navigationMode;
  final bool showNavigationContext;
  final MarketplaceDetailPresentation detailPresentation;
  final bool showGallery;
  final bool showSpecifications;
  final bool showOptions;
  final bool showQuantity;
  final MarketplaceCustomerContextPolicy customerContext;
  final MarketplaceCommitStyle commitStyle;
  final bool persistentTray;
  final MarketplaceMotionTempo motionTempo;
  final bool reducedMotionSafe;

  const MarketplaceExperienceBlueprint({
    required this.preset,
    required this.navigationMode,
    required this.showNavigationContext,
    required this.detailPresentation,
    required this.showGallery,
    required this.showSpecifications,
    required this.showOptions,
    required this.showQuantity,
    required this.customerContext,
    required this.commitStyle,
    required this.persistentTray,
    required this.motionTempo,
    required this.reducedMotionSafe,
  });

  factory MarketplaceExperienceBlueprint.fromJson(
    Map<String, dynamic>? json,
    String category,
  ) {
    final key = category.trim().toUpperCase();
    final defaults = _defaultsForCategory(key);
    final raw = json ?? const <String, dynamic>{};
    final navigation = _asMap(raw['navigation']);
    final detail = _asMap(raw['detail']);
    final context = _asMap(raw['customerContext']);
    final commit = _asMap(raw['commit']);
    final motion = _asMap(raw['motion']);

    return MarketplaceExperienceBlueprint(
      // The backend deliberately constrains the preset to the category. Keep
      // that invariant at the Flutter boundary as well so malformed/stale
      // remote data cannot redirect a category into the wrong primitive.
      preset: _enumValue<String>(
            raw['preset'],
            <String>[defaults.preset],
          ) ??
          defaults.preset,
      navigationMode: _navigationMode(
        navigation['mode'],
        defaults.navigationMode,
      ),
      showNavigationContext: _bool(
        navigation['showProgress'],
        defaults.showNavigationContext,
      ),
      detailPresentation: _detailPresentation(
        detail['presentation'],
        defaults.detailPresentation,
      ),
      showGallery: _bool(detail['showGallery'], defaults.showGallery),
      showSpecifications: _bool(
        detail['showSpecifications'],
        defaults.showSpecifications,
      ),
      showOptions: _bool(detail['showOptions'], defaults.showOptions),
      showQuantity: _bool(detail['showQuantity'], defaults.showQuantity),
      customerContext: MarketplaceCustomerContextPolicy(
        enabled: _bool(context['enabled'], defaults.customerContext.enabled),
        tableNumber: _bool(
          context['tableNumber'],
          defaults.customerContext.tableNumber,
        ),
        serviceMode: _bool(
          context['serviceMode'],
          defaults.customerContext.serviceMode,
        ),
        passenger: _bool(
          context['passenger'],
          defaults.customerContext.passenger,
        ),
      ),
      commitStyle: _commitStyle(commit['style'], defaults.commitStyle),
      persistentTray: _bool(
        commit['persistentTray'],
        defaults.persistentTray,
      ),
      motionTempo: _motionTempo(motion['tempo'], defaults.motionTempo),
      // This is non-negotiable at the platform boundary.
      reducedMotionSafe: true,
    );
  }

  Duration motionDuration(BuildContext context) {
    final normal = switch (motionTempo) {
      MarketplaceMotionTempo.relaxed => MotionTokens.spatial,
      MarketplaceMotionTempo.balanced => MotionTokens.standard,
      MarketplaceMotionTempo.quick => MotionTokens.control,
    };
    return MotionTokens.accessibleDuration(context, normal);
  }

  IconData get commitIcon => switch (commitStyle) {
        MarketplaceCommitStyle.material => IconData(
            0xe8b6,
            fontFamily: 'MaterialIcons',
          ),
        MarketplaceCommitStyle.paperRip => IconData(
            0xe8b8,
            fontFamily: 'MaterialIcons',
          ),
        MarketplaceCommitStyle.liftIntoTray => IconData(
            0xe59c,
            fontFamily: 'MaterialIcons',
          ),
      };

  String get navigationLabel => switch (navigationMode) {
        MarketplaceNavigationMode.contextual => 'Explore what matters here',
        MarketplaceNavigationMode.floorTraverse => 'Explore by floor',
        MarketplaceNavigationMode.aisleTraverse => 'Browse by collection',
        MarketplaceNavigationMode.journeyTimeline => 'Follow the journey',
      };

  String get detailLabel => switch (detailPresentation) {
        MarketplaceDetailPresentation.morph => 'Details',
        MarketplaceDetailPresentation.dishDossier => 'Dish details',
        MarketplaceDetailPresentation.productDossier => 'Product details',
        MarketplaceDetailPresentation.roomDossier => 'Room details',
        MarketplaceDetailPresentation.seatDossier => 'Seat details',
        MarketplaceDetailPresentation.serviceDossier => 'Service details',
      };

  static MarketplaceExperienceBlueprint _defaultsForCategory(String category) {
    var preset = 'SERVICE_JOURNEY';
    var navigationMode = MarketplaceNavigationMode.contextual;
    var detailPresentation = MarketplaceDetailPresentation.serviceDossier;
    var context = const MarketplaceCustomerContextPolicy();
    var commitStyle = MarketplaceCommitStyle.material;
    var motionTempo = MarketplaceMotionTempo.balanced;

    switch (category) {
      case 'FOOD_BEVERAGE':
        preset = 'DINING_JOURNEY';
        detailPresentation = MarketplaceDetailPresentation.dishDossier;
        context = const MarketplaceCustomerContextPolicy(
          tableNumber: true,
          serviceMode: true,
        );
        commitStyle = MarketplaceCommitStyle.paperRip;
      case 'RETAIL':
        preset = 'SHOP_FLOOR';
        navigationMode = MarketplaceNavigationMode.aisleTraverse;
        detailPresentation = MarketplaceDetailPresentation.productDossier;
        commitStyle = MarketplaceCommitStyle.liftIntoTray;
      case 'HOSPITALITY':
        preset = 'BUILDING_WALK';
        navigationMode = MarketplaceNavigationMode.floorTraverse;
        detailPresentation = MarketplaceDetailPresentation.roomDossier;
        commitStyle = MarketplaceCommitStyle.liftIntoTray;
      case 'LOGISTICS':
        preset = 'TRAVEL_JOURNEY';
        navigationMode = MarketplaceNavigationMode.journeyTimeline;
        detailPresentation = MarketplaceDetailPresentation.seatDossier;
        context = const MarketplaceCustomerContextPolicy(passenger: true);
      default:
        break;
    }

    return MarketplaceExperienceBlueprint(
      preset: preset,
      navigationMode: navigationMode,
      showNavigationContext: true,
      detailPresentation: detailPresentation,
      showGallery: true,
      showSpecifications: true,
      showOptions: true,
      showQuantity: true,
      customerContext: context,
      commitStyle: commitStyle,
      persistentTray: true,
      motionTempo: motionTempo,
      reducedMotionSafe: true,
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static bool _bool(dynamic value, bool fallback) =>
      value is bool ? value : fallback;

  static T? _enumValue<T>(dynamic value, List<T> allowed) {
    if (allowed.contains(value)) return value as T;
    return null;
  }

  static MarketplaceNavigationMode _navigationMode(
    dynamic value,
    MarketplaceNavigationMode fallback,
  ) {
    return switch (value) {
      'CONTEXTUAL' => MarketplaceNavigationMode.contextual,
      'FLOOR_TRAVERSE' => MarketplaceNavigationMode.floorTraverse,
      'AISLE_TRAVERSE' => MarketplaceNavigationMode.aisleTraverse,
      'JOURNEY_TIMELINE' => MarketplaceNavigationMode.journeyTimeline,
      _ => fallback,
    };
  }

  static MarketplaceDetailPresentation _detailPresentation(
    dynamic value,
    MarketplaceDetailPresentation fallback,
  ) {
    return switch (value) {
      'MORPH' => MarketplaceDetailPresentation.morph,
      'DISH_DOSSIER' => MarketplaceDetailPresentation.dishDossier,
      'PRODUCT_DOSSIER' => MarketplaceDetailPresentation.productDossier,
      'ROOM_DOSSIER' => MarketplaceDetailPresentation.roomDossier,
      'SEAT_DOSSIER' => MarketplaceDetailPresentation.seatDossier,
      'SERVICE_DOSSIER' => MarketplaceDetailPresentation.serviceDossier,
      _ => fallback,
    };
  }

  static MarketplaceCommitStyle _commitStyle(
    dynamic value,
    MarketplaceCommitStyle fallback,
  ) {
    return switch (value) {
      'MATERIAL' => MarketplaceCommitStyle.material,
      'PAPER_RIP' => MarketplaceCommitStyle.paperRip,
      'LIFT_INTO_TRAY' => MarketplaceCommitStyle.liftIntoTray,
      _ => fallback,
    };
  }

  static MarketplaceMotionTempo _motionTempo(
    dynamic value,
    MarketplaceMotionTempo fallback,
  ) {
    return switch (value) {
      'RELAXED' => MarketplaceMotionTempo.relaxed,
      'BALANCED' => MarketplaceMotionTempo.balanced,
      'QUICK' => MarketplaceMotionTempo.quick,
      _ => fallback,
    };
  }
}
