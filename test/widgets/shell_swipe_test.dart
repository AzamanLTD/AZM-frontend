// =============================================================================
// PR-B — shell swipe between the three primary destinations
//
// On the REAL MainWrapper (same harness as the ticker-budget guard):
//
//   * a deliberate left swipe moves Home → Chat → Marketplace (content
//     follows the finger: left reveals the destination to the right),
//     a right swipe moves back the same way — through the shell's ONE
//     selection contract (_onNavItemSelected): the nav's selected
//     index, the shell bus, the ticker budget and the retap registry
//     all follow;
//   * NO WRAP at either boundary: past Home/Marketplace a swipe in the
//     out-of-range direction does nothing;
//   * a vertical drag on a scrollable page NEVER commits a swipe
//     (vertical scroll stays the page's own);
//   * an indeterminate drag below the deliberate threshold commits
//     nothing;
//   * a fling commits even under the travel threshold (real velocity,
//     same direction);
//   * pages stay MOUNTED and a visited page's scroll offset is
//     preserved across a swipe away and back — a swipe is NOT a retap
//     (the retap spring never fires from a swipe);
//   * while the + launcher is open the shell swipe is suspended
//     (launcher owns the screen) and resumes when it closes.
// =============================================================================

import '../support/money_access_test_support.dart';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
import 'package:azaman/widgets/contextual_nav_band.dart' show appShellBus;
import 'package:azaman/screens/home_screen.dart' show AzamanHomePage;
import 'package:azaman/services/business_service.dart';
import 'package:azaman/widgets/home/plus_action_launcher.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';
import 'package:azaman/widgets/shell_swipe_detector.dart';
import 'package:azaman/widgets/marketplace/profile_joystick.dart';

bool _fontsLoaded = false;

Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final bytes = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final loader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
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

void _select(WidgetTester tester, int index) {
  tester
      .widget<PremiumBottomNav>(find.byType(PremiumBottomNav))
      .onItemSelected
      .call(index);
}

/// Seed a non-top scroll offset on home's outer list.

/// Tap the real + trigger and pump through the logo-fill (the launcher
/// opens only after the LAST fill segment completes — the open call is
/// an awaited animation future, so it resolves BETWEEN frames, which a
/// single big pump steps over).
Future<void> _openLauncher(WidgetTester tester) async {
  await tester.tap(find.byType(PlusLauncherTrigger));
  for (var ms = 0; ms < 800; ms += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _scrollHomeTo(WidgetTester tester, double pixels) async {
  final elements = find
      .descendant(
        of: find.byType(AzamanHomePage, skipOffstage: false),
        matching: find.byType(Scrollable, skipOffstage: false),
      )
      .evaluate();
  for (final element in elements) {
    final state = (element as StatefulElement).state as ScrollableState;
    final position = state.position;
    if (position.axis == Axis.vertical && position.maxScrollExtent > 0) {
      position.jumpTo(pixels.clamp(0, position.maxScrollExtent));
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
      return;
    }
  }
  fail('home outer scrollable not found');
}

int _selectedIndex(WidgetTester tester) => tester
    .widget<PremiumBottomNav>(find.byType(PremiumBottomNav))
    .selectedIndex;

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(400, 800),
}) async {
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
    // The drawer peek hint schedules a 900ms delay + a 2200ms show
    // animation on first mount — suppress it, this suite is about
    // the swipe contract.
    'has_seen_drawer_peek_hint': true,
  });
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(size);

  final container = ProviderContainer(
    overrides: [
      auth_pkg.authProvider.overrideWith((ref) => auth_pkg.AuthProvider()),
      // This suite's subject is the launcher/captures, so money starts
      // unlocked; the privacy gate has its own suites.
      unlockedMoneyAccess(),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 100),
      ),
      oracleRateProvider.overrideWith((ref) => 1.0),
      businessSearchProvider.overrideWith((ref) => _InertSearchNotifier()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const MainWrapper(),
        ),
      ),
    ),
  );
  // First frame + entrance one-shots.
  await tester.pump(const Duration(milliseconds: 600));
}

/// A deliberate committed swipe on the shell's page surface (the body
/// area, clear of the bottom nav and the header chrome).
Future<void> _swipe(
  WidgetTester tester,
  double dx, {
  Offset from = const Offset(200, 400),
}) async {
  final gesture = await tester.startGesture(from);
  // Cross the slop in steps so the horizontal recognizer accepts
  // deliberately, not by fluke of a single synthetic jump.
  await gesture.moveBy(Offset(dx * 0.4, 0));
  await gesture.moveBy(Offset(dx * 0.6, 0));
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 40));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 100));
}

