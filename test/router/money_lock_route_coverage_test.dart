// EVERY ROUTE THAT SHOWS THE MEMBER'S MONEY CARRIES THE SAME GATE.
//
// docs/MONEY_LOCK_INVENTORY.md lists what is protected and what is not. This
// file turns the protected half into a contract: a screen whose whole purpose
// is the member's own money must sit behind MoneyRouteGuard, and a future route
// added without one fails here rather than shipping a balance to a locked
// phone.
//
// Structure is read from the router source, one GoRoute block at a time. A text
// search over the whole file would attribute a later guard to an earlier route,
// which is how the first inventory draft wrongly reported /queue and
// /marketplace as guarded.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// route path -> why it must be gated
const _mustBeGated = <String, String>{
  '/account/activity': 'amounts and references in the feed',
  '/spending-insights': 'spending totals',
  '/round-up': 'round-up savings amounts',
  '/my-orders': 'order totals and payment state',
  '/trade/:tradeId': 'trade amount, counterparty and payment method',
  '/vault/:vaultId/yield': 'vault yield figures',
  '/storefront/staking': 'stake amounts and rewards',
  '/susu/completion': 'group payout amounts',
  '/worker/payroll': 'wage amounts',
  '/worker/ewa': 'earned wage access',
  '/business-market/dine-in/:tabId': 'a running tab is money owed',
  '/savings': 'savings totals and goals',
  '/receive': 'address and QR',
  '/deposit': 'funding',
  '/send': 'transfer',
  '/withdraw': 'payout destination',
  '/convert': 'GHS/USDC conversion',
  '/card-transfer': 'card-to-card transfer',
  '/payment-requests': 'request amounts',
  '/request/:token': 'a public link to a money request',
  '/susu': 'group balances',
  '/susu/:id': 'group ledger',
  '/susu/:id/contract': 'contract terms and amounts',
  // Owner decisions, 2026-10-31.
  '/business-market/orders': 'order totals and payment state',
  '/business-market/invoices': 'amounts owed and paid',
  '/business-market/invoices/:invoiceId':
      'invoice amount, payment state, paperwork',
  '/wallet-pass/:passType/:itemId':
      'a pass can carry stored value and payment credentials',
};

/// Routes that must stay browsable: catalogue, social or configuration data.
const _mustStayOpen = <String>[
  '/bills',
  '/marketplace',
  '/business-market',
  // Owner decisions, 2026-10-31: these three are browsable, and only their
  // money-bearing section or commitment is gated.
  '/loyalty-cards', // points are not money; the pass is (gated above)
  '/marketplace/transit/:tripId/seats', // seat map and fare are catalogue
  '/susu/position-picker', // chooses a hand, commits nothing
  '/notifications',
  '/settings',
];

/// The `AzRoutes` path constants, read from the registry so a renamed constant
/// cannot silently drop a route out of this contract.
final Map<String, String> _azRoutes = () {
  final source = File('lib/router/route_registry.dart').readAsStringSync();
  final start = source.indexOf('abstract final class AzRoutes');
  final body = start == -1 ? source : source.substring(start);
  return {
    for (final m in RegExp(r"static const (\w+) = '([^']*)'").allMatches(body))
      m.group(1)!: m.group(2)!,
  };
}();

