// lib/providers/presence_preferences_provider.dart
// =============================================================================
// AZAMAN — NEARBY PRESENCE PREFERENCES
//
// Three INDEPENDENT switches, all defaulting OFF, persisted locally.
//
// There is deliberately no `enableAll()` and no constructor default of `true`
// anywhere in this file: enabling Discovery must never silently enable
// Notifications or Personalisation, and a fresh install must be fully off.
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/presence/presence_models.dart';

const String kPresencePreferencesKey = 'presence_preferences_v1';

class PresencePreferencesNotifier extends StateNotifier<PresencePreferences> {
  PresencePreferencesNotifier() : super(PresencePreferences.allOff) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kPresencePreferencesKey);
    if (raw == null) return; // stays allOff
    try {
      state = PresencePreferences.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      state = PresencePreferences.allOff;
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPresencePreferencesKey, jsonEncode(state.toJson()));
  }

  /// Flips ONE switch. The other two are carried through untouched.
  Future<void> setNearbyDiscovery(bool value) async {
    state = state.copyWith(nearbyDiscovery: value);
    await _persist();
  }

  Future<void> setPresenceNotifications(bool value) async {
    state = state.copyWith(presenceNotifications: value);
    await _persist();
  }

  Future<void> setPersonalisation(bool value) async {
    state = state.copyWith(personalisation: value);
    await _persist();
  }
}

final presencePreferencesProvider =
    StateNotifierProvider<PresencePreferencesNotifier, PresencePreferences>(
      (ref) => PresencePreferencesNotifier(),
    );
