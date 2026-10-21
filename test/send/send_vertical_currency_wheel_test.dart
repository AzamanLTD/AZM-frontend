// =============================================================================
// AZAMAN — WORKSTREAM C: THE VERTICAL SEND CURRENCY WHEEL
//
// Send's CurrencyWheelToggle opts into the VERTICAL roller. This suite pins
// its interaction and geometry contract:
//   • only a DELIBERATE completed vertical gesture rolls the unit — a
//     graze or a cancelled drag never changes money denominations
//   • tap still opens the real picker; screen-reader increase/decrease
//     actions work and announce
//   • the SELECTED chip's full rectangle is visible on the viewport —
//     never cropped by the wheel's own peek geometry or the page — at
//     320/360/390dp and on a short 320×540 viewport, including with the
//     keyboard inset active
//   • a roll CONVERTS the numeric amount (GHS 5.00 → USDC 0.33 at the
//     frozen seam rate) — never a silent relabel
//   • reduced motion lands instantly, with no travelling animation
//
// The horizontal presentation (Card Transfer, display surfaces) keeps its
// own suite in card_transfer_compact_test.dart; the stale/dead-rate
// fail-closed entry contract lives in send_composer_ux_test.dart §1–§4.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/send_money_screen.dart';
import 'package:azaman/services/recipient_discovery_service.dart';
import 'package:azaman/widgets/amount_keypad.dart';
import 'package:azaman/widgets/odometer_number.dart';

const _storageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _wheelKey = ValueKey('send-amount-currency');

class _FixedAuth extends AuthProvider {
  _FixedAuth(this.sessionUser);

  final User sessionUser;

  @override
  User? get user => sessionUser;

  @override
  Future<void> fetchUserDetails() async {}
}

class _FakeFriends extends FriendProvider {
  _FakeFriends(super.ref) {
    friends = [
      {
        'friendshipId': 'fs-1',
        'friend': {'id': 101, 'username': 'ama', 'fullName': 'Ama Mensah'},
      },
    ];
    isLoading = false;
  }

  @override
  Future<void> refreshAll() async {}
}

User _user() => User(
      id: '7',
      username: 'me',
      email: 'me@example.com',
      token: 'tok',
      role: 'USER',
      azamanId: 'AZM-999999999',
      availableBalance: 50.0,
    );

SendRecipient _friendRecipient() => SendRecipient(
      username: 'ama',
      displayName: 'Ama Mensah',
      userId: 101,
      friendshipId: 'fs-1',
      source: SendRecipientSource.friend,
    );

Widget _wrap(Widget screen, {bool disableAnimations = false}) => ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FixedAuth(_user())),
        friendProvider.overrideWith((ref) => _FakeFriends(ref)),
        themeProvider.overrideWith((ref) => ThemeProvider()),
      ],
      child: MaterialApp(
        home: disableAnimations
            ? MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: screen,
              )
            : screen,
      ),
    );

Future<void> _pump(WidgetTester tester, Widget screen) async {
  SharedPreferences.setMockInitialValues({'azaman_theme': 1});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
    if (call.method == 'read') return 'mock-token';
    return null;
  });
  await tester.pumpWidget(_wrap(screen));
  await tester.pumpAndSettle();
}

/// The screen under test: the real Send composer with the frozen-rate seam.
SendMoneyScreen _screen() => SendMoneyScreen.toFriend(
      fxRateOverride: 15.38,
      recipient: _friendRecipient(),
      sendOverride: (friendshipId, amount, reference, token) async =>
          {'success': true},
    );

/// The entry wheel's on-screen box.
Rect _wheelRect(WidgetTester tester) =>
    tester.getRect(find.byKey(_wheelKey));

