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
    final categoryKey = category.trim().toUpperCase();
    final defaults = _defaultsForCategory(categoryKey);
    final raw = json ?? const <String, dynamic>{};
    final navigation = _asMap(raw['navigation']);
    final detail = _asMap(raw['detail']);
    final context = _asMap(raw['customerContext']);
    final commit = _asMap(raw['commit']);
    final motion = _asMap(raw['motion']);
    final policy = _policyForCategory(categoryKey);

    final requestedPreset = raw['preset'];
    final preset = requestedPreset == defaults.preset ? requestedPreset as String : defaults.preset;

    return MarketplaceExperienceBlueprint(
      preset: preset,
      navigationMode: _navigationMode(navigation['mode'], defaults.navigationMode, policy.navigationModes),
      showNavigationContext: _bool(navigation['showProgress'], defaults.showNavigationContext),
      detailPresentation: _detailPresentation(detail['presentation'], defaults.detailPresentation, policy.detailPresentations),
      showGallery: _bool(detail['showGallery'], defaults.showGallery),
      showSpecifications: _bool(detail['showSpecifications'], defaults.showSpecifications),
      showOptions: _bool(detail['showOptions'], defaults.showOptions),
      showQuantity: _bool(detail['showQuantity'], defaults.showQuantity),
      customerContext: MarketplaceCustomerContextPolicy(
        enabled: _bool(context['enabled'], defaults.customerContext.enabled),
        tableNumber: policy.customerContext.tableNumber
            ? _bool(context['tableNumber'], defaults.customerContext.tableNumber)
            : false,
        serviceMode: policy.customerContext.serviceMode
            ? _bool(context['serviceMode'], defaults.customerContext.serviceMode)
            : false,
        passenger: policy.customerContext.passenger
            ? _bool(context['passenger'], defaults.customerContext.passenger)
            : false,
      ),
      commitStyle: _commitStyle(commit['style'], defaults.commitStyle, policy.commitStyles),
      persistentTray: policy.persistentTray
          ? _bool(commit['persistentTray'], defaults.persistentTray)
          : false,
      motionTempo: _motionTempo(motion['tempo'], defaults.motionTempo),
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

  static _MarketplaceCategoryPolicy _policyForCategory(String category) {
    switch (category) {
      case 'FOOD_BEVERAGE':
      case 'RESTAURANT':
        return const _MarketplaceCategoryPolicy(
          navigationModes: [MarketplaceNavigationMode.contextual],
          detailPresentations: [MarketplaceDetailPresentation.morph, MarketplaceDetailPresentation.dishDossier],
          commitStyles: [MarketplaceCommitStyle.material, MarketplaceCommitStyle.paperRip],
          customerContext: MarketplaceCustomerContextPolicy(tableNumber: true, serviceMode: true),
          persistentTray: true,
        );
      case 'RETAIL':
        return const _MarketplaceCategoryPolicy(
          navigationModes: [MarketplaceNavigationMode.contextual, MarketplaceNavigationMode.aisleTraverse],
          detailPresentations: [MarketplaceDetailPresentation.morph, MarketplaceDetailPresentation.productDossier],
          commitStyles: [MarketplaceCommitStyle.material, MarketplaceCommitStyle.liftIntoTray],
          customerContext: MarketplaceCustomerContextPolicy(),
          persistentTray: true,
        );
      case 'HOSPITALITY':
      case 'HOTEL':
        return const _MarketplaceCategoryPolicy(
          navigationModes: [MarketplaceNavigationMode.contextual, MarketplaceNavigationMode.floorTraverse],
          detailPresentations: [MarketplaceDetailPresentation.morph, MarketplaceDetailPresentation.roomDossier],
          commitStyles: [MarketplaceCommitStyle.material],
          customerContext: MarketplaceCustomerContextPolicy(),
          persistentTray: false,
        );
      case 'LOGISTICS':
      case 'TRANSIT':
        return const _MarketplaceCategoryPolicy(
          navigationModes: [MarketplaceNavigationMode.contextual, MarketplaceNavigationMode.journeyTimeline],
          detailPresentations: [MarketplaceDetailPresentation.morph, MarketplaceDetailPresentation.seatDossier],
          commitStyles: [MarketplaceCommitStyle.material],
          customerContext: MarketplaceCustomerContextPolicy(passenger: true),
          persistentTray: false,
        );
      default:
        return const _MarketplaceCategoryPolicy(
          navigationModes: [MarketplaceNavigationMode.contextual],
          detailPresentations: [MarketplaceDetailPresentation.morph, MarketplaceDetailPresentation.serviceDossier],
          commitStyles: [MarketplaceCommitStyle.material],
          customerContext: MarketplaceCustomerContextPolicy(),
          persistentTray: false,
        );
    }
  }

  static MarketplaceExperienceBlueprint _defaultsForCategory(String category) {
    final policy = _policyForCategory(category);
    var preset = 'SERVICE_JOURNEY';
    var navigationMode = policy.navigationModes.first;
    var detailPresentation = policy.detailPresentations.last;
    var commitStyle = policy.commitStyles.first;

    switch (category) {
      case 'FOOD_BEVERAGE':
      case 'RESTAURANT':
        preset = 'DINING_JOURNEY';
        detailPresentation = MarketplaceDetailPresentation.dishDossier;
        commitStyle = MarketplaceCommitStyle.paperRip;
        break;
      case 'RETAIL':
        preset = 'SHOP_FLOOR';
        navigationMode = MarketplaceNavigationMode.aisleTraverse;
        detailPresentation = MarketplaceDetailPresentation.productDossier;
        commitStyle = MarketplaceCommitStyle.liftIntoTray;
        break;
      case 'HOSPITALITY':
      case 'HOTEL':
        preset = 'BUILDING_WALK';
        navigationMode = MarketplaceNavigationMode.floorTraverse;
        detailPresentation = MarketplaceDetailPresentation.roomDossier;
        commitStyle = MarketplaceCommitStyle.material;
        break;
      case 'LOGISTICS':
      case 'TRANSIT':
        preset = 'TRAVEL_JOURNEY';
        navigationMode = MarketplaceNavigationMode.journeyTimeline;
        detailPresentation = MarketplaceDetailPresentation.seatDossier;
        commitStyle = MarketplaceCommitStyle.material;
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
      customerContext: policy.customerContext,
      commitStyle: commitStyle,
      persistentTray: policy.persistentTray,
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
    List<MarketplaceNavigationMode> allowed,
  ) {
    final requested = switch (value) {
      'CONTEXTUAL' => MarketplaceNavigationMode.contextual,
      'FLOOR_TRAVERSE' => MarketplaceNavigationMode.floorTraverse,
      'AISLE_TRAVERSE' => MarketplaceNavigationMode.aisleTraverse,
      'JOURNEY_TIMELINE' => MarketplaceNavigationMode.journeyTimeline,
      _ => null,
    };
    return requested != null && allowed.contains(requested) ? requested : fallback;
  }

  static MarketplaceDetailPresentation _detailPresentation(
    dynamic value,
    MarketplaceDetailPresentation fallback,
    List<MarketplaceDetailPresentation> allowed,
  ) {
    final requested = switch (value) {
      'MORPH' => MarketplaceDetailPresentation.morph,
      'DISH_DOSSIER' => MarketplaceDetailPresentation.dishDossier,
      'PRODUCT_DOSSIER' => MarketplaceDetailPresentation.productDossier,
      'ROOM_DOSSIER' => MarketplaceDetailPresentation.roomDossier,
      'SEAT_DOSSIER' => MarketplaceDetailPresentation.seatDossier,
      'SERVICE_DOSSIER' => MarketplaceDetailPresentation.serviceDossier,
      _ => null,
    };
    return requested != null && allowed.contains(requested) ? requested : fallback;
  }

  static MarketplaceCommitStyle _commitStyle(
    dynamic value,
    MarketplaceCommitStyle fallback,
    List<MarketplaceCommitStyle> allowed,
  ) {
    final requested = switch (value) {
      'MATERIAL' => MarketplaceCommitStyle.material,
      'PAPER_RIP' => MarketplaceCommitStyle.paperRip,
      'LIFT_INTO_TRAY' => MarketplaceCommitStyle.liftIntoTray,
      _ => null,
    };
    return requested != null && allowed.contains(requested) ? requested : fallback;
  }

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

class _MarketplaceCategoryPolicy {
  final List<MarketplaceNavigationMode> navigationModes;
  final List<MarketplaceDetailPresentation> detailPresentations;
  final List<MarketplaceCommitStyle> commitStyles;
  final MarketplaceCustomerContextPolicy customerContext;
  final bool persistentTray;

  const _MarketplaceCategoryPolicy({
    required this.navigationModes,
    required this.detailPresentations,
    required this.commitStyles,
    required this.customerContext,
    required this.persistentTray,
  });
}
