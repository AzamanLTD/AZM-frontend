// =============================================================================
// TASK-010b — PremiumBottomNav long-press contract: permanent guard
//
// Pins the gesture seam the vertical launcher plugs into — the seam TASK-018
// will inherit:
//
//   * a deliberate long-press reports exactly that tab's index, once per
//     press, and NEVER issues a tab selection (a long-press must not
//     double-trigger navigation),
//   * a normal tap NEVER reports a long-press, and tap navigation is
//     byte-for-byte the TASK-010 behaviour (re-tapping the active tab does
//     not re-select),
//   * a long-press without a callback is inert (tabs 0..2 ship without one),
//   * an interrupted (moved-out) long-press fires neither callback — the
//     launcher can never be left "half-open" by a cancelled gesture,
//   * reduced motion does not change the callback contract.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/chat_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';

Widget _host(Widget child, {bool reduceMotion = false}) {
  return ProviderScope(
    // The badge providers' real bodies are async and hit the API; in a test
    // they resolve after the container is disposed. Pin them to inert values
    // so the nav under test never leaves the container's lifetime.
    overrides: [
      totalUnreadChatCountProvider.overrideWith((ref) async => 0),
      activeTradeCountProvider.overrideWith((ref) async => 0),
      unreadCountProvider.overrideWith((ref) => 0),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, navigatorChild) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: navigatorChild ?? const SizedBox.shrink(),
      ),
      home: Scaffold(body: const SizedBox.expand(), bottomNavigationBar: child),
    ),
  );
}

Future<void> _pumpNav(
  WidgetTester tester, {
  int selectedIndex = 0,
  required List<int> selections,
  List<int>? longPresses,
  bool reduceMotion = false,
}) {
  return tester.pumpWidget(
    _host(
      PremiumBottomNav(
        selectedIndex: selectedIndex,
        onItemSelected: selections.add,
        onTabLongPress: longPresses?.add,
      ),
      reduceMotion: reduceMotion,
    ),
  );
}

// UX-CORRECTION §3/§4: the resting nav is icon-only (no visible labels),
// so long-presses target the stable `nav-item-N` keys on the nav buttons.
final _keys = [
  const ValueKey('nav-item-0'),
  const ValueKey('nav-item-1'),
  const ValueKey('nav-item-2'),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    navScrollCompression.value = 0;
  });

  group('long-press reports the tab index (the launcher seam)', () {
    testWidgets('a long-press on each tab reports exactly that index', (
      tester,
    ) async {
      final longPresses = <int>[];
      final selections = <int>[];
      await _pumpNav(tester, selections: selections, longPresses: longPresses);
      for (var i = 0; i < _keys.length; i++) {
        await tester.longPress(find.byKey(_keys[i]));
      }
      expect(longPresses, [0, 1, 2]);
      expect(selections, isEmpty);
    });

    testWidgets('a long-press never issues a tab selection', (tester) async {
      final selections = <int>[];
      final longPresses = <int>[];
      await _pumpNav(tester, selections: selections, longPresses: longPresses);
      for (final label in _keys) {
        await tester.longPress(find.byKey(label));
      }
      expect(longPresses, [0, 1, 2]);
      expect(
        selections,
        isEmpty,
        reason: 'a long-press must not double-trigger navigation',
      );
    });

    testWidgets('rapid repeated long-presses each fire exactly once', (
      tester,
    ) async {
      final longPresses = <int>[];
      final selections = <int>[];
      await _pumpNav(tester, selections: selections, longPresses: longPresses);
      await tester.longPress(find.byKey(const ValueKey('nav-item-2')));
      await tester.longPress(find.byKey(const ValueKey('nav-item-2')));
      await tester.longPress(find.byKey(const ValueKey('nav-item-2')));
      expect(longPresses, [2, 2, 2]);
      expect(selections, isEmpty);
    });

    testWidgets('a long-press on the ACTIVE tab still reports (switch '
        'verticals from inside the marketplace)', (tester) async {
      final longPresses = <int>[];
      final selections = <int>[];
      await _pumpNav(
        tester,
        selectedIndex: 2,
        selections: selections,
        longPresses: longPresses,
      );
      await tester.longPress(find.byKey(const ValueKey('nav-item-2')));
      expect(longPresses, [2]);
    });

    testWidgets('reduced motion does not change the callback contract', (
      tester,
    ) async {
      final longPresses = <int>[];
      final selections = <int>[];
      await _pumpNav(
        tester,
        selections: selections,
        longPresses: longPresses,
        reduceMotion: true,
      );
      await tester.longPress(find.byKey(const ValueKey('nav-item-2')));
      expect(longPresses, [2]);
    });
  });

  group('a normal tap never touches the long-press seam', () {
    testWidgets('tap navigation is byte-for-byte TASK-010 behaviour', (
      tester,
    ) async {
      final selections = <int>[];
      final longPresses = <int>[];
      await _pumpNav(tester, selections: selections, longPresses: longPresses);
      await tester.tap(find.byKey(const ValueKey('nav-item-1')));
      await tester.tap(find.byKey(const ValueKey('nav-item-2')));
      expect(selections, [1, 2]);
      expect(longPresses, isEmpty);
    });

    testWidgets('re-tapping the active tab still does not re-select', (
      tester,
    ) async {
      final selections = <int>[];
      final longPresses = <int>[];
      await _pumpNav(
        tester,
        selectedIndex: 2,
        selections: selections,
        longPresses: longPresses,
      );
      await tester.tap(find.byKey(const ValueKey('nav-item-2')));
      expect(
        selections,
        isEmpty,
        reason: 'TASK-010: re-tap acknowledges with a haptic only',
      );
      expect(longPresses, isEmpty);
    });
  });

  group('cancelled and absent gestures', () {
    testWidgets('an interrupted long-press fires neither callback', (
      tester,
    ) async {
      final selections = <int>[];
      final longPresses = <int>[];
      await _pumpNav(tester, selections: selections, longPresses: longPresses);
      // Press Market, then wander out of the slop region before the long-press
      // deadline: the gesture arena must resolve to neither a long press nor
      // a tap — no callback, no navigation, nothing left half-open.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('nav-item-2'))),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();
      expect(longPresses, isEmpty);
      expect(selections, isEmpty);
    });

    testWidgets('without a callback, a long hold degrades to the ordinary '
        'tap (no long-press seam, navigation unchanged)', (tester) async {
      // With no long-press recognizer registered, the tap recognizer is
      // unopposed, so a long hold resolves as a normal tap on release. This
      // is the shipped fallback: a nav wired without a launcher keeps its
      // plain tap behaviour — nothing crashes, nothing double-fires.
      final selections = <int>[];
      await _pumpNav(tester, selections: selections);
      await tester.longPress(find.byKey(const ValueKey('nav-item-2')));
      expect(selections, [2]);
    });
  });
}