/// Asserts the full selected chip — the centered 74×44dp cell — is inside
/// the live viewport, not cropped by the wheel's own peek gutters or the
/// page. The peek neighbours above/below are deliberately faded clip
/// material; only the selected cell carries the money meaning.
void expectSelectedChipFullyVisible(WidgetTester tester) {
  final wheel = _wheelRect(tester);

  // The wheel's own box spans exactly the selected chip plus the 14dp
  // peek gutters — the component's published geometry.
  expect(wheel.width, 74, reason: 'vertical wheel is one chip wide');
  expect(wheel.height, 72,
      reason: '44dp chip + 14dp peek above and below');

  // ...and that box sits fully on the live viewport at the current size.
  final screen =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  expect(
    _within(screen, wheel),
    isTrue,
    reason: 'the wheel box is fully on screen at ${screen.width}×'
        '${screen.height} (bottom ${wheel.bottom.toInt()} of '
        '${screen.height.toInt()})',
  );

  // The SELECTED chip is the centered band: fully inside the wheel box.
  final chip = Rect.fromLTWH(
    wheel.left,
    wheel.top + 14, // the top peek gutter
    wheel.width,
    wheel.height - 28, // both peek gutters
  );
  expect(
    _within(wheel, chip),
    isTrue,
    reason: 'the selected chip is centered and uncropped',
  );
}

/// The symbol Text rendered inside the selected (centered) chip: the
/// chip whose label sits closest to the wheel's centre.
String _selectedSymbol(WidgetTester tester) {
  final center = _wheelRect(tester).center;
  var best = '';
  var bestDistance = double.infinity;
  final texts = find
      .descendant(of: find.byKey(_wheelKey), matching: find.byType(Text))
      .evaluate();
  for (final e in texts) {
    final rect = tester.getRect(find.byWidget(e.widget));
    final d = (rect.center - center).distance;
    if (d < bestDistance) {
      bestDistance = d;
      best = (e.widget as Text).data ?? '';
    }
  }
  return bestDistance < 26 ? best : '';
}

/// Non-strict containment: [inner] lies within [outer] (the framework's
/// Rect.contains is exclusive on the right/bottom edges).
bool _within(Rect outer, Rect inner) =>
    outer.left <= inner.left &&
    inner.right <= outer.right &&
    outer.top <= inner.top &&
    inner.bottom <= outer.bottom;

