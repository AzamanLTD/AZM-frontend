// =============================================================================
// CART PROVIDER — Phase 12 (Marketplace Cart)
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class CartItem {
  final String productId;
  final String name;
  final double unitPrice;
  final int quantity;
  final String? image_url;
  final String? notes;
  final String? category;
  final Map<String, String> variants;

  const CartItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.image_url,
    this.notes,
    this.category,
    this.variants = const {},
  });

  double get lineTotal => unitPrice * quantity;

  String get lineKey {
    final entries = variants.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return productId;
    return '$productId:${entries.map((entry) => '${entry.key}=${entry.value}').join('|')}';
  }

  CartItem copyWith({int? quantity, String? notes}) => CartItem(
        productId: productId,
        name: name,
        unitPrice: unitPrice,
        quantity: quantity ?? this.quantity,
        image_url: image_url,
        notes: notes ?? this.notes,
        category: category,
        variants: variants,
      );

  Map<String, dynamic> toCheckoutJson() => {
        'productId': productId,
        'quantity': quantity,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (variants.isNotEmpty) 'variants': Map<String, String>.from(variants),
      };

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'imageUrl': image_url,
        'notes': notes,
        'category': category,
        'variants': variants,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final rawVariants = json['variants'];
    final variants = rawVariants is Map
        ? Map<String, String>.fromEntries(rawVariants.entries.map((entry) => MapEntry(entry.key.toString(), entry.value.toString())))
        : const <String, String>{};
    return CartItem(
      productId: json['productId'] as String,
      name: json['name'] as String,
      unitPrice: (json['unitPrice'] as num).toDouble(),
      quantity: json['quantity'] as int,
      image_url: json['imageUrl'] as String?,
      notes: json['notes'] as String?,
      category: json['category'] as String?,
      variants: Map<String, String>.unmodifiable(variants),
    );
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is CartItem && lineKey == other.lineKey;

  @override
  int get hashCode => lineKey.hashCode;
}

@immutable
class CartState {
  final String? businessProfileId;
  final String? businessName;
  final String? experiencePreset;
  final List<CartItem> items;
  final bool isCheckingOut;

  const CartState({
    this.businessProfileId,
    this.businessName,
    this.experiencePreset,
    this.items = const [],
    this.isCheckingOut = false,
  });

  bool get isEmpty => items.isEmpty;
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);
  double get subtotal => items.fold(0.0, (sum, item) => sum + item.lineTotal);

  List<Map<String, dynamic>> toCheckoutItems() => items.map((item) => item.toCheckoutJson()).toList(growable: false);

  CartState copyWith({
    String? businessProfileId,
    String? businessName,
    String? experiencePreset,
    List<CartItem>? items,
    bool? isCheckingOut,
    bool clearBusiness = false,
  }) => CartState(
        businessProfileId: clearBusiness ? null : (businessProfileId ?? this.businessProfileId),
        businessName: clearBusiness ? null : (businessName ?? this.businessName),
        experiencePreset: clearBusiness ? null : (experiencePreset ?? this.experiencePreset),
        items: items ?? this.items,
        isCheckingOut: isCheckingOut ?? this.isCheckingOut,
      );

  Map<String, dynamic> toPersistJson() => {
        'businessProfileId': businessProfileId,
        'businessName': businessName,
        if (experiencePreset != null) 'experiencePreset': experiencePreset,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory CartState.fromPersistJson(Map<String, dynamic> json) => CartState(
        businessProfileId: json['businessProfileId'] as String?,
        businessName: json['businessName'] as String?,
        experiencePreset: json['experiencePreset'] as String?,
        items: (json['items'] as List? ?? []).whereType<Map>().map((e) => CartItem.fromJson(Map<String, dynamic>.from(e))).toList(),
      );

  static const empty = CartState();
}

class CartNotifier extends StateNotifier<CartState> {
  static const _storageKey = 'azaman_cart_v1';
  StreamSubscription<String?>? _sub;

