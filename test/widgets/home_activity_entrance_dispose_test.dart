// =============================================================================
// ACTIVITY SURFACE — ENTRANCE-CONTROLLER LIFECYCLE (teardown-defect regression)
//
// The entrance AnimationController was a `late final` FIELD INITIALIZER, so
// its construction landed at its point of first use. On a surface that
// mounts inactive (the Home rest keeps it in the tree, faded out) with an
// empty transaction history, nothing ever referenced it — build takes the
// empty-state branch (no rows, no _StaggeredRow) and _maybeEnter
// early-returns on !active — so the FIRST reference was `_entrance.dispose()`
// itself. Constructing the controller on a deactivated element does the
// deactivated-element ticker-mode lookup: an assertion on Flutter 3.44.x,
// and on 3.47.x a silent attach to the CONSTANT FALLBACK notifier instead
// of the subtree's real TickerMode (see TickerMode.getValuesNotifier's own
// comment in the framework, which calls out this exact late-final pattern).
//
// The fix constructs the controller EAGERLY in initState. These tests pin
// that contract:
//   1. the controller exists from mount (a live-element construction),
//      observed through SingleTickerProviderStateMixin's ticker diagnostics
//      — version-independent, unlike the 3.44.x assertion;
//   2. the teardown-only scenario (mount inactive → dispose, entrance never
//      touched) disposes with no error, on any engine that still trips;
//   3. the entrance choreography itself still drives (active surface).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/widgets/home/activity_doorway.dart';

/// Never fetches — the lazy-load boundary stays local to the test.
class _NoFetchHistoryNotifier extends TransactionHistoryNotifier {
  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadMore() async {}
}

Future<ProviderContainer> _pumpSurface(
  WidgetTester tester, {
  required bool active,
}) async {
  final container = ProviderContainer(
    overrides: [
      transactionHistoryProvider.overrideWith(
        (ref) => _NoFetchHistoryNotifier(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: Scaffold(
          body: SizedBox.expand(
            child: HomeActivitySurface(
              onClose: _noopClose,
              active: active,
              headingProgress: 0,
              armedCue: 0,
              onTopPullUpdate: _noopPull,
              onTopPullEnd: _noopPullEnd,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void _noopClose() {}
void _noopPull(double px) {}
void _noopPullEnd(bool commits) {}

State<StatefulWidget> _surfaceState(WidgetTester tester) =>
    tester.state<State<StatefulWidget>>(
      find.byType(HomeActivitySurface, skipOffstage: false),
    );

void main() {
  testWidgets(
    'entrance controller is constructed EAGERLY at mount — never lazily at first use',
    (tester) async {
      // The discriminating scenario: inactive surface + empty history.
      // Under the old lazy pattern nothing referenced the controller
      // before dispose, so the ticker did not exist at this point and the
      // mixin reported NO ticker property.
      await _pumpSurface(tester, active: false);

      final diag = _surfaceState(tester).toString();
      expect(
        diag,
        contains('ticker'),
        reason:
            'the entrance controller must exist from initState (a live-element '
            'construction). Under the lazy late-final pattern the ticker was '
            'first created inside dispose() — the teardown defect.',
      );
      expect(
        diag,
        contains('inactive'),
        reason: 'a never-entered surface has an idle (not running) ticker',
      );
    },
  );

  testWidgets(
    'teardown-only scenario: mounting inactive and disposing constructs nothing and raises no error',
    (tester) async {
      // testWidgets fails the test on ANY uncaught FlutterError during the
      // pumps below, so reaching the final expect is itself the assertion.
      // On engine versions where the deactivated-element ticker-mode lookup
      // still asserts (Flutter 3.44.x), the lazy pattern fails here; on
      // 3.47.x it was silent — the eager-construction test is the one that
      // discriminates there.
      await _pumpSurface(tester, active: false);

      // Unmount the surface — dispose runs while nothing ever touched the
      // entrance.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(find.byType(HomeActivitySurface), findsNothing);
    },
  );

  testWidgets(
    'entrance choreography still drives on the active surface (eager construction changed no behavior)',
    (tester) async {
      await _pumpSurface(tester, active: true);

      // Active + empty history: _maybeEnter fires on mount and forward()
      // drives the 900ms settle — the ticker must be running, constructed
      // against the LIVE element's ticker-mode notifier.
      final running = _surfaceState(tester).toString();
      expect(
        running,
        contains('ticker active'),
        reason: 'the entrance must be mid-flight right after the active mount',
      );

      // Run the choreography out (900ms duration; pump past it so the
      // controller completes on a frame boundary and the ticker idles).
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      final settled = _surfaceState(tester).toString();
      expect(
        settled,
        contains('ticker inactive'),
        reason: 'the 900ms entrance completes and releases the ticker',
      );

      // And the surface itself still renders (the empty-state tile).
      expect(find.byType(HomeActivitySurface), findsOneWidget);
    },
  );
}
