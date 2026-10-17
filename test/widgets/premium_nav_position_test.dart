// =============================================================================
// NEW-LEFT (logo position) — the AZM logo/action launcher sits on the LEFT of
// the centred bottom-navigation pill.
//
// Pins the POSITION contracts of the combined [logo + pill] composition:
//   1. ADJACENCY — the launcher is immediately adjacent to the pill, on the
//      pill's LEFT (never to its right), vertically centred on it.
//   2. CENTRING — the combined group ([launcher][gap][pill]) is visually
//      CENTRED in the band as ONE responsive composition: its centre equals
//      the surface centre (within the symmetric outer inset), at normal AND
//      narrow widths.
//   3. NARROW WIDTHS — the same position contract holds at 320px with no
//      overflow, every segment keeps its 44dp touch target, and the launcher
//      never leaves the composition.
//   4. FOCUSED MARKETPLACE — the launcher departs to the LEFT (its own side
//      of the composition), releasing its layout space.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/marketplace_nav_focus.dart';
import 'package:azaman/providers/chat_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';

Widget _harness({
  required int selectedIndex,
  required Size size,
  bool focused = false,
}) {
  return ProviderScope(
    overrides: [
      totalUnreadChatCountProvider.overrideWith((ref) async => 0),
      activeTradeCountProvider.overrideWith((ref) async => 0),
      unreadCountProvider.overrideWith((ref) => 0),
      marketplaceNavFocusProvider.overrideWith((ref) => focused),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: Scaffold(
          bottomNavigationBar: PremiumBottomNav(
            selectedIndex: selectedIndex,
            onItemSelected: (_) {},
            leading: const SizedBox(
              key: ValueKey('plus-stand-in'),
              width: 54,
              height: 54,
            ),
          ),
        ),
      ),
    ),
  );
}

Rect _pillRect(WidgetTester tester) => tester.getRect(
  find
      .descendant(
        of: find.byType(PremiumBottomNav),
        matching: find.byType(AnimatedContainer),
      )
      .first,
);

Rect _plusRect(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('plus-stand-in')));

/// The band's REAL width (the test window, not the harness MediaQuery —
/// Scaffold sizes bottomNavigationBar from the window).
double _bandWidth(WidgetTester tester) =>
    tester.getSize(find.byType(PremiumBottomNav)).width;

