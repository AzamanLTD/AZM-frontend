import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/marketplace_search_provider.dart';
import 'package:azaman/services/business_service.dart';

class _RecordingSearch extends BusinessSearchNotifier {
  _RecordingSearch() : super(BusinessService());
  final List<(String, String?)> calls = [];

  @override
  Future<void> search(String query,
      {String? category, bool? verified, String? subcategory}) async {
    calls.add((query, category));
  }
}

void main() {
  late ProviderContainer container;
  late _RecordingSearch backend;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = _RecordingSearch();
    container = ProviderContainer(overrides: [
      businessSearchProvider.overrideWith((_) => backend),
    ]);
  });

  tearDown(() => container.dispose());

  MarketplaceSearchNotifier n() => container.read(marketplaceSearchProvider.notifier);
  MarketplaceSearchState s() => container.read(marketplaceSearchProvider);

  test('starts idle in marketplace scope', () {
    expect(s().scope, MarketplaceSearchScope.marketplace);
    expect(s().isActive, isFalse);
  });

  test('focus and text make the search active', () {
    n().focus(true);
    expect(s().isActive, isTrue);
    n().focus(false);
    expect(s().isActive, isFalse);
    n().changed('jollof');
    expect(s().isActive, isTrue);
  });

  test('submit records the recent search (newest first, deduped, capped at 8)', () async {
    for (final q in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'a']) {
      n().changed(q);
      await n().submit();
    }
    expect(s().recent.first, 'a');
    expect(s().recent.length, MarketplaceSearchNotifier.kMaxRecent);
    expect(s().recent.where((r) => r == 'a').length, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(MarketplaceSearchNotifier.kRecentKey), s().recent);
  });

  test('submit fetches through businessSearchProvider with the world as category', () async {
    n().setScope(MarketplaceSearchScope.world, worldWire: 'FOOD_BEVERAGE');
    n().changed('waakye');
    await n().submit();
    expect(backend.calls, [('waakye', 'FOOD_BEVERAGE')]);
  });

  test('submit(fetch: false) only does the bookkeeping', () async {
    n().changed('waakye');
    await n().submit(fetch: false);
    expect(backend.calls, isEmpty);
    expect(s().recent, ['waakye']);
    expect(s().focused, isFalse);
  });

  test('store scope never fetches', () async {
    n().setScope(MarketplaceSearchScope.store, worldWire: 'RETAIL', storeBizId: 'BIZ-1');
    n().changed('shoes');
    await n().submit();
    expect(backend.calls, isEmpty);
  });

  test('empty submit is a no-op', () async {
    n().changed('   ');
    await n().submit();
    expect(backend.calls, isEmpty);
    expect(s().recent, isEmpty);
  });

  test('changing scope clears the typed text', () {
    n().changed('pizza');
    n().setScope(MarketplaceSearchScope.world, worldWire: 'RETAIL');
    expect(s().text, '');
    expect(s().worldWire, 'RETAIL');
    expect(s().isActive, isFalse);
  });

  test('clear resets text and focus but keeps scope', () {
    n().setScope(MarketplaceSearchScope.world, worldWire: 'RETAIL');
    n().changed('bag');
    n().focus(true);
    n().clear();
    expect(s().text, '');
    expect(s().focused, isFalse);
    expect(s().scope, MarketplaceSearchScope.world);
    expect(s().worldWire, 'RETAIL');
  });

  test('suggestions: short text → recents, longer text → matching categories', () async {
    n().changed('hotel');
    await n().submit();
    n().changed('h');
    expect(s().suggestions, ['hotel']);
    n().changed('rest');
    expect(s().suggestions, contains('Restaurants'));
  });

  test('loads persisted recents on construction', () async {
    SharedPreferences.setMockInitialValues({
      MarketplaceSearchNotifier.kRecentKey: ['kelewele'],
    });
    final c = ProviderContainer(overrides: [
      businessSearchProvider.overrideWith((_) => _RecordingSearch()),
    ]);
    addTearDown(c.dispose);
    c.read(marketplaceSearchProvider);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(marketplaceSearchProvider).recent, ['kelewele']);
  });
}