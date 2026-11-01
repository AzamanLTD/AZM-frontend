// test/services/notification_action_dispatcher_test.dart
// =============================================================================
// AZAMAN — NOTIFICATION ACTION DISPATCHER TESTS
//
// The dispatcher is the single canonical resolver from a notification
// actionPayload to a route. These tests pin the two invariants it exists
// to hold:
//   1. Determinism — the same payload resolves to the same route from
//      any surface (overlay, hub) because resolution is pure.
//   2. Honesty — it never invents a destination. An OPEN_TRADE without
//      a tradeId, an unknown action, or a route string outside the
//      mounted allowlist resolves to unsupportedAction/informational,
//      never to a navigation the payload never named.
// =============================================================================

import 'package:azaman/services/notification_action_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('no payload', () {
    test('null payload is informational', () {
      expect(
        NotificationActionDispatcher.resolve(null).resolution,
        NotificationActionResolution.informational,
      );
    });

    test('empty payload is informational', () {
      expect(
        NotificationActionDispatcher.resolve({}).resolution,
        NotificationActionResolution.informational,
      );
    });

    test('payload with only unrelated keys is informational', () {
      expect(
        NotificationActionDispatcher.resolve({'title': 'hey'}).resolution,
        NotificationActionResolution.informational,
      );
    });
  });

  group('trade lifecycle', () {
    test('OPEN_TRADE with tradeId navigates to the trade route', () {
      final a = NotificationActionDispatcher.resolve({
        'action': 'OPEN_TRADE',
        'tradeId': 'TRD-42',
      });
      expect(a.resolution, NotificationActionResolution.navigable);
      expect(a.route, '/trade/TRD-42');
    });

    test('OPEN_TRADE without tradeId is unsupported — never invents an id', () {
      final a = NotificationActionDispatcher.resolve({'action': 'OPEN_TRADE'});
      expect(a.resolution, NotificationActionResolution.unsupportedAction);
      expect(a.route, isNull);
    });

    test('OPEN_TRADE with empty-string tradeId is unsupported', () {
      final a = NotificationActionDispatcher.resolve({
        'action': 'OPEN_TRADE',
        'tradeId': '',
      });
      expect(a.resolution, NotificationActionResolution.unsupportedAction);
    });

    test('PING_TOPUP with tradeId navigates like OPEN_TRADE', () {
      final a = NotificationActionDispatcher.resolve({
        'action': 'PING_TOPUP',
        'tradeId': 77,
      });
      expect(a.resolution, NotificationActionResolution.navigable);
      expect(a.route, '/trade/77');
    });
  });

  group('disputes', () {
    test('OPEN_DISPUTE with disputeId navigates', () {
      final a = NotificationActionDispatcher.resolve({
        'action': 'OPEN_DISPUTE',
        'disputeId': 'DSP-9',
      });
      expect(a.resolution, NotificationActionResolution.navigable);
      expect(a.route, '/dispute/DSP-9');
    });

    test('OPEN_DISPUTE without disputeId is unsupported', () {
      final a = NotificationActionDispatcher.resolve({
        'action': 'OPEN_DISPUTE',
      });
      expect(a.resolution, NotificationActionResolution.unsupportedAction);
    });
  });

  group('friends & dm', () {
    for (final action in [
      'OPEN_FRIEND_REQUEST',
      'OPEN_FRIEND_CHAT',
      'OPEN_FRIEND_TRANSFER_REQUEST',
    ]) {
      test('$action navigates to /friends', () {
        final a = NotificationActionDispatcher.resolve({'action': action});
        expect(a.resolution, NotificationActionResolution.navigable);
        expect(a.route, '/friends');
      });
    }
  });

  group('queue', () {
    test('OPEN_QUEUE builds the queue route with position and adId', () {
      final a = NotificationActionDispatcher.resolve({
        'action': 'OPEN_QUEUE',
        'queueId': 'Q-1',
        'queuePosition': 3,
        'adId': 'AD-7',
      });
      expect(a.resolution, NotificationActionResolution.navigable);
      expect(a.route, '/queue?queueId=Q-1&position=3&adId=AD-7');
    });

    test(
      'OPEN_QUEUE without optional fields still navigates with defaults',
      () {
        final a = NotificationActionDispatcher.resolve({
          'action': 'OPEN_QUEUE',
        });
        expect(a.resolution, NotificationActionResolution.navigable);
        expect(a.route, '/queue?queueId=&position=1&adId=');
      },
    );
  });

  group('account surfaces', () {
    test('OPEN_WALLET is informational — no dedicated route to push', () {
      final a = NotificationActionDispatcher.resolve({'action': 'OPEN_WALLET'});
      expect(a.resolution, NotificationActionResolution.informational);
      expect(a.route, isNull);
    });

    for (final action in ['KYC_STATUS', 'ACCOUNT_STATUS']) {
      test('$action navigates to settings', () {
        final a = NotificationActionDispatcher.resolve({'action': action});
        expect(a.route, '/settings');
      });
    }

    test('VIEW_SAVINGS navigates to savings', () {
      final a = NotificationActionDispatcher.resolve({
        'action': 'VIEW_SAVINGS',
      });
      expect(a.route, '/savings');
    });

    for (final action in ['OPEN_AD', 'OPEN_MARKETPLACE']) {
      test('$action navigates to marketplace', () {
        final a = NotificationActionDispatcher.resolve({'action': action});
        expect(a.route, '/marketplace');
      });
    }
  });

  group('unknown actions', () {
    test('an unsupported action name is unsupportedAction', () {
      final a = NotificationActionDispatcher.resolve({
        'action': 'DEPLOY_ROBOT',
      });
      expect(a.resolution, NotificationActionResolution.unsupportedAction);
    });

    test('an unknown action with an incidental tradeId does NOT navigate', () {
      // An id the payload carries is not a navigation instruction unless
      // the action names it — the unsupported check must precede the
      // legacy flat-key fallback.
      final a = NotificationActionDispatcher.resolve({
        'action': 'SOME_NEW_ACTION',
        'tradeId': 'TRD-1',
      });
      expect(a.resolution, NotificationActionResolution.unsupportedAction);
      expect(a.route, isNull);
    });
  });

  group('legacy flat-key payloads', () {
    test('flat tradeId without action navigates to the trade', () {
      final a = NotificationActionDispatcher.resolve({'tradeId': 'TRD-5'});
      expect(a.resolution, NotificationActionResolution.navigable);
      expect(a.route, '/trade/TRD-5');
    });

    test('flat disputeId without action navigates to the dispute', () {
      final a = NotificationActionDispatcher.resolve({'disputeId': 'DSP-2'});
      expect(a.route, '/dispute/DSP-2');
    });

    test('tradeId takes precedence over disputeId in legacy payloads', () {
      final a = NotificationActionDispatcher.resolve({
        'tradeId': 'TRD-1',
        'disputeId': 'DSP-1',
      });
      expect(a.route, '/trade/TRD-1');
    });
  });

  group('route allowlist', () {
    test('a known top-level route navigates', () {
      final a = NotificationActionDispatcher.resolve({'route': '/savings'});
      expect(a.resolution, NotificationActionResolution.navigable);
      expect(a.route, '/savings');
    });

    test(
      'a subpath of a known root navigates (deep payload, mounted route)',
      () {
        final a = NotificationActionDispatcher.resolve({
          'route': '/business/BIZ-123',
        });
        expect(a.resolution, NotificationActionResolution.navigable);
        expect(a.route, '/business/BIZ-123');
      },
    );

    test('query strings are stripped before the allowlist check', () {
      final a = NotificationActionDispatcher.resolve({
        'route': '/marketplace?tab=near',
      });
      expect(a.resolution, NotificationActionResolution.navigable);
      expect(a.route, '/marketplace?tab=near');
    });

    test('trailing slash normalises to the known route', () {
      final a = NotificationActionDispatcher.resolve({'route': '/savings/'});
      expect(a.resolution, NotificationActionResolution.navigable);
    });

    test('an unmounted route string is rejected as unsupported', () {
      final a = NotificationActionDispatcher.resolve({
        'route': '/admin/payouts',
      });
      expect(a.resolution, NotificationActionResolution.unsupportedAction);
      expect(a.route, isNull);
    });

    test('an injected external-looking path never navigates', () {
      for (final bad in ['//evil.example', '/\\evil', '/not-mounted']) {
        final a = NotificationActionDispatcher.resolve({'route': bad});
        expect(
          a.resolution,
          NotificationActionResolution.unsupportedAction,
          reason: '$bad must not resolve',
        );
      }
    });
  });

  group('determinism', () {
    test('the same payload resolves identically on repeated calls', () {
      const payload = {'action': 'OPEN_TRADE', 'tradeId': 'TRD-9'};
      final first = NotificationActionDispatcher.resolve(payload);
      final second = NotificationActionDispatcher.resolve(payload);
      expect(first.resolution, second.resolution);
      expect(first.route, second.route);
    });

    test('resolution never mutates the payload map', () {
      final payload = {'action': 'OPEN_QUEUE', 'queueId': 'Q-1'};
      final before = Map<String, dynamic>.from(payload);
      NotificationActionDispatcher.resolve(payload);
      expect(payload, before);
    });
  });
  group('restored action parity (review 4.2 matrix)', () {
    const rows = [
      // name, payload, resolution, route / delegated action
      _ParityRow(
        'OPEN_SUSU',
        {'susuId': 'sus-1'},
        NotificationActionResolution.navigable,
        '/susu/sus-1',
      ),
      _ParityRow(
        'OPEN_SUSU',
        {},
        NotificationActionResolution.navigable,
        '/susu',
      ),
      _ParityRow(
        'OPEN_SUSU',
        {'susuId': ''},
        NotificationActionResolution.navigable,
        '/susu',
      ),
      _ParityRow(
        'OPEN_SUSU_INVITE',
        {'token': 'tok-9'},
        NotificationActionResolution.navigable,
        '/susu/invite/tok-9',
      ),
      _ParityRow(
        'OPEN_SUSU_INVITE',
        {'susuId': 'sus-2'},
        NotificationActionResolution.navigable,
        '/susu/sus-2',
      ),
      _ParityRow(
        'OPEN_SUSU_INVITE',
        {'token': 't', 'susuId': 'sus-3'},
        NotificationActionResolution.navigable,
        '/susu/invite/t',
      ),
      _ParityRow(
        'OPEN_SUSU_INVITE',
        {},
        NotificationActionResolution.navigable,
        '/susu',
      ),
      _ParityRow(
        'OPEN_DEPOSIT_FOR_SUSU',
        {'amount': '50', 'susuId': 'sus-4'},
        NotificationActionResolution.navigable,
        '/deposit?amount=50&memo=susu%3Asus-4',
      ),
      _ParityRow(
        'OPEN_DEPOSIT_FOR_SUSU',
        {'susuId': 'sus-5'},
        NotificationActionResolution.navigable,
        '/deposit?memo=susu%3Asus-5',
      ),
      _ParityRow(
        'OPEN_DEPOSIT_FOR_SUSU',
        {},
        NotificationActionResolution.navigable,
        '/deposit',
      ),
      _ParityRow(
        'OPEN_ORDER',
        {'orderId': 'ord-1'},
        NotificationActionResolution.navigable,
        '/orders/ord-1/tracking',
      ),
      _ParityRow(
        'OPEN_ORDER',
        {'orderId': 'ord-2', 'orderRef': 'REF 77'},
        NotificationActionResolution.navigable,
        '/orders/ord-2/tracking?orderRef=REF+77',
      ),
      _ParityRow(
        'OPEN_ORDER',
        {},
        NotificationActionResolution.unsupportedAction,
        null,
      ),
      _ParityRow(
        'OPEN_ORDER',
        {'orderId': ''},
        NotificationActionResolution.unsupportedAction,
        null,
      ),
      _ParityRow(
        'OPEN_PROOF_OF_RESIDENCY',
        {},
        NotificationActionResolution.navigable,
        '/proof-of-residency',
      ),
      _ParityRow('OPEN_HOME', {}, NotificationActionResolution.navigable, '/'),
      // OPEN_CHAT keeps its ESTABLISHED imperative behaviour: delegated.
      _ParityRow(
        'OPEN_CHAT',
        {'conversationId': 'c1'},
        NotificationActionResolution.delegated,
        'OPEN_CHAT',
      ),
      _ParityRow(
        'OPEN_CHAT',
        {},
        NotificationActionResolution.delegated,
        'OPEN_CHAT',
      ),
    ];

    for (final r in rows) {
      test(
        '${r.action} with ${r.payload.isEmpty ? 'no fields' : r.payload} → '
        '${r.expected.name}${r.expectedOutcome != null ? ' (${r.expectedOutcome})' : ''}',
        () {
          final action = NotificationActionDispatcher.resolve({
            'action': r.action,
            ...r.payload,
          });
          expect(
            action.resolution,
            r.expected,
            reason: '${r.action} must keep its restored resolution',
          );
          if (r.expected == NotificationActionResolution.navigable) {
            expect(action.route, r.expectedOutcome);
          } else if (r.expected == NotificationActionResolution.delegated) {
            expect(action.actionName, r.expectedOutcome);
            expect(
              action.route,
              isNull,
              reason: 'a delegated action never invents a stand-in route',
            );
          } else {
            expect(action.route, isNull);
            expect(action.actionName, isNull);
          }
        },
      );
    }

    test('the delegated OPEN_CHAT payload passes through untouched', () {
      final payload = {
        'action': 'OPEN_CHAT',
        'conversationId': 'c-42',
        'friendName': 'Ama',
        'friendId': 'u-7',
      };
      final action = NotificationActionDispatcher.resolve(payload);
      expect(action.resolution, NotificationActionResolution.delegated);
      expect(action.actionName, 'OPEN_CHAT');
      expect(action.payload, equals(payload));
      expect(
        payload['action'],
        'OPEN_CHAT',
        reason: 'resolution never mutates the payload map',
      );
    });
  });
}

class _ParityRow {
  final String action;
  final Map<String, dynamic> payload;
  final NotificationActionResolution expected;
  final String? expectedOutcome;
  const _ParityRow(
    this.action,
    this.payload,
    this.expected,
    this.expectedOutcome,
  );
}