  CartNotifier() : super(CartState.empty) {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null) state = CartState.fromPersistJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[Cart] Failed to load from storage: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(state.toPersistJson()));
    } catch (e) {
      debugPrint('[Cart] Failed to persist: $e');
    }
  }

  bool addItem({
    required String businessProfileId,
    required String businessName,
    required String productId,
    required String name,
    required double unitPrice,
    String? imageUrl,
    String? category,
    String? experiencePreset,
    int quantity = 1,
    String? notes,
    Map<String, String> variants = const {},
  }) {
    if (state.businessProfileId != null && state.businessProfileId != businessProfileId && state.items.isNotEmpty) return false;

    final normalizedVariants = Map<String, String>.unmodifiable(Map<String, String>.from(variants));
    final incoming = CartItem(
      productId: productId,
      name: name,
      unitPrice: unitPrice,
      quantity: quantity,
      image_url: imageUrl,
      notes: notes,
      category: category,
      variants: normalizedVariants,
    );
    final existingIdx = state.items.indexWhere((i) => i.lineKey == incoming.lineKey);
    final newItems = List<CartItem>.from(state.items);
    if (existingIdx >= 0) {
      final existing = newItems[existingIdx];
      newItems[existingIdx] = existing.copyWith(quantity: existing.quantity + quantity, notes: notes ?? existing.notes);
    } else {
      newItems.add(incoming);
    }
    state = state.copyWith(
      businessProfileId: businessProfileId,
      businessName: businessName,
      experiencePreset: experiencePreset ?? state.experiencePreset,
      items: newItems,
    );
    _persist();
    return true;
  }

  void startNewCart({required String businessProfileId, required String businessName, String? experiencePreset}) {
    state = CartState(
      businessProfileId: businessProfileId,
      businessName: businessName,
      experiencePreset: experiencePreset,
    );
    _persist();
  }

  void updateLineQuantity(String lineKey, int quantity) {
    if (quantity <= 0) {
      removeLine(lineKey);
      return;
    }
    state = state.copyWith(items: state.items.map((i) => i.lineKey == lineKey ? i.copyWith(quantity: quantity) : i).toList());
    _persist();
  }

  void updateQuantity(String productId, int quantity) {
    final item = state.items.cast<CartItem?>().firstWhere((i) => i?.productId == productId, orElse: () => null);
    if (item == null) return;
    updateLineQuantity(item.lineKey, quantity);
  }

  void incrementLine(String lineKey) => updateLineQuantity(lineKey, state.items.firstWhere((i) => i.lineKey == lineKey).quantity + 1);
  void decrementLine(String lineKey) => updateLineQuantity(lineKey, state.items.firstWhere((i) => i.lineKey == lineKey).quantity - 1);
  void incrementItem(String productId) => incrementLine(state.items.firstWhere((i) => i.productId == productId).lineKey);
  void decrementItem(String productId) => decrementLine(state.items.firstWhere((i) => i.productId == productId).lineKey);

  void removeLine(String lineKey) {
    final newItems = state.items.where((i) => i.lineKey != lineKey).toList();
    state = state.copyWith(items: newItems, clearBusiness: newItems.isEmpty);
    _persist();
  }

  void removeItem(String productId) {
    final newItems = state.items.where((i) => i.productId != productId).toList();
    state = state.copyWith(items: newItems, clearBusiness: newItems.isEmpty);
    _persist();
  }

  void updateNotesForLine(String lineKey, String notes) {
    state = state.copyWith(items: state.items.map((i) => i.lineKey == lineKey ? i.copyWith(notes: notes) : i).toList());
    _persist();
  }

  void updateNotes(String productId, String notes) {
    final item = state.items.cast<CartItem?>().firstWhere((i) => i?.productId == productId, orElse: () => null);
    if (item == null) return;
    updateNotesForLine(item.lineKey, notes);
  }

  void clearCart() {
    state = CartState.empty;
    _persist();
  }

  void setCheckingOut(bool value) => state = state.copyWith(isCheckingOut: value);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) => CartNotifier());
