import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/marketplace_world_memory_provider.dart';

void main() {
  late DateTime now;
  late WorldMemoryNotifier n;

  setUp(() {
    now = DateTime(2026, 10, 4, 12, 0);
    n = WorldMemoryNotifier(clock: () => now);
  });

  test('remember then recall within freshness window', () {
    n.remember('RETAIL', query: 'shoes', scrollOffset: 420);
    final m = n.recall('RETAIL')!;
    expect(m.query, 'shoes');
    expect(m.scrollOffset, 420);
  });

  test('remember merges partial updates', () {
    n.remember('RETAIL', query: 'shoes');
    n.remember('RETAIL', scrollOffset: 100);
    expect(n.recall('RETAIL')!.query, 'shoes');
    expect(n.recall('RETAIL')!.scrollOffset, 100);
  });

  test('memory expires after 30 minutes', () {
    n.remember('RETAIL', query: 'shoes');
    now = now.add(const Duration(minutes: 29));
    expect(n.recall('RETAIL'), isNotNull);
    now = now.add(const Duration(minutes: 2));
    expect(n.recall('RETAIL'), isNull);
    expect(n.mostRecentWire(), isNull);
  });

  test('mostRecentWire picks the latest fresh world', () {
    n.remember('RETAIL');
    now = now.add(const Duration(minutes: 1));
    n.remember('FOOD_BEVERAGE');
    expect(n.mostRecentWire(), 'FOOD_BEVERAGE');
  });

  test('forget removes a world; unknown world is a no-op', () {
    n.remember('RETAIL');
    n.forget('RETAIL');
    n.forget('NOPE');
    expect(n.recall('RETAIL'), isNull);
    expect(n.state, isEmpty);
  });
}