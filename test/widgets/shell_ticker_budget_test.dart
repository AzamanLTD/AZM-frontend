// =============================================================================
// Shell ticker budget (milestone 2026-09-30) — permanent guard
//
// The shell keeps previously-visited pages MOUNTED (state preserved) but
// wraps each in a TickerMode that is enabled ONLY while the page is the
// selected or displayed (mid-transition) page. This test proves, on the
// real MainWrapper:
//
//   * the initial page's TickerMode is enabled,
//   * mid-transition BOTH the outgoing and the incoming page stay
//     ticker-enabled (the entrance animation must run),
//   * once navigation settles the outgoing page's TickerMode is DISABLED
//     and the incoming page's is enabled — inactive pages stop
//     consuming animation cycles,
//   * navigating back re-enables the first page and disables the other —
//     the budget is reversible, not a one-way kill switch,
//   * pages are never unmounted: both page subtrees still exist.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data' show ByteData, Uint8List;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/main.dart' show MainWrapper;
import 'package:azaman/providers/auth_provider.dart' as auth_pkg;
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';

bool _fontsLoaded = false;

Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final bytes = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final loader = FontLoader('Inter')
    ..addFont(Future<ByteData>.value(
        ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
  _fontsLoaded = true;
}

class _InertSearchNotifier extends BusinessSearchNotifier {
  _InertSearchNotifier() : super(BusinessService());

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    // Recorded, not fired — no network in this guard.
  }
}

/// The TickerMode the shell wraps [pageFinder] in. It is the shell's own
/// budget wrapper — never a page-internal TickerMode — because the finder
/// requires the page widget as a descendant.
TickerMode _budgetOf(WidgetTester tester, Finder pageFinder) {
  final shellWrapper = find.ancestor(
    of: pageFinder,
    matching: find.byType(TickerMode),
  );
  // The nearest ancestor TickerMode is the shell's wrapper.
  return tester.widget<TickerMode>(shellWrapper.first);
}

Future<void> _pumpShell(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(
      {'has_seen_flippable_card_hint': true});
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(const Size(800, 600));

  final container = ProviderContainer(
    overrides: [
      auth_pkg.authProvider.overrideWith((ref) => auth_pkg.AuthProvider()),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
          (ref) => const BalanceData(availableBalance: 100)),
      oracleRateProvider.overrideWith((ref) => 1.0),
      businessSearchProvider.overrideWith((ref) => _InertSearchNotifier()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(800, 600)),
          child: MainWrapper(),
        ),
      ),
    ),
  );
  // First frame + entrance one-shots.
  await tester.pump(const Duration(milliseconds: 600));
}

void _select(WidgetTester tester, int index) {
  tester
      .widget<PremiumBottomNav>(find.byType(PremiumBottomNav))
      .onItemSelected.call(index);
}

void main() {
  testWidgets('inactive pages are ticker-disabled after navigation settles',
      (tester) async {
    await _pumpShell(tester);

    final homeFinder = find.byType(AzamanHomePage);
    final marketFinder = find.byType(MarketplaceHomeScreen);

    // Before any navigation only Home is mounted and its budget is on.
    expect(homeFinder, findsOneWidget);
    expect(marketFinder, findsNothing);
    expect(_budgetOf(tester, homeFinder).enabled, isTrue);

    // Navigate Home -> Marketplace (tab 3).
    _select(tester, 3);
    // First frame of the transition: both pages exist, both budgets ON.
    await tester.pump(const Duration(milliseconds: 40));
    expect(homeFinder, findsOneWidget);
    expect(marketFinder, findsOneWidget);
    expect(_budgetOf(tester, homeFinder).enabled, isTrue,
        reason: 'mid-transition the outgoing page animates its exit');
    expect(_budgetOf(tester, marketFinder).enabled, isTrue,
        reason: 'mid-transition the incoming page animates its entrance');

    // Let the transition complete. Fixed pumps, not pumpAndSettle: Home
    // legitimately runs repeating tickers (live market shimmer), which never
    // "settle" — that repeating work is exactly what this budget removes
    // from inactive pages.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));

    // Settled: Marketplace enabled, Home STILL MOUNTED but ticker-disabled.
    expect(homeFinder, findsOneWidget,
        reason: 'page state is preserved — the shell never unmounts pages');
    expect(marketFinder, findsOneWidget);
    expect(_budgetOf(tester, homeFinder).enabled, isFalse,
        reason: 'the settled-out page must stop consuming animation cycles');
    expect(_budgetOf(tester, marketFinder).enabled, isTrue);

    // Navigate back Home: the budget reverses.
    _select(tester, 0);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));
    expect(homeFinder, findsOneWidget);
    expect(marketFinder, findsOneWidget,
        reason: 'Marketplace stays mounted after returning home');
    expect(_budgetOf(tester, homeFinder).enabled, isTrue);
    expect(_budgetOf(tester, marketFinder).enabled, isFalse);
  });
}
