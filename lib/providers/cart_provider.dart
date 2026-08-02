// =============================================================================
// CART PROVIDER — Phase 12 (Marketplace Cart)
//
// Persistent per-business cart (Bolt Food / Uber Eats pattern).
// - One active cart per business — switching businesses prompts to clear.
// - Items persist across navigation via Riverpod + SharedPreferences.
// - Floating cart bar reads from this provider.
// =============================================================================

import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Cart Item ────────────────────────────────────────────────────────────────

@immutable
class CartItem {
  final String productId;
  final String name;
  final double unitPrice;
  final int quantity;
  final String? image_url;
  final String? notes;
  final String? category;

  const CartItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.image_url,
    this.notes,
    this.category,
  });

  double get lineTotal => unitPrice * quantity;

  CartItem copyWith({
    int? quantity,
    String? notes,
  }) =>
      CartItem(
        productId: productId,
        name: name,
        unitPrice: unitPrice,
        quantity: quantity ?? this.quantity,
        image_url: image_url,
        notes: notes ?? this.notes,
        category: category,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'imageUrl': image_url,
        'notes': notes,
        'category': category,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        productId: json['productId'] as String,
        name: json['name'] as String,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        quantity: json['quantity'] as int,
        image_url: json['imageUrl'] as String?,
        notes: json['notes'] as String?,
        category: json['category'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CartItem && productId == other.productId;

  @override
  int get hashCode => productId.hashCode;
}

// ── Cart State ───────────────────────────────────────────────────────────────

@immutable
class CartState {
  final String? businessProfileId;
  final String? businessName;
  final List<CartItem> items;
  final bool isCheckingOut;

  const CartState({
    this.businessProfileId,
    this.businessName,
    this.items = const [],
    this.isCheckingOut = false,
  });

  bool get isEmpty => items.isEmpty;
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);
  double get subtotal => items.fold(0.0, (sum, item) => sum + item.lineTotal);

  CartState copyWith({
    String? businessProfileId,
    String? businessName,
    List<CartItem>? items,
    bool? isCheckingOut,
    bool clearBusiness = false,
  }) =>
      CartState(
        businessProfileId: clearBusiness ? null : (businessProfileId ?? this.businessProfileId),
        businessName: clearBusiness ? null : (businessName ?? this.businessName),
        items: items ?? this.items,
        isCheckingOut: isCheckingOut ?? this.isCheckingOut,
      );

  Map<String, dynamic> toPersistJson() => {
        'businessProfileId': businessProfileId,
        'businessName': businessName,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory CartState.fromPersistJson(Map<String, dynamic> json) => CartState(
        businessProfileId: json['businessProfileId'] as String?,
        businessName: json['businessName'] as String?,
        items: (json['items'] as List? ?? [])
            .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static const empty = CartState();
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class CartNotifier extends StateNotifier<CartState> {
  static const _storageKey = 'azaman_cart_v1';
  StreamSubscription<String?>? _sub;

  CartNotifier() : super(CartState.empty) {
    _loadFromStorage();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        state = CartState.fromPersistJson(json);
      }
    } catch (e) {
      debugPrint('[Cart] Failed to load from storage: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      prefs.setString(_storageKey, jsonEncode(state.toPersistJson()));
    } catch (e) {
      debugPrint('[Cart] Failed to persist: $e');
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Adds a product to the cart. If a different business's cart is active,
  /// returns `false` — the caller should prompt the user to clear.
  /// Returns `true` if added successfully.
  bool addItem({
    required String businessProfileId,
    required String businessName,
    required String productId,
    required String name,
    required double unitPrice,
    String? imageUrl,
    String? category,
    int quantity = 1,
    String? notes,
  }) {
    // Check if we need to switch businesses
    if (state.businessProfileId != null &&
        state.businessProfileId != businessProfileId &&
        state.items.isNotEmpty) {
      return false; // Caller must call forceClearAndAdd or clearCart first
    }

    final existingIdx = state.items.indexWhere((i) => i.productId == productId);
    List<CartItem> newItems;

    if (existingIdx >= 0) {
      // Increment quantity on existing item
      newItems = List<CartItem>.from(state.items);
      final existing = newItems[existingIdx];
      newItems[existingIdx] = existing.copyWith(
        quantity: existing.quantity + quantity,
        notes: notes ?? existing.notes,
      );
    } else {
      newItems = [
        ...state.items,
        CartItem(
          productId: productId,
          name: name,
          unitPrice: unitPrice,
          quantity: quantity,
          image_url: imageUrl,
          notes: notes,
          category: category,
        ),
      ];
    }

    state = state.copyWith(
      businessProfileId: businessProfileId,
      businessName: businessName,
      items: newItems,
    );
    _persist();
    return true;
  }

  /// Clears the current cart and starts fresh with the given business.
  void startNewCart({
    required String businessProfileId,
    required String businessName,
  }) {
    state = CartState(
      businessProfileId: businessProfileId,
      businessName: businessName,
    );
    _persist();
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeItem(productId);
      return;
    }
    state = state.copyWith(
      items: state.items
          .map((i) => i.productId == productId ? i.copyWith(quantity: quantity) : i)
          .toList(),
    );
    _persist();
  }

  void incrementItem(String productId) {
    final item = state.items.firstWhere((i) => i.productId == productId);
    updateQuantity(productId, item.quantity + 1);
  }

  void decrementItem(String productId) {
    final item = state.items.firstWhere((i) => i.productId == productId);
    updateQuantity(productId, item.quantity - 1);
  }

  void removeItem(String productId) {
    final newItems = state.items.where((i) => i.productId != productId).toList();
    state = state.copyWith(
      items: newItems,
      // Clear business if cart is now empty
      clearBusiness: newItems.isEmpty,
    );
    _persist();
  }

  void updateNotes(String productId, String notes) {
    state = state.copyWith(
      items: state.items
          .map((i) => i.productId == productId ? i.copyWith(notes: notes) : i)
          .toList(),
    );
    _persist();
  }

  void clearCart() {
    state = CartState.empty;
    _persist();
  }

  void setCheckingOut(bool value) {
    state = state.copyWith(isCheckingOut: value);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final cartProvider = StateNotifierProvider<CartNotifier, CartState>(
  (ref) => CartNotifier(),
);