/// Splits the router into `GoRoute(...)` blocks by INDENTATION, not by counting
/// parentheses: the file is formatted, so a block opens on a line that is only
/// `GoRoute(` and closes on the matching `),` at the same indent. Parenthesis
/// counting is fragile here because comments and strings inside a route mention
/// brackets and paths of their own.
Map<String, String> _routeBlocks(String source) {
  final lines = source.split('\n');
  final open = RegExp(r'^(\s*)GoRoute\($');
  final blocks = <String, String>{};
  for (var i = 0; i < lines.length; i++) {
    final match = open.firstMatch(lines[i]);
    if (match == null) continue;
    final indent = match.group(1)!;
    final close = '$indent),';
    var j = i + 1;
    while (j < lines.length && lines[j] != close) {
      j++;
    }
    // A route's block spans its nested children too, and a child's guard is not
    // the parent's: the Bills hub is public while /bills/add is gated. Cut the
    // block at the first nested GoRoute so a guard is only ever credited to the
    // route that actually declares it.
    var end = j;
    for (var k = i + 1; k <= j; k++) {
      if (lines[k].trimLeft().startsWith('GoRoute(')) {
        end = k - 1;
        break;
      }
    }
    final block = lines.sublist(i, end + 1).join('\n');

    // Read the path from the TOP of the block only. Printing the whole block
    // and taking the first match finds a NESTED route's path instead — the
    // Bills hub resolved to its own child 'add' and /bills vanished from the
    // map, which is exactly the kind of quiet miss this contract exists to
    // prevent.
    final head = lines.sublist(i, (i + 6).clamp(0, lines.length)).join('\n');
    final literal = RegExp(r"path:\s*'([^']+)'").firstMatch(head);
    final named = RegExp(r'path:\s*AzRoutes\.(\w+)').firstMatch(head);
    final String? path =
        literal?.group(1) ??
        (named == null ? null : _azRoutes[named.group(1)!]);
    if (path != null) blocks.putIfAbsent(path, () => block);
    // Do NOT skip to the end of this block: routes nest inside the shell route,
    // and jumping past them silently dropped /bills from the map.
  }
  return blocks;
}

void main() {
  final source = File('lib/router/app_router.dart').readAsStringSync();
  final blocks = _routeBlocks(source);

  test('every member-money route is behind MoneyRouteGuard', () {
    final unguarded = <String>[];
    for (final entry in _mustBeGated.entries) {
      final block = blocks[entry.key];
      expect(block, isNotNull, reason: 'route ${entry.key} no longer exists');
      if (!block!.contains('MoneyRouteGuard') &&
          !block.contains('MoneyLockGate')) {
        unguarded.add('${entry.key} — ${entry.value}');
      }
    }
    expect(
      unguarded,
      isEmpty,
      reason:
          'these routes expose the member\'s money with no gate: '
          '${unguarded.join('; ')}',
    );
  });

  test('catalogue and social routes stay browsable', () {
    final wronglyGated = <String>[];
    for (final path in _mustStayOpen) {
      final block = blocks[path];
      expect(block, isNotNull, reason: 'route $path no longer exists');
      if (block!.contains('MoneyRouteGuard')) wronglyGated.add(path);
    }
    expect(
      wronglyGated,
      isEmpty,
      reason:
          'a catalogue is not money; these routes were gated and would read as '
          'broken to a locked member: ${wronglyGated.join(', ')}',
    );
  });

  test('a gated transit commitment still leaves the seat map browsable', () {
    final route = blocks['/marketplace/transit/:tripId/seats'];
    expect(route, isNotNull);
    expect(
      route!.contains('MoneyRouteGuard'),
      isFalse,
      reason: 'gating the whole route would hide the fare map while locked',
    );

    final screen = File(
      'lib/screens/marketplace/transit_seat_selection_screen.dart',
    ).readAsStringSync();
    final commit = screen.indexOf(
      "Text(busy ? 'Booking…' : 'Continue to book')",
    );
    expect(commit, greaterThan(-1));
    expect(
      screen.substring(0, commit).lastIndexOf('MoneyLockGate('),
      greaterThan(-1),
      reason: 'the commitment must sit inside MoneyLockGate',
    );
    expect(
      screen.contains('toStringAsFixed(2)} USDC'),
      isTrue,
      reason: 'the fare stays visible: it is the price, not the member money',
    );
  });

  test('the Bills hub is public and only YOUR BILLS is gated', () {
    final hub = blocks['/bills'];
    expect(hub, isNotNull);
    expect(
      hub!.contains('MoneyRouteGuard'),
      isFalse,
      reason: 'the biller catalogue must stay readable while locked',
    );

    final screen = File(
      'lib/screens/bills/bills_home_screen.dart',
    ).readAsStringSync();
    final section = screen.indexOf("title: 'YOUR BILLS',");
    expect(section, greaterThan(-1));
    expect(
      screen.substring(0, section).lastIndexOf('MoneyLockGate('),
      greaterThan(-1),
      reason: 'the saved bills section must be inside MoneyLockGate',
    );
  });
}
