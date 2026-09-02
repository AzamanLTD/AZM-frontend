import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/marketplace_extensions_models.dart';

void main() {
  test('DineInTab parses business and table context from the authoritative payload', () {
    final tab = DineInTab.fromJson({
      'id': 'tab-1',
      'status': 'OPEN',
      'openedAt': '2026-09-02T10:00:00Z',
      'subtotalUsdc': 24,
      'taxTotalUsdc': 0,
      'tipUsdc': 0,
      'grandTotalUsdc': 24,
      'businessProfile': {
        'id': 'business-1',
        'bizId': 'BIZ-123456789',
        'businessName': 'Table & Co',
        'logoUrl': 'https://example.com/logo.jpg',
      },
      'tableId': 'table-7',
      'locationId': 'location-1',
      'table': {
        'id': 'table-7',
        'label': 'Table 7',
        'locationId': 'location-1',
        'isActive': true,
      },
      'items': [],
    });

    expect(tab.businessProfileId, 'business-1');
    expect(tab.businessBizId, 'BIZ-123456789');
    expect(tab.businessName, 'Table & Co');
    expect(tab.tableId, 'table-7');
    expect(tab.tableLabel, 'Table 7');
    expect(tab.locationId, 'location-1');
  });

  test('DineInTab tolerates tab payloads without table context', () {
    final tab = DineInTab.fromJson({
      'id': 'tab-2',
      'status': 'OPEN',
      'openedAt': '2026-09-02T10:00:00Z',
      'businessProfile': {
        'id': 'business-2',
        'bizId': 'BIZ-987654321',
        'businessName': 'Counter Service',
      },
      'items': [],
    });

    expect(tab.businessBizId, 'BIZ-987654321');
    expect(tab.tableId, isNull);
    expect(tab.tableLabel, isNull);
    expect(tab.locationId, isNull);
  });
}
