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

  HQShortcut({
    required this.id,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.order = 0,
  });
}

class SettingsProvider with ChangeNotifier {
  bool _pushNotifications = true;
  bool _tradeAlerts = true;
  bool _chatNotifications = true;

  // NOTE (2026-10-20): the duplicate currency preference that lived here
  // ('default_currency' + backend 'currencyDisplay') is RETIRED. The ONE
  // authoritative display preference is CurrencyNotifier (currencyProvider,
  // 'display_currency' key, GHS-first). This provider no longer reads,
  // writes or syncs any currency value — see lib/models/currency_model.dart
  // for the migration rule and the one-way backend mirror.
  String _appLanguage = 'English';

  bool _vendorTagEnabled = false;

  final List<HQShortcut> _shortcuts = [
    HQShortcut(
      id: 'deposit',
      label: 'Deposit',
      icon: Icons.account_balance_wallet_outlined,
      order: 0,
    ),
    HQShortcut(
      id: 'withdraw',
      label: 'Withdraw',
      icon: Icons.send_outlined,
      order: 1,
    ),
    HQShortcut(id: 'history', label: 'History', icon: Icons.history, order: 2),
    HQShortcut(
      id: 'stats',
      label: 'Stats',
      icon: Icons.analytics_outlined,
      order: 3,
    ),
    HQShortcut(
      id: 'p2p',
      label: 'P2P Trading',
      icon: Icons.swap_horiz,
      order: 4,
    ),
    HQShortcut(
      id: 'savings',
      label: 'Savings',
      icon: Icons.savings_outlined,
      order: 5,
    ),
    HQShortcut(
      id: 'support',
      label: 'Support',
      icon: Icons.headset_mic_outlined,
      order: 6,
    ),
    HQShortcut(
      id: 'ads',
      label: 'Ad Manager',
      icon: Icons.campaign_outlined,
      order: 7,
    ),
    HQShortcut(
      id: 'settings',
      label: 'Settings',
      icon: Icons.settings_outlined,
      order: 8,
    ),
  ];

  bool _isLoaded = false;

  bool get pushNotifications => _pushNotifications;
  bool get tradeAlerts => _tradeAlerts;
  bool get chatNotifications => _chatNotifications;
  bool get vendorTagEnabled => _vendorTagEnabled;
  String get appLanguage => _appLanguage;
  List<HQShortcut> get shortcuts => _shortcuts;
  List<HQShortcut> get enabledShortcuts =>
      _shortcuts.where((s) => s.enabled).toList();
  bool get isLoaded => _isLoaded;

  SettingsProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    _pushNotifications = prefs.getBool('push_notifications') ?? true;
    _tradeAlerts = prefs.getBool('trade_alerts') ?? true;
    _chatNotifications = prefs.getBool('chat_notifications') ?? true;
    _appLanguage = prefs.getString('app_language') ?? 'English';
    _vendorTagEnabled = prefs.getBool('vendor_tag_enabled') ?? false;

    for (var shortcut in _shortcuts) {
      shortcut.enabled =
          prefs.getBool('shortcut_${shortcut.id}') ?? shortcut.enabled;
    }

    _isLoaded = true;
    notifyListeners();
  }

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

  Future<void> setVendorTagEnabled(bool value) async {
    _vendorTagEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vendor_tag_enabled', value);
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

  Future<void> _syncPreferencesToBackend() async {
    try {
      await apiClient.put('/users/preferences', {
        'preferences': {
          'pushNotifications': _pushNotifications,
          'tradeAlerts': _tradeAlerts,
          'chatNotifications': _chatNotifications,
          'language': _appLanguage,
        },
      });
    } catch (_) {}
  }

  Future<void> _syncShortcutsToBackend() async {
    try {
      final shortcuts = _shortcuts
          .map((s) => {'id': s.id, 'enabled': s.enabled, 'order': s.order})
          .toList();

      await apiClient.put('/users/preferences/shortcuts', {
        'shortcuts': shortcuts,
      });
    } catch (_) {}
  }

  Future<void> loadFromBackend() async {
    try {
      final response = await apiClient.get('/users/preferences');
      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body);
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return;

      bool changed = false;
      final prefs = await SharedPreferences.getInstance();

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
        if (preferences['language'] is String &&
            (preferences['language'] as String).isNotEmpty) {
          _appLanguage = preferences['language'];
          await prefs.setString('app_language', _appLanguage);
          changed = true;
        }
      }

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
        _shortcuts.sort((a, b) => a.order.compareTo(b.order));
        changed = true;
      }

      if (changed) notifyListeners();
    } catch (_) {}
  }
}

// Canonical Riverpod handle retained for existing consumers.
final settingsProvider = ChangeNotifierProvider<SettingsProvider>((ref) {
  return SettingsProvider();
});
