import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/models/notification_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/socket_service.dart';

class NotificationNotifier extends StateNotifier<List<AppNotification>> {
  final Ref _ref;

  NotificationNotifier(this._ref) : super([]) {
    _initSocketListener();
    fetchNotifications();
  }

  /// Listen for real-time notifications via the unified SocketService.
  ///
  /// Phase P3 (2026-05-25): Migrated from TradeProvider's socket to
  /// SocketService callbacks. Two distinct event channels:
  ///   - `new_notification`  → a brand-new notification arriving (BE
  ///     calls `notificationService.sendNotification`).
  ///   - `notifications_updated`  → state-of-existing-notifications
  ///     changed (Phase B2, BE PR #50). Emitted after `markAsRead`
  ///     and `markAllAsRead`. Lets other open sessions of the same
  ///     user (web + phone) stay in sync without pull-to-refresh.
  ///     Two subtypes: `MARKED_READ` (single id) and `MARKED_ALL_READ`.
  void _initSocketListener() {
    final socketService = _ref.read(socketServiceProvider);
    socketService.onNewNotification(_handleNewNotification);
    socketService.onNotificationsUpdated(_handleNotificationsUpdated);
  }

  void _handleNewNotification(Map<String, dynamic> data) {
    try {
      final notification = AppNotification.fromJson(data);
      addNotification(notification);
    } catch (e) {
      debugPrint('[NotificationProvider] new_notification parse error: $e');
    }
  }

  void _handleNotificationsUpdated(Map<String, dynamic> raw) {
    try {
      final type = raw['type']?.toString();
      if (type == 'MARKED_READ') {
        final id = raw['notificationId']?.toString();
        if (id != null && id.isNotEmpty) {
          _applyMarkAsReadLocal(id);
        }
      } else if (type == 'MARKED_ALL_READ') {
        _applyMarkAllAsReadLocal();
      }
    } catch (e) {
      debugPrint('[NotificationProvider] notifications_updated parse error: $e');
    }
  }

  @override
  void dispose() {
    final socketService = _ref.read(socketServiceProvider);
    socketService.removeNewNotificationListener(_handleNewNotification);
    socketService.removeNotificationsUpdatedListener(_handleNotificationsUpdated);
    super.dispose();
  }

  /// Fetch notifications from the backend API.
  Future<void> fetchNotifications() async {
    try {
      final auth = _ref.read(authProvider);
      final token = auth.user?.token;
      if (token == null || token.isEmpty) return;

      final response = await apiClient.get('/notifications?limit=50');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List notificationsJson = body['notifications'] ?? [];

        state = notificationsJson
            .map<AppNotification>((json) => AppNotification.fromJson(
                  json is Map<String, dynamic>
                      ? json
                      : Map<String, dynamic>.from(json),
                ))
            .toList();

        debugPrint('[NotificationProvider] Fetched ${state.length} notifications');
      } else {
        debugPrint('[NotificationProvider] Fetch failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[NotificationProvider] Fetch error: $e');
    }
  }

  /// User-initiated mark-as-read. Updates local state optimistically
  /// then fires the API call. The BE will emit a `notifications_updated`
  /// event back to this user's socket room; the resulting echo is a
  /// no-op because `_applyMarkAsReadLocal` is idempotent.
  void markAsRead(String id) {
    _applyMarkAsReadLocal(id);
    _markAsReadOnServer(id);
  }

  Future<void> _markAsReadOnServer(String id) async {
    try {
      final auth = _ref.read(authProvider);
      final token = auth.user?.token;
      if (token == null) return;

      await apiClient.patch('/notifications/$id/read');
    } catch (e) {
      debugPrint('[NotificationProvider] markAsRead API error: $e');
    }
  }

  /// User-initiated mark-all-as-read. Same optimistic + server-call +
  /// socket-echo-is-idempotent pattern as `markAsRead`. Returns the
  /// number of rows that were actually flipped on the server (best-
  /// effort — returns null if the call failed so callers can decide
  /// whether to show an error banner).
  Future<int?> markAllAsRead() async {
    final unreadCount = state.where((n) => !n.isRead).length;
    if (unreadCount == 0) return 0;

    _applyMarkAllAsReadLocal();
    return _markAllAsReadOnServer();
  }

