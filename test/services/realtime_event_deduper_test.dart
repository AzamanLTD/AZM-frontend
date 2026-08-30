import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/services/realtime_event_deduper.dart';

void main() {
  group('RealtimeEventDeduper', () {
    test('accepts an event once and rejects duplicate delivery', () {
      final deduper = RealtimeEventDeduper();

      expect(deduper.accept('notification-1'), isTrue);
      expect(deduper.accept('notification-1'), isFalse);
      expect(deduper.length, 1);
    });

    test('accepts missing identifiers because identity is unavailable', () {
      final deduper = RealtimeEventDeduper();

      expect(deduper.accept(null), isTrue);
      expect(deduper.accept(''), isTrue);
      expect(deduper.accept('   '), isTrue);
      expect(deduper.length, 0);
    });

    test('evicts the oldest identifier when the bounded cache is full', () {
      final deduper = RealtimeEventDeduper(maxEntries: 2);

      expect(deduper.accept('one'), isTrue);
      expect(deduper.accept('two'), isTrue);
      expect(deduper.accept('three'), isTrue);
      expect(deduper.length, 2);

      // 'one' was evicted, so it is accepted again. The cache now contains
      // 'three' and 'one', while 'three' remains a duplicate.
      expect(deduper.accept('one'), isTrue);
      expect(deduper.accept('three'), isFalse);
    });

    test('clear resets the session cache', () {
      final deduper = RealtimeEventDeduper(maxEntries: 2);

      expect(deduper.accept('notification-1'), isTrue);
      deduper.clear();

      expect(deduper.length, 0);
      expect(deduper.accept('notification-1'), isTrue);
    });
  });
}
