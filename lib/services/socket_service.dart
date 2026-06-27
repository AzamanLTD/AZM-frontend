// =============================================================================
// AZAMAN UNIFIED SOCKET SERVICE — V5 (Phase P3)
//
// Responsibilities:
//   - Maintain a SINGLE persistent socket.io connection to the Node backend.
//   - Listen to `balance_update` → write full V2 ledger balances + patch AuthProvider.
//   - Listen to `rate_update` → write oracleRateProvider.
//   - Listen to `azm_reward` / `azm_spend` → update hologram + notify callbacks.
//   - Listen to `trade_update`, `market_update`, `new_notification`,
//     `new_trade_request`, `trade_completed` → dispatch via registered callbacks.
//   - Expose connect / disconnect / joinRoom / emit helpers.
//   - Handle Android-emulator host aliasing + configurable environments.
//   - Auto-authenticate via JWT token in handshake.
//
// Phase P3 unification (2026-05-25):
//   Previously the app ran TWO concurrent socket.io connections — one from
//   SocketService (hologram/balance/rate) and another from TradeProvider
//   (trade/chat/vendor). This V5 consolidates both into a single connection,
//   eliminating duplicate bandwidth, race conditions on balance_update, and
//   confusion about which socket instance owns which events.
//
// Usage:
//   In your app bootstrap (e.g. MainWrapper.initState):
//     SocketService.instance.init(ref);
//     SocketService.instance.joinUserRoom(userId);
// =============================================================================

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:azaman/config.dart';
import 'package:azaman/providers/hologram_provider.dart';

// ---------------------------------------------------------------------------
// Riverpod provider so widgets / other providers can read service state.
// Returns the static singleton instance so there's only ONE socket connection.
// ---------------------------------------------------------------------------
final socketServiceProvider = Provider<SocketService>((ref) {
  ref.onDispose(SocketService.instance.disconnect);
  return SocketService.instance;
});

// ---------------------------------------------------------------------------
// SocketService — singleton wrapper around socket_io_client
// ---------------------------------------------------------------------------
class SocketService {
  SocketService._internal();
  static final SocketService instance = SocketService._internal();

  io.Socket? _socket;
  WidgetRef? _ref;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // =========================================================================
  // CALLBACK REGISTRY — modules register handlers instead of listening directly
  // =========================================================================

  /// AZM reward events (registered by the app shell)
  void Function(double azmBalance, double awarded, String source, String reason)?
      _onAzmReward;

  /// AZM spend events (Phase E2: real-time debit notification)
  void Function(double azmBalance, double spent, String source, String reason)?
      _onAzmSpend;

  /// Trade update events (registered by TradeProvider)
  void Function(Map<String, dynamic> data)? _onTradeUpdate;

  /// Market update events (registered by TradeProvider for vendor ad refresh)
  void Function()? _onMarketUpdate;

  /// New notification events (for notification badge)
  void Function(Map<String, dynamic> data)? _onNewNotification;

  /// Notifications updated (Phase B2: multi-device sync)
  void Function(Map<String, dynamic> data)? _onNotificationsUpdated;

  /// New trade request events (vendor snackbar)
  void Function(Map<String, dynamic> data)? _onNewTradeRequest;

  /// Trade completed events (success receipt dialog)
  void Function(Map<String, dynamic> data)? _onTradeCompleted;

  // ── V3 Marketplace Sprint (2026-06-21): business + escrow callbacks ────────

  /// New owner-facing business notification (drives the badge + feed).
  void Function(Map<String, dynamic> data)? _onBizNotification;

  /// Authoritative unread-count push (multi-device sync).
  void Function(int unreadCount)? _onBizNotificationsUpdated;

  /// A business order was marked delivered (customer-facing nudge).
  void Function(Map<String, dynamic> data)? _onBusinessOrderDelivered;

  /// Any `escrow_*` / `invoice_paid` event — the second arg is the event name
  /// so a single handler can fan out (the ticket workspace filters by ticket).
  void Function(Map<String, dynamic> data, String eventName)? _onEscrowEvent;

