// =============================================================================
// TRADE PROVIDER — V3 (Phase P3: Unified Socket)
//
// Phase P3 refactor (2026-05-25):
//   Removed the duplicate IO.Socket instance that TradeProvider used to own.
//   All socket operations now go through SocketService.instance (the single
//   connection). TradeProvider remains the canonical Riverpod handle for:
//     - AppRole (user vs vendor)
//     - Active trade state
//     - Notification count
//     - Vendor ad management (CRUD)
//     - Yellow Card rate cache
//   But socket connection/room management is delegated to SocketService.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:azaman/config.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

// Enum for switching the entire app shell
enum AppRole { user, vendor }

class TradeProvider with ChangeNotifier {
  // =========================================================================
  // Phase P3: Socket access via SocketService singleton.
  // `socket` getter preserved for screen-level code that still reads it
  // (active_trade_screen, vendor_trade_execution, chat_interface, etc.)
  // — these access the raw IO.Socket for per-trade `.on()` / `.off()` hooks.
  // =========================================================================
  IO.Socket? get socket => SocketService.instance.rawSocket;

  // --- CORE APP STATE ---
  AppRole _currentRole = AppRole.user;
  Map<String, dynamic>? _activeTrade;
  int _notificationCount = 0;

  // --- VENDOR SPECIFIC STATE ---
  bool _isMerchantOnline = true;
  List<Map<String, dynamic>> _myActiveAds = [];
  bool _isLoadingAds = false;

  // --- YELLOW CARD RATE (cached, in NGN per 1 USD) ---
  double _yellowCardRate = 0.0;
  double get yellowCardRate => _yellowCardRate;

  // Cache the token for socket-triggered refreshes
  String? _cachedToken;

  // --- CONSTRUCTOR ---
  TradeProvider() {
    // Phase P3: Register callbacks on the unified SocketService so we
    // get trade_update and market_update events dispatched to us.
    _registerSocketCallbacks();
  }

  void _registerSocketCallbacks() {
    // trade_update → track disputed trades for notification badge
    SocketService.instance.onTradeUpdate((data) {
      if (data['status'] == 'DISPUTED') {
        _notificationCount++;
        notifyListeners();
      }
    });

    // market_update → auto-refresh vendor ads when marketplace changes
    SocketService.instance.onMarketUpdate(() {
      if (_currentRole == AppRole.vendor && _cachedToken != null) {
        fetchMyAds(_cachedToken!);
      }
    });
  }

  // --- GETTERS ---
  AppRole get currentRole => _currentRole;
  Map<String, dynamic>? get activeTrade => _activeTrade;
  int get notificationCount => _notificationCount;
  bool get isMerchantOnline => _isMerchantOnline;
  List<Map<String, dynamic>> get myActiveAds => _myActiveAds;
  bool get isLoadingAds => _isLoadingAds;

  // ============================================================
  // --- CENTRALIZED ROOM MANAGEMENT (delegates to SocketService) ---
  // ============================================================

  /// Join the user's personal notification room. Call once after login.
  void joinUserRoom(dynamic userId) {
    // Now handled centrally by SocketService.instance.joinUserRoom()
    // This method is kept for backwards compat but is a no-op if
    // SocketService already joined the room during init.
    debugPrint('[TradeProvider] joinUserRoom delegated to SocketService');
  }

  /// Join the balance update room. Call once after login.
  void joinBalanceRoom(dynamic userId) {
    // Now handled centrally by SocketService.instance.joinUserRoom()
    debugPrint('[TradeProvider] joinBalanceRoom delegated to SocketService');
  }

  // --------------------------------------------------------------------------
  // GLOBAL BALANCE LISTENER (Phase P3: delegates to SocketService)
  //
  // SocketService already writes to balanceDataProvider on balance_update.
  // This method adds an AuthProvider patch so screens using AuthProvider.user
  // also get fresh numbers.
  // --------------------------------------------------------------------------
  void attachAuthBalance(AuthProvider auth) {
    // No longer needed — SocketService handles balance_update directly
    // and writes to balanceDataProvider. Kept as no-op for API compat.
    debugPrint('[TradeProvider] attachAuthBalance — no-op (Phase P3: SocketService handles balance_update)');
  }

  /// Join a specific trade room. Idempotent — safe to call multiple times.
  void joinTradeRoom(String tradeId) {
    SocketService.instance.joinTradeRoom(tradeId);
  }

  /// Leave a trade room (call when navigating away from trade screen).
  void leaveTradeRoom(String tradeId) {
    SocketService.instance.leaveTradeRoom(tradeId);
  }

  // --- METHODS ---

  void toggleRole() {
    _currentRole = (_currentRole == AppRole.user) ? AppRole.vendor : AppRole.user;
    notifyListeners();
  }

  /// Sync the app role from the authenticated user's actual role.
  /// Call after login / profile fetch to ensure the pull tab and
  /// vendor-specific UI reflects the real server-side role.
  void syncRoleFromAuth(String? role) {
    final normalized = (role ?? '').toUpperCase();
    final newRole = (normalized == 'VENDOR' || normalized == 'ADMIN')
        ? AppRole.vendor
        : AppRole.user;
    if (_currentRole != newRole) {
      _currentRole = newRole;
      notifyListeners();
    }
  }

  void toggleMerchantStatus() {
    _isMerchantOnline = !_isMerchantOnline;
    notifyListeners();
  }

  void updateTrade(Map<String, dynamic> tradeData) {
    _activeTrade = tradeData;
    _notificationCount++;
    notifyListeners();
  }