void _pinPosition(WidgetTester tester, double surfaceWidth) {
  final plus = _plusRect(tester);
  final pill = _pillRect(tester);

  // 1. ADJACENCY — the launcher is on the pill's LEFT, immediately
  // adjacent (no gap larger than the band's own seam token).
  expect(
    plus.right,
    lessThanOrEqualTo(pill.left),
    reason: 'the launcher sits to the pill’s LEFT',
  );
  expect(
    pill.left - plus.right,
    lessThanOrEqualTo(AzSpace.sm),
    reason: 'the launcher is immediately adjacent to the pill',
  );
  expect(
    plus.left,
    lessThan(pill.left),
    reason: 'the launcher is never on the pill’s right',
  );
  expect(
    plus.center.dx,
    lessThan(pill.center.dx),
    reason: 'the whole launcher sits left of the pill',
  );

  // 2. VERTICAL CENTRING — the launcher and the pill share one band:
  // vertically centred on each other.
  expect(
    (plus.center.dy - pill.center.dy).abs(),
    lessThan(1.0),
    reason: 'the launcher is vertically centred on the pill',
  );

  // 3. CENTRING — the combined group is ONE composition centred in the
  // band: [launcher … pill] spans a group whose centre is the surface
  // centre (the symmetric outer inset keeps the composition centred on
  // the real viewport centre, never hugging an edge).
  final groupCentre = (plus.left + pill.right) / 2;
  expect(
    (groupCentre - surfaceWidth / 2).abs(),
    lessThan(1.0),
    reason: 'the [logo + pill] group is visually centred',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NEW-LEFT position — normal width', () {
    testWidgets('the launcher sits immediately LEFT of the centred pill '
        'as one composition (430px)', (tester) async {
      await tester.pumpWidget(
        _harness(selectedIndex: 0, size: const Size(430, 200)),
      );
      await tester.pumpAndSettle();

      _pinPosition(tester, _bandWidth(tester));
      // The labelled pill is the rest identity on a normal surface.
      expect(find.text('Home'), findsOneWidget);
      // Every segment keeps its 44dp touch target.
      for (var i = 0; i < 3; i++) {
        final rect = tester.getRect(find.byKey(ValueKey('nav-item-$i')));
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('the same position contract holds for the Market tab '
        '(390px)', (tester) async {
      await tester.pumpWidget(
        _harness(selectedIndex: 2, size: const Size(390, 200)),
      );
      await tester.pumpAndSettle();

      _pinPosition(tester, _bandWidth(tester));
      expect(find.byKey(const ValueKey('plus-stand-in')), findsOneWidget);
    });
  });

  group('NEW-LEFT position — narrow width', () {
    testWidgets('at 320px the launcher stays immediately LEFT, the group '
        'stays centred, and nothing overflows', (tester) async {
      tester.view.physicalSize = const Size(320, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _harness(selectedIndex: 0, size: const Size(320, 200)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'no overflow at 320px');
      _pinPosition(tester, _bandWidth(tester));
      // The composition stays responsive: the pill compresses (label may
      // fall back to the icon identity) instead of pushing the group off
      // centre or clipping.
      expect(
        find.byKey(const ValueKey('plus-stand-in')),
        findsOneWidget,
        reason: 'the launcher never leaves the composition',
      );
      for (var i = 0; i < 3; i++) {
        final rect = tester.getRect(find.byKey(ValueKey('nav-item-$i')));
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('at a 260px sub-label surface the centring holds with the '
        'icon-only pill (responsive composition)', (tester) async {
      // 260 is the composition's floor with the launcher mounted: the
      // three 44dp anchors (132) + the pill's own padding (16) + the seam
      // (8) + the launcher (54) + the symmetric outer insets (32) — a
      // 240px surface cannot fit the launcher at all (242px minimum),
      // so the sub-label proof runs at the honest floor.
      tester.view.physicalSize = const Size(260, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _harness(selectedIndex: 0, size: const Size(260, 200)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      _pinPosition(tester, _bandWidth(tester));
    });
  });

  group('NEW-LEFT position — focused Marketplace departure', () {
    testWidgets('the launcher departs to the LEFT of the composition '
        '(its own side), releasing its layout space', (tester) async {
      // Rest position first.
      await tester.pumpWidget(
        _harness(selectedIndex: 2, size: const Size(430, 200)),
      );
      await tester.pumpAndSettle();
      final restLeft = _plusRect(tester).left;

      // Enter the focused Marketplace composition mid-animation. The live
      // provider state is flipped in place (ProviderScope overrides are
      // read once at mount, so a re-pump with new overrides would be
      // ignored): the launcher's push-out runs toward ITS OWN side (LEFT),
      // never right.
      ProviderScope.containerOf(
        tester.element(find.byType(PremiumBottomNav)),
      ).read(marketplaceNavFocusProvider.notifier).state = true;
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        _plusRect(tester).left,
        lessThan(restLeft),
        reason: 'the exit push moves the launcher LEFT',
      );
      // (The pill surface legitimately expands into the released width —
      // the focused search composition owns the band by design; the
      // departure contract is the launcher's direction and final state.)

      // Fully out: the layout space is released and the pill recentres as
      // the sole composition (the search field owns the width).
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plus-stand-in')), findsNothing);
      final pill = _pillRect(tester);
      // The focused composition is CONTENT-SIZED: its interior asymmetry
      // (the back-arrow affordance) is a few px on the test surface, so
      // the tolerance covers the content's own breathing room while
      // still pinning the centred composition (a left-anchored pill would
      // be ~380px off centre here).
      expect(
        (pill.center.dx - _bandWidth(tester) / 2).abs(),
        lessThan(6.0),
        reason: 'the pill alone stays centred after the launcher exits',
      );
    });
  });
}
