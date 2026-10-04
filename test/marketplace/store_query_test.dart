import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/store_query.dart';

void main() {
  test('empty or whitespace query matches everything', () {
    expect(matchesStoreQuery('', name: 'x'), isTrue);
    expect(matchesStoreQuery('   ', name: 'x'), isTrue);
  });

  test('case-insensitive substring over name, description, tags', () {
    expect(matchesStoreQuery('JOL', name: 'Jollof rice'), isTrue);
    expect(matchesStoreQuery('spicy', name: 'Jollof', description: 'Very Spicy'), isTrue);
    expect(matchesStoreQuery('vegan', name: 'Jollof', tags: ['Vegan', 'rice']), isTrue);
    expect(matchesStoreQuery('pizza', name: 'Jollof', description: 'rice', tags: ['vegan']), isFalse);
  });

  test('null description is not an error', () {
    expect(matchesStoreQuery('a', name: 'b', description: null), isFalse);
  });
}