/// The home page's outermost scrollable offset (the retap registry's
/// scrollable), so state preservation can be measured honestly.
double _homeScrollOffset(WidgetTester tester) {
  final scrollables = find
      .descendant(
        of: find.byType(AzamanHomePage, skipOffstage: false),
        matching: find.byType(Scrollable, skipOffstage: false),
      )
      .evaluate();
  // The outer list = the VERTICAL scrollable with the largest extent
  // (nested rails and page-internal lists are smaller or horizontal).
  ScrollableState? outer;
  for (final element in scrollables) {
    final state = (element as StatefulElement).state as ScrollableState;
    final position = state.position;
    if (position.axis == Axis.vertical &&
        (outer == null ||
            position.maxScrollExtent > outer.position.maxScrollExtent)) {
      outer = state;
    }
  }
  return outer?.position.pixels ?? 0;
}

void main() {
  // ONE transition per testWidgets (the live shell schedules timers
  // that must drain; a second transition before teardown leaks them —
  // harness lesson from the quiet-depth captures suite).
  testWidgets('a deliberate left swipe moves Home → Chat', (tester) async {
    await _pumpShell(tester);
    expect(_selectedIndex(tester), 0);
    expect(appShellBus.activeTab, 0);

    await _swipe(tester, -240);
    expect(_selectedIndex(tester), 1, reason: 'Home → Chat');
    expect(appShellBus.activeTab, 1);
  });

  testWidgets('from Chat, a left swipe moves Chat → Marketplace', (
    tester,
  ) async {
    await _pumpShell(tester);
    _select(tester, 1);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_selectedIndex(tester), 1);

    await _swipe(tester, -240);
    expect(_selectedIndex(tester), 2, reason: 'Chat → Marketplace');
    expect(appShellBus.activeTab, 2);
  });

  testWidgets('from Marketplace, a right swipe moves Marketplace → Chat', (
    tester,
  ) async {
    await _pumpShell(tester);
    _select(tester, 2);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_selectedIndex(tester), 2);

    await _swipe(tester, 240);
    expect(_selectedIndex(tester), 1, reason: 'Marketplace → Chat');
  });

  testWidgets('from Chat, a right swipe moves Chat → Home', (tester) async {
    await _pumpShell(tester);
    _select(tester, 1);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_selectedIndex(tester), 1);

    await _swipe(tester, 240);
    expect(_selectedIndex(tester), 0, reason: 'Chat → Home');
  });

  testWidgets('NO WRAP: a rightward swipe on Home does nothing', (
    tester,
  ) async {
    await _pumpShell(tester);

    await _swipe(tester, 240);
    expect(_selectedIndex(tester), 0, reason: 'no wrap before Home');
  });

  testWidgets('NO WRAP: a leftward swipe on Marketplace does nothing', (
    tester,
  ) async {
    await _pumpShell(tester);
    _select(tester, 2);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_selectedIndex(tester), 2);

    await _swipe(tester, -240);
    expect(_selectedIndex(tester), 2, reason: 'no wrap past Marketplace');
  });

  testWidgets('a vertical drag scrolls the page and never commits a swipe', (
    tester,
  ) async {
    await _pumpShell(tester);

    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -180)); // vertical-dominant
    await gesture.moveBy(const Offset(12, -120));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 800));

    expect(
      _selectedIndex(tester),
      0,
      reason: 'vertical scrolling must never switch tabs',
    );
  });

  testWidgets('an indeterminate drag below the threshold commits nothing', (
    tester,
  ) async {
    await _pumpShell(tester);

    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(-40, 0)); // over slop, under 56
    await gesture.moveBy(const Offset(12, 0)); // wander back
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 800));

    expect(
      _selectedIndex(tester),
      0,
      reason: 'below-threshold horizontal wander is not a swipe',
    );
  });

  testWidgets('a fling commits even under the travel threshold', (
    tester,
  ) async {
    await _pumpShell(tester);

    // 45px of travel in ~40ms ≈ 1100 px/s — a real flick, under the
    // 56px travel threshold, over the 350 px/s fling threshold. Widget-
    // test gestures carry zero timestamps by default (the velocity
    // tracker would see no time at all), so the flick is dispatched
    // with explicit event timestamps.
    final pointer = TestPointer(5, PointerDeviceKind.touch);
    var t = 0;
    await tester.sendEventToBinding(pointer.down(const Offset(200, 400)));
    for (var i = 1; i <= 5; i++) {
      t += 8;
      await tester.sendEventToBinding(
        pointer.move(
          Offset(200 - 9.0 * i, 400),
          timeStamp: Duration(milliseconds: t),
        ),
      );
    }
    await tester.sendEventToBinding(
      pointer.up(timeStamp: const Duration(milliseconds: 42)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _selectedIndex(tester),
      1,
      reason: 'a deliberate flick in the same direction commits',
    );
  });

  testWidgets('swipes preserve the page tree: a visited page keeps its scroll '
      'position across a swipe away and back (a swipe is NOT a retap)', (
    tester,
  ) async {
    await _pumpShell(tester);

    // Seed a non-top scroll offset on home's outer list. (Position-
    // driven: the home finger-scroll path is covered by the nav-band,
    // retap and doorway suites — here only preservation matters.)
    await _scrollHomeTo(tester, 40);
    final before = _homeScrollOffset(tester);
    expect(before, greaterThan(0), reason: 'the home list is scrolled');

    // The page stays MOUNTED while away, and returns untouched.
    _select(tester, 1);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byType(AzamanHomePage),
      findsOneWidget,
      reason: 'pages stay mounted across a swipe',
    );
    expect(
      _homeScrollOffset(tester),
      before,
      reason:
          'the mounted home page keeps its scroll offset while '
          'another tab is active — untouched, not reset',
    );
  });

  testWidgets('a swipe back to Home finds the list exactly where it was', (
    tester,
  ) async {
    await _pumpShell(tester);

    await _scrollHomeTo(tester, 40);
    final before = _homeScrollOffset(tester);
    expect(before, greaterThan(0), reason: 'the home list is scrolled');

    await _swipe(tester, -240); // → Chat
    expect(find.byType(AzamanHomePage), findsOneWidget);

    await _swipe(tester, 240); // → Home
    expect(
      _homeScrollOffset(tester),
      before,
      reason:
          'swipe away and back preserves scroll; the retap spring '
          'never fired (that would have sprung the list to the top)',
    );
  });

  testWidgets('while the + launcher is open the shell swipe is suspended', (
    tester,
  ) async {
    await _pumpShell(tester);

    // Open the real launcher through its real trigger.
    final trigger = find.byType(PlusLauncherTrigger);
    expect(trigger, findsOneWidget);
    await _openLauncher(tester);
    expect(
      tester
          .widget<PlusActionLauncher>(find.byType(PlusActionLauncher))
          .controller
          .isOpen,
      isTrue,
      reason: 'the real trigger opened the real launcher',
    );

    await _swipe(tester, -240);
    expect(
      _selectedIndex(tester),
      0,
      reason: 'the launcher owns the screen — no tab switch',
    );
  });

  testWidgets('once the + launcher closes the swipe contract resumes', (
    tester,
  ) async {
    await _pumpShell(tester);

    await _openLauncher(tester); // open
    await tester.tap(find.byType(PlusLauncherTrigger)); // close (toggle)
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      tester
          .widget<PlusActionLauncher>(find.byType(PlusActionLauncher))
          .controller
          .isOpen,
      isFalse,
      reason: 'the toggle closed the launcher',
    );

    await _swipe(tester, -240);
    expect(
      _selectedIndex(tester),
      1,
      reason: 'with the launcher closed the swipe contract resumes',
    );
  });

  testWidgets(
    'a cancelled in-flight swipe fires nothing (no commit, no unwind)',
    (tester) async {
      await _pumpShell(tester);

      final gesture = await tester.startGesture(const Offset(200, 400));
      await gesture.moveBy(const Offset(-120, 0)); // deliberate-looking…
      await gesture.cancel(); // …then the system takes it away
      await tester.pump(const Duration(milliseconds: 800));

      expect(
        _selectedIndex(tester),
        0,
        reason: 'a cancelled swipe never commits',
      );
    },
  );

  testWidgets('the shell body is the ShellSwipeDetector (exact wiring)', (
    tester,
  ) async {
    await _pumpShell(tester);
    // The detector is ANCESTOR of the page stack and descendant of the
    // Scaffold — the exact wiring PR-B ships.
    final detector = find.byType(ShellSwipeDetector);
    expect(detector, findsOneWidget);
    expect(
      find.descendant(of: detector, matching: find.byType(AzamanHomePage)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: detector, matching: find.byType(Scaffold)),
      findsOneWidget,
    );
  });

  // ─────────────────────────────────────────────────────────────────────
  // ARENA HONESTY (closeout): nested horizontal content and the
  // ProfileJoystick keep their own gestures — the shell swipe NEVER
  // hijacks a deeper horizontal control.
  // ─────────────────────────────────────────────────────────────────────

  testWidgets('a nested horizontal control row keeps its drag: the strip '
      'scrolls, the shell does NOT switch tabs', (tester) async {
    // At 360dp the marketplace control row genuinely overflows (16px,
    // documented in _controlRow) — so the inner horizontal scrollable
    // has real travel and the arena contest is real.
    await _pumpShell(tester, size: const Size(360, 800));
    _select(tester, 2); // Marketplace
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_selectedIndex(tester), 2);

    // The marketplace's horizontal SingleChildScrollView control row
    // (category dial + Mix + Near You).
    final horizontalScrolls = find
        .byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        )
        .evaluate();
    StatefulElement? stripElement;
    for (final e in horizontalScrolls) {
      final scrollables = find
          .descendant(
            of: find.byElementPredicate((el) => el == e),
            matching: find.byType(Scrollable),
          )
          .evaluate();
      for (final se in scrollables) {
        final state = (se as StatefulElement).state as ScrollableState;
        if (state.position.maxScrollExtent > 0) {
          stripElement = se;
          break;
        }
      }
      if (stripElement != null) break;
    }
    expect(
      stripElement,
      isNotNull,
      reason:
          'at 360dp the marketplace control row must have real '
          'travel (its documented 16px overflow)',
    );
    final strip = (stripElement!.state as ScrollableState).position;
    final before = strip.pixels;
    final stripCenter = tester.getCenter(
      find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
    );

    // A deliberate horizontal drag ON the strip (arena contest: the
    // strip's own recognizer vs the shell's ancestor detector).
    final gesture = await tester.startGesture(stripCenter);
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      strip.pixels,
      greaterThan(before),
      reason: 'the INNER horizontal strip consumed the drag',
    );
    expect(
      _selectedIndex(tester),
      2,
      reason:
          'the shell swipe NEVER fires under a nested horizontal '
          'control — the strip won its arena',
    );
  });

  testWidgets('the ProfileJoystick keeps its own drag: the shell detector '
      'never hijacks the dial', (tester) async {
    // The joystick wins its arena at pointer-down (PR #204's design).
    // Compose it DIRECTLY under a ShellSwipeDetector — a strictly
    // harsher arena than the real shell, where pushed surfaces sit
    // ABOVE the detector's subtree entirely — and prove a deliberate
    // horizontal drag on the dial fires the joystick's action and
    // never the shell's swipe.
    var shellSwipes = 0;
    var bookmarks = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: ShellSwipeDetector(
                onAdjacentSwipe: (_) => shellSwipes++,
                child: SizedBox(
                  width: 300,
                  height: 300,
                  child: Center(
                    child: ProfileJoystick(
                      semanticLabel: 'Test shortcuts',
                      actions: ProfileJoystickActions(
                        menu: ProfileJoystickAction(
                          icon: Icons.menu,
                          label: 'Menu',
                          onRelease: () {},
                        ),
                        story: ProfileJoystickAction(
                          icon: Icons.auto_awesome,
                          label: 'Story',
                          onRelease: () {},
                        ),
                        bookmark: ProfileJoystickAction(
                          icon: Icons.bookmark_add_outlined,
                          label: 'Save',
                          onRelease: () => bookmarks++,
                        ),
                        showLess: ProfileJoystickAction(
                          icon: Icons.expand_less,
                          label: 'Show less',
                          onRelease: () {},
                        ),
                      ),
                      onLongPress: () {},
                      child: const SizedBox(
                        width: 72,
                        height: 72,
                        child: ColoredBox(color: Colors.amber),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final center = tester.getCenter(find.byType(ProfileJoystick));
    final gesture = await tester.startGesture(center);
    // A deliberate rightward drag: the joystick's SAVE (bookmark)
    // direction — the same motion that would be a shell "previous tab"
    // swipe if the ancestor could steal it.
    await gesture.moveBy(const Offset(60, 0));
    await gesture.moveBy(const Offset(60, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      bookmarks,
      1,
      reason: 'the JOYSTICK consumed the drag (its save action fired)',
    );
    expect(
      shellSwipes,
      0,
      reason:
          'the shell swipe never fires on the ProfileJoystick — the '
          'dial wins the arena at pointer-down',
    );
  });
}
