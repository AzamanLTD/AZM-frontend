import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/services/escrow_subscription_registry.dart';

void main() {
  late List<EscrowEventCallback> sourceListeners;
  late EscrowSubscriptionRegistry registry;

  setUp(() {
    sourceListeners = <EscrowEventCallback>[];
    registry = EscrowSubscriptionRegistry(
      addSourceListener: sourceListeners.add,
      removeSourceListener: sourceListeners.remove,
    );
  });

  tearDown(() => registry.dispose());

  void emit(String ticketId, String event) {
    final snapshot = List<EscrowEventCallback>.of(sourceListeners);
    final payload = <String, dynamic>{'ticketId': ticketId};
    for (final listener in snapshot) {
      listener(payload, event);
    }
  }

  test('routes events only to the matching ticket subscriber', () {
    final ticketA = <String>[];
    final ticketB = <String>[];

    registry.subscribe(
      ticketId: 'ticket-a',
      onEvent: (_, event) => ticketA.add(event),
    );
    registry.subscribe(
      ticketId: 'ticket-b',
      onEvent: (_, event) => ticketB.add(event),
    );

    expect(registry.subscriptionCount, 2);
    expect(sourceListeners, hasLength(1));

    emit('ticket-a', 'escrow_settled');
    emit('ticket-b', 'escrow_disputed');

    expect(ticketA, <String>['escrow_settled']);
    expect(ticketB, <String>['escrow_disputed']);
  });

  test('unsubscribe is exact and preserves other subscribers', () {
    var ticketACalls = 0;
    var ticketBCalls = 0;

    final unsubscribeA = registry.subscribe(
      ticketId: 'ticket-a',
      onEvent: (_, __) => ticketACalls++,
    );
    registry.subscribe(
      ticketId: 'ticket-b',
      onEvent: (_, __) => ticketBCalls++,
    );

    unsubscribeA();
    unsubscribeA();

    expect(registry.subscriptionCount, 1);
    expect(sourceListeners, hasLength(1));

    emit('ticket-a', 'escrow_funded');
    emit('ticket-b', 'escrow_funded');

    expect(ticketACalls, 0);
    expect(ticketBCalls, 1);
  });

  test('detaches from the global source after the final unsubscribe', () {
    final unsubscribe = registry.subscribe(
      ticketId: 'ticket-a',
      onEvent: (_, __) {},
    );

    expect(sourceListeners, hasLength(1));

    unsubscribe();

    expect(registry.hasSubscriptions, isFalse);
    expect(sourceListeners, isEmpty);
  });

  test('invalid ticket ids are rejected without attaching a source listener', () {
    expect(
      () => registry.subscribe(ticketId: '  ', onEvent: (_, __) {}),
      throwsArgumentError,
    );
    expect(sourceListeners, isEmpty);
  });

  test('missing ticket ids and unsupported events are ignored safely', () {
    var calls = 0;
    registry.subscribe(
      ticketId: 'ticket-a',
      onEvent: (_, __) => calls++,
    );

    final source = sourceListeners.single;
    source(<String, dynamic>{}, 'escrow_settled');
    source(<String, dynamic>{'ticketId': 'ticket-a'}, 'other_event');

    expect(calls, 0);
  });

  test('one throwing subscriber does not block another subscriber', () {
    var healthyCalls = 0;
    registry.subscribe(
      ticketId: 'ticket-a',
      onEvent: (_, __) => throw StateError('broken subscriber'),
    );
    registry.subscribe(
      ticketId: 'ticket-a',
      onEvent: (_, __) => healthyCalls++,
    );

    emit('ticket-a', 'escrow_refunded');

    expect(healthyCalls, 1);
  });

  test('normalizes surrounding ticket whitespace before matching', () {
    var calls = 0;
    registry.subscribe(
      ticketId: ' ticket-a ',
      onEvent: (_, __) => calls++,
    );

    emit('ticket-a', 'escrow_terms_updated');

    expect(calls, 1);
  });
}
