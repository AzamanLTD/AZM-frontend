// =============================================================================
// AZAMAN UNIFIED SOCKET SERVICE — V6
//
// One singleton owns one Socket.IO connection, one listener registry, and one
// reconnectable room registry. Providers/screens register callbacks here;
// they never create or destroy their own global socket.
// =============================================================================

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:azaman/config.dart';
import 'package:azaman/providers/hologram_provider.dart';

final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService.instance;
});

class SocketService {
  SocketService._internal();
  static final SocketService instance = SocketService._internal();

  io.Socket? _socket;
  dynamic _ref;
  bool _connecting = false;
  bool _authBlocked = false;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _currentUserId;
  final Set<String> _joinedTradeRooms = <String>{};
  final Set<String> _joinedFriendRooms = <String>{};
  final Set<String> _joinedGroupRooms = <String>{};
  final Set<String> _joinedOrderRooms = <String>{};

  void Function(double, double, String, String)? _onAzmReward;
  void Function(double, double, String, String)? _onAzmSpend;
  void Function(Map<String, dynamic>)? _onTradeUpdate;
  void Function()? _onMarketUpdate;
  void Function(Map<String, dynamic>)? _onNewNotification;
  void Function(Map<String, dynamic>)? _onNotificationsUpdated;
  void Function(Map<String, dynamic>)? _onNewTradeRequest;
  void Function(Map<String, dynamic>)? _onTradeCompleted;
  void Function(Map<String, dynamic>)? _onBizNotification;
  void Function(int)? _onBizNotificationsUpdated;
  void Function(Map<String, dynamic>)? _onBusinessOrderDelivered;
  void Function(Map<String, dynamic>)? _onOrderLocation;
  void Function(Map<String, dynamic>)? _onOrderStatus;
  void Function(Map<String, dynamic>)? _onOrderEta;
  void Function(Map<String, dynamic>, String)? _onEscrowEvent;
  void Function(double, double, String, String)? _onDepositSuccess;
  void Function(Map<String, dynamic>)? _onWithdrawalProgress;
  void Function(Map<String, dynamic>)? _onWithdrawalSettled;

  void onAzmReward(void Function(double, double, String, String) cb) => _onAzmReward = cb;
  void onAzmSpend(void Function(double, double, String, String) cb) => _onAzmSpend = cb;
  void onTradeUpdate(void Function(Map<String, dynamic>) cb) => _onTradeUpdate = cb;
  void onMarketUpdate(void Function() cb) => _onMarketUpdate = cb;
  void onNewNotification(void Function(Map<String, dynamic>) cb) => _onNewNotification = cb;
  void onNotificationsUpdated(void Function(Map<String, dynamic>) cb) => _onNotificationsUpdated = cb;
  void onNewTradeRequest(void Function(Map<String, dynamic>) cb) => _onNewTradeRequest = cb;
  void onTradeCompleted(void Function(Map<String, dynamic>) cb) => _onTradeCompleted = cb;
  void onBizNotification(void Function(Map<String, dynamic>) cb) => _onBizNotification = cb;
  void onBizNotificationsUpdated(void Function(int) cb) => _onBizNotificationsUpdated = cb;
  void onBusinessOrderDelivered(void Function(Map<String, dynamic>) cb) => _onBusinessOrderDelivered = cb;
  void onOrderLocation(void Function(Map<String, dynamic>) cb) => _onOrderLocation = cb;
  void onOrderStatus(void Function(Map<String, dynamic>) cb) => _onOrderStatus = cb;
  void onOrderEta(void Function(Map<String, dynamic>) cb) => _onOrderEta = cb;
  void onEscrowEvent(void Function(Map<String, dynamic>, String) cb) => _onEscrowEvent = cb;
  void onDepositSuccess(void Function(double, double, String, String) cb) => _onDepositSuccess = cb;
  void onWithdrawalProgress(void Function(Map<String, dynamic>) cb) => _onWithdrawalProgress = cb;
  void onWithdrawalSettled(void Function(Map<String, dynamic>) cb) => _onWithdrawalSettled = cb;

