// lib/providers/saved_businesses_provider.dart
// =============================================================================
// Saved Businesses — local wishlist backed by SharedPreferences.
//
// State: Set<String> of bizIds (e.g. {"BIZ-000001", "BIZ-000002"}).
// Persisted key: 'saved_businesses' → JSON list of bizId strings.
// All operations are synchronous from the caller's perspective (write to
// SharedPreferences in background); the UI updates immediately.
// =============================================================================
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kKey = 'saved_businesses';

class SavedBusinessesNotifier extends StateNotifier<Set<String>> {
  SavedBusinessesNotifier() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
      state = list;
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(state.toList()));
  }

  /// Toggle the saved state for a business. Returns the new state (true = saved).
  Future<bool> toggle(String bizId) async {
    final next = Set<String>.from(state);
    if (next.contains(bizId)) {
      next.remove(bizId);
    } else {
      next.add(bizId);
    }
    state = next;
    await _persist();
    return next.contains(bizId);
  }

  Future<void> remove(String bizId) async {
    final next = Set<String>.from(state)..remove(bizId);
    state = next;
    await _persist();
  }

  Future<void> clear() async {
    state = const {};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}

final savedBusinessesProvider =
    StateNotifierProvider<SavedBusinessesNotifier, Set<String>>(
  (_) => SavedBusinessesNotifier(),
);