  void clearNotifications() {
    _notificationCount = 0;
    notifyListeners();
  }

  void incrementNotificationCount() {
    _notificationCount++;
    notifyListeners();
  }

  void addAd(Map<String, dynamic> adData) {
    _myActiveAds.insert(0, adData);
    notifyListeners();
  }

  /// Fetch the latest Yellow Card rate from the backend.
  Future<void> fetchYellowCardRate({String? token}) async {
    try {
      final response = await apiClient.get('/oracle/yellowcard-rate');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _yellowCardRate =
            (data['rate'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {
      // keep last cached value
    }
  }

  void updateYellowCardRate(double rate) {
    _yellowCardRate = rate;
    notifyListeners();
  }

  // ============================================================
  // --- PHASE 8: VENDOR AD MANAGEMENT METHODS ---
  // ============================================================

  Future<void> fetchMyAds(String token) async {
    _cachedToken = token;
    _isLoadingAds = true;
    notifyListeners();

    try {
      final response = await apiClient.get('/ads/mine');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List adsList = data['ads'] ?? [];

        _myActiveAds = adsList.map<Map<String, dynamic>>((ad) {
          return {
            'id': ad['id'],
            'type': ad['type'] ?? 'SELL',
            'crypto': ad['crypto'] ?? 'USDT',
            'pricePerUSD': (ad['pricePerUSD'] as num?)?.toDouble() ?? 0.0,
            'margin': (ad['margin'] as num?)?.toDouble(),
            'minLimit': (ad['minLimit'] as num?)?.toDouble() ?? 0.0,
            'maxLimit': (ad['maxLimit'] as num?)?.toDouble() ?? 0.0,
            'paymentMethod': ad['paymentMethod'] ?? 'Bank Transfer',
            'terms': ad['terms'],
            'status': ad['status'] ?? 'ACTIVE',
            'createdAt': ad['createdAt'],
            'activeHoursStart': ad['activeHoursStart'] ?? '08:00',
            'activeHoursEnd': ad['activeHoursEnd'] ?? '22:00',
            'maxPaymentWindow': (ad['maxPaymentWindow'] as num?)?.toInt() ?? 15,
          };
        }).toList();

        debugPrint("📋 Fetched ${_myActiveAds.length} vendor ads");
      }
    } catch (e) {
      debugPrint("❌ Error fetching vendor ads: $e");
    } finally {
      _isLoadingAds = false;
      notifyListeners();
    }
  }

  Future<bool> createAd(Map<String, dynamic> adData, String token) async {
    try {
      final response = await apiClient.post('/ads/create', adData);

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['ad'] != null) {
          final ad = data['ad'];
          _myActiveAds.insert(0, {
            'id': ad['id'],
            'type': ad['type'] ?? 'SELL',
            'crypto': ad['crypto'] ?? 'USDT',
            'pricePerUSD': (ad['pricePerUSD'] as num?)?.toDouble() ?? 0.0,
            'margin': (ad['margin'] as num?)?.toDouble(),
            'minLimit': (ad['minLimit'] as num?)?.toDouble() ?? 0.0,
            'maxLimit': (ad['maxLimit'] as num?)?.toDouble() ?? 0.0,
            'paymentMethod': ad['paymentMethod'] ?? 'Bank Transfer',
            'terms': ad['terms'],
            'status': ad['status'] ?? 'ACTIVE',
            'createdAt': ad['createdAt'],
            'activeHoursStart': ad['activeHoursStart'] ?? '08:00',
            'activeHoursEnd': ad['activeHoursEnd'] ?? '22:00',
            'maxPaymentWindow': (ad['maxPaymentWindow'] as num?)?.toInt() ?? 15,
          });
          notifyListeners();
        }
        return true;
      } else {
        return false;
      }
    } catch (e) {
      debugPrint("❌ Error creating ad: $e");
      return false;
    }
  }

  Future<bool> toggleAdStatus(int adId, String token) async {
    final index = _myActiveAds.indexWhere((ad) => ad['id'] == adId);
    if (index == -1) return false;

    final oldStatus = _myActiveAds[index]['status'];
    final newStatus = oldStatus == 'ACTIVE' ? 'OFFLINE' : 'ACTIVE';
    _myActiveAds[index]['status'] = newStatus;
    notifyListeners();

    try {
      final response = await apiClient.put('/ads/$adId/toggle', {});

      if (response.statusCode == 200) {
        return true;
      } else {
        _myActiveAds[index]['status'] = oldStatus;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _myActiveAds[index]['status'] = oldStatus;
      notifyListeners();
      return false;
    }
  }

  Future<bool> disputeTrade(String tradeId, String reason, String token) async {
    try {
      final response = await apiClient.post('/trades/dispute', {
        'tradeId': tradeId,
        'reason': reason,
      });

      if (response.statusCode == 200) {
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Error disputing trade: $e");
      return false;
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void dispose() {
    // Phase P3: No socket to dispose — SocketService owns the connection.
    // Just clean up ChangeNotifier state.
    super.dispose();
  }
}



// =============================================================================
// RIVERPOD HANDLE  (canonical V2 access path)
//
// Read in NEW code via:
//   final trade = ref.watch(tradeProvider);
//   ref.read(tradeProvider).joinTradeRoom(tradeId);
//
// Granular reads — only the specific text repaints, never the layout:
//   final rate = ref.watch(tradeProvider.select((t) => t.yellowCardRate));
//   final notifs = ref.watch(tradeProvider.select((t) => t.notificationCount));
// =============================================================================
final tradeProvider = ChangeNotifierProvider<TradeProvider>((ref) {
  return TradeProvider();
});
