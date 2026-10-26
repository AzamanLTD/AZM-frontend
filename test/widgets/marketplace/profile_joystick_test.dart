// =============================================================================
// PROFILE JOYSTICK — component-level tests (Workstream A5, 2026-10-26)
//
// Pins the shared directional contract on the REAL ProfileJoystick:
//   * touch-down starts the interaction — no long press,
//   * ~16px activation slop (14-20 band), deterministic dominant axis,
//   * dead zone + axis hysteresis (tremor never thrashes selection),
//   * actions fire EXACTLY once, only on release, never during the
//     drag and never for an unavailable direction,
//   * the preserved short-tap behaviour below the slop,
//   * cancellation / second pointer / dispose close cleanly with no
//     action and no stuck overlay,
//   * the parent scrollable never scrolls for a gesture that began on
//     the avatar, while scrolling outside it keeps working,
//   * reduced motion stays usable — no perpetual animations.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/marketplace/profile_joystick.dart';

// WORKSTREAM J1 helpers — read the semantics tree and invoke custom
// actions exactly the way a TalkBack/VoiceOver activation does.
SemanticsNode _nodeFor(WidgetTester tester) =>
    tester.getSemantics(find.byKey(const ValueKey('avatar')));

int _idFor(String label) =>
    CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: label));

bool _exposes(SemanticsData data, String label) =>
    data.customSemanticsActionIds?.contains(_idFor(label)) ?? false;

SemanticsOwner _ownerOf(WidgetTester tester) =>
    tester.binding.renderViews.first.owner!.semanticsOwner!;

void _invoke(WidgetTester tester, String label) {
  _ownerOf(tester).performAction(
    _nodeFor(tester).id,
    SemanticsAction.customAction,
    _idFor(label),
  );
}

void _invokeTap(WidgetTester tester) {
  _ownerOf(tester).performAction(
    _nodeFor(tester).id,
    SemanticsAction.tap,
  );
}

/// Walks the whole semantics tree collecting every node's data.
List<SemanticsData> _allNodes(SemanticsNode root) {
  final result = <SemanticsData>[root.getSemanticsData()];
  int i = 0;
  final queue = <SemanticsNode>[root];
  while (i < queue.length) {
    final node = queue[i++];
    node.visitChildren((child) {
      queue.add(child);
      result.add(child.getSemanticsData());
      return true;
    });
  }
  return result;
}

