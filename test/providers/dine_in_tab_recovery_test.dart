import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/providers/marketplace_extensions_provider.dart';

void main() {
  Map<String, dynamic> tab({
    String id = 'tab-1',
    String status = 'CLOSED',
    double tip = 2,
  }) => {
    'tab': {
      'id': id,
      'status': status,
      'openedAt': '2026-09-05T08:00:00.000Z',
      'subtotalUsdc': 40,
      'taxTotalUsdc': 5,
      'tipUsdc': tip,
      'grandTotalUsdc': 47,
      'invoice': {'invoiceRef': 'INV-260905-TEST'},
      'businessProfile': {
        'id': 'biz-profile-1',
        'bizId': 'BIZ-1',
        'businessName': 'Azaman Test Bistro',
      },
      'items': [
        {
          'id': 'item-1',
          'name': 'Jollof',
          'unitPriceUsdc': 40,
          'quantity': 1,
          'lineTotalUsdc': 40,
          'addedAt': '2026-09-05T08:01:00.000Z',
        },
      ],
    },
  };

  test('accepts only the requested tab in durable CLOSED state', () {
    final recovered = parseRecoveredClosedTab(tab(), 'tab-1');

    expect(recovered, isNotNull);
    expect(recovered!.id, 'tab-1');
    expect(recovered.status, 'CLOSED');
    expect(recovered.tip, 2);
    expect(recovered.grandTotal, 47);
  });

  test('does not convert a non-CLOSED response into payment success', () {
    expect(parseRecoveredClosedTab(tab(status: 'FINALIZED'), 'tab-1'), isNull);
  });

  test('does not accept a different tab id from the recovery response', () {
    expect(parseRecoveredClosedTab(tab(), 'tab-2'), isNull);
  });

  test('rejects malformed recovery envelopes without throwing', () {
    expect(parseRecoveredClosedTab(const <String, dynamic>{}, 'tab-1'), isNull);
    expect(
      parseRecoveredClosedTab(const <String, dynamic>{'tab': 'not-an-object'}, 'tab-1'),
      isNull,
    );
  });
}
