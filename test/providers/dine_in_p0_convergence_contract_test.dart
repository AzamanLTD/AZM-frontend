import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer payment recovery keeps server state authoritative', () {
    final source = File(
      'lib/providers/marketplace_extensions_provider.dart',
    ).readAsStringSync();

    // WP-J: the tab payment now travels through the durable/step-up client
    // (postFinancial) instead of a bare post, so the same money call is
    // retry-safe. The contract asserted here is unchanged and stricter: the
    // pay endpoint is still called, and it now carries a stable operation
    // identity so a retry cannot double-charge.
    expect(source, contains('_api.postFinancial('));
    expect(source, contains(r"'/dine-in/tabs/$tabId/pay'"));
    expect(source, contains("operationType: 'dinein.tabpay'"));
    expect(source, contains(r"await _api.get('/dine-in/tabs/$tabId'"));
    expect(source, contains('parseRecoveredClosedTab(body, _tabId)'));
    expect(source, contains('rethrow;'));
    expect(
      source,
      contains('// Socket payloads are convergence signals only.'),
    );
  });
}