Widget _host(Widget child, {bool disableAnimations = false}) {
  return ProviderScope(
    child: MaterialApp(
      builder: (context, loaded) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: loaded!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

Widget _avatar() => const SizedBox(
  key: ValueKey('avatar'),
  width: 64,
  height: 64,
  child: ColoredBox(color: Colors.blue),
);

/// A Joystick with spy delegates for every direction.
class _Spies {
  int menu = 0;
  int story = 0;
  int bookmark = 0;
  int showLess = 0;
  int taps = 0;

  ProfileJoystickActions actions({bool storyAvailable = true}) =>
      ProfileJoystickActions(
        menu: ProfileJoystickAction(
          icon: Icons.menu_book_rounded,
          label: 'Menu',
          onRelease: () => menu++,
        ),
        story: ProfileJoystickAction(
          icon: Icons.play_circle_outline_rounded,
          label: 'Story',
          onRelease: storyAvailable ? () => story++ : null,
          unavailableLabel: 'No active story',
        ),
        bookmark: ProfileJoystickAction(
          icon: Icons.bookmark_border_rounded,
          label: 'Save',
          onRelease: () => bookmark++,
        ),
        showLess: ProfileJoystickAction(
          icon: Icons.visibility_off_outlined,
          label: 'Show less',
          onRelease: () => showLess++,
        ),
      );
}

Future<Offset> _center(WidgetTester tester) async =>
    tester.getCenter(find.byKey(const ValueKey('avatar')));

/// Start the joystick: pointer-down + one frame so the overlay reveals.
Future<TestGesture> _start(WidgetTester tester) async {
  final gesture = await tester.startGesture(await _center(tester));
  await tester.pump();
  return gesture;
}

Future<void> _move(WidgetTester tester, TestGesture gesture, Offset by) async {
  await gesture.moveBy(by);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pointer-down starts the interaction', () {
    testWidgets('the dial reveals immediately on pointer-down — no '
        'long press (matrix 1)', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(ProfileJoystick(actions: spies.actions(), child: _avatar())),
      );
      expect(
        find.byKey(const ValueKey('joystick-satellite-menu')),
        findsNothing,
        reason: 'nothing is revealed before touch',
      );

      await _start(tester);

      expect(
        find.byKey(const ValueKey('joystick-satellite-menu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('joystick-satellite-story')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('joystick-satellite-bookmark')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('joystick-satellite-showLess')),
        findsOneWidget,
      );
    });

    testWidgets('nothing fires on pointer-down itself (matrix 8)', (
      tester,
    ) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(ProfileJoystick(actions: spies.actions(), child: _avatar())),
      );

      await _start(tester);

      expect(spies.menu, 0);
      expect(spies.story, 0);
      expect(spies.bookmark, 0);
      expect(spies.showLess, 0);
      expect(spies.taps, 0);
    });
  });

  group('directional selection and release', () {
    testWidgets('a small upward drag selects Menu and the release '
        'invokes the delegate exactly once (matrix 2, 8)', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(ProfileJoystick(actions: spies.actions(), child: _avatar())),
      );

      final gesture = await _start(tester);
      await _move(tester, gesture, const Offset(0, -20)); // up, past slop
      expect(spies.menu, 0, reason: 'never during the drag');

      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.menu, 1);
      expect(spies.story, 0);
      expect(
        find.byKey(const ValueKey('joystick-satellite-menu')),
        findsNothing,
        reason: 'the dial closed after the release',
      );
    });

    testWidgets('a small rightward drag selects Bookmark (matrix 4)', (
      tester,
    ) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(ProfileJoystick(actions: spies.actions(), child: _avatar())),
      );

      final gesture = await _start(tester);
      await _move(tester, gesture, const Offset(20, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.bookmark, 1);
      expect(spies.menu, 0);
    });

    testWidgets('a small leftward drag selects Show less (matrix 5 seam)', (
      tester,
    ) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(ProfileJoystick(actions: spies.actions(), child: _avatar())),
      );

      final gesture = await _start(tester);
      await _move(tester, gesture, const Offset(-20, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.showLess, 1);
    });

    testWidgets('a small downward drag selects Story when available '
        '(matrix 3)', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(
          ProfileJoystick(
            actions: spies.actions(storyAvailable: true),
            child: _avatar(),
          ),
        ),
      );

      final gesture = await _start(tester);
      await _move(tester, gesture, const Offset(0, 20));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.story, 1);
    });

    testWidgets('diagonals select the DOMINANT axis deterministically', (
      tester,
    ) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(ProfileJoystick(actions: spies.actions(), child: _avatar())),
      );

      // Mostly up with horizontal drift -> Menu.
      final gesture = await _start(tester);
      await _move(tester, gesture, const Offset(6, -26));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(spies.menu, 1);
      expect(spies.bookmark, 0);
    });
  });

  group('thresholds, hysteresis and the preserved tap', () {
    testWidgets('movement below the slop is a tap, not a direction '
        '(matrix 9)', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(
          ProfileJoystick(
            actions: spies.actions(),
            onTap: () => spies.taps++,
            child: _avatar(),
          ),
        ),
      );

      final gesture = await _start(tester);
      await _move(tester, gesture, const Offset(0, -10)); // under 16
      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.menu, 0, reason: 'below the activation slop');
      expect(spies.taps, 1, reason: 'the short-tap behaviour survives');
    });

    testWidgets('a plain tap still fires onTap (matrix 9)', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(
          ProfileJoystick(
            actions: spies.actions(),
            onTap: () => spies.taps++,
            child: _avatar(),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('avatar')));
      await tester.pumpAndSettle();

      expect(spies.taps, 1);
      expect(spies.menu, 0);
    });

    testWidgets('axis hysteresis keeps tremor from thrashing the '
        'selection', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(ProfileJoystick(actions: spies.actions(), child: _avatar())),
      );

      final gesture = await _start(tester);
      await _move(tester, gesture, const Offset(0, -26)); // Menu
      // Small horizontal drift must NOT flip the axis (margin 4).
      await _move(tester, gesture, const Offset(10, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.menu, 1);
      expect(
        spies.bookmark,
        0,
        reason: '10px of horizontal drift is tremor, not intent',
      );
    });

    testWidgets('a clear axis switch DOES flip after the margin', (
      tester,
    ) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(ProfileJoystick(actions: spies.actions(), child: _avatar())),
      );

      final gesture = await _start(tester);
      await _move(tester, gesture, const Offset(0, -26)); // Menu
      await _move(tester, gesture, const Offset(32, 0)); // decisively right
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        spies.bookmark,
        1,
        reason: 'a dominant rightward travel flips to Bookmark',
      );
    });

    testWidgets('returning into the dead zone clears the selection', (
      tester,
    ) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(ProfileJoystick(actions: spies.actions(), child: _avatar())),
      );

      final gesture = await _start(tester);
      await _move(tester, gesture, const Offset(0, -26)); // Menu
      await _move(tester, gesture, const Offset(0, 18)); // back inside slop
      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.menu, 0, reason: 'released inside the dead zone');
    });
  });

  group('unavailable directions (matrix 13)', () {
    testWidgets('an unavailable story direction renders dimmed and a '
        'release on it fires nothing', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(
          ProfileJoystick(
            actions: spies.actions(storyAvailable: false),
            child: _avatar(),
          ),
        ),
      );

      final gesture = await _start(tester);
      await _move(tester, gesture, const Offset(0, 20));
      expect(
        find.text('Story (No active story)'),
        findsOneWidget,
        reason:
            'the unavailable satellite renders its honest reason '
            'while the session is live',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.story, 0, reason: 'no dead delegate ever fires');
    });
  });

  group('cancellation and teardown (matrix 10)', () {
    testWidgets('pointer cancellation closes the dial without firing', (
      tester,
    ) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(ProfileJoystick(actions: spies.actions(), child: _avatar())),
      );

      final gesture = await _start(tester);
      await _move(tester, gesture, const Offset(0, -26));
      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(spies.menu, 0);
      expect(
        find.byKey(const ValueKey('joystick-satellite-menu')),
        findsNothing,
        reason: 'no stuck overlay after cancellation',
      );
    });

    testWidgets('a second pointer cancels the session and the first '
        'pointer release fires nothing', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(ProfileJoystick(actions: spies.actions(), child: _avatar())),
      );

      final first = await _start(tester);
      await _move(tester, first, const Offset(0, -26));

      // A second finger lands elsewhere on the screen.
      final second = await tester.startGesture(const Offset(300, 500));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('joystick-satellite-menu')),
        findsNothing,
        reason: 'the second pointer closed the dial',
      );

      await first.up();
      await second.up();
      await tester.pumpAndSettle();

      expect(spies.menu, 0, reason: 'cancelled sessions never fire');
    });

    testWidgets('widget disposal mid-session removes the overlay and '
        'fires nothing', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(ProfileJoystick(actions: spies.actions(), child: _avatar())),
      );

      final gesture = await _start(tester);
      await _move(tester, gesture, const Offset(0, -26));

      await tester.pumpWidget(const SizedBox.shrink()); // route disposal
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('joystick-satellite-menu')),
        findsNothing,
      );
      expect(spies.menu, 0);
    });
  });

  group('gesture-arena arbitration vs the parent scroll (matrix 11, 12)', () {
    testWidgets('a drag that begins on the avatar never scrolls the '
        'parent list', (tester) async {
      final spies = _Spies();
      final controller = ScrollController();
      await tester.pumpWidget(
        _host(
          SizedBox(
            height: 300,
            child: ListView(
              controller: controller,
              children: [
                ProfileJoystick(actions: spies.actions(), child: _avatar()),
                for (var i = 0; i < 40; i++) ListTile(title: Text('row $i')),
              ],
            ),
          ),
        ),
      );

      final gesture = await _start(tester);
      // A decisive VERTICAL drag — exactly the movement a scroll
      // recogniser would love to claim.
      await _move(tester, gesture, const Offset(0, 40));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        0.0,
        reason: 'the joystick won the arena before the scroll could',
      );
      expect(spies.story, 1, reason: 'down selected Story');
    });

    testWidgets('a drag that begins OUTSIDE the avatar scrolls '
        'normally', (tester) async {
      final spies = _Spies();
      final controller = ScrollController();
      await tester.pumpWidget(
        _host(
          SizedBox(
            height: 300,
            child: ListView(
              controller: controller,
              children: [
                ProfileJoystick(actions: spies.actions(), child: _avatar()),
                for (var i = 0; i < 40; i++) ListTile(title: Text('row $i')),
              ],
            ),
          ),
        ),
      );

      await tester.drag(find.text('row 1'), const Offset(0, -60));
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(0.0));
      expect(spies.story, 0);
    });
  });

  group('reduced motion (matrix 14)', () {
    testWidgets('with disableAnimations the dial is instantly readable '
        'and closes without perpetual animation', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(
        _host(
          ProfileJoystick(actions: spies.actions(), child: _avatar()),
          disableAnimations: true,
        ),
      );

      final gesture = await _start(tester);
      await _move(tester, gesture, const Offset(0, -26));

      final satellite =
          find
                  .byKey(const ValueKey('joystick-satellite-menu'))
                  .evaluate()
                  .first
                  .widget
              as Positioned;
      final animated = satellite.child as AnimatedOpacity;
      expect(animated.opacity, 1.0);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('joystick-satellite-menu')),
        findsNothing,
      );
      expect(spies.menu, 1);
    });
  });

  test('the pure classifier pins the spec band', () {
    // Activation: 14-20 logical px, tuned at 16.
    expect(directionFor(const Offset(0, -15.9)), isNull);
    expect(directionFor(const Offset(0, -16)), ProfileJoystickDirection.menu);
    expect(directionFor(const Offset(0, 16)), ProfileJoystickDirection.story);
    expect(
      directionFor(const Offset(16, 0)),
      ProfileJoystickDirection.bookmark,
    );
    expect(
      directionFor(const Offset(-16, 0)),
      ProfileJoystickDirection.showLess,
    );
    // Dominant axis wins on diagonals; ties go vertical.
    expect(directionFor(const Offset(6, -26)), ProfileJoystickDirection.menu);
    expect(
      directionFor(const Offset(26, -6)),
      ProfileJoystickDirection.bookmark,
    );
    expect(directionFor(const Offset(20, -20)), ProfileJoystickDirection.menu);
  });

  group('Workstream J1 — usable WITHOUT directional touch gestures', () {
    testWidgets('every AVAILABLE direction is exposed as a custom '
        'semantics action and invoking it fires the real callback exactly '
        'once', (tester) async {
      final handle = tester.ensureSemantics();
      final spies = _Spies();
      await tester.pumpWidget(
        _host(
          ProfileJoystick(
            actions: spies.actions(),
            onTap: () => spies.taps++,
            child: _avatar(),
          ),
        ),
      );

      final data = _nodeFor(tester).getSemanticsData();
      for (final label in ['Menu', 'Story', 'Save', 'Show less']) {
        expect(
          _exposes(data, label),
          isTrue,
          reason:
              'the available action "$label" must be exposed to '
              'screen readers',
        );
      }

      // Each invocation fires the REAL delegate exactly once — the same
      // guarded execution path as a gesture release.
      _invoke(tester, 'Menu');
      expect(spies.menu, 1);
      _invoke(tester, 'Story');
      expect(spies.story, 1);
      _invoke(tester, 'Save');
      expect(spies.bookmark, 1);
      _invoke(tester, 'Show less');
      expect(spies.showLess, 1);

      // And not more than once per activation — no double fire.
      _invoke(tester, 'Save');
      expect(spies.bookmark, 2);
      handle.dispose();
    });

    testWidgets('an UNAVAILABLE story is not exposed and cannot be '
        'executed through semantics', (tester) async {
      final handle = tester.ensureSemantics();
      final spies = _Spies();
      await tester.pumpWidget(
        _host(
          ProfileJoystick(
            actions: spies.actions(storyAvailable: false),
            onTap: () => spies.taps++,
            child: _avatar(),
          ),
        ),
      );

      final data = _nodeFor(tester).getSemanticsData();
      expect(
        _exposes(data, 'Story'),
        isFalse,
        reason:
            'no active story means no story action — never an '
            'advertised shortcut that fires nothing',
      );
      expect(_exposes(data, 'Menu'), isTrue);
      expect(_exposes(data, 'Save'), isTrue);
      expect(_exposes(data, 'Show less'), isTrue);

      // Even a forced dispatch through the raw owner is refused — the
      // delegate simply is not registered.
      _invoke(tester, 'Story');
      expect(spies.story, 0);
      handle.dispose();
    });

    testWidgets('the semantic tap fires the real short-tap callback; '
        'without onTap no button/tap is advertised', (tester) async {
      final handle = tester.ensureSemantics();
      final spies = _Spies();
      await tester.pumpWidget(
        _host(
          ProfileJoystick(
            actions: spies.actions(),
            onTap: () => spies.taps++,
            child: _avatar(),
          ),
        ),
      );

      final data = _nodeFor(tester).getSemanticsData();
      expect(
        data.hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'a short tap exists, so the tap action is advertised',
      );
      expect(data.flagsCollection.isButton, isTrue);
      _invokeTap(tester);
      expect(spies.taps, 1);

      // Without an onTap, the joystick must not advertise a button tap
      // that does nothing.
      final spies2 = _Spies();
      await tester.pumpWidget(
        _host(ProfileJoystick(actions: spies2.actions(), child: _avatar())),
      );
      final data2 = _nodeFor(tester).getSemanticsData();
      expect(data2.hasAction(SemanticsAction.tap), isFalse);
      expect(
        data2.flagsCollection.isButton,
        isFalse,
        reason: 'J1: never advertise a button role with no tap',
      );
      // The custom actions remain — the shortcuts are the real fallback.
      expect(_exposes(data2, 'Menu'), isTrue);
      handle.dispose();
    });

    testWidgets('the open dial adds NO duplicate screen-reader stops — '
        'the satellites are semantics-free', (tester) async {
      final handle = tester.ensureSemantics();
      final spies = _Spies();
      await tester.pumpWidget(
        _host(
          ProfileJoystick(
            actions: spies.actions(storyAvailable: false),
            onTap: () => spies.taps++,
            child: _avatar(),
          ),
        ),
      );
      await tester.pump();

      // BEFORE the dial: one node carries the custom actions.
      final owner = _ownerOf(tester);
      var carriersBefore = _allNodes(
        owner.rootSemanticsNode!,
      ).where((d) => (d.customSemanticsActionIds ?? []).isNotEmpty).length;

      final gesture = await _start(tester);

      // WHILE the dial is open: the satellites (which render 'Story (No
      // active story)' etc. VISUALLY) must not have appeared as any
      // semantics node — no duplicate or confusing stops.
      final nodes = _allNodes(owner.rootSemanticsNode!);
      var carriersDuring = nodes
          .where((d) => (d.customSemanticsActionIds ?? []).isNotEmpty)
          .length;
      expect(
        carriersDuring,
        carriersBefore,
        reason: 'the dial adds no second node carrying the actions',
      );
      final allLabels = nodes
          .map((d) => '${d.attributedLabel.string} ${d.attributedValue.string}')
          .join(' | ');
      expect(
        allLabels.contains('No active story'),
        isFalse,
        reason:
            'the display-only satellites stay out of the semantics '
            'tree (IgnorePointer)',
      );
      expect(allLabels.contains('joystick-satellite'), isFalse);

      await gesture.cancel();
      await tester.pump();
      handle.dispose();
    });
  });
}
