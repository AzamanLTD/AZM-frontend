class RestaurantDish {
  final String id;
  final String name;
  final String? description;
  final double? price;
  final String? currency;
  final List<String> imageUrls;
  final List<RestaurantOptionGroup> optionGroups;
  final bool available;

  const RestaurantDish({
    required this.id,
    required this.name,
    this.description,
    this.price,
    this.currency,
    this.imageUrls = const [],
    this.optionGroups = const [],
    this.available = true,
  });

  factory RestaurantDish.fromJson(Map<String, dynamic> json) {
    final rawGroups = json['optionGroups'] ?? json['options'];
    return RestaurantDish(
      id: (json['id'] ?? json['dishId'] ?? '').toString(),
      name: (json['name'] ?? json['title'] ?? 'Dish').toString(),
      description: json['description']?.toString(),
      price: json['price'] is num ? (json['price'] as num).toDouble() : double.tryParse('${json['price'] ?? ''}'),
      currency: json['currency']?.toString(),
      imageUrls: (json['imageUrls'] ?? json['images']) is List
          ? ((json['imageUrls'] ?? json['images']) as List).map((e) => e.toString()).where((e) => e.isNotEmpty).toList(growable: false)
          : const [],
      optionGroups: rawGroups is List
          ? rawGroups.whereType<Map<String, dynamic>>().map(RestaurantOptionGroup.fromJson).toList(growable: false)
          : const [],
      available: json['available'] != false && json['isAvailable'] != false,
    );
  }
}

class RestaurantOptionGroup {
  final String id;
  final String name;
  final bool required;
  final List<RestaurantOption> options;

  const RestaurantOptionGroup({required this.id, required this.name, this.required = false, this.options = const []});

  factory RestaurantOptionGroup.fromJson(Map<String, dynamic> json) => RestaurantOptionGroup(
        id: (json['id'] ?? json['groupId'] ?? '').toString(),
        name: (json['name'] ?? 'Options').toString(),
        required: json['required'] == true,
        options: json['options'] is List
            ? (json['options'] as List).whereType<Map<String, dynamic>>().map(RestaurantOption.fromJson).toList(growable: false)
            : const [],
      );
}

class RestaurantOption {
  final String id;
  final String name;
  final double priceDelta;

  const RestaurantOption({required this.id, required this.name, this.priceDelta = 0});

  factory RestaurantOption.fromJson(Map<String, dynamic> json) => RestaurantOption(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? json['label'] ?? 'Option').toString(),
        priceDelta: json['priceDelta'] is num ? (json['priceDelta'] as num).toDouble() : double.tryParse('${json['priceDelta'] ?? 0}') ?? 0,
      );
}

class RestaurantTrayLine {
  final RestaurantDish dish;
  final int quantity;
  final Map<String, String> selections;

  const RestaurantTrayLine({required this.dish, this.quantity = 1, this.selections = const {}});

  String get key => '${dish.id}:${selections.entries.map((e) => '${e.key}=${e.value}').join('|')}';

  RestaurantTrayLine copyWith({int? quantity}) => RestaurantTrayLine(dish: dish, quantity: quantity ?? this.quantity, selections: selections);
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
