import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/marketplace_extensions_models.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/widgets/inbox/inbox_entry.dart';

// Fixes from the plan's bug table (28 Nov): GHS dine-in tabs shown as
// "0.00 USDC", the inbox money signal, and the stores-marketplace link.
void main() {
  group('a dine-in tab in its own currency', () {
    test('a GHS tab reads the cedi columns and shows GH₵', () {
      final tab = DineInTab.fromJson({
        'id': 't1',
        'status': 'OPEN',
        'openedAt': '2026-11-28T12:00:00Z',
        'currency': 'GHS',
        'subtotalGhs': '120.00',
        'taxTotalGhs': '6.00',
        'tipGhs': '0.00',
        'grandTotalGhs': '126.00',
        'subtotalUsdc': '0',
        'grandTotalUsdc': '0',
        'businessProfile': {'businessName': 'Chef Abby'},
        'items': [
          {
            'id': 'i1',
            'name': 'Jollof',
            'quantity': 2,
            'unitPriceGhs': '60.00',
            'lineTotalGhs': '120.00',
            'unitPriceUsdc': '0',
            'lineTotalUsdc': '0',
            'addedAt': '2026-11-28T12:05:00Z',
          },
        ],
      });
      expect(tab.isGhs, isTrue);
      expect(tab.grandTotal, 126.0);
      expect(tab.items.single.lineTotal, 120.0);
      expect(tab.money(tab.grandTotal), 'GH₵ 126.00');
    });

    test('an untagged (older) tab stays USDC', () {
      final tab = DineInTab.fromJson({
        'id': 't2',
        'openedAt': '2026-11-28T12:00:00Z',
        'grandTotalUsdc': '8.5',
        'items': [],
      });
      expect(tab.isGhs, isFalse);
      expect(tab.money(tab.grandTotal), '8.50 USDC');
    });
  });

  group('the inbox money signal', () {
    InboxEntry entry(Map<String, dynamic> latest) => InboxEntry.fromFriend({
      'friendshipId': 'f1',
      'friend': {'id': 2, 'username': 'ama'},
      'latestMessage': latest,
      'unreadCount': 0,
    });

    test('from the message type the server sends (REST and live)', () {
      expect(
        entry({
          'content': '[TRANSFER SENT]',
          'messageType': 'TRANSFER_SENT',
          'isFromMe': true,
        }).signal,
        InboxSignal.moneyOut,
      );
      expect(
        entry({
          'content': '[TRANSFER SENT]',
          'messageType': 'TRANSFER_SENT',
          'isFromMe': false,
        }).signal,
        InboxSignal.moneyIn,
      );
      expect(
        entry({
          'content': '[TRANSFER REQUEST]',
          'messageType': 'TRANSFER_REQUEST',
        }).signal,
        InboxSignal.request,
      );
      expect(
        entry({'content': 'hi', 'messageType': 'TEXT'}).signal,
        InboxSignal.none,
      );
    });
  });

  test('the stores marketplace, on a category', () {
    expect(AzRoutes.businessMarket(), '/business-market');
    expect(
      AzRoutes.businessMarket(category: 'FOOD_BEVERAGE'),
      '/business-market?category=FOOD_BEVERAGE',
    );
  });
}
