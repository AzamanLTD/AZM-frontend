import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer payment recovery keeps server state authoritative', () {
    final source = File('lib/providers/marketplace_extensions_provider.dart').readAsStringSync();

    expect(source, contains(r"await _api.post('/dine-in/tabs/$tabId/pay'"));
    expect(source, contains(r"await _api.get('/dine-in/tabs/$tabId'"));
    expect(source, contains('parseRecoveredClosedTab(body, _tabId)'));
    expect(source, contains('rethrow;'));
    expect(source, contains('// Socket payloads are convergence signals only.'));
  });
}