  Future<int?> _markAllAsReadOnServer() async {
    try {
      final auth = _ref.read(authProvider);
      final token = auth.user?.token;
      if (token == null) return null;

      final response = await apiClient.patch('/notifications/read-all');

      if (response.statusCode == 200) {
        try {
          final body = jsonDecode(response.body);
          final updated = body['updated'];
          if (updated is int) return updated;
          if (updated is num) return updated.toInt();
        } catch (_) {
          // Fall through: a 200 with a non-numeric body is still a
          // success from our side; we already updated local state.
        }
        return state.length;
      }
      debugPrint('[NotificationProvider] markAllAsRead failed: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[NotificationProvider] markAllAsRead API error: $e');
      return null;
    }
  }

  /// Local-state mutation, used by both the user-initiated path and
  /// the socket-echo path. Idempotent: calling it on an already-read
  /// notification is a no-op.
  void _applyMarkAsReadLocal(String id) {
    var changed = false;
    final next = state.map((n) {
      if (n.id == id && !n.isRead) {
        changed = true;
        return n.copyWith(isRead: true);
      }
      return n;
    }).toList();
    if (changed) state = next;
  }

  /// Same as `_applyMarkAsReadLocal` but for the bulk path.
  void _applyMarkAllAsReadLocal() {
    final hasAnyUnread = state.any((n) => !n.isRead);
    if (!hasAnyUnread) return;
    state = state.map((n) => n.isRead ? n : n.copyWith(isRead: true)).toList();
  }

  void addNotification(AppNotification notification) {
    // Dedup: don't add if we already have this id
    if (state.any((n) => n.id == notification.id)) return;
    state = [notification, ...state];
  }

  void removeNotification(String id) {
    state = state.where((n) => n.id != id).toList();
  }

  void deleteNotification(String id) {
    removeNotification(id);
  }

  /// Refresh notifications from the backend (pull-to-refresh).
  Future<void> refresh() async {
    await fetchNotifications();
  }
}

final notificationProvider =
    StateNotifierProvider<NotificationNotifier, List<AppNotification>>((ref) {
  return NotificationNotifier(ref);
});

final unreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificationProvider)
      .where((n) => !n.isRead && n.category != NotificationCategory.general)
      .length;
});

final generalNotificationsProvider = Provider<List<AppNotification>>((ref) {
  return ref.watch(notificationProvider)
      .where((n) => n.category == NotificationCategory.general).toList();
});

final securityNotificationsProvider = Provider<List<AppNotification>>((ref) {
  return ref.watch(notificationProvider)
      .where((n) => n.category == NotificationCategory.securityAccount).toList();
});

final vendorNotificationsProvider = Provider<List<AppNotification>>((ref) {
  return ref.watch(notificationProvider)
      .where((n) => n.category == NotificationCategory.vendorPriority).toList();
});

final adminNotificationsProvider = Provider<List<AppNotification>>((ref) {
  return ref.watch(notificationProvider)
      .where((n) => n.category == NotificationCategory.adminSystem).toList();
});

// ── New category providers (used by notification_hub_screen) ──────────────────
final moneyNotificationsProvider = Provider<List<AppNotification>>((ref) {
  return ref.watch(notificationProvider)
      .where((n) => n.category == NotificationCategory.money).toList();
});

final socialNotificationsProvider = Provider<List<AppNotification>>((ref) {
  return ref.watch(notificationProvider)
      .where((n) => n.category == NotificationCategory.social).toList();
});

final chatNotificationsProvider = Provider<List<AppNotification>>((ref) {
  return ref.watch(notificationProvider)
      .where((n) => n.category == NotificationCategory.chat).toList();
});

final systemNotificationsProvider = Provider<List<AppNotification>>((ref) {
  return ref.watch(notificationProvider)
      .where((n) =>
        n.category == NotificationCategory.system ||
        n.category == NotificationCategory.adminSystem ||
        n.category == NotificationCategory.vendorPriority
      ).toList();
});
