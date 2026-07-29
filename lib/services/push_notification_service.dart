// lib/services/push_notification_service.dart
//
// Phase 15: centralised Firebase Cloud Messaging integration.
//
// Responsibilities:
//   1. Request OS notification permissions (iOS + Android 13+).
//   2. Fetch and refresh the device FCM token, then POST it to the
//      backend so server.js can push notifications when a recipient is
//      offline. (Backend route: PUT /api/auth/fcm-token.)
//   3. Wire foreground, tapped-from-background, and launched-from-terminated
//      message handlers so trade / chat notifications can deep-link.
//
// The background isolate handler (_firebaseMessagingBackgroundHandler)
// is defined in main.dart because it must be a top-level annotated
// function registered before runApp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:azaman/services/api_client.dart';

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  bool _initialized = false;

  /// Deep-link callback invoked when the user taps a notification that
  /// carries a `tradeId` in its data payload. Wire this from main.dart to
  /// navigate to the correct trade screen.
  void Function(Map<String, dynamic> data)? onNotificationTap;

  /// Foreground banner callback: the app is running, a notification just
  /// arrived, and we want to surface an in-app toast/snackbar instead of
  /// the OS chrome. Consumer supplies the UI.
  void Function(RemoteMessage message)? onForegroundMessage;

  /// Call once from main.dart after Firebase.initializeApp and before
  /// runApp(). Idempotent.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint(
          '🔔 [Push] permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      // iOS foreground presentation (noop on Android but cheap to call).
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen(_handleForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpened);

      // Cold start: app launched by tapping a notification.
      final RemoteMessage? initial = await _messaging.getInitialMessage();
      if (initial != null) _handleOpened(initial);

      // Proactively log token refreshes — the backend picks up the new
      // token via the next syncToken() call (e.g. after login).
      _messaging.onTokenRefresh.listen((token) {
        debugPrint('🔁 [Push] token refreshed: ${token.substring(0, 12)}...');
      });
    } catch (e) {
      debugPrint('⚠️ [Push] init failed: $e');
    }
  }

  /// Fetch the current FCM token and upload it to the backend. Called
  /// from AuthProvider.setUser after login, and safe to call again on
  /// token refresh.
  Future<String?> syncToken(String authToken) async {
    try {
      final fcmToken = await _messaging.getToken();
      if (fcmToken == null) return null;

      final res = await apiClient.put('/auth/fcm-token', {'fcmToken': fcmToken});

      if (res.statusCode == 200) {
        debugPrint('✅ [Push] FCM token synced with server');
      } else {
        debugPrint(
            '⚠️ [Push] token sync failed (${res.statusCode}): ${res.body}');
      }
      return fcmToken;
    } on ApiException catch (e) {
      debugPrint('⚠️ [Push] syncToken error: $e');
      return null;
    } catch (e) {
      debugPrint('⚠️ [Push] syncToken error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal handlers
  // ---------------------------------------------------------------------------

  void _handleForeground(RemoteMessage message) {
    debugPrint(
        '📨 [Push] foreground: ${message.notification?.title} / ${message.data}');
    HapticFeedback.lightImpact();
    onForegroundMessage?.call(message);
  }

  void _handleOpened(RemoteMessage message) {
    debugPrint('🪝 [Push] opened: ${message.data}');
    final data = <String, dynamic>{};
    message.data.forEach((k, v) => data[k] = v);
    onNotificationTap?.call(data);
  }
}
