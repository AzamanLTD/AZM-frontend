import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';


/// All available shortcuts the user can pin to their HQ drawer
class HQShortcut {
  final String id;
  final String label;
  final IconData icon;
  bool enabled;
  int order;

  HQShortcut({required this.id, required this.label, required this.icon, this.enabled = true, this.order = 0});
}

class SettingsProvider with ChangeNotifier {
  // --- NOTIFICATION PREFERENCES ---
  bool _pushNotifications = true;
  bool _tradeAlerts = true;
  bool _chatNotifications = true;

  // --- CURRENCY & LANGUAGE ---
  String _defaultCurrency = 'USD';
  String _appLanguage = 'English';

  // --- VENDOR TAG (Master Sprint v2, 2026-05-27) ---
  // Controls whether the vendor pull-tab is visible on the home + p2p
  // overlays. Defaults OFF so casual users aren't bothered by an
  // affordance they have no interest in. Vendors can flip it on in
  // Settings → "Show vendor pull tab".
  bool _vendorTagEnabled = false;

  // --- HQ SHORTCUTS ---
  final List<HQShortcut> _shortcuts = [
    HQShortcut(id: 'deposit', label: 'Deposit', icon: Icons.account_balance_wallet_outlined, order: 0),
    HQShortcut(id: 'withdraw', label: 'Withdraw', icon: Icons.send_outlined, order: 1),
    HQShortcut(id: 'history', label: 'History', icon: Icons.history, order: 2),
    HQShortcut(id: 'stats', label: 'Stats', icon: Icons.analytics_outlined, order: 3),
    HQShortcut(id: 'p2p', label: 'P2P Trading', icon: Icons.swap_horiz, order: 4),
    HQShortcut(id: 'savings', label: 'Savings', icon: Icons.savings_outlined, order: 5),
    HQShortcut(id: 'support', label: 'Support', icon: Icons.headset_mic_outlined, order: 6),
    HQShortcut(id: 'ads', label: 'Ad Manager', icon: Icons.campaign_outlined, order: 7),
    HQShortcut(id: 'settings', label: 'Settings', icon: Icons.settings_outlined, order: 8),
  ];

  bool _isLoaded = false;

  // --- GETTERS ---
  bool get pushNotifications => _pushNotifications;
  bool get tradeAlerts => _tradeAlerts;
  bool get chatNotifications => _chatNotifications;
  bool get vendorTagEnabled => _vendorTagEnabled;
  String get defaultCurrency => _defaultCurrency;
  String get appLanguage => _appLanguage;
  List<HQShortcut> get shortcuts => _shortcuts;
  List<HQShortcut> get enabledShortcuts => _shortcuts.where((s) => s.enabled).toList();
  bool get isLoaded => _isLoaded;

  SettingsProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    _pushNotifications = prefs.getBool('push_notifications') ?? true;
    _tradeAlerts = prefs.getBool('trade_alerts') ?? true;
    _chatNotifications = prefs.getBool('chat_notifications') ?? true;
    _defaultCurrency = prefs.getString('default_currency') ?? 'USD';
    _appLanguage = prefs.getString('app_language') ?? 'English';
    _vendorTagEnabled = prefs.getBool('vendor_tag_enabled') ?? false;

    // Load shortcut states
    for (var shortcut in _shortcuts) {
      shortcut.enabled = prefs.getBool('shortcut_${shortcut.id}') ?? shortcut.enabled;
    }