  /// Deposit confirmed by payment provider webhook (Moolre on-ramp).
  /// Called with: amountGhs, amountUsdc, provider, reference.
  void Function(double amountGhs, double amountUsdc, String provider, String reference)?
      _onDepositSuccess;

  // ── Registration methods ──────────────────────────────────────────────────

  void onAzmReward(
      void Function(double azmBalance, double awarded, String source, String reason) callback) {
    _onAzmReward = callback;
  }

  void onAzmSpend(
      void Function(double azmBalance, double spent, String source, String reason) callback) {
    _onAzmSpend = callback;
  }

  void onTradeUpdate(void Function(Map<String, dynamic> data) callback) {
    _onTradeUpdate = callback;
  }

  void onMarketUpdate(void Function() callback) {
    _onMarketUpdate = callback;
  }

  void onNewNotification(void Function(Map<String, dynamic> data) callback) {
    _onNewNotification = callback;
  }

  void onNotificationsUpdated(void Function(Map<String, dynamic> data) callback) {
    _onNotificationsUpdated = callback;
  }

  void onNewTradeRequest(void Function(Map<String, dynamic> data) callback) {
    _onNewTradeRequest = callback;
  }

  void onTradeCompleted(void Function(Map<String, dynamic> data) callback) {
    _onTradeCompleted = callback;
  }

  // ── V3 Marketplace Sprint registration methods ────────────────────────────

  void onBizNotification(void Function(Map<String, dynamic>) cb) {
    _onBizNotification = cb;
  }

  void onBizNotificationsUpdated(void Function(int) cb) {
    _onBizNotificationsUpdated = cb;
  }

  void onBusinessOrderDelivered(void Function(Map<String, dynamic>) cb) {
    _onBusinessOrderDelivered = cb;
  }

  void onEscrowEvent(void Function(Map<String, dynamic>, String) cb) {
    _onEscrowEvent = cb;
  }

  void onDepositSuccess(
      void Function(double amountGhs, double amountUsdc, String provider, String reference) callback) {
    _onDepositSuccess = callback;
  }

  // ── V3 Marketplace Sprint dispatch helpers ────────────────────────────────

