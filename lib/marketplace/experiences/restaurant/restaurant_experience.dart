class RestaurantProductVariant {
  final String id;
  final String name;
  final double priceDelta;

  const RestaurantProductVariant({required this.id, required this.name, this.priceDelta = 0});

  factory RestaurantProductVariant.fromJson(Map<String, dynamic> json, int index) {
    return RestaurantProductVariant(
      id: (json['id'] ?? json['value'] ?? json['label'] ?? 'variant-$index').toString(),
      name: (json['name'] ?? json['label'] ?? json['value'] ?? 'Option').toString(),
      priceDelta: json['priceDelta'] is num
          ? (json['priceDelta'] as num).toDouble()
          : double.tryParse('${json['priceDelta'] ?? 0}') ?? 0,
    );
  }
}

class RestaurantOptionGroup {
  final String id;
  final String name;
  final bool required;
  final int maxSelection;
  final List<RestaurantOption> options;

  const RestaurantOptionGroup({
    required this.id,
    required this.name,
    this.required = false,
    this.maxSelection = 1,
    this.options = const [],
  });

  factory RestaurantOptionGroup.fromJson(Map<String, dynamic> json, int index) {
    final rawOptions = json['options'];
    final rawMax = json['maxSelection'] ?? json['max'];
    final parsedMax = rawMax is num ? rawMax.toInt() : int.tryParse('${rawMax ?? 1}') ?? 1;
    return RestaurantOptionGroup(
      id: (json['id'] ?? json['groupId'] ?? 'modifier-$index').toString(),
      name: (json['name'] ?? 'Options').toString(),
      required: json['required'] == true,
      maxSelection: parsedMax < 1 ? 1 : parsedMax,
      options: rawOptions is List
          ? rawOptions.whereType<Map<String, dynamic>>().toList(growable: false).asMap().entries
              .map((entry) => RestaurantOption.fromJson(entry.value, entry.key))
              .toList(growable: false)
          : const [],
    );
  }
}

class RestaurantOption {
  final String id;
  final String name;
  final double priceDelta;

  const RestaurantOption({required this.id, required this.name, this.priceDelta = 0});

  factory RestaurantOption.fromJson(Map<String, dynamic> json, int index) => RestaurantOption(
        id: (json['id'] ?? json['value'] ?? json['name'] ?? 'option-$index').toString(),
        name: (json['name'] ?? json['label'] ?? json['value'] ?? 'Option').toString(),
        priceDelta: json['priceDelta'] is num
            ? (json['priceDelta'] as num).toDouble()
            : double.tryParse('${json['priceDelta'] ?? 0}') ?? 0,
      );
}

class RestaurantDish {
  final String id;
  final String name;
  final String? description;
  final double? price;
  final String? currency;
  final List<String> imageUrls;
  final List<RestaurantProductVariant> variants;
  final List<RestaurantOptionGroup> optionGroups;
  final String? locationId;
  final String? deliveryTerms;
  final String? estimatedDelivery;
  final int? preparationMins;
  final int? calorieCount;
  final bool available;

  const RestaurantDish({
    required this.id,
    required this.name,
    this.description,
    this.price,
    this.currency,
    this.imageUrls = const [],
    this.variants = const [],
    this.optionGroups = const [],
    this.locationId,
    this.deliveryTerms,
    this.estimatedDelivery,
    this.preparationMins,
    this.calorieCount,
    this.available = true,
  });

  factory RestaurantDish.fromJson(Map<String, dynamic> json) {
    final rawVariants = json['variants'];
    final rawGroups = json['modifierGroups'] ?? json['optionGroups'] ?? json['options'];
    return RestaurantDish(
      id: (json['id'] ?? json['dishId'] ?? '').toString(),
      name: (json['name'] ?? json['title'] ?? 'Dish').toString(),
      description: json['description']?.toString(),
      price: json['price'] is num
          ? (json['price'] as num).toDouble()
          : double.tryParse('${json['price'] ?? json['priceUsdc'] ?? ''}'),
      currency: json['currency']?.toString() ?? 'USDC',
      imageUrls: (json['imageUrls'] ?? json['images']) is List
          ? ((json['imageUrls'] ?? json['images']) as List).map((e) => e.toString()).where((e) => e.isNotEmpty).toList(growable: false)
          : const [],
      variants: rawVariants is List
          ? rawVariants.whereType<Map<String, dynamic>>().toList(growable: false).asMap().entries
              .map((entry) => RestaurantProductVariant.fromJson(entry.value, entry.key))
              .toList(growable: false)
          : const [],
      optionGroups: rawGroups is List
          ? rawGroups.whereType<Map<String, dynamic>>().toList(growable: false).asMap().entries
              .map((entry) => RestaurantOptionGroup.fromJson(entry.value, entry.key))
              .toList(growable: false)
          : const [],
      locationId: json['locationId']?.toString(),
      deliveryTerms: json['deliveryTerms']?.toString(),
      estimatedDelivery: json['estimatedDelivery']?.toString(),
      preparationMins: json['preparationMins'] == null ? null : int.tryParse('${json['preparationMins']}'),
      calorieCount: json['calorieCount'] == null ? null : int.tryParse('${json['calorieCount']}'),
      available: json['available'] != false && json['isAvailable'] != false,
    );
  }

  factory RestaurantDish.fromBusinessProductJson(Map<String, dynamic> json) => RestaurantDish.fromJson(json);
}

class RestaurantTrayLine {
  final RestaurantDish dish;
  final int quantity;
  final Map<String, String> selections;

  const RestaurantTrayLine({required this.dish, this.quantity = 1, this.selections = const {}});

  String get key => '${dish.id}:${selections.entries.map((e) => '${e.key}=${e.value}').join('|')}';

  RestaurantTrayLine copyWith({int? quantity}) => RestaurantTrayLine(
        dish: dish,
        quantity: quantity ?? this.quantity,
        selections: selections,
      );
}

class RestaurantTray {
  final List<RestaurantTrayLine> lines;
  const RestaurantTray({this.lines = const []});

  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);

  RestaurantTray add(RestaurantDish dish, {Map<String, String> selections = const {}}) {
    final line = RestaurantTrayLine(dish: dish, selections: Map.unmodifiable(selections));
    final index = lines.indexWhere((item) => item.key == line.key);
    if (index < 0) return RestaurantTray(lines: [...lines, line]);
    final updated = [...lines];
    updated[index] = updated[index].copyWith(quantity: updated[index].quantity + 1);
    return RestaurantTray(lines: updated);
  }

  RestaurantTray setQuantity(String key, int quantity) {
    if (quantity <= 0) return RestaurantTray(lines: lines.where((line) => line.key != key).toList(growable: false));
    return RestaurantTray(lines: lines.map((line) => line.key == key ? line.copyWith(quantity: quantity) : line).toList(growable: false));
  }
}