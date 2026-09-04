import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/services/socket_service.dart';

void main() {
  setUp(() {
    SocketService.instance.disconnect();
  });

  tearDown(() {
    SocketService.instance.disconnect();
  });

  test('dispatches customer dine-in lifecycle events only to registered listeners', () {
    final socket = SocketService.instance;
    final received = <Map<String, dynamic>>[];
    void listener(Map<String, dynamic> payload) => received.add(payload);

    socket.onDineInTabEvent(listener);
    socket.dispatchTestEvent('dine_in_tab_finalized', {
      'tabId': 'tab-123',
      'totalAmount': 42.5,
    });

    expect(received, hasLength(1));
    expect(received.single['tabId'], 'tab-123');
    expect(received.single['totalAmount'], 42.5);

    socket.removeDineInTabEventListener(listener);
    socket.dispatchTestEvent('dine_in_tab_paid', {'tabId': 'tab-123'});
    expect(received, hasLength(1));
  });

  test('malformed customer dine-in payloads do not escape the socket boundary', () {
    final socket = SocketService.instance;
    final received = <Map<String, dynamic>>[];
    socket.onDineInTabEvent(received.add);

    socket.dispatchTestEvent('dine_in_item_added', 'not-a-map');

    expect(received, isEmpty);
  });
}
