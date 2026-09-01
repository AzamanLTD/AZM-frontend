import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:azaman/services/push_notification_service.dart';

typedef FirebaseInitializer = Future<bool> Function();
typedef PushInitializer = Future<bool> Function({
  required void Function(Map<String, dynamic> data) onNotificationTap,
  required void Function(RemoteMessage message) onForegroundMessage,
});

/// Coordinates non-critical application hydration after the first frame.
///
/// Startup work is deliberately idempotent so concurrent callers share one
/// initialization attempt. A failed attempt is discarded so a later lifecycle
/// re-entry can retry transient Firebase/push failures. The coordinator does
/// not own UI state; callers provide callbacks for notification
/// presentation/navigation.
class StartupCoordinator {
  StartupCoordinator._({
    FirebaseInitializer? firebaseInitializer,
    PushInitializer? pushInitializer,
  })  : _firebaseInitializer = firebaseInitializer ?? _initializeFirebase,
        _pushInitializer = pushInitializer ?? _initializePush;

  @visibleForTesting
  StartupCoordinator.test({
    FirebaseInitializer? firebaseInitializer,
    PushInitializer? pushInitializer,
  }) : this._(
          firebaseInitializer: firebaseInitializer,
          pushInitializer: pushInitializer,
        );

  static final StartupCoordinator instance = StartupCoordinator._();

  final FirebaseInitializer _firebaseInitializer;
  final PushInitializer _pushInitializer;

  Future<void>? _running;
  bool _firebaseReady = false;
  bool _pushReady = false;

  /// Registers the FCM background callback at the earliest safe point.
  /// Firebase itself and foreground push setup remain post-frame so they do
  /// not delay first paint.
  static void registerBackgroundMessageHandler() {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  Future<void> start({
    required void Function(Map<String, dynamic> data) onNotificationTap,
    required void Function(RemoteMessage message) onForegroundMessage,
  }) {
    final running = _running;
    if (running != null) return running;

    final attempt = _start(
      onNotificationTap: onNotificationTap,
      onForegroundMessage: onForegroundMessage,
    );
    _running = attempt;

    attempt.whenComplete(() {
      if (identical(_running, attempt) && (!_firebaseReady || !_pushReady)) {
        _running = null;
      }
    });

    return attempt;
  }

  Future<void> _start({
    required void Function(Map<String, dynamic> data) onNotificationTap,
    required void Function(RemoteMessage message) onForegroundMessage,
  }) async {
    try {
      _firebaseReady = await _firebaseInitializer();
      if (!_firebaseReady) return;

      _pushReady = await _pushInitializer(
        onNotificationTap: onNotificationTap,
        onForegroundMessage: onForegroundMessage,
      );
    } catch (e, stack) {
      debugPrint('[Startup] post-frame initialization failed: $e\n$stack');
    }
  }

  static Future<bool> _initializeFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      return true;
    } catch (e) {
      debugPrint('[Startup] Firebase init failed: $e');
      return false;
    }
  }

  static Future<bool> _initializePush({
    required void Function(Map<String, dynamic> data) onNotificationTap,
    required void Function(RemoteMessage message) onForegroundMessage,
  }) async {
    final push = PushNotificationService.instance;
    // Install callbacks before init so getInitialMessage() can deliver a
    // cold-start notification tap to the UI instead of dropping it.
    push.onNotificationTap = onNotificationTap;
    push.onForegroundMessage = onForegroundMessage;
    await push.init();
    return true;
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
