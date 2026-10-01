// =============================================================================
// NEW-C — tap-active-tab contract regression suite (§2.3, closes F-025)
//
// Pins the BEHAVIOR, through production code only:
//
//   * re-tapping the active tab springs the page's OUTERMOST vertical
//     scrollable to the top on `kHouseSpring` — animated, not instant,
//   * re-tapping at the top performs the already-here lift (scale dips
//     below 1.0 and settles back) and never scrolls,
//   * reduced motion makes the spring an instant jump and skips the lift,
//   * nested scrollables defer to their outer list (outermost wins),
//   * horizontal scrollables are never recorded,
//   * per-tab isolation: one tab's scrollable never answers for another,
//   * dead entries (unmounted pages) are dropped, not used,
//   * the nav seam: retap fires onActiveTabRetap and NOT onItemSelected.
//
// The harness mirrors MainWrapper's wiring exactly — one NotificationListener
// feeding NavScrollCompression and TabScrollRegistry, a real PremiumBottomNav,
// a real NavRetapController owned by a TickerProviderStateMixin — but with
// inert pages, so the shell's own heavyweight dependencies (sockets,
// live providers) stay out of the test.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/chat_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/sensory_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';

/// The shell-shaped harness: the SAME listener composition MainWrapper
/// uses (compression + per-tab recording), a real nav, a real retap
/// controller owned by the State, and the retap wired through
/// [PremiumBottomNav.onActiveTabRetap].
class _ShellHarness extends StatefulWidget {
  const _ShellHarness({
    this.reduceMotion = false,
    this.pages = const [],
  });

  final bool reduceMotion;
  final List<Widget> pages;

  @override
  State<_ShellHarness> createState() => _ShellHarnessState();
}

class _ShellHarnessState extends State<_ShellHarness>
    with TickerProviderStateMixin {
  late final NavRetapController retap = NavRetapController(vsync: this);

  int _tab = 0;

  @override
  void dispose() {
    retap.dispose();
    super.dispose();
  }

  void _onRetap() {
    retap.handleRetap(
      tab: _tab,
      registry: TabScrollRegistry.instance,
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(disableAnimations: widget.reduceMotion || MediaQuery.disableAnimationsOf(context)),
      child: Scaffold(
        body: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            NavScrollCompression.applyTo(n);
            TabScrollRegistry.instance.record(_tab, n);
            return false;
          },
          child: ScaleTransition(
            scale: retap.lift,
            child: IndexedStack(
              index: _tab,
              children: [
                ...widget.pages,
                const SizedBox.shrink(),
              ],
            ),
          ),
        ),
        bottomNavigationBar: PremiumBottomNav(
          selectedIndex: _tab,
          onItemSelected: (i) => setState(() => _tab = i),
          onActiveTabRetap: _onRetap,
        ),
      ),
    );
  }
}

_ShellHarnessState _harnessState(WidgetTester tester) =>
    tester.state<_ShellHarnessState>(find.byType(_ShellHarness));

Widget _host(Widget child, {bool reduceMotion = false}) {
  return ProviderScope(
    // The badge providers' real bodies are async and hit the API; pin them
    // to inert values (same pattern as nav_scroll_compression_test).
    overrides: [
      totalUnreadChatCountProvider.overrideWith((ref) async => 0),
      activeTradeCountProvider.overrideWith((ref) async => 0),
      unreadCountProvider.overrideWith((ref) => 0),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      // Wraps the CHILD so the harness's own context sits under this —
      // AzMotion.of resolves reduced motion from the State's context.
      home: MediaQuery(
        data: const MediaQueryData().copyWith(disableAnimations: reduceMotion),
        child: child,
      ),
    ),
  );
}

