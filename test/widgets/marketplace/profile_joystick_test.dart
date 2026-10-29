// =============================================================================
// PROFILE JOYSTICK / LIQUID DIAL — component-level tests (2026-10-27
// redesign: persistent icon-only goo dial + tap/drag/hold state machine).
//
// Pins the shared contract on the REAL ProfileJoystick, per the required
// regression matrix:
//   1-2.   tap opens the persistent icon dial (no visible action text) and
//          it STAYS open after the opening tap.
//   3.     tapping an available icon runs the correct delegate exactly
//          once and closes the dial.
//   4-5.   outside tap closes silently (no action, no feed scroll); the
//          anchor dismisses the open dial.
//   6.     directional drag highlights the correct icon, executes once on
//          release and closes.
//   7.     cancel / no-direction release / second pointer never fire.
//   8.     long press opens the full action menu ONLY — the same pointer
//          sequence produces nothing else.
//   9.     unavailable directions render visibly disabled and never
//          execute.
//   10.    show-less fires once per deliberate activation — no double
//          invoke from gesture overlap.
//   11.    a profile-started gesture never scrolls the parent; scrolling
//          that begins outside still works.
//   12.    geometry: 44×44 targets, uniform spacing, fully on-screen at
//          320/360/390dp.
//   13.    reduced motion: instantly readable, instantly closed.
//   a11y.  action labels preserved; tap/dial/menu semantics exposed;
//          unavailable directions never advertised; no duplicate stops
//          from the transient dial; satellites carry honest labels.
// =============================================================================

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/marketplace/profile_joystick.dart';

// Semantics helpers — read the tree and invoke actions exactly the way
// TalkBack/VoiceOver activation does.
SemanticsNode _nodeFor(WidgetTester tester, Key key) =>
    tester.getSemantics(find.byKey(key));

SemanticsData _dataFor(WidgetTester tester, Key key) =>
    _nodeFor(tester, key).getSemanticsData();

int _idFor(String label) =>
    CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: label));

bool _exposes(SemanticsData data, String label) =>
    data.customSemanticsActionIds?.contains(_idFor(label)) ?? false;

SemanticsOwner _ownerOf(WidgetTester tester) =>
    tester.binding.renderViews.first.owner!.semanticsOwner!;

void _invokeCustom(WidgetTester tester, Key key, String label) {
  _ownerOf(tester).performAction(
    _nodeFor(tester, key).id,
    SemanticsAction.customAction,
    _idFor(label),
  );
}

void _invokeTap(WidgetTester tester, Key key) {
  _ownerOf(tester).performAction(_nodeFor(tester, key).id, SemanticsAction.tap);
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

const _avatarKey = ValueKey('avatar');

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
  key: _avatarKey,
  width: 64,
  height: 64,
  child: ColoredBox(color: Colors.blue),
);

/// Joystick with spy delegates for every direction + the hold outcome.
class _Spies {
  int menu = 0;
  int story = 0;
  int bookmark = 0;
  int showLess = 0;
  int holds = 0;
  int taps = 0; // nothing should ever fire this — tap belongs to the dial

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

  int get total => menu + story + bookmark + showLess;
}

Widget _joystick(_Spies spies, {bool storyAvailable = true}) => ProfileJoystick(
  actions: spies.actions(storyAvailable: storyAvailable),
  onLongPress: () => spies.holds++,
  child: _avatar(),
);

Future<void> _tapAvatar(WidgetTester tester) async {
  await tester.tap(find.byKey(_avatarKey));
  await tester.pumpAndSettle();
}

Future<TestGesture> _press(WidgetTester tester) =>
    tester.startGesture(tester.getCenter(find.byKey(_avatarKey)));

