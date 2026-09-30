// NEW-D — Home's 3-pill structure and the History→Withdraw demotion.
//
// Pins §G.8's §10.10 decision on the live page: FOUR quick actions became
// THREE — "fewer, larger, better". Withdraw is a rare, considered action
// (and WithdrawalScreen commits through its own slide-to-confirm), so it
// moves one tap deeper behind History. These tests pin both halves:
//
//   1. The pill row is exactly Add Money / Send / History — no Withdraw
//      pill on the page surface.
//   2. History opens the sheet, and the sheet exposes the two-tap path
//      back to Withdraw — the demotion must be a relocation, not a loss.
//      (Navigation is pinned on the Transaction history tile; both tiles
//      share the same pop-then-push seam.)
//
// The harness mirrors test/widgets/home_entrance_test.dart: an inert
// AuthProvider (user null → greeting degrades to "there"), zeroed unread
// count, stubbed balance/oracle, and the real app theme with the Inter
// face loaded (the fixed-width default test font overflows layouts that
// fit). The empty history also pins the honesty gate end-to-end: no
// loaded history means NO insight card in the deck.
import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/screens/transaction_history_screen.dart';
import 'package:azaman/widgets/home/az_insight_card.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _surfaceSize = Size(400, 900);

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

Future<ProviderContainer> _pumpHome(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(
      {'has_seen_flippable_card_hint': true});
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(_surfaceSize);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
          (ref) => const BalanceData(availableBalance: 100)),
      oracleRateProvider.overrideWith((ref) => 1.0),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: MediaQuery(
          data: const MediaQueryData(size: _surfaceSize),
          child: const Scaffold(body: AzamanHomePage()),
        ),
      ),
    ),
  );
  // Fire the entrance start timer + the choreography, then settle the
  // network-idle sections (same cadence as home_entrance_test).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

void main() {
  testWidgets('Home shows exactly the three pills — Add Money, Send, History',
      (tester) async {
    await _pumpHome(tester);

    expect(find.text('Add Money'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);

    // The demotion: no Withdraw PILL on the page surface anymore.
    expect(find.text('Withdraw'), findsNothing);

    // Honesty gate, end to end: no loaded history → no insight card in
    // the deck, and no fabricated insight to fill the slot.
    expect(find.byType(AzInsightCard), findsNothing);
  });

  testWidgets('History opens the sheet with the two-tap path back to Withdraw',
      (tester) async {
    await _pumpHome(tester);

    await tester.tap(find.text('History'));
    // Fixed pumps, never pumpAndSettle: Home carries repeating controllers
    // (bell fade, live-market ticker) that never settle — the same reason
    // home_entrance_test pumps fixed durations.
    await tester.pump(); // tap
    await tester.pump(const Duration(milliseconds: 400)); // sheet entrance

    // The sheet is the relocated home for the rare action: both tiles
    // visible at once.
    expect(find.text('Transaction history'), findsOneWidget);
    expect(find.text('Withdraw'), findsOneWidget);

    // Both tiles must actually navigate: the sheet is a router, not a
    // dead end. (WithdrawalScreen's background services crash the test
    // shell, so the navigation is pinned on the lighter Transaction
    // history tile — the same pop-then-push seam both tiles share.)
    await tester.tap(find.text('Transaction history'));
    await tester.pump(); // sheet pop
    await tester.pump(const Duration(milliseconds: 600)); // route transition

    expect(find.byType(TransactionHistoryScreen), findsOneWidget);
  });
}
