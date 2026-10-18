// test/router/send_money_route_test.dart
// =============================================================================
// r43 source-contract guard (PR #159) — the 'Send Money' affordances must
// route to the REAL canonical send surface, never to the unrelated deposit
// flow. Style: source-contract assertions (same convention as
// marketplace_demo_seed_test.dart) because the router table is assembled
// from app-scoped singletons that are hostile to direct widget mounting.
// =============================================================================

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Send Money route contract (r43)', () {
    final router = File('lib/router/app_router.dart').readAsStringSync();
    final registry = File('lib/router/route_registry.dart').readAsStringSync();
    final search =
        File('lib/screens/universal_search_screen.dart').readAsStringSync();

    test('the /send-money route is registered on the real router', () {
      // Route path comes from the registry constant, not a string literal.
      expect(router, contains('path: AzRoutes.sendMoney'));
      expect(router, contains("name: AzRouteNames.sendMoney,"));
    });

    test('the route mounts the canonical SendMoneyScreen', () {
      expect(router, contains('const SendMoneyScreen()'));
      expect(
        router,
        contains("import 'package:azaman/screens/send_money_screen.dart';"),
      );
    });

    test('the registry declares both the name and the path', () {
      expect(registry, contains("static const sendMoney = 'send-money';"));
      expect(registry, contains('static const sendMoney = \'/send-money\';'));
    });

    test("universal search 'Send Money' routes to the send surface", () {
      expect(search, contains("route: AzRoutes.sendMoney"));
      // The old misroute — 'Send Money' landing on /deposit — must be gone.
      expect(
        search,
        isNot(contains("title: 'Send Money', icon: HugeIconsSolid.moneySend01,"
            " route: '/deposit'")),
      );
    });

    test('the deposit route keeps its own unrelated contract untouched', () {
      expect(registry, contains("static const deposit = 'deposit';"));
      expect(router, contains("path: '/deposit',"));
    });
  });
}