  // Callback removal is identity-based so a disposed screen cannot clear a
  // newer screen/provider's callback from the singleton registry.
  void removeOrderLocationListener(void Function(Map<String, dynamic>) cb) {
    if (_onOrderLocation == cb) _onOrderLocation = null;
  }

  void removeOrderStatusListener(void Function(Map<String, dynamic>) cb) {
    if (_onOrderStatus == cb) _onOrderStatus = null;
  }

  void removeOrderEtaListener(void Function(Map<String, dynamic>) cb) {
    if (_onOrderEta == cb) _onOrderEta = null;
  }

  static String get _resolvedHost {
    var host = AppConfig.socketUrl;
    try {
      if (!kIsWeb && Platform.isAndroid) {
        host = host.replaceFirst('localhost', '10.0.2.2');
      }
    } catch (_) {}
    return host;
  }

  void init(WidgetRef ref) {
    _ref = ref;
    _connect();
  }

  void initWithRef(Ref ref) {
    _ref = ref;
    _connect();
  }

  Future<void> _connect() async {
    if (AppConfig.demoMode || _socket != null || _connecting || _authBlocked) return;
    _connecting = true;

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) {
        _connecting = false;
        return;
      }

      final socket = io.io(
        _resolvedHost,
        io.OptionBuilder()
            .setTransports(['polling', 'websocket'])
            .enableAutoConnect()
            .enableReconnection()
            .enableForceNew()
            .enableForceNewConnection()
            .setReconnectionAttempts(double.infinity)
            .setReconnectionDelay(AppConfig.socketReconnectDelayMs)
            .setAuth({'token': token})
            .build(),
      );

