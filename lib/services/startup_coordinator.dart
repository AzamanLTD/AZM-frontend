import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:azaman/services/push_notification_service.dart';

/// Coordinates non-critical application hydration after the first frame.
///
/// Startup work is deliberately idempotent so a lifecycle re-entry cannot
/// initialize the same subsystem twice. The coordinator does not own UI
/// state; callers provide callbacks for notification presentation/navigation.
class StartupCoordinator {
  StartupCoordinator._();

  static final StartupCoordinator instance = StartupCoordinator._();

  Future<void>? _running;
  bool _firebaseReady = false;
  bool _pushReady = false;

  Future<void> start({
    required void Function(Map<String, dynamic> data) onNotificationTap,
    required void Function(RemoteMessage message) onForegroundMessage,
  }) {
    return _running ??= _start(
      onNotificationTap: onNotificationTap,
      onForegroundMessage: onForegroundMessage,
    );
  }

  Future<void> _start({
    required void Function(Map<String, dynamic> data) onNotificationTap,
    required void Function(RemoteMessage message) onForegroundMessage,
  }) async {
    try {
      await _initFirebase();
      if (!_firebaseReady) return;

      await _initPush(
        onNotificationTap: onNotificationTap,
        onForegroundMessage: onForegroundMessage,
      );
    } catch (e, stack) {
      debugPrint('[Startup] post-frame initialization failed: $e\n$stack');
    }
  }

  Future<void> _initFirebase() async {
    if (_firebaseReady) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      _firebaseReady = true;
    } catch (e) {
      debugPrint('[Startup] Firebase init failed: $e');
    }
  }

  Future<void> _initPush({
    required void Function(Map<String, dynamic> data) onNotificationTap,
    required void Function(RemoteMessage message) onForegroundMessage,
  }) async {
    if (_pushReady) return;

    await PushNotificationService.instance.init();
    PushNotificationService.instance.onNotificationTap = onNotificationTap;
    PushNotificationService.instance.onForegroundMessage = onForegroundMessage;
    _pushReady = true;
  }

  /// Runs lower-priority network hydration without delaying first paint.
  Future<void> hydrateBusinessState({
    required Future<void> Function() loadBusiness,
    required Future<void> Function() loadUnreadCount,
    required bool Function() isMounted,
  }) async {
    try {
      await loadBusiness();
      if (!isMounted()) return;
      await loadUnreadCount();
    } catch (e) {
      debugPrint('[Startup] business hydration failed: $e');
    }
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM] Background message: ${message.messageId}');
}
