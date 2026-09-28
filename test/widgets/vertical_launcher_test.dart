// =============================================================================
// TASK-010b — Vertical launcher: permanent guard
//
// Pins the launcher's single authoritative lifecycle end to end:
//
//   * ONLY the Market tab index opens the launcher — other tabs return false
//     and leave the navigator untouched,
//   * the launcher offers exactly the five guarded launch wires, in dial
//     presentation order, and never a null/blank/unknown wire,
//   * picking a target closes the sheet exactly once, selects the Market tab
//     underneath, and pushes MarketplaceHomeScreen(initialCategory: wire) —
//     the already-guarded TASK-011 downstream contract,
//   * dismissing (barrier) navigates nothing,
//   * repeated open/close cycles never leave a duplicate sheet route,
//   * reduced motion: the rows are fully rendered on the sheet's first frame
//     (the launcher owns no animation of its own),
//   * the sheet stays bounded on a small viewport with a bottom inset — no
//     target ever lands in an unusable region.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/main.dart'
    show kVerticalLauncherEntries, openVerticalLauncherForTab;
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/services/business_service.dart';

/// The five wires TASK-011's launch allowlist guards. Duplicated here
/// deliberately: if the launcher ever offers a wire outside this set (or this
/// set drifts from the allowlist), this guard fails.
const kGuardedLaunchWires = {
  'RETAIL',
  'FOOD_BEVERAGE',
  'LOGISTICS',
  'HOSPITALITY',
  'REAL_ESTATE',
};

class _RecordingSearchNotifier extends BusinessSearchNotifier {
  _RecordingSearchNotifier() : super(BusinessService());

  final List<String?> searchedCategories = [];

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    searchedCategories.add(category);
    // Recorded, not fired — no network in this guard.
  }
}

class _RouteRecorder extends NavigatorObserver {
  final List<String> events = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add('push:${route.runtimeType}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add('pop:${route.runtimeType}');
  }

  int get pushes => events.where((e) => e.startsWith('push:')).length;
  int get pops => events.where((e) => e.startsWith('pop:')).length;
}