    _isLoaded = true;
    notifyListeners();
  }

  // --- SETTERS (all persist locally + sync to backend) ---

  Future<void> setPushNotifications(bool value) async {
    _pushNotifications = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_notifications', value);
    _syncPreferencesToBackend();
  }

  Future<void> setTradeAlerts(bool value) async {
    _tradeAlerts = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('trade_alerts', value);
    _syncPreferencesToBackend();
  }

  Future<void> setChatNotifications(bool value) async {
    _chatNotifications = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('chat_notifications', value);
    _syncPreferencesToBackend();
  }

  /// Master Sprint v2 — toggle the vendor pull-tab visibility. Persists
  /// locally only (UI affordance, not a backend-synced setting).
  Future<void> setVendorTagEnabled(bool value) async {
    _vendorTagEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vendor_tag_enabled', value);
  }

  Future<void> setDefaultCurrency(String value) async {
    _defaultCurrency = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_currency', value);
    _syncPreferencesToBackend();
  }

  Future<void> setAppLanguage(String value) async {
    _appLanguage = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', value);
    _syncPreferencesToBackend();
  }

  Future<void> toggleShortcut(String id, bool enabled) async {
    final index = _shortcuts.indexWhere((s) => s.id == id);
    if (index == -1) return;
    _shortcuts[index].enabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shortcut_$id', enabled);
    _syncShortcutsToBackend();
  }

  // =========================================================================
  // CROSS-DEVICE SYNC — Backend Persistence
  // =========================================================================

  /// Sync notification/general preferences to backend (fire-and-forget).
  /// Called automatically on every setter. Non-fatal on failure.
  Future<void> _syncPreferencesToBackend() async {
    try {
      await apiClient.put('/users/preferences', {
        'preferences': {
          'pushNotifications': _pushNotifications,
          'tradeAlerts': _tradeAlerts,
          'chatNotifications': _chatNotifications,
          'currencyDisplay': _defaultCurrency,
          'language': _appLanguage,
        },
      });
    } catch (_) {
      // Non-fatal: backend sync failure should never affect local UX
    }
  }

  /// Sync shortcut arrangement to backend (fire-and-forget).
  Future<void> _syncShortcutsToBackend() async {
    try {
      final shortcuts = _shortcuts.map((s) => {
        'id': s.id,
        'enabled': s.enabled,
        'order': s.order,
      }).toList();

      await apiClient.put('/users/preferences/shortcuts', {
        'shortcuts': shortcuts,
      });
    } catch (_) {
      // Non-fatal
    }
  }

  /// Load preferences + shortcuts from backend (cross-device sync).
  /// Call after successful authentication to restore user's settings
  /// from the server. Falls back to local SharedPreferences if backend
  /// is unreachable.
  Future<void> loadFromBackend() async {
    try {
      final response = await apiClient.get('/users/preferences');
      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body);
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return;

      bool changed = false;
      final prefs = await SharedPreferences.getInstance();

      // --- Restore general preferences ---
      final preferences = data['preferences'] as Map<String, dynamic>?;
      if (preferences != null) {
        if (preferences['pushNotifications'] is bool) {
          _pushNotifications = preferences['pushNotifications'];
          await prefs.setBool('push_notifications', _pushNotifications);
          changed = true;
        }
        if (preferences['tradeAlerts'] is bool) {
          _tradeAlerts = preferences['tradeAlerts'];
          await prefs.setBool('trade_alerts', _tradeAlerts);
          changed = true;
        }
        if (preferences['chatNotifications'] is bool) {
          _chatNotifications = preferences['chatNotifications'];
          await prefs.setBool('chat_notifications', _chatNotifications);
          changed = true;
        }
        if (preferences['currencyDisplay'] is String && (preferences['currencyDisplay'] as String).isNotEmpty) {
          _defaultCurrency = preferences['currencyDisplay'];
          await prefs.setString('default_currency', _defaultCurrency);
          changed = true;
        }
        if (preferences['language'] is String && (preferences['language'] as String).isNotEmpty) {
          _appLanguage = preferences['language'];
          await prefs.setString('app_language', _appLanguage);
          changed = true;
        }
      }

      // --- Restore shortcuts ---
      final shortcuts = data['shortcuts'] as List<dynamic>?;
      if (shortcuts != null && shortcuts.isNotEmpty) {
        for (final s in shortcuts) {
          if (s is! Map<String, dynamic>) continue;
          final id = s['id'] as String?;
          final enabled = s['enabled'] as bool?;
          final order = s['order'] as int?;
          if (id == null) continue;

          final index = _shortcuts.indexWhere((sc) => sc.id == id);
          if (index != -1) {
            if (enabled != null) _shortcuts[index].enabled = enabled;
            if (order != null) _shortcuts[index].order = order;
            await prefs.setBool('shortcut_$id', _shortcuts[index].enabled);
          }
        }
        // Sort by order
        _shortcuts.sort((a, b) => a.order.compareTo(b.order));
        changed = true;
      }

      if (changed) notifyListeners();
    } catch (_) {
      // Non-fatal: if backend is unreachable, keep local preferences
    }
  }
}

// =============================================================================
// RIVERPOD HANDLE  (canonical V2 access path)
//
// Read in NEW code via:
//   final settings = ref.watch(settingsProvider);
//   ref.read(settingsProvider).setPushNotifications(true);
// =============================================================================
final settingsProvider = ChangeNotifierProvider<SettingsProvider>((ref) {
  return SettingsProvider();
});