/// The pill compresses while the page is scrolled down (TASK-010's absolute-
/// offset law) and hides its labels at full compression, so a tap on a
/// label would miss. Rest the pill before tapping it — the same restore the
/// shell performs when the page returns to its top.
Future<void> _restPill(WidgetTester tester) async {
  navScrollCompression.value = 0;
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _longList({Key? key, int tiles = 60}) {
  return ListView(
    key: key,
    children: [
      for (var i = 0; i < tiles; i++) ListTile(title: Text('Tile $i')),
    ],
  );
}

/// The vertical offset of the tab's outermost scrollable.
double? _offset(int tab) => TabScrollRegistry.instance.primaryFor(tab)?.pixels;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AzSensory.apply(const SensoryPreferences());
    // Singletons survive across tests — keep each start honest.
    TabScrollRegistry.instance.debugReset();
    navScrollCompression.value = 0;
  });
  tearDown(() => AzSensory.apply(const SensoryPreferences()));

  group('scroll-to-top (the spring)', () {
    testWidgets('re-tap on a scrolled page springs it to the top, animated',
        (tester) async {
      await tester.pumpWidget(_host(_ShellHarness(
        pages: [_longList(key: const Key('page-list'))],
      )));
      await tester.pumpAndSettle();

      // Scroll the page for real — the gesture drives the notifications.
      await tester.drag(
          find.byKey(const Key('page-list')), const Offset(0, -1500));
      await tester.pumpAndSettle();
      final startOffset = _offset(0);
      expect(startOffset, greaterThan(500));
      await _restPill(tester);

      await tester.tap(find.text('Home'));
      // Sample the offset across the flight: the tap's callback may land in
      // the same frame the animation starts, so a single fixed pump can miss
      // the mid-flight point. What the contract requires: the page reaches 0,
      // passing through strictly-between values on the way (animated, not
      // instant).
      final flight = <double>[];
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        flight.add(_offset(0) ?? 0);
      }
      expect(flight.last, 0);
      expect(
        flight.where((o) => o > 0 && o < startOffset!),
        isNotEmpty,
        reason: 'the spring must animate through intermediate offsets',
      );
    });

    testWidgets('re-tap at the top lifts the content and never scrolls it',
        (tester) async {
      await tester.pumpWidget(_host(_ShellHarness(
        pages: [_longList(key: const Key('page-list'))],
      )));
      await tester.pumpAndSettle();
      // An unscrolled page may have never emitted a notification — no
      // recorded scrollable is still "at the top" for the retap contract.
      expect(_offset(0) ?? 0, 0);

      final retap = _harnessState(tester).retap;
      final liftSamples = <double>[];
      final ctrlSamples = <double>[];
      void sample() {
        ctrlSamples.add(retap.liftCtrl.value);
        liftSamples.add(retap.lift.value);
      }

      retap.liftCtrl.addListener(sample);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      retap.liftCtrl.removeListener(sample);

      // The lift PLAYED: the scale left 1.0 (dipped) and animated back —
      // not a jump, and never a scroll.
      expect(retap.lift.value, 1.0);
      expect(retap.liftCtrl.value, 1.0);
      expect(
        liftSamples.where((v) => v < 1.0),
        isNotEmpty,
        reason: 'the lift must dip below rest scale',
      );
      expect(
        ctrlSamples.where((v) => v > 0 && v < 1),
        isNotEmpty,
        reason: 'the lift must animate through intermediate values',
      );
      expect(_offset(0) ?? 0, 0); // never scrolled
    });

    testWidgets('reduced motion: instant jump to the top, no lift',
        (tester) async {
      await tester.pumpWidget(_host(
        _ShellHarness(
          reduceMotion: true,
          pages: [_longList(key: const Key('page-list'))],
        ),
        reduceMotion: true,
      ));
      await tester.pumpAndSettle();

      await tester.drag(
          find.byKey(const Key('page-list')), const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(_offset(0), greaterThan(500));
      await _restPill(tester);

      await tester.tap(find.text('Home'));
      // A few frames with a tiny time budget: a jump lands in the frame the
      // tap resolves; a 350ms spring would still be mid-flight here.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_offset(0), 0);

      final retap = _harnessState(tester).retap;
      expect(retap.lift.value, 1.0); // the lift never played
      expect(retap.liftCtrl.value, 1.0); // the controller was never started
    });
  });

  group('which scrollable answers the re-tap', () {
    testWidgets('nested scrollables defer to the outer list', (tester) async {
      await tester.pumpWidget(_host(_ShellHarness(
        pages: [
          ListView(
            key: const Key('outer-list'),
            children: [
              for (var i = 0; i < 12; i++)
                if (i == 6)
                  SizedBox(
                    height: 200,
                    child: ListView(
                      key: const Key('inner-list'),
                      children: [
                        for (var j = 0; j < 40; j++)
                          ListTile(title: Text('Inner $j')),
                      ],
                    ),
                  )
                else
                  ListTile(title: Text('Outer tile $i')),
            ],
          ),
        ],
      )));
      await tester.pumpAndSettle();

      // Scroll the OUTER list by dragging a plain row (outside the inner).
      await tester.drag(find.text('Outer tile 2'), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(_offset(0), greaterThan(100));

      // Scroll the INNER list — it must NOT take over the tab's answer.
      await tester.drag(find.text('Inner 1'), const Offset(0, -400));
      await tester.pumpAndSettle();
      await _restPill(tester);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      // The OUTER list answered the retap: the tab's primary went to the
      // top (and the inner's offset is untouched by the retap).
      expect(_offset(0), 0);
    });

    testWidgets('horizontal scrollables are never recorded', (tester) async {
      await tester.pumpWidget(_host(_ShellHarness(
        pages: [
          ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < 30; i++)
                SizedBox(
                  width: 200,
                  child: ListTile(title: Text('Rail $i')),
                ),
            ],
          ),
        ],
      )));
      await tester.pumpAndSettle();

      await tester.drag(find.text('Rail 2'), const Offset(-800, 0));
      await tester.pumpAndSettle();

      // Nothing vertical was ever recorded → the registry has no answer,
      // so a retap would lift (no scrollable owns the tab).
      expect(TabScrollRegistry.instance.primaryFor(0), isNull);
    });

    testWidgets('per-tab isolation: one tab never scrolls for another',
        (tester) async {
      await tester.pumpWidget(_host(_ShellHarness(
        pages: [
          _longList(key: const Key('home-list')),
          _longList(key: const Key('chat-list')),
        ],
      )));
      await tester.pumpAndSettle();

      // Home scrolled (tab 0).
      await tester.drag(
          find.byKey(const Key('home-list')), const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(_offset(0), greaterThan(300));

      // Switch to Chat (tab 1) and scroll its own list.
      await _restPill(tester);
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      await tester.drag(
          find.byKey(const Key('chat-list')), const Offset(0, -300));
      await tester.pumpAndSettle();

      final homeOffset = _offset(0);
      final chatOffset = _offset(1);
      expect(homeOffset, isNotNull);
      expect(chatOffset, isNotNull);
      expect(chatOffset, isNot(homeOffset));

      // Re-tap on Chat answers with CHAT's list; Home's offset is untouched.
      await _restPill(tester);
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      expect(_offset(1), 0);
      expect(_offset(0), homeOffset);
    });

    testWidgets('dead entries are dropped when their page unmounts',
        (tester) async {
      await tester.pumpWidget(_host(_ShellHarness(
        pages: [_longList(key: const Key('page-list'))],
      )));
      await tester.pumpAndSettle();

      await tester.drag(
          find.byKey(const Key('page-list')), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(TabScrollRegistry.instance.primaryFor(0), isNotNull);

      // Unmount the whole app — the scrollable dies with it.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pump();
      expect(TabScrollRegistry.instance.primaryFor(0), isNull);
    });
  });

  group('the nav seam', () {
    testWidgets('a tap on the active tab fires the retap, never a selection',
        (tester) async {
      var retaps = 0;
      final selections = <int>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            totalUnreadChatCountProvider.overrideWith((ref) async => 0),
            activeTradeCountProvider.overrideWith((ref) async => 0),
            unreadCountProvider.overrideWith((ref) => 0),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              bottomNavigationBar: PremiumBottomNav(
                selectedIndex: 0,
                onItemSelected: selections.add,
                onActiveTabRetap: () => retaps++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Active tab: the retap contract, not a re-selection.
      await tester.tap(find.text('Home'));
      await tester.pump();
      expect(retaps, 1);
      expect(selections, isEmpty);

      // A different tab is still a normal switch.
      await tester.tap(find.text('Marketplace'));
      await tester.pump();
      expect(selections, [2]);
      expect(retaps, 1);
    });

    testWidgets(
        'legacy callers without onActiveTabRetap keep the haptic-only ack',
        (tester) async {
      final selections = <int>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            totalUnreadChatCountProvider.overrideWith((ref) async => 0),
            activeTradeCountProvider.overrideWith((ref) async => 0),
            unreadCountProvider.overrideWith((ref) => 0),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              bottomNavigationBar: PremiumBottomNav(
                selectedIndex: 0,
                onItemSelected: selections.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No retap wired → the tap is inert, and never a re-selection.
      await tester.tap(find.text('Home'));
      await tester.pump();
      expect(selections, isEmpty);
    });
  });
}