  Map<String, dynamic> _toMap(dynamic data) =>
      data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map);

  void _dispatchEscrow(dynamic data, String eventName) {
    try {
      _onEscrowEvent?.call(_toMap(data), eventName);
    } catch (e) {
      debugPrint('[SocketService] $eventName error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Resolve the correct backend host:
  //   - Android emulator → 10.0.2.2 (maps to host machine localhost)
  //   - iOS simulator / physical device / web → use AppConfig.socketUrl
  // -------------------------------------------------------------------------
  static String get _resolvedHost {
    String host = AppConfig.socketUrl;
    try {
      if (!kIsWeb && Platform.isAndroid) {
        host = host
            .replaceFirst('localhost', '10.0.2.2')
            .replaceFirst('127.0.0.1', '10.0.2.2');
      }
    } catch (_) {
      // Platform.isAndroid throws on web; kIsWeb guard above prevents that
    }
    return host;
  }

  // -------------------------------------------------------------------------
  // init — call once after ProviderScope is available (e.g. MainWrapper)
  // -------------------------------------------------------------------------
  void init(WidgetRef ref) {
    _ref = ref;
    _connect();
  }

  // Overload for use outside widget tree (plain Ref from a provider)
  void initWithRef(Ref ref) {
    _connectWithRef(ref);
  }

  // -------------------------------------------------------------------------
  // Internal connect helpers
  // -------------------------------------------------------------------------
  Future<void> _connect() async {
    if (_socket != null && (_socket!.connected)) return;

    // Get token for authenticated socket connection
    final token = await _storage.read(key: 'auth_token');

    _socket = io.io(
      _resolvedHost,
      io.OptionBuilder()
          .setTransports(['polling', 'websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(double.infinity)
          .setReconnectionDelay(AppConfig.socketReconnectDelayMs)
          .setAuth({'token': token ?? ''})
          .setExtraHeaders({'ngrok-skip-browser-warning': 'true'})
          .build(),
    );

    _attachCoreListeners();
  }

  Future<void> _connectWithRef(Ref ref) async {
    if (_socket != null && (_socket!.connected)) return;

    final token = await _storage.read(key: 'auth_token');

    _socket = io.io(
      _resolvedHost,
      io.OptionBuilder()
          .setTransports(['polling', 'websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(double.infinity)
          .setReconnectionDelay(AppConfig.socketReconnectDelayMs)
          .setAuth({'token': token ?? ''})
          .setExtraHeaders({'ngrok-skip-browser-warning': 'true'})
          .build(),
    );

    _attachCoreListenersPlainRef(ref);
  }

  // =========================================================================
  // TRADE ROOM MANAGEMENT
  // =========================================================================

  /// Track which trade rooms we've joined to avoid duplicate joins
  final Set<String> _joinedTradeRooms = {};

  /// Join a specific trade room. Idempotent — safe to call multiple times.
  void joinTradeRoom(String tradeId) {
    final cleanId = tradeId.replaceAll('#', '');
    if (_joinedTradeRooms.contains(cleanId)) {
      if (AppConfig.enableNetworkLogs) {
        debugPrint('[SocketService] Already in trade room: trade_$cleanId');
      }
      return;
    }
    _socket?.emit('join_trade', cleanId);
    _joinedTradeRooms.add(cleanId);
    if (AppConfig.enableNetworkLogs) {
      debugPrint('[SocketService] Joined trade room: trade_$cleanId');
    }
  }

  /// Leave a trade room (call when navigating away from trade screen).
  void leaveTradeRoom(String tradeId) {
    final cleanId = tradeId.replaceAll('#', '');
    _joinedTradeRooms.remove(cleanId);
    if (AppConfig.enableNetworkLogs) {
      debugPrint('[SocketService] Left trade room tracking: trade_$cleanId');
    }
  }

  // -------------------------------------------------------------------------
  // Room management
  // -------------------------------------------------------------------------

  /// Join the user's personal balance + notification rooms
  void joinUserRoom(String userId) {
    _socket?.emit('join_user_room', {'userId': userId});
    _socket?.emit('join_balance_room', userId);
    if (AppConfig.enableNetworkLogs) {
      debugPrint('[SocketService] Joined user + balance rooms: $userId');
    }
  }

  /// Leave a previously joined room
  void leaveRoom(String roomId) {
    _socket?.emit('leave_room', {'roomId': roomId});
  }

  // -------------------------------------------------------------------------
  // Emit helper — allows screens to emit events without importing socket_io
  // -------------------------------------------------------------------------
  void emit(String event, dynamic data) {
    if (_socket == null) {
      debugPrint('⚠️ [SocketService] emit "$event" FAILED — socket is null');
      return;
    }
    if (!_socket!.connected) {
      debugPrint('⚠️ [SocketService] emit "$event" — socket NOT connected');
    }
    debugPrint('📤 [SocketService] emit "$event"');
    _socket?.emit(event, data);
  }

  // -------------------------------------------------------------------------
  // Core event listeners — WidgetRef variant
  // -------------------------------------------------------------------------
  void _attachCoreListeners() {
    _socket!
      ..onConnect((_) {
        if (AppConfig.enableNetworkLogs) {
          debugPrint('[SocketService] Connected → $_resolvedHost (ID: ${_socket?.id})');
        }
        // Re-join any trade rooms on reconnect
        for (final roomId in _joinedTradeRooms) {
          _socket?.emit('join_trade', roomId);
          if (AppConfig.enableNetworkLogs) {
            debugPrint('[SocketService] Re-joined trade room: trade_$roomId');
          }
        }
      })
      ..onDisconnect((_) {
        if (AppConfig.enableNetworkLogs) {
          debugPrint('[SocketService] Disconnected');
        }
      })
      ..onConnectError((err) {
        if (AppConfig.enableNetworkLogs) {
          debugPrint('[SocketService] Connect error: $err');
        }
      })

      // ── balance_update (V4: full ledger) ────────────────────────────────
      ..on('balance_update', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);

          final balances = BalanceData(
            availableBalance: _toDouble(raw['availableBalance']),
            vendorUnallocatedBalance: _toDouble(raw['vendorUnallocatedBalance']),
            escrowLockedBalance: _toDouble(raw['escrowLockedBalance']),
            disputeEscrowBalance: _toDouble(raw['disputeEscrowBalance']),
            azmBalance: _toDouble(raw['azmBalance']),
          );

          _ref?.read(balanceDataProvider.notifier).state = balances;

          // Also update legacy single-value provider for backwards compat
          _ref?.read(userUsdcBalanceProvider.notifier).state =
              balances.availableBalance + balances.vendorUnallocatedBalance;

          if (AppConfig.enableNetworkLogs) {
            debugPrint('[SocketService] balance_update → ${balances.totalBalance} USDC');
          }
        } catch (e) {
          debugPrint('[SocketService] balance_update parse error: $e');
        }
      })

      // ── rate_update ─────────────────────────────────────────────────────
      ..on('rate_update', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          final double rate = _toDouble(raw['rate']);
          if (rate > 0) {
            _ref?.read(oracleRateProvider.notifier).state = rate;
          }
          if (AppConfig.enableNetworkLogs) {
            debugPrint('[SocketService] rate_update → $rate GHS/USDC');
          }
        } catch (e) {
          debugPrint('[SocketService] rate_update parse error: $e');
        }
      })

      // ── deposit_success (Moolre on-ramp webhook confirmation) ────────────
      ..on('deposit_success', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          final amountGhs  = _toDouble(raw['amountGhs']);
          final amountUsdc = _toDouble(raw['amountUsdc']);
          final provider   = raw['provider']?.toString() ?? 'MOBILE_MONEY';
          final reference  = raw['reference']?.toString() ?? '';
          if (AppConfig.enableNetworkLogs) {
            debugPrint('[SocketService] deposit_success → GH₵$amountGhs / $amountUsdc USDC ($provider)');
          }
          _onDepositSuccess?.call(amountGhs, amountUsdc, provider, reference);
        } catch (e) {
          debugPrint('[SocketService] deposit_success parse error: $e');
        }
      })

      // ── azm_reward (Phase E1: real-time AZM credit notification) ────────
      ..on('azm_reward', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);

          final newAzmBalance = _toDouble(raw['azmBalance']);
          final awarded = _toDouble(raw['awarded']);
          final source = raw['source']?.toString() ?? '';
          final reason = raw['reason']?.toString() ?? '';

          final current = _ref?.read(balanceDataProvider);
          if (current != null) {
            _ref?.read(balanceDataProvider.notifier).state =
                current.copyWith(azmBalance: newAzmBalance);
          }

          if (AppConfig.enableNetworkLogs) {
            debugPrint('[SocketService] azm_reward → +$awarded AZM ($source)');
          }

          _onAzmReward?.call(newAzmBalance, awarded, source, reason);
        } catch (e) {
          debugPrint('[SocketService] azm_reward parse error: $e');
        }
      })

      // ── azm_spend (Phase E2: real-time AZM debit notification) ──────────
      ..on('azm_spend', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);

          final newAzmBalance = _toDouble(raw['azmBalance']);
          final spent = _toDouble(raw['spent']);
          final source = raw['source']?.toString() ?? '';
          final reason = raw['reason']?.toString() ?? '';

          final current = _ref?.read(balanceDataProvider);
          if (current != null) {
            _ref?.read(balanceDataProvider.notifier).state =
                current.copyWith(azmBalance: newAzmBalance);
          }

          if (AppConfig.enableNetworkLogs) {
            debugPrint('[SocketService] azm_spend → -$spent AZM ($source)');
          }

          _onAzmSpend?.call(newAzmBalance, spent, source, reason);
        } catch (e) {
          debugPrint('[SocketService] azm_spend parse error: $e');
        }
      })

      // ── trade_update (Phase P3: unified from TradeProvider) ─────────────
      ..on('trade_update', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          _onTradeUpdate?.call(raw);
        } catch (e) {
          debugPrint('[SocketService] trade_update parse error: $e');
        }
      })

      // ── market_update (Phase P3: vendor ad refresh trigger) ─────────────
      ..on('market_update', (_) {
        _onMarketUpdate?.call();
      })

      // ── new_notification ────────────────────────────────────────────────
      ..on('new_notification', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          _onNewNotification?.call(raw);
        } catch (e) {
          debugPrint('[SocketService] new_notification parse error: $e');
        }
      })

      // ── notifications_updated (Phase B2: multi-device sync) ─────────────
      ..on('notifications_updated', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          _onNotificationsUpdated?.call(raw);
        } catch (e) {
          debugPrint('[SocketService] notifications_updated parse error: $e');
        }
      })

      // ── new_trade_request (vendor snackbar) ─────────────────────────────
      ..on('new_trade_request', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          _onNewTradeRequest?.call(raw);
        } catch (e) {
          debugPrint('[SocketService] new_trade_request parse error: $e');
        }
      })

      // ── trade_completed (success receipt) ───────────────────────────────
      ..on('trade_completed', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          _onTradeCompleted?.call(raw);
        } catch (e) {
          debugPrint('[SocketService] trade_completed parse error: $e');
        }
      })

      // ── V3 Marketplace Sprint (2026-06-21): business + escrow events ────
      ..on('biz_notification', (data) {
        try {
          _onBizNotification?.call(_toMap(data));
        } catch (_) {}
      })
      ..on('biz_notifications_updated', (data) {
        try {
          _onBizNotificationsUpdated
              ?.call(_toMap(data)['unreadCount'] as int? ?? 0);
        } catch (_) {}
      })
      ..on('business_order_delivered', (data) {
        try {
          _onBusinessOrderDelivered?.call(_toMap(data));
        } catch (_) {}
      })
      ..on('escrow_funded', (d) => _dispatchEscrow(d, 'escrow_funded'))
      ..on('escrow_settled', (d) => _dispatchEscrow(d, 'escrow_settled'))
      ..on('escrow_pending_settlement',
          (d) => _dispatchEscrow(d, 'escrow_pending_settlement'))
      ..on('escrow_disputed', (d) => _dispatchEscrow(d, 'escrow_disputed'))
      ..on('escrow_resolved', (d) => _dispatchEscrow(d, 'escrow_resolved'))
      ..on('escrow_terms_updated',
          (d) => _dispatchEscrow(d, 'escrow_terms_updated'))
      ..on('invoice_paid', (d) => _dispatchEscrow(d, 'invoice_paid'));
  }

  // -------------------------------------------------------------------------
  // Core event listeners — plain Ref variant
  // -------------------------------------------------------------------------
  void _attachCoreListenersPlainRef(Ref ref) {
    _socket!
      ..onConnect((_) {
        if (AppConfig.enableNetworkLogs) {
          debugPrint('[SocketService] Connected → $_resolvedHost (ID: ${_socket?.id})');
        }
        for (final roomId in _joinedTradeRooms) {
          _socket?.emit('join_trade', roomId);
        }
      })
      ..onDisconnect((_) {
        if (AppConfig.enableNetworkLogs) {
          debugPrint('[SocketService] Disconnected');
        }
      })
      ..onConnectError((err) {
        if (AppConfig.enableNetworkLogs) {
          debugPrint('[SocketService] Connect error: $err');
        }
      })
      ..on('balance_update', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);

          final balances = BalanceData(
            availableBalance: _toDouble(raw['availableBalance']),
            vendorUnallocatedBalance: _toDouble(raw['vendorUnallocatedBalance']),
            escrowLockedBalance: _toDouble(raw['escrowLockedBalance']),
            disputeEscrowBalance: _toDouble(raw['disputeEscrowBalance']),
            azmBalance: _toDouble(raw['azmBalance']),
          );

          ref.read(balanceDataProvider.notifier).state = balances;
          ref.read(userUsdcBalanceProvider.notifier).state =
              balances.availableBalance + balances.vendorUnallocatedBalance;
        } catch (e) {
          debugPrint('[SocketService] balance_update parse error: $e');
        }
      })
      ..on('rate_update', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          final double rate = _toDouble(raw['rate']);
          if (rate > 0) {
            ref.read(oracleRateProvider.notifier).state = rate;
          }
        } catch (e) {
          debugPrint('[SocketService] rate_update parse error: $e');
        }
      })
      ..on('azm_reward', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);

          final newAzmBalance = _toDouble(raw['azmBalance']);

          final current = ref.read(balanceDataProvider);
          ref.read(balanceDataProvider.notifier).state =
              current.copyWith(azmBalance: newAzmBalance);

          _onAzmReward?.call(
            newAzmBalance,
            _toDouble(raw['awarded']),
            raw['source']?.toString() ?? '',
            raw['reason']?.toString() ?? '',
          );
        } catch (e) {
          debugPrint('[SocketService] azm_reward parse error: $e');
        }
      })
      ..on('azm_spend', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);

          final newAzmBalance = _toDouble(raw['azmBalance']);

          final current = ref.read(balanceDataProvider);
          ref.read(balanceDataProvider.notifier).state =
              current.copyWith(azmBalance: newAzmBalance);

          _onAzmSpend?.call(
            newAzmBalance,
            _toDouble(raw['spent']),
            raw['source']?.toString() ?? '',
            raw['reason']?.toString() ?? '',
          );
        } catch (e) {
          debugPrint('[SocketService] azm_spend parse error: $e');
        }
      })
      // Phase P3: dispatch trade/notification events via callbacks
      ..on('trade_update', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          _onTradeUpdate?.call(raw);
        } catch (_) {}
      })
      ..on('market_update', (_) => _onMarketUpdate?.call())
      ..on('new_notification', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          _onNewNotification?.call(raw);
        } catch (_) {}
      })
      ..on('notifications_updated', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          _onNotificationsUpdated?.call(raw);
        } catch (_) {}
      })
      ..on('new_trade_request', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          _onNewTradeRequest?.call(raw);
        } catch (_) {}
      })
      ..on('trade_completed', (data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          _onTradeCompleted?.call(raw);
        } catch (_) {}
      })

      // ── V3 Marketplace Sprint (2026-06-21): business + escrow events ────
      ..on('biz_notification', (data) {
        try {
          _onBizNotification?.call(_toMap(data));
        } catch (_) {}
      })
      ..on('biz_notifications_updated', (data) {
        try {
          _onBizNotificationsUpdated
              ?.call(_toMap(data)['unreadCount'] as int? ?? 0);
        } catch (_) {}
      })
      ..on('business_order_delivered', (data) {
        try {
          _onBusinessOrderDelivered?.call(_toMap(data));
        } catch (_) {}
      })
      ..on('escrow_funded', (d) => _dispatchEscrow(d, 'escrow_funded'))
      ..on('escrow_settled', (d) => _dispatchEscrow(d, 'escrow_settled'))
      ..on('escrow_pending_settlement',
          (d) => _dispatchEscrow(d, 'escrow_pending_settlement'))
      ..on('escrow_disputed', (d) => _dispatchEscrow(d, 'escrow_disputed'))
      ..on('escrow_resolved', (d) => _dispatchEscrow(d, 'escrow_resolved'))
      ..on('escrow_terms_updated',
          (d) => _dispatchEscrow(d, 'escrow_terms_updated'))
      ..on('invoice_paid', (d) => _dispatchEscrow(d, 'invoice_paid'));
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------
  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _ref = null;
    _joinedTradeRooms.clear();
    // Clear all registered callbacks
    _onAzmReward = null;
    _onAzmSpend = null;
    _onTradeUpdate = null;
    _onMarketUpdate = null;
    _onNewNotification = null;
    _onNotificationsUpdated = null;
    _onNewTradeRequest = null;
    _onTradeCompleted = null;
    // V3 Marketplace Sprint callbacks
    _onBizNotification = null;
    _onBizNotificationsUpdated = null;
    _onBusinessOrderDelivered = null;
    _onEscrowEvent = null;
    _onDepositSuccess = null;
    if (AppConfig.enableNetworkLogs) {
      debugPrint('[SocketService] Disposed');
    }
  }

  bool get isConnected => _socket?.connected ?? false;
  io.Socket? get rawSocket => _socket;

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
