import 'package:flutter/widgets.dart';

import 'package:azaman/theme/motion_tokens.dart';

enum MarketplaceNavigationMode { contextual, floorTraverse, aisleTraverse, journeyTimeline }
enum MarketplaceDetailPresentation { morph, dishDossier, productDossier, roomDossier, seatDossier, serviceDossier }
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
    final defaults = _defaultsForCategory(category.trim().toUpperCase());
    final raw = json ?? const <String, dynamic>{};
    final navigation = _asMap(raw['navigation']);
    final detail = _asMap(raw['detail']);
    final context = _asMap(raw['customerContext']);
    final commit = _asMap(raw['commit']);
    final motion = _asMap(raw['motion']);

    return MarketplaceExperienceBlueprint(
      preset: raw['preset'] == defaults.preset ? raw['preset'] as String : defaults.preset,
      navigationMode: _navigationMode(navigation['mode'], defaults.navigationMode),
      showNavigationContext: _bool(navigation['showProgress'], defaults.showNavigationContext),
      detailPresentation: _detailPresentation(detail['presentation'], defaults.detailPresentation),
      showGallery: _bool(detail['showGallery'], defaults.showGallery),
      showSpecifications: _bool(detail['showSpecifications'], defaults.showSpecifications),
      showOptions: _bool(detail['showOptions'], defaults.showOptions),
      showQuantity: _bool(detail['showQuantity'], defaults.showQuantity),
      customerContext: MarketplaceCustomerContextPolicy(
        enabled: _bool(context['enabled'], defaults.customerContext.enabled),
        tableNumber: _bool(context['tableNumber'], defaults.customerContext.tableNumber),
        serviceMode: _bool(context['serviceMode'], defaults.customerContext.serviceMode),
        passenger: _bool(context['passenger'], defaults.customerContext.passenger),
      ),
      commitStyle: _commitStyle(commit['style'], defaults.commitStyle),
      persistentTray: _bool(commit['persistentTray'], defaults.persistentTray),
      motionTempo: _motionTempo(motion['tempo'], defaults.motionTempo),
      // Accessibility behavior is enforced by the platform motion helper.
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

    switch (category) {
      case 'FOOD_BEVERAGE':
        preset = 'DINING_JOURNEY';
        detailPresentation = MarketplaceDetailPresentation.dishDossier;
        context = const MarketplaceCustomerContextPolicy(tableNumber: true, serviceMode: true);
        commitStyle = MarketplaceCommitStyle.paperRip;
        break;
      case 'RETAIL':
        preset = 'SHOP_FLOOR';
        navigationMode = MarketplaceNavigationMode.aisleTraverse;
        detailPresentation = MarketplaceDetailPresentation.productDossier;
        commitStyle = MarketplaceCommitStyle.liftIntoTray;
        break;
      case 'HOSPITALITY':
        preset = 'BUILDING_WALK';
        navigationMode = MarketplaceNavigationMode.floorTraverse;
        detailPresentation = MarketplaceDetailPresentation.roomDossier;
        commitStyle = MarketplaceCommitStyle.liftIntoTray;
        break;
      case 'LOGISTICS':
        preset = 'TRAVEL_JOURNEY';
        navigationMode = MarketplaceNavigationMode.journeyTimeline;
        detailPresentation = MarketplaceDetailPresentation.seatDossier;
        context = const MarketplaceCustomerContextPolicy(passenger: true);
        break;
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
      motionTempo: MarketplaceMotionTempo.balanced,
      reducedMotionSafe: true,
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

  static bool _bool(dynamic value, bool fallback) => value is bool ? value : fallback;

  static MarketplaceNavigationMode _navigationMode(
    dynamic value,
    MarketplaceNavigationMode fallback,
  ) => switch (value) {
        'CONTEXTUAL' => MarketplaceNavigationMode.contextual,
        'FLOOR_TRAVERSE' => MarketplaceNavigationMode.floorTraverse,
        'AISLE_TRAVERSE' => MarketplaceNavigationMode.aisleTraverse,
        'JOURNEY_TIMELINE' => MarketplaceNavigationMode.journeyTimeline,
        _ => fallback,
      };

  static MarketplaceDetailPresentation _detailPresentation(
    dynamic value,
    MarketplaceDetailPresentation fallback,
  ) => switch (value) {
        'MORPH' => MarketplaceDetailPresentation.morph,
        'DISH_DOSSIER' => MarketplaceDetailPresentation.dishDossier,
        'PRODUCT_DOSSIER' => MarketplaceDetailPresentation.productDossier,
        'ROOM_DOSSIER' => MarketplaceDetailPresentation.roomDossier,
        'SEAT_DOSSIER' => MarketplaceDetailPresentation.seatDossier,
        'SERVICE_DOSSIER' => MarketplaceDetailPresentation.serviceDossier,
        _ => fallback,
      };

  static MarketplaceCommitStyle _commitStyle(
    dynamic value,
    MarketplaceCommitStyle fallback,
  ) => switch (value) {
        'MATERIAL' => MarketplaceCommitStyle.material,
        'PAPER_RIP' => MarketplaceCommitStyle.paperRip,
        'LIFT_INTO_TRAY' => MarketplaceCommitStyle.liftIntoTray,
        _ => fallback,
      };

  static MarketplaceMotionTempo _motionTempo(
    dynamic value,
    MarketplaceMotionTempo fallback,
  ) => switch (value) {
        'RELAXED' => MarketplaceMotionTempo.relaxed,
        'BALANCED' => MarketplaceMotionTempo.balanced,
        'QUICK' => MarketplaceMotionTempo.quick,
        _ => fallback,
      };
}
