import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/services/socket_service.dart';

void main() {
  late SocketService socket;

  setUp(() {
    socket = SocketService.instance;
    socket.removeNewTradeRequestListener();
    socket.removeBizNotificationListener();
    socket.removeBizNotificationsUpdatedListener();
  });

  tearDown(() {
    socket.removeNewTradeRequestListener();
    socket.removeBizNotificationListener();
    socket.removeBizNotificationsUpdatedListener();
  });

  test('removing new trade request listener stops dispatch', () {
    var calls = 0;
    socket.onNewTradeRequest((_) => calls++);

    expect(socket.hasNewTradeRequestListener, isTrue);
    socket.dispatchTestEvent('new_trade_request', {'tradeId': 'trade-1'});
    expect(calls, 1);

    socket.removeNewTradeRequestListener();

    expect(socket.hasNewTradeRequestListener, isFalse);
    socket.dispatchTestEvent('new_trade_request', {'tradeId': 'trade-2'});
    expect(calls, 1);
  });

  test('removing business notification listener stops dispatch', () {
    var calls = 0;
    socket.onBizNotification((_) => calls++);

    expect(socket.hasBizNotificationListener, isTrue);
    socket.dispatchTestEvent('biz_notification', {'notificationId': 'notification-1'});
    expect(calls, 1);

    socket.removeBizNotificationListener();

    expect(socket.hasBizNotificationListener, isFalse);
    socket.dispatchTestEvent('biz_notification', {'notificationId': 'notification-2'});
    expect(calls, 1);
  });

  test('removing business notification count listener stops dispatch', () {
    var calls = 0;
    socket.onBizNotificationsUpdated((_) => calls++);

    expect(socket.hasBizNotificationsUpdatedListener, isTrue);
    socket.dispatchTestEvent('biz_notifications_updated', {'unreadCount': 3});
    expect(calls, 1);

    socket.removeBizNotificationsUpdatedListener();

    expect(socket.hasBizNotificationsUpdatedListener, isFalse);
    socket.dispatchTestEvent('biz_notifications_updated', {'unreadCount': 4});
    expect(calls, 1);
  });
}
