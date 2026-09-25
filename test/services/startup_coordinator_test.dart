import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/services/startup_coordinator.dart';

void main() {
  void onNotificationTap(Map<String, dynamic> _) {}
  void onForegroundMessage(RemoteMessage _) {}

  test('shares a successful initialization attempt with concurrent callers', () async {
    var firebaseCalls = 0;
    var pushCalls = 0;

    final coordinator = StartupCoordinator.test(
      firebaseInitializer: () async {
        firebaseCalls++;
        await Future<void>.delayed(Duration.zero);
        return true;
      },
      pushInitializer: ({
        required onNotificationTap,
        required onForegroundMessage,
      }) async {
        pushCalls++;
        await Future<void>.delayed(Duration.zero);
        return true;
      },
    );

    final first = coordinator.start(
      onNotificationTap: onNotificationTap,
      onForegroundMessage: onForegroundMessage,
    );
    final second = coordinator.start(
      onNotificationTap: onNotificationTap,
      onForegroundMessage: onForegroundMessage,
    );

    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);

    expect(firebaseCalls, 1);
    expect(pushCalls, 1);
  });

  test('allows a later start to retry after Firebase initialization fails', () async {
    var firebaseCalls = 0;
    var pushCalls = 0;

    final coordinator = StartupCoordinator.test(
      firebaseInitializer: () async {
        firebaseCalls++;
        if (firebaseCalls == 1) return false;
        return true;
      },
      pushInitializer: ({
        required onNotificationTap,
        required onForegroundMessage,
      }) async {
        pushCalls++;
        return true;
      },
    );

    await coordinator.start(
      onNotificationTap: onNotificationTap,
      onForegroundMessage: onForegroundMessage,
    );
    await coordinator.start(
      onNotificationTap: onNotificationTap,
      onForegroundMessage: onForegroundMessage,
    );

    expect(firebaseCalls, 2);
    expect(pushCalls, 1);
  });

  test('allows a later start to retry after push initialization fails', () async {
    var firebaseCalls = 0;
    var pushCalls = 0;

    final coordinator = StartupCoordinator.test(
      firebaseInitializer: () async => true,
      pushInitializer: ({
        required onNotificationTap,
        required onForegroundMessage,
      }) async {
        pushCalls++;
        if (pushCalls == 1) {
          throw StateError('transient push failure');
        }
        return true;
      },
    );

    await coordinator.start(
      onNotificationTap: onNotificationTap,
      onForegroundMessage: onForegroundMessage,
    );
    await coordinator.start(
      onNotificationTap: onNotificationTap,
      onForegroundMessage: onForegroundMessage,
    );

    expect(pushCalls, 2);
  });

  test('does not repeat initialization after a successful attempt', () async {
    var firebaseCalls = 0;
    var pushCalls = 0;

    final coordinator = StartupCoordinator.test(
      firebaseInitializer: () async {
        firebaseCalls++;
        return true;
      },
      pushInitializer: ({
        required onNotificationTap,
        required onForegroundMessage,
      }) async {
        pushCalls++;
        return true;
      },
    );

    await coordinator.start(
      onNotificationTap: onNotificationTap,
      onForegroundMessage: onForegroundMessage,
    );
    await coordinator.start(
      onNotificationTap: onNotificationTap,
      onForegroundMessage: onForegroundMessage,
    );

    expect(firebaseCalls, 1);
    expect(pushCalls, 1);
  });
}