Future<_RouteRecorder> _pumpHarness(
  WidgetTester tester, {
  required _RecordingSearchNotifier notifier,
  List<int>? tabSelections,
  bool reduceMotion = false,
  // 800 logical px wide: the same surface width the existing marketplace
  // guards pump at. (The category dial's Row overflows below ~600px — a
  // pre-existing marketplace layout property, not this task's surface.)
  Size size = const Size(800, 1000),
  EdgeInsets mediaPadding = EdgeInsets.zero,
  bool openIt = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Force a full unmount of any prior tree: pumping the same MaterialApp
  // type again would UPDATE the old element tree in place and keep the old
  // Navigator's route stack (e.g. a marketplace pushed by a previous loop
  // iteration) hiding the harness's home page.
  await tester.pumpWidget(const SizedBox.shrink());

  final recorder = _RouteRecorder();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [businessSearchProvider.overrideWith((ref) => notifier)],
      child: MaterialApp(
        navigatorObservers: [recorder],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion, padding: mediaPadding),
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const ValueKey('open_launcher'),
                onPressed: () => openVerticalLauncherForTab(
                  3,
                  context,
                  selectTab: tabSelections == null ? (_) {} : tabSelections.add,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // The MaterialApp pushes its initial home route during the pump above;
  // drop it so every recorder event is a launcher-owned route event.
  recorder.events.clear();
  if (openIt) {
    await tester.tap(find.byKey(const ValueKey('open_launcher')));
    await tester.pump();
  }
  return recorder;
}

final _sheetFinder = find.text('Explore the market');
final _sheetRouteFinder = find.byType(DraggableScrollableSheet);

/// Settle the panel's entrance without pumpAndSettle: the launcher must not
/// depend on every animation in the tree having settled.
Future<void> _settleEntrance(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 350));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('gating — only the Market tab owns a launcher', () {
    testWidgets('a non-Market index returns false and opens nothing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final opened = <bool>[];
      for (final index in [0, 1, 2]) {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () => opened.add(
                        openVerticalLauncherForTab(
                          index,
                          context,
                          selectTab: (_) {},
                        ),
                      ),
                      child: const Text('go'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('go'));
        await tester.pump();
        expect(opened.single, isFalse, reason: 'tab $index has no launcher');
        expect(_sheetFinder, findsNothing);
        expect(_sheetRouteFinder, findsNothing);
        opened.clear();
      }
    });

    testWidgets('the Market index opens the launcher as a sheet route', (
      tester,
    ) async {
      final recorder = await _pumpHarness(
        tester,
        notifier: _RecordingSearchNotifier(),
      );
      expect(_sheetFinder, findsOneWidget);
      expect(_sheetRouteFinder, findsOneWidget);
      expect(
        recorder.pushes,
        1,
        reason: 'opening the launcher pushes its sheet route',
      );
      expect(
        find.byType(MarketplaceHomeScreen),
        findsNothing,
        reason: 'opening the launcher alone never navigates',
      );
    });
  });

  group('targets — the five guarded launch wires', () {
    testWidgets('renders all five wires in dial presentation order', (
      tester,
    ) async {
      await _pumpHarness(tester, notifier: _RecordingSearchNotifier());
      await _settleEntrance(tester);

      // Every wire's row exists (shrinkWrap keeps all rows materialised).
      for (final entry in kVerticalLauncherEntries) {
        expect(
          find.byKey(Key('vertical_launcher_${entry.wire}')),
          findsOneWidget,
        );
      }
      // Dial order: Restaurants, Hotels, Transit, Retail — plus the
      // model-canonical HOSPITALITY wire last.
      final dy = <String, double>{};
      for (final entry in kVerticalLauncherEntries) {
        dy[entry.wire] = tester
            .getTopLeft(find.byKey(Key('vertical_launcher_${entry.wire}')))
            .dy;
      }
      expect(dy['FOOD_BEVERAGE']! < dy['REAL_ESTATE']!, isTrue);
      expect(dy['REAL_ESTATE']! < dy['LOGISTICS']!, isTrue);
      expect(dy['LOGISTICS']! < dy['RETAIL']!, isTrue);
      expect(dy['RETAIL']! < dy['HOSPITALITY']!, isTrue);
    });

    test('the wire list is exactly the guarded allowlist — never null, blank '
        'or unknown', () {
      final wires = kVerticalLauncherEntries.map((e) => e.wire).toList();
      expect(wires.toSet(), kGuardedLaunchWires);
      for (final wire in wires) {
        expect(wire.trim(), wire, reason: 'wires must not need trimming');
        expect(wire.isEmpty, isFalse);
      }
    });

    testWidgets('each of the five wires reaches the marketplace with that '
        'initialCategory', (tester) async {
      for (final entry in kVerticalLauncherEntries) {
        final notifier = _RecordingSearchNotifier();
        final tabSelections = <int>[];
        final recorder = await _pumpHarness(
          tester,
          notifier: notifier,
          tabSelections: tabSelections,
        );
        await _settleEntrance(tester);
        await tester.tap(find.text(entry.label));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        final marketplace = tester.widget<MarketplaceHomeScreen>(
          find.byType(MarketplaceHomeScreen),
        );
        expect(marketplace.initialCategory, entry.wire);
        expect(tabSelections, [
          3,
        ], reason: 'the Market tab is selected underneath the landing');
        // Sheet route + exactly one filtered marketplace route.
        expect(recorder.pushes, 2);
        expect(recorder.pops, 1, reason: 'the launcher closes exactly once');

        // The pushed screen honours the wire through the already-guarded
        // TASK-011 contract: the seeding search fires with the category.
        expect(notifier.searchedCategories, [entry.wire]);
      }
    });
  });

  group('lifecycle — one authoritative implementation', () {
    testWidgets('dismissing by the barrier navigates nothing', (tester) async {
      final tabSelections = <int>[];
      final recorder = await _pumpHarness(
        tester,
        notifier: _RecordingSearchNotifier(),
        tabSelections: tabSelections,
      );
      await _settleEntrance(tester);
      // Tap the scrim, above the sheet.
      await tester.tapAt(const Offset(400, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_sheetFinder, findsNothing);
      expect(tabSelections, isEmpty);
      expect(find.byType(MarketplaceHomeScreen), findsNothing);
      // The only route events are the sheet's own open and dismiss.
      expect(recorder.pushes, 1);
      expect(recorder.pops, 1);
    });

    testWidgets('repeated open/dismiss cycles keep exactly one sheet at a '
        'time', (tester) async {
      final notifier = _RecordingSearchNotifier();
      final recorder = await _pumpHarness(tester, notifier: notifier);
      await _settleEntrance(tester);

      for (var i = 0; i < 3; i++) {
        expect(_sheetRouteFinder, findsOneWidget);
        await tester.tapAt(const Offset(400, 40));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(_sheetRouteFinder, findsNothing);

        await tester.tap(find.byKey(const ValueKey('open_launcher')));
        await tester.pump();
        await _settleEntrance(tester);
      }
      // Four sheet opens (the harness's initial one + three loop opens) and
      // three dismissals — zero page navigation.
      expect(recorder.pushes, 4);
      expect(recorder.pops, 3);
      expect(find.byType(MarketplaceHomeScreen), findsNothing);
    });

    testWidgets('open → pick → back → open again: no leaked state, one '
        'landing per pick', (tester) async {
      final notifier = _RecordingSearchNotifier();
      final tabSelections = <int>[];
      final recorder = await _pumpHarness(
        tester,
        notifier: notifier,
        tabSelections: tabSelections,
      );
      await _settleEntrance(tester);
      await tester.tap(find.text('Retail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(MarketplaceHomeScreen), findsOneWidget);

      // The marketplace is a full-bleed screen with no in-app back button
      // (the real app pops it with the system back gesture); drive the
      // Navigator the way that gesture does.
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byKey(const ValueKey('open_launcher')));
      await tester.pump();
      await _settleEntrance(tester);
      expect(
        _sheetRouteFinder,
        findsOneWidget,
        reason: 'the second open produces no duplicate sheet',
      );
      await tester.tap(find.text('Restaurants'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Events: sheet1, marketplace1, back(marketplace1), sheet2, sheet2 pop,
      // marketplace2 → pushes 4 (2 sheets + 2 pages), pops 3.
      expect(recorder.pushes, 4);
      expect(recorder.pops, 3);
      expect(tabSelections, [3, 3]);
      expect(_sheetRouteFinder, findsNothing);
      expect(
        tester
            .widget<MarketplaceHomeScreen>(find.byType(MarketplaceHomeScreen))
            .initialCategory,
        'FOOD_BEVERAGE',
      );
    });
  });

  group('motion and placement', () {
    testWidgets('reduced motion: all five rows are rendered on the sheet\'s '
        'first frame', (tester) async {
      await _pumpHarness(
        tester,
        notifier: _RecordingSearchNotifier(),
        reduceMotion: true,
      );
      // No settle: the launcher owns no animation, so nothing may be
      // mid-flight — every target must already exist on the first frame.
      for (final entry in kVerticalLauncherEntries) {
        expect(
          find.byKey(Key('vertical_launcher_${entry.wire}')),
          findsOneWidget,
        );
        expect(find.text(entry.label), findsOneWidget);
      }
    });

    testWidgets('bounded on a small viewport with a bottom inset — the sheet '
        'stays on screen and every target is reachable', (tester) async {
      const size = Size(360, 480);
      await _pumpHarness(
        tester,
        notifier: _RecordingSearchNotifier(),
        size: size,
        mediaPadding: const EdgeInsets.only(bottom: 40),
      );
      await _settleEntrance(tester);

      // The sheet never leaves the screen.
      final sheetRect = tester.getRect(_sheetRouteFinder);
      expect(sheetRect.top, greaterThanOrEqualTo(0));
      expect(sheetRect.bottom, lessThanOrEqualTo(size.height));

      // All five targets exist and the last one is reachable by scrolling
      // the sheet's own scrollable (I.10.1: scope to the sheet, not the last
      // Scrollable on screen).
      await tester.scrollUntilVisible(
        find.byKey(const Key('vertical_launcher_HOSPITALITY')),
        120,
        scrollable: find.descendant(
          of: _sheetRouteFinder,
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.byKey(const Key('vertical_launcher_HOSPITALITY')),
        findsOneWidget,
      );
    });
  });
}