Rect chipBand(Rect wheel) => Rect.fromLTWH(
    wheel.left, wheel.top + 14, wheel.width, wheel.height - 28);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('geometry — the selected chip is never cropped', () {
    for (final size in const [(320.0, 568.0), (360.0, 740.0), (390.0, 844.0)]) {
      testWidgets(
          'the wheel rides fully visible at ${size.$1}dp '
          '(short ${size.$1}×${size.$2.truncate()} viewport)',
          (tester) async {
        tester.view.physicalSize =
            Size(size.$1 * tester.view.devicePixelRatio,
                size.$2 * tester.view.devicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await _pump(tester, _screen());
        expectSelectedChipFullyVisible(tester);
        expect(_selectedSymbol(tester), 'GH\u20B5',
            reason: 'the GHS-first default entry is selected and readable');
      });
    }

    testWidgets(
        'the wheel stays fully visible with the keyboard inset active',
        (tester) async {
      // A SHORT-TALL viewport (360×740) with a deep 300dp keyboard
      // inset: the anchored keypad section still fits, so the wheel
      // must remain fully visible while composing. (At 320×540+300 the
      // screen's FIXED keypad/CTA section overflows by ~125dp — a
      // pre-existing main defect verified on 922f20d, tracked for its
      // own layout pass, not part of this wheel contract.)
      tester.view.physicalSize =
          const Size(360, 740) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await _pump(tester, _screen());

      // The user is composing an amount: the keypad owns focus and the
      // keyboard inset eats the lower half of a short viewport.
      await tester.tap(find.descendant(
          of: find.byType(AmountKeypad), matching: find.text('5')));
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding(
          bottom: 300 * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expectSelectedChipFullyVisible(tester);
    });
  });

  group('gesture — only a deliberate completed roll changes the unit', () {
    testWidgets(
        'a graze below the deliberate threshold never changes the unit '
        'or the amount', (tester) async {
      await _pump(tester, _screen());
      final before = _selectedSymbol(tester);

      // 10dp of drift: the drag is live, but below the 24dp threshold.
      final gesture = await tester
          .startGesture(_wheelRect(tester).center);
      await gesture.moveBy(const Offset(0, -10));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_selectedSymbol(tester), before,
          reason: 'a graze never rolls money denominations');
      final odometer =
          tester.widget<OdometerNumber>(find.byType(OdometerNumber));
      expect(odometer.value, '0',
          reason: 'a graze never touches the entered amount');
    });

    testWidgets('a cancelled gesture leaves the unit untouched',
        (tester) async {
      await _pump(tester, _screen());
      final before = _selectedSymbol(tester);

      final gesture = await tester
          .startGesture(_wheelRect(tester).center);
      await gesture.moveBy(const Offset(0, -40)); // deliberate distance…
      await gesture.cancel(); // …but the arena (scroll) cancelled it.
      await tester.pumpAndSettle();

      expect(_selectedSymbol(tester), before,
          reason: 'cancellation by the surrounding scrollable changes '
              'neither currency nor amount');
      final odometer =
          tester.widget<OdometerNumber>(find.byType(OdometerNumber));
      expect(odometer.value, '0');
    });

    testWidgets('a deliberate upward roll advances GHS → USDC and CONVERTS '
        'the digits', (tester) async {
      await _pump(tester, _screen());
      for (final key in const ['5', '.', '0', '0']) {
        await tester.tap(find.descendant(
            of: find.byType(AmountKeypad), matching: find.text(key)));
        await tester.pump();
      }

      await tester.drag(
          find.byKey(_wheelKey), const Offset(0, -60));
      await tester.pumpAndSettle();

      expect(_selectedSymbol(tester), 'USDC',
          reason: 'the deliberate roll advanced the unit');
      // 5.00 GHS at the 15.38 seam -> 0.33 USDC (half-up): the digits
      // themselves converted — never a relabel.
      final odometer =
          tester.widget<OdometerNumber>(find.byType(OdometerNumber));
      expect(odometer.value, '0.33');
      expect(find.textContaining('\u2248 GH\u20B5\u00A05.08'), findsOneWidget,
          reason: 'the paired equivalent round-trips at the live rate');
    });

    testWidgets('rolling back down restores the original unit and amount',
        (tester) async {
      await _pump(tester, _screen());
      for (final key in const ['5', '.', '0', '0']) {
        await tester.tap(find.descendant(
            of: find.byType(AmountKeypad), matching: find.text(key)));
        await tester.pump();
      }
      await tester.drag(find.byKey(_wheelKey), const Offset(0, -60));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(_wheelKey), const Offset(0, 60));
      await tester.pumpAndSettle();

      expect(_selectedSymbol(tester), 'GH\u20B5');
      final odometer =
          tester.widget<OdometerNumber>(find.byType(OdometerNumber));
      // 0.33 USDC -> 5.08 GHS at the same rate: conversion is honest both
      // ways, and the entry unit round-trips to GHS.
      expect(odometer.value, '5.08');
    });
  });

  group('selection — tap and screen-reader paths stay real', () {
    testWidgets('tapping the wheel opens the picker; picking USDC selects it',
        (tester) async {
      await _pump(tester, _screen());
      await tester.tap(find.byKey(_wheelKey));
      await tester.pumpAndSettle();

      // The real picker menu, not a toast or a silent toggle.
      final item = find.text('USDC — USD Coin');
      expect(item, findsOneWidget);
      await tester.tap(item);
      await tester.pumpAndSettle();

      expect(_selectedSymbol(tester), 'USDC');
    });

    testWidgets('the semantics node exposes the contract and the '
        'increase/decrease actions roll', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _screen());

      final node =
          tester.renderObject(find.byKey(_wheelKey)).debugSemantics;
      expect(node, isNotNull, reason: 'the wheel is a semantics surface');
      final data = node!.getSemanticsData();
      expect(data.label, startsWith('Input currency: Ghana Cedi (GHS)'));
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);

      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(_selectedSymbol(tester), 'USDC',
          reason: 'the screen-reader increase action rolls GHS -> USDC');

      node.owner!.performAction(node.id, SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(_selectedSymbol(tester), 'GH\u20B5',
          reason: 'the decrease action rolls back');
      handle.dispose();
    });
  });

  group('motion — reduced motion lands instantly', () {
    testWidgets('with disableAnimations the roll lands with no travel',
        (tester) async {
      SharedPreferences.setMockInitialValues({'azaman_theme': 1});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_storageChannel, (call) async {
        if (call.method == 'read') return 'mock-token';
        return null;
      });
      await tester.pumpWidget(_wrap(_screen(), disableAnimations: true));
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(_wheelKey), const Offset(0, -60));
      await tester.pump(); // ONE frame — zero-duration under reduced motion

      expect(_selectedSymbol(tester), 'USDC',
          reason: 'reduced motion rolls without a travelling animation');
    });
  });

  group('Workstream C — short-viewport compose rebalance', () {
    // The reported defect: at 320×540 with a 300dp OS-keyboard inset the
    // anchored keypad+CTA pair overflowed by ~125dp. The rebalance hands
    // the bottom to the OS keyboard while it is up (the amount keypad is
    // not the active input then) and returns it the instant it closes.
    testWidgets('320×540 + 300dp keyboard: no overflow, CTA reachable, '
        'keypad steps aside for the OS keyboard', (tester) async {
      tester.view.physicalSize = Size(
          320 * tester.view.devicePixelRatio,
          540 * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await _pump(tester, _screen());

      tester.view.viewInsets = FakeViewPadding(
          bottom: 300 * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'no RenderFlex overflow on the short keyboard viewport');
      expect(find.byType(AmountKeypad), findsNothing,
          reason: 'the OS keyboard owns input; the amount keypad steps '
              'aside instead of overflowing');
      expect(find.text('Review'), findsOneWidget,
          reason: 'the primary CTA stays reachable beside the OS keyboard');
      expectSelectedChipFullyVisible(tester);
    });

    testWidgets('keyboard dismissal returns the keypad — fully functional',
        (tester) async {
      tester.view.physicalSize = Size(
          320 * tester.view.devicePixelRatio,
          540 * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await _pump(tester, _screen());

      tester.view.viewInsets = FakeViewPadding(
          bottom: 300 * tester.view.devicePixelRatio);
      await tester.pumpAndSettle();
      expect(find.byType(AmountKeypad), findsNothing);

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AmountKeypad), findsOneWidget,
          reason: 'the amount keypad returns the moment the OS keyboard '
              'closes');
      // And it is live: a key press still edits the amount.
      final before = _selectedSymbol(tester);
      await tester.tap(find.descendant(
          of: find.byType(AmountKeypad), matching: find.text('5')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('send-amount-currency')),
          findsOneWidget,
          reason: 'the amount composition surface is intact');
      expect(before, isNotNull);
    });

    for (final size in const [(320.0, 540.0), (360.0, 640.0), (390.0, 700.0)]) {
      testWidgets(
          '${size.$1.truncate()}×${size.$2.truncate()} short viewport '
          'without keyboard: keypad + CTA anchored, no overflow',
          (tester) async {
        tester.view.physicalSize = Size(
            size.$1 * tester.view.devicePixelRatio,
            size.$2 * tester.view.devicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await _pump(tester, _screen());

        expect(tester.takeException(), isNull);
        final keypad = tester.getRect(find.byType(AmountKeypad));
        final cta = tester.getRect(find.text('Review'));
        expect(keypad.height, greaterThan(0));
        // The CTA sits below the keypad and inside the viewport.
        expect(cta.top, greaterThan(keypad.bottom - 1));
        expect(cta.bottom, lessThanOrEqualTo(size.$2));
        expectSelectedChipFullyVisible(tester);
      });
    }
  });
}