Future<void> _pumpMove(
  WidgetTester tester,
  TestGesture gesture,
  Offset by,
) async {
  await gesture.moveBy(by);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dialKey = ValueKey('profile-dial');
  const barrierKey = ValueKey('profile-dial-barrier');
  const anchorKey = ValueKey('profile-dial-anchor');
  Key sat(String name) => ValueKey('profile-dial-satellite-$name');

  group('outcome 1 — tap opens the persistent dial (regressions 1, 2)', () {
    testWidgets('a short tap opens the FOUR icon-only satellites with NO '
        'visible action text', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      await _tapAvatar(tester);

      expect(find.byKey(dialKey), findsOneWidget);
      expect(find.byKey(barrierKey), findsOneWidget);
      for (final name in ['menu', 'story', 'bookmark', 'showLess']) {
        expect(find.byKey(sat(name)), findsOneWidget, reason: name);
      }
      // Icon-only: no label text anywhere in the dial.
      expect(
        find.descendant(of: find.byKey(dialKey), matching: find.byType(Text)),
        findsNothing,
      );
      // And nothing fired from the opening tap itself.
      expect(spies.total, 0);
      expect(spies.holds, 0);
    });

    testWidgets('the dial STAYS open after the opening tap', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      await _tapAvatar(tester);
      // Long after the open animation (and no interaction): still open.
      await tester.pump(const Duration(seconds: 3));

      expect(find.byKey(dialKey), findsOneWidget);
    });

    testWidgets('regression 3 — tapping an available icon runs the correct '
        'delegate EXACTLY once and closes the dial', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      await _tapAvatar(tester);
      await tester.tap(find.byKey(sat('bookmark')));
      await tester.pumpAndSettle();

      expect(spies.bookmark, 1);
      expect(spies.total, 1);
      expect(find.byKey(dialKey), findsNothing, reason: 'dial closed');
    });

    testWidgets('regression 4 — tapping OUTSIDE closes silently: no action, '
        'and the barrier swallows the tap', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      await _tapAvatar(tester);
      await tester.tap(find.byKey(barrierKey));
      await tester.pumpAndSettle();

      expect(find.byKey(dialKey), findsNothing);
      expect(spies.total, 0);
      expect(spies.holds, 0);
    });

    testWidgets('regression 5 — tapping the anchor again dismisses the open '
        'dial with no action', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      await _tapAvatar(tester);
      expect(find.byKey(anchorKey), findsOneWidget);
      await tester.tap(find.byKey(anchorKey));
      await tester.pumpAndSettle();

      expect(find.byKey(dialKey), findsNothing);
      expect(spies.total, 0);
    });
  });

  group('outcome 2 — directional drag (transient dial, regressions 6, 7)', () {
    testWidgets('a decisive up-drag highlights the Menu satellite and the '
        'release executes EXACTLY once, then closes', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      final gesture = await _press(tester);
      await _pumpMove(tester, gesture, const Offset(0, -26));

      // Transient dial is up while the pointer is still down.
      expect(find.byKey(dialKey), findsOneWidget);
      // The dragged direction is highlighted: its icon colour differs
      // from a non-selected satellite's (accent vs neutral ink).
      final menuIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(sat('menu')),
          matching: find.byType(Icon),
        ),
      );
      final storyIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(sat('story')),
          matching: find.byType(Icon),
        ),
      );
      expect(
        menuIcon.color,
        isNot(storyIcon.color),
        reason: 'the selected satellite is visually highlighted',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.menu, 1);
      expect(spies.total, 1);
      expect(find.byKey(dialKey), findsNothing);
    });

    testWidgets('regression 7a — pointer CANCELLATION executes nothing', (
      tester,
    ) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      final gesture = await _press(tester);
      await _pumpMove(tester, gesture, const Offset(0, -26));
      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(spies.total, 0);
      expect(find.byKey(dialKey), findsNothing);
    });

    testWidgets('regression 7b — release BACK INSIDE the dead zone executes '
        'nothing (no valid direction selected)', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      final gesture = await _press(tester);
      await _pumpMove(tester, gesture, const Offset(0, -26)); // select menu…
      await _pumpMove(
        tester,
        gesture,
        const Offset(0, 26),
      ); // …then return to dead
      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.total, 0);
      expect(find.byKey(dialKey), findsNothing);
    });

    testWidgets('regression 7c — a SECOND POINTER cancels the session and '
        'the first pointer\'s release fires nothing', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      final first = await _press(tester);
      await _pumpMove(tester, first, const Offset(0, -26));
      final second = await tester.startGesture(
        // ignore: avoid_redundant_argument_values
        const Offset(300, 300),
      );
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();

      expect(spies.total, 0);
      expect(find.byKey(dialKey), findsNothing);
    });
  });

  group('outcome 3 — long press (regression 8)', () {
    testWidgets('press-and-hold opens the full action menu ONLY: no dial, '
        'no direction, and the SAME pointer\'s release fires nothing', (
      tester,
    ) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      final gesture = await _press(tester);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));

      expect(spies.holds, 1, reason: 'the hold opened the full menu');
      expect(find.byKey(dialKey), findsNothing, reason: 'no dial from a hold');
      expect(spies.total, 0);

      // The gesture is CONSUMED: the release must not open the
      // persistent dial either.
      await gesture.up();
      await tester.pumpAndSettle();
      expect(spies.holds, 1);
      expect(spies.total, 0);
      expect(find.byKey(dialKey), findsNothing);
    });

    testWidgets('a drag that wins the arena first KILLS the hold — the same '
        'sequence can never produce both', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      final gesture = await _press(tester);
      await _pumpMove(tester, gesture, const Offset(0, -26)); // drag wins
      // Hold the finger still well past the long-press timeout.
      await tester.pump(kLongPressTimeout * 2);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.menu, 1);
      expect(spies.holds, 0);
    });

    testWidgets('small sub-slop drift does NOT cancel the hold', (
      tester,
    ) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      final gesture = await _press(tester);
      await _pumpMove(tester, gesture, const Offset(0, -10)); // below the slop
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));

      expect(spies.holds, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(spies.holds, 1);
      expect(spies.total, 0);
    });
  });

  group('honest unavailability (regression 9)', () {
    testWidgets('transient release on an unavailable direction fires '
        'NOTHING and the dial still closes', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies, storyAvailable: false)));

      final gesture = await _press(tester);
      await _pumpMove(tester, gesture, const Offset(0, 26)); // down = story
      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.story, 0);
      expect(spies.total, 0);
      expect(find.byKey(dialKey), findsNothing);
    });

    testWidgets('persistent dial: the unavailable satellite is present, '
        'visibly dimmed, and tapping it neither fires NOR closes', (
      tester,
    ) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies, storyAvailable: false)));

      await _tapAvatar(tester);
      final storyPositioned = find.byKey(sat('story'));
      expect(storyPositioned, findsOneWidget);

      // Dimmed: the unavailable satellite renders at 0.45 opacity,
      // clearly below an available satellite's 0.9.
      // The dimming wrapper is layered under LiquidReveal's own
      // reveal Opacity — pin it BY VALUE, order-independent.
      List<double> opacitiesOf(Finder finder) => [
        for (final w
            in find
                .descendant(of: finder, matching: find.byType(Opacity))
                .evaluate())
          (w.widget as Opacity).opacity,
      ];
      expect(
        opacitiesOf(storyPositioned).contains(0.45),
        isTrue,
        reason: 'unavailable renders visibly dimmed',
      );
      expect(
        opacitiesOf(find.byKey(sat('menu'))).contains(0.9),
        isTrue,
        reason: 'available stays fully readable',
      );

      await tester.tap(storyPositioned);
      await tester.pumpAndSettle();

      expect(spies.story, 0);
      expect(find.byKey(dialKey), findsOneWidget, reason: 'dial stays open');
    });

    testWidgets('all four positions stay STABLE when a direction is '
        'unavailable — never removed, never rearranged', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies, storyAvailable: false)));

      await _tapAvatar(tester);
      for (final name in ['menu', 'story', 'bookmark', 'showLess']) {
        expect(find.byKey(sat(name)), findsOneWidget, reason: name);
      }
    });
  });

  group('show-less + no double invoke (regression 10)', () {
    testWidgets('a left drag fires show-less exactly ONCE per activation', (
      tester,
    ) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      final gesture = await _press(tester);
      await _pumpMove(tester, gesture, const Offset(-26, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.showLess, 1);
      expect(spies.total, 1);
    });

    testWidgets('one held diagonal tremor cannot double-invoke: the release '
        'fires the FINAL direction once', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      final gesture = await _press(tester);
      await _pumpMove(tester, gesture, const Offset(-26, 0));
      await _pumpMove(
        tester,
        gesture,
        const Offset(0, -26),
      ); // diagonal flip denied
      await _pumpMove(tester, gesture, const Offset(-8, 8)); // tremor back
      await gesture.up();
      await tester.pumpAndSettle();

      expect(spies.showLess + spies.menu, 1, reason: 'exactly one outcome');
    });

    testWidgets('a drag release and a LATER deliberate dial tap are two '
        'distinct activations (both legitimate)', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      final gesture = await _press(tester);
      await _pumpMove(tester, gesture, const Offset(-26, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(spies.showLess, 1);

      // A second, separate gesture: tap-open then pick the same icon.
      await _tapAvatar(tester);
      await tester.tap(find.byKey(sat('showLess')));
      await tester.pumpAndSettle();
      expect(spies.showLess, 2, reason: 'two deliberate activations');
    });
  });

  group('gesture ownership vs the parent scroll (regression 11)', () {
    Widget scrollHost(_Spies spies, ScrollController controller) => _host(
      SizedBox(
        height: 300,
        child: ListView(
          controller: controller,
          children: [
            _joystick(spies),
            for (var i = 0; i < 40; i++) ListTile(title: Text('row $i')),
          ],
        ),
      ),
    );

    testWidgets('a drag that begins on the avatar NEVER scrolls the list', (
      tester,
    ) async {
      final spies = _Spies();
      final controller = ScrollController();
      await tester.pumpWidget(scrollHost(spies, controller));

      final gesture = await _press(tester);
      await _pumpMove(tester, gesture, const Offset(0, 40)); // pure vertical
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.offset, 0.0, reason: 'the joystick won the arena');
      expect(spies.story, 1);
    });

    testWidgets('the OPEN persistent dial owns the screen: a vertical drag '
        'on the barrier never scrolls the feed', (tester) async {
      final spies = _Spies();
      final controller = ScrollController();
      await tester.pumpWidget(scrollHost(spies, controller));

      await _tapAvatar(tester);
      await tester.drag(find.byKey(barrierKey), const Offset(0, -80));
      await tester.pumpAndSettle();

      expect(controller.offset, 0.0, reason: 'the barrier ate the drag');
      expect(find.byKey(dialKey), findsOneWidget, reason: 'drag ≠ dismissal');
      expect(spies.total, 0);
    });

    testWidgets('a drag that begins OUTSIDE the avatar scrolls normally', (
      tester,
    ) async {
      final spies = _Spies();
      final controller = ScrollController();
      await tester.pumpWidget(scrollHost(spies, controller));

      await tester.drag(find.text('row 1'), const Offset(0, -60));
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(0.0));
      expect(spies.total, 0);
    });
  });

  group('geometry (regression 12)', () {
    for (final width in [320.0, 360.0, 390.0]) {
      testWidgets('at ${width.toInt()}dp every satellite keeps its 44×44 '
          'target fully on-screen with uniform spacing', (tester) async {
        final spies = _Spies();
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // The listing-like left-leaning anchor — the hard case.
        await tester.pumpWidget(
          _host(
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 54),
                child: _joystick(spies),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _tapAvatar(tester);
        await tester.pumpAndSettle();

        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        final anchorRect = tester.getRect(find.byKey(anchorKey));
        final anchorCenter =
            anchorRect.center; // central zone centre == avatar centre

        for (final name in ['menu', 'story', 'bookmark', 'showLess']) {
          final rect = tester.getRect(find.byKey(sat(name)));
          expect(rect.width, 44.0, reason: '$name hit target width');
          expect(rect.height, 44.0, reason: '$name hit target height');
          expect(
            rect.left,
            greaterThanOrEqualTo(0.0),
            reason: '$name never off the left edge',
          );
          expect(
            rect.right,
            lessThanOrEqualTo(screen.width),
            reason: '$name never off the right edge',
          );
          expect(rect.top, greaterThanOrEqualTo(0.0));
          expect(rect.bottom, lessThanOrEqualTo(screen.height));
        }

        // Uniform ring: every satellite centre equidistant from the
        // anchor centre (the solve may shift the whole ring, never one
        // satellite on its own).
        final distances = [
          for (final name in ['menu', 'story', 'bookmark', 'showLess'])
            (tester.getRect(find.byKey(sat(name))).center - anchorCenter)
                .distance,
        ];
        for (final d in distances) {
          expect(
            d,
            closeTo(distances.first, 0.5),
            reason: 'uniform spacing, not per-direction fitting',
          );
        }
      });
    }
  });

  group('reduced motion (regression 13)', () {
    testWidgets('with disableAnimations the dial is instantly readable and '
        'closes instantly with no pending animation', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies), disableAnimations: true));

      await _tapAvatar(tester); // reduced: open is instant
      expect(find.byKey(dialKey), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);

      await tester.tap(find.byKey(barrierKey));
      await tester.pump();
      expect(find.byKey(dialKey), findsNothing, reason: 'instant close');
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('accessibility (A5)', () {
    testWidgets('the avatar node exposes tap (open/close), every AVAILABLE '
        'direction and the Open-full-menu action — an unavailable direction '
        'is never advertised', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies, storyAvailable: false)));

      final data = _dataFor(tester, _avatarKey);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(_exposes(data, 'Menu'), isTrue);
      expect(_exposes(data, 'Save'), isTrue);
      expect(_exposes(data, 'Show less'), isTrue);
      expect(
        _exposes(data, 'Story'),
        isFalse,
        reason: 'unavailable directions are never advertised',
      );
      expect(_exposes(data, 'Open full action menu'), isTrue);

      // The semantic activations drive the REAL delegates exactly once.
      _invokeCustom(tester, _avatarKey, 'Menu');
      await tester.pumpAndSettle();
      expect(spies.menu, 1);

      _invokeCustom(tester, _avatarKey, 'Open full action menu');
      await tester.pumpAndSettle();
      expect(spies.holds, 1);

      // The semantic TAP opens the persistent dial.
      _invokeTap(tester, _avatarKey);
      await tester.pumpAndSettle();
      expect(find.byKey(dialKey), findsOneWidget);
      // …and toggles it closed again.
      _invokeTap(tester, _avatarKey);
      await tester.pumpAndSettle();
      expect(find.byKey(dialKey), findsNothing);
    });

    testWidgets('the persistent dial\'s satellites are honest semantic '
        'buttons: labels kept, unavailable carries disabled', (tester) async {
      final spies = _Spies();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(_joystick(spies, storyAvailable: false)));

      await _tapAvatar(tester);
      await tester.pumpAndSettle();

      final nodes = _allNodes(_ownerOf(tester).rootSemanticsNode!);

      SemanticsData? nodeWith(String label) {
        for (final n in nodes) {
          if (n.label == label) return n;
        }
        return null;
      }

      final menu = nodeWith('Menu');
      expect(menu, isNotNull, reason: 'icon-only is visual; labels are kept');
      expect(menu!.flagsCollection.isButton, isTrue);

      final story = nodeWith('Story (No active story)');
      expect(story, isNotNull);
      expect(story!.flagsCollection.isButton, isTrue);
      expect(
        story.flagsCollection.isEnabled,
        Tristate.isFalse,
        reason: 'disabled state is carried',
      );
      expect(
        story.flagsCollection.isEnabled,
        Tristate.isFalse,
        reason: 'honestly disabled',
      );
      expect(menu.flagsCollection.isEnabled, Tristate.isTrue);
      semantics.dispose();
    });

    testWidgets('the TRANSIENT dial adds NO duplicate screen-reader stops', (
      tester,
    ) async {
      final spies = _Spies();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(_joystick(spies)));

      final gesture = await _press(tester);
      await _pumpMove(tester, gesture, const Offset(0, -26));

      final labels = _allNodes(
        _ownerOf(tester).rootSemanticsNode!,
      ).map((n) => n.label).toSet();
      expect(
        labels.contains('Menu'),
        isFalse,
        reason: 'satellite labels exist only on the persistent dial',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      semantics.dispose();
    });
  });

  group('teardown honesty', () {
    testWidgets('widget disposal mid-session removes the overlay and fires '
        'nothing', (tester) async {
      final spies = _Spies();
      await tester.pumpWidget(_host(_joystick(spies)));

      final gesture = await _press(tester);
      await _pumpMove(tester, gesture, const Offset(0, -26));

      await tester.pumpWidget(const SizedBox.shrink());
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byKey(dialKey), findsNothing);
      expect(spies.total, 0);
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
}