      _socket = socket;
      _attachListeners(socket);
      _connecting = false;
    } catch (e) {
      _connecting = false;
      _socket = null;
      debugPrint('[SocketService] connection setup failed: $e');
    }
  }

  void _attachListeners(io.Socket socket) {
    socket.onConnect((_) {
      _authBlocked = false;
      if (AppConfig.enableNetworkLogs) {
        debugPrint('[SocketService] connected id=${socket.id}');
      }
      _restoreRooms(socket);
    });

    socket.onDisconnect((reason) {
      if (AppConfig.enableNetworkLogs) {
        debugPrint('[SocketService] disconnected: $reason');
      }
    });

    socket.onConnectError((err) {
      final message = err.toString();
      if (AppConfig.enableNetworkLogs) {
        debugPrint('[SocketService] connect error: $message');
      }
      if (_isAuthError(message)) {
        _authBlocked = true;
        socket.io.disconnect();
      }
    });

    socket.on('balance_update', (data) {
      try {
        final raw = _toMap(data);
        final balances = BalanceData(
          availableBalance: _toDouble(raw['availableBalance']),
          vendorUnallocatedBalance: _toDouble(raw['vendorUnallocatedBalance']),
          escrowLockedBalance: _toDouble(raw['escrowLockedBalance']),
          disputeEscrowBalance: _toDouble(raw['disputeEscrowBalance']),
          azmBalance: _toDouble(raw['azmBalance']),
        );
        _read(balanceDataProvider.notifier).state = balances;
        _read(userUsdcBalanceProvider.notifier).state =
            balances.availableBalance + balances.vendorUnallocatedBalance;
      } catch (e) {
        debugPrint('[SocketService] balance_update parse error: $e');
      }
    });

    socket.on('rate_update', (data) {
      try {
        final rate = _toDouble(_toMap(data)['rate']);
        if (rate > 0) _read(oracleRateProvider.notifier).state = rate;
      } catch (e) {
        debugPrint('[SocketService] rate_update parse error: $e');
      }
    });

    socket.on('deposit_success', (data) {
      try {
        final raw = _toMap(data);
        _onDepositSuccess?.call(
          _toDouble(raw['amountGhs']),
          _toDouble(raw['amountUsdc']),
          raw['provider']?.toString() ?? 'MOBILE_MONEY',
          raw['reference']?.toString() ?? '',
        );
      } catch (e) {
        debugPrint('[SocketService] deposit_success parse error: $e');
      }
    });

    socket.on('withdrawal_progress', (data) =>
        _safeMapCallback(_onWithdrawalProgress, data, 'withdrawal_progress'));
    socket.on('withdrawal_settled', (data) =>
        _safeMapCallback(_onWithdrawalSettled, data, 'withdrawal_settled'));

    socket.on('azm_reward', (data) => _handleAzmEvent(data, true));
    socket.on('azm_spend', (data) => _handleAzmEvent(data, false));

    socket.on('trade_update', (data) => _safeMapCallback(_onTradeUpdate, data, 'trade_update'));
    socket.on('market_update', (_) => _safeVoidCallback(_onMarketUpdate));
    socket.on('new_notification', (data) => _safeMapCallback(_onNewNotification, data, 'new_notification'));
    socket.on('notifications_updated', (data) => _safeMapCallback(_onNotificationsUpdated, data, 'notifications_updated'));
    socket.on('new_trade_request', (data) => _safeMapCallback(_onNewTradeRequest, data, 'new_trade_request'));
    socket.on('trade_completed', (data) => _safeMapCallback(_onTradeCompleted, data, 'trade_completed'));
    socket.on('biz_notification', (data) => _safeMapCallback(_onBizNotification, data, 'biz_notification'));
    socket.on('biz_notifications_updated', (data) {
      try {
        _onBizNotificationsUpdated?.call(_toInt(_toMap(data)['unreadCount']));
      } catch (e) {
        debugPrint('[SocketService] biz_notifications_updated parse error: $e');
      }
    });
    socket.on('business_order_delivered', (data) => _safeMapCallback(_onBusinessOrderDelivered, data, 'business_order_delivered'));
    socket.on('order_location', (data) => _safeMapCallback(_onOrderLocation, data, 'order_location'));
    socket.on('order_status', (data) => _safeMapCallback(_onOrderStatus, data, 'order_status'));
    socket.on('order_eta', (data) => _safeMapCallback(_onOrderEta, data, 'order_eta'));

    for (final event in const [
      'escrow_funded',
      'escrow_settled',
      'escrow_pending_settlement',
      'escrow_disputed',
      'escrow_resolved',
      'escrow_terms_updated',
      'invoice_paid',
    ]) {
      socket.on(event, (data) => _dispatchEscrow(data, event));
    }
  }

  void _handleAzmEvent(dynamic data, bool reward) {
    try {
      final raw = _toMap(data);
      final balance = _toDouble(raw['azmBalance']);
      final current = _read(balanceDataProvider);
      _read(balanceDataProvider.notifier).state = current.copyWith(azmBalance: balance);
      final amount = _toDouble(raw[reward ? 'awarded' : 'spent']);
      final source = raw['source']?.toString() ?? '';
      final reason = raw['reason']?.toString() ?? '';
      if (reward) {
        _onAzmReward?.call(balance, amount, source, reason);
      } else {
        _onAzmSpend?.call(balance, amount, source, reason);
      }
    } catch (e) {
      debugPrint('[SocketService] AZM event parse error: $e');
    }
  }

  void _restoreRooms(io.Socket socket) {
    if (_currentUserId != null) {
      socket.emit('join_user_room', {'userId': _currentUserId});
      socket.emit('join_balance_room', _currentUserId);
    }
    for (final id in _joinedTradeRooms) socket.emit('join_trade', id);
    for (final id in _joinedFriendRooms) {
      socket.emit('join_friend_chat', {'friendshipId': id, 'userId': _currentUserId});
    }
    for (final id in _joinedGroupRooms) {
      socket.emit('join_group', {'groupId': id, 'userId': _currentUserId});
    }
    for (final id in _joinedOrderRooms) socket.emit('join_order', {'orderId': id});
  }

  void joinTradeRoom(String tradeId) {
    final id = tradeId.replaceAll('#', '');
    if (!_joinedTradeRooms.add(id)) return;
    _socket?.emit('join_trade', id);
  }

  void leaveTradeRoom(String tradeId) => _joinedTradeRooms.remove(tradeId.replaceAll('#', ''));

  void joinFriendRoom(String friendshipId, String userId) {
    if (!_joinedFriendRooms.add(friendshipId)) return;
    _socket?.emit('join_friend_chat', {'friendshipId': friendshipId, 'userId': userId});
  }

  void leaveFriendRoom(String friendshipId, String userId) {
    _socket?.emit('leave_friend_chat', {'friendshipId': friendshipId, 'userId': userId});
    _joinedFriendRooms.remove(friendshipId);
  }

  void joinGroupRoom(String groupId, String userId) {
    if (!_joinedGroupRooms.add(groupId)) return;
    _socket?.emit('join_group', {'groupId': groupId, 'userId': userId});
  }

  void leaveGroupRoom(String groupId, String userId) {
    _socket?.emit('leave_group', {'groupId': groupId, 'userId': userId});
    _joinedGroupRooms.remove(groupId);
  }

  void joinOrderRoom(String orderId) {
    if (!_joinedOrderRooms.add(orderId)) return;
    _socket?.emit('join_order', {'orderId': orderId});
  }

  void leaveOrderRoom(String orderId) {
    _socket?.emit('leave_order', {'orderId': orderId});
    _joinedOrderRooms.remove(orderId);
  }

  void joinUserRoom(String userId) {
    _currentUserId = userId;
    _socket?.emit('join_user_room', {'userId': userId});
    _socket?.emit('join_balance_room', userId);
  }

  void leaveRoom(String roomId) => _socket?.emit('leave_room', {'roomId': roomId});

  void emit(String event, dynamic data) {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      if (AppConfig.enableNetworkLogs) debugPrint('[SocketService] emit skipped: $event');
      return;
    }
    socket.emit(event, data);
  }

  Future<void> forceReconnect() async {
    final socket = _socket;
    if (socket != null) {
      socket.offAny();
      socket.disconnect();
      socket.dispose();
    }
    _socket = null;
    _connecting = false;
    _authBlocked = false;
    await _connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _ref = null;
    _connecting = false;
    _authBlocked = false;
    _currentUserId = null;
    _joinedTradeRooms.clear();
    _joinedFriendRooms.clear();
    _joinedGroupRooms.clear();
    _joinedOrderRooms.clear();
    _clearCallbacks();
  }

  void _clearCallbacks() {
    _onAzmReward = null;
    _onAzmSpend = null;
    _onTradeUpdate = null;
    _onMarketUpdate = null;
    _onNewNotification = null;
    _onNotificationsUpdated = null;
    _onNewTradeRequest = null;
    _onTradeCompleted = null;
    _onBizNotification = null;
    _onBizNotificationsUpdated = null;
    _onBusinessOrderDelivered = null;
    _onOrderLocation = null;
    _onOrderStatus = null;
    _onOrderEta = null;
    _onEscrowEvent = null;
    _onDepositSuccess = null;
    _onWithdrawalProgress = null;
    _onWithdrawalSettled = null;
  }

  bool get isConnected => _socket?.connected ?? false;
  io.Socket? get rawSocket => _socket;
  io.Socket? get socket => _socket;
  String? get userId => _currentUserId;
  int get userIdInt => int.tryParse(_currentUserId ?? '0') ?? 0;

  bool _isAuthError(String value) {
    final lower = value.toLowerCase();
    return lower.contains('authentication failed') ||
        lower.contains('token expired') ||
        lower.contains('token superseded') ||
        lower.contains('banned') ||
        lower.contains('no longer exists');
  }

  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const FormatException('Expected map payload');
  }

  dynamic _read(dynamic provider) => _ref.read(provider);

  void _dispatchEscrow(dynamic data, String event) {
    try {
      _onEscrowEvent?.call(_toMap(data), event);
    } catch (e) {
      debugPrint('[SocketService] $event error: $e');
    }
  }

  void _safeMapCallback(void Function(Map<String, dynamic>)? cb, dynamic data, String event) {
    try {
      cb?.call(_toMap(data));
    } catch (e) {
      debugPrint('[SocketService] $event error: $e');
    }
  }

  void _safeVoidCallback(void Function()? cb) {
    try {
      cb?.call();
    } catch (e) {
      debugPrint('[SocketService] callback error: $e');
    }
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
