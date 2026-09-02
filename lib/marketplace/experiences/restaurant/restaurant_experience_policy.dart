import 'restaurant_experience.dart';

/// Applies the non-negotiable parts of the restaurant ordering contract to a
/// persisted Experience Blueprint. Merchants may hide optional configuration
/// controls, but the customer must always be able to supply choices required
/// to produce a valid order.
Map<String, dynamic>? effectiveRestaurantExperience({
  required Map<String, dynamic>? experience,
  required Iterable<RestaurantDish> dishes,
}) {
  if (experience == null || experience.isEmpty) return experience;

  final detail = experience['detail'];
  final detailMap = detail is Map
      ? Map<String, dynamic>.from(detail)
      : <String, dynamic>{};
  if (detailMap['showOptions'] != false) return experience;

  final requiredChoicesExist = dishes.any(
    (dish) =>
        dish.variants.isNotEmpty ||
        dish.optionGroups.any((group) => group.required),
  );
  if (!requiredChoicesExist) return experience;

  return <String, dynamic>{
    ...experience,
    'detail': <String, dynamic>{
      ...detailMap,
      'showOptions': true,
    },
  };
}
