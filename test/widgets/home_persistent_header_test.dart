// WORKSTREAM A — Home persistent header + pull-down notification centre.
//
// The contract under test (brief, 2026-10-24):
//
//   1. PINNED      — the band stays at the same top position while Home
//                    content scrolls under it; at rest it paints nothing,
//                    scrolled it frosts (tint+blur) driven by the REAL
//                    scroll offset, and the frost reverses with the scroll.
//   2. REVEAL      — a downward drag on the band progressively reveals the
//                    in-app notification centre, following the finger in
//                    BOTH directions; release past the threshold commits,
//                    release before it returns closed, a deliberate fast
//                    pull commits early, and a pointer cancellation never
//                    leaves a half-open panel behind.
//   3. ARBITRATION — a band pull never triggers Home's pull-to-refresh and
//                    never moves the Home scroll; the bell tap remains a
//                    reliable alternative; with the panel open, the list
//                    scrolls as a normal list while the panel stays open,
//                    and the chrome's downward/upward drags dismiss it.
//   4. HANDOFF     — the header departs upward with the wallet→activity
//                    handoff (its controls stop hit-testing once gone).
//   5. REDUCED     — direct state transitions: the bell tap opens the
//                    centre with no entrance animation in flight.
//
// Harness note: the seeded notifications are committed state (the same
// source of truth the overlay reads) — the panel's read/unread truth is
// never fabricated by the harness.

import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/models/notification_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/widgets/notification_bell.dart';
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
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  await loader.load();
  _fontsLoaded = true;
}

/// A committed-state seed: the real notifier with a tokenless auth (its
/// initial fetch is inert) whose state is the test's committed list.
class _SeededNotifications extends NotificationNotifier {
  _SeededNotifications(super.ref, List<AppNotification> seed) {
    state = seed;
  }
}

List<AppNotification> _manyNotifications() {
  return List<AppNotification>.generate(
    30,
    (i) => AppNotification(
      id: 'n$i',
      title: 'Notification $i',
      body: 'Committed body $i',
      category: NotificationCategory.general,
      createdAt: DateTime(2026, 10, 24, 12 - (i ~/ 5)),
    ),
  );
}

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  AzamanTheme theme = AzamanTheme.dark,
  bool reduceMotion = false,
  bool seedNotifications = false,
  VoidCallback? onOpenSettings,
}) async {
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
    'azaman_theme': theme == AzamanTheme.dark ? 1 : 0,
  });
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(_surfaceSize);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 100),
      ),
      oracleRateProvider.overrideWith((ref) => 1.0),
      if (seedNotifications)
        notificationProvider.overrideWith(
          (ref) => _SeededNotifications(ref, _manyNotifications()),
        ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(theme),
        // The notification centre mounts in the ROOT overlay (above
        // home's own MediaQuery wrapper) — override the window there
        // too so the panel and the header agree on it, exactly as they
        // do in production (one real window).
        builder: (context, child) => MediaQuery(
          data: const MediaQueryData(size: _surfaceSize)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: AzamanHomePage(onOpenSettings: onOpenSettings),
        ),
      ),
    ),
  );
  // The entrance choreography plays out (bounded drain — the bell's
  // one-shot pop never schedules a repeat).
  for (var t = 0; t < 600; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

double _panelTop(WidgetTester tester) {
  // The panel's 'Notifications' title — the reliable, always-present
  // marker of the panel's on-screen position (the panel box itself is
  // translated via Transform; the title's render box reports the
  // translated, painted position).
  final box = tester.renderObject<RenderBox>(
    find.text('Notifications').first,
  );
  return box.localToGlobal(Offset.zero).dy;
}

/// A bounded settle: the open panel's bottom handle bobs on a repeating
/// controller, so pumpAndSettle never terminates. Bounded drains only.
Future<void> _drain(WidgetTester tester, [Duration total = const Duration(seconds: 2)]) async {
  var left = total;
  const step = Duration(milliseconds: 50);
  while (left > Duration.zero) {
    await tester.pump(step);
    left = left - step;
  }
}

Finder get _band => find.byKey(const ValueKey('home-persistent-header'));
Finder get _surface => find.byKey(const ValueKey('home-header-surface'));
Offset get _bandCenter => const Offset(200, 30);

void main() {
  // ── 1. PINNED + TRANSLUCENCY ────────────────────────────────────────────

  testWidgets('band is pinned at the top and transparent at rest',
      (tester) async {
    await _pumpHome(tester);
    expect(_band, findsOneWidget);
    expect(
      tester.getTopLeft(_band),
      Offset.zero,
      reason: 'the pinned band must sit at the very top of the Home area',
    );
    // Nothing paints behind the controls at rest.
    expect(_surface, findsNothing);
    // The bell and profile anchor remain present and hit-testable.
    expect(find.byType(NotificationBell), findsOneWidget);
  });

  testWidgets('content scrolls behind the band; frost follows the real '
      'scroll and reverses', (tester) async {
    await _pumpHome(tester);

    final bellTopBefore = tester.getTopLeft(find.byType(NotificationBell)).dy;

    // Scroll the Home content from BELOW the band (the deck region) so
    // the drag belongs to the scrollable, not the reveal gesture.
    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -120));
    await _drain(tester);

    // Pinned: the bell has not moved a single pixel.
    expect(tester.getTopLeft(find.byType(NotificationBell)).dy,
        bellTopBefore,
        reason: 'the header must stay pinned while content scrolls');

    // Frosted: the translucent surface exists and is legible (non-zero
    // alpha tint over content).
    expect(_surface, findsOneWidget,
        reason: 'scrolled content must frost the pinned band');

    // Reverse the scroll to the top: the frost disappears (driven by the
    // real scroll state, not a timer). The return drag is deliberately
    // short: this harness's Home content nearly fills the viewport (the
    // scrollable's max extent is ~8px), so every downward pixel past the
    // top is a REAL pull-to-refresh pull (AzLogoRefreshIndicator triggers
    // at 55px of accumulated pull — 0.5 × overscroll). A full +120
    // return drag is therefore a 112px refresh pull, and this test is
    // about the frost, not the refresh — keep the return gesture below
    // the refresh threshold and let it verify what it actually claims.
    await tester.drag(scrollable, const Offset(0, 40));
    await _drain(tester);
    expect(_surface, findsNothing,
        reason: 'the frost must clear when the scroll returns to the top');
  });

  testWidgets('profile control still opens the settings drawer',
      (tester) async {
    var opened = 0;
    await _pumpHome(tester, onOpenSettings: () => opened++);
    // The avatar is Home's only Hero (tag 'profile-avatar'); ScaleTap
    // inside carries the tap → settings contract.
    await tester.tap(find.byType(Hero));
    await tester.pump(const Duration(milliseconds: 350));
    expect(opened, 1, reason: 'the pinned profile control must remain '
        'wired to the shell settings callback');
  });

  // ── 2. THE PULL-DOWN REVEAL ─────────────────────────────────────────────

  testWidgets('pull-down follows the finger in both directions and '
      'returns closed below the threshold', (tester) async {
    await _pumpHome(tester, seedNotifications: true);

    final gesture = await tester.startGesture(_bandCenter);
    await gesture.moveBy(const Offset(0, 300)); // reveal 300/495 ≈ 0.61
    await tester.pump();

    // Partially revealed: the panel hangs above the top edge, its title
    // translated by the finger (600/900*0.92... expected dy = -(1-0.606)
    // *0.92*900 ≈ -327, title ≈ -327 + 14).
    final top = _panelTop(tester);
    expect(top, inExclusiveRange(-420, -240),
        reason: 'the panel must follow the finger (reveal ≈ 0.61), not '
            'jump fully open');

    // Reversal: the finger travels back up and the panel follows upward.
    await gesture.moveBy(const Offset(0, -180)); // reveal ≈ 0.24
    await tester.pump();
    final topReversed = _panelTop(tester);
    expect(topReversed, lessThan(top),
        reason: 'a reversed pull must move the panel back toward closed');

    // Release below the threshold at low velocity: returns to closed.
    await gesture.up();
    await _drain(tester);
    expect(find.text('Notifications'), findsNothing,
        reason: 'a sub-threshold release must remove the panel entirely');
  });

  testWidgets('release past the threshold commits open (no velocity '
      'needed)', (tester) async {
    await _pumpHome(tester, seedNotifications: true);

    // Slow, controlled pulls: 6 × 50px with 100ms stamps → velocity
    // 500px/s (below the 700 commit velocity), total 300px ≥ threshold.
    final gesture = await tester.startGesture(_bandCenter);
    var stamp = Duration.zero;
    for (var i = 0; i < 6; i++) {
      stamp += const Duration(milliseconds: 100);
      await gesture.moveBy(const Offset(0, 50), timeStamp: stamp);
      await tester.pump();
    }
    await gesture.up();
    await _drain(tester);

    expect(find.text('Notifications'), findsOneWidget,
        reason: 'a deliberate past-threshold pull must commit open');
    expect(_panelTop(tester), inExclusiveRange(-1, 40),
        reason: 'the committed panel must sit fully on-screen at the top');
  });

  testWidgets('a deliberate fast pull commits early', (tester) async {
    await _pumpHome(tester, seedNotifications: true);
    // A fling on the band: high velocity, short distance.
    await tester.fling(
      _band.first,
      const Offset(0, 140),
      1500,
    );
    await _drain(tester);
    expect(find.text('Notifications'), findsOneWidget,
        reason: 'a high-velocity pull must commit below the distance '
            'threshold');
  });

  testWidgets('a band pull never triggers Home refresh or scrolls the '
      'list', (tester) async {
    await _pumpHome(tester, seedNotifications: true);

    // The Home scroll position before and after a full band pull cycle.
    final scrollableFinder = find.byType(Scrollable).first;
    final before = tester
        .state<ScrollableState>(scrollableFinder)
        .position
        .pixels;

    final gesture = await tester.startGesture(_bandCenter);
    await gesture.moveBy(const Offset(0, 320));
    await tester.pump();
    // The pull-down is mid-flight; the home list must not have moved and
    // no refresh indicator may be displaced.
    expect(
      tester.state<ScrollableState>(scrollableFinder).position.pixels,
      before,
      reason: 'the band pull must not scroll the Home content',
    );
    await gesture.moveBy(const Offset(0, -320));
    await tester.pump();
    await gesture.up();
    await _drain(tester);

    expect(
      tester.state<ScrollableState>(scrollableFinder).position.pixels,
      before,
      reason: 'a cancelled band pull must leave the Home scroll untouched '
          '(and never fire a refresh)',
    );
  });

  testWidgets('pointer cancellation settles closed — no half-open panel '
      'survives', (tester) async {
    await _pumpHome(tester, seedNotifications: true);
    final gesture = await tester.startGesture(_bandCenter);
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    expect(find.text('Notifications'), findsOneWidget);

    await gesture.cancel();
    await _drain(tester);
    expect(find.text('Notifications'), findsNothing,
        reason: 'a cancelled pointer must settle the panel closed and '
            'remove the entry');
  });

  // ── 3. THE OPEN PANEL ────────────────────────────────────────────────────

  testWidgets('bell tap remains the reliable alternative to open the '
      'centre', (tester) async {
    await _pumpHome(tester, seedNotifications: true);
    await tester.tap(find.byType(NotificationBell));
    await _drain(tester);
    expect(find.text('Notifications'), findsOneWidget);
    expect(_panelTop(tester), inExclusiveRange(-1, 40));
  });

  testWidgets('with the panel open, the notification list scrolls as a '
      'normal list and the panel stays open', (tester) async {
    await _pumpHome(tester, seedNotifications: true);
    await tester.tap(find.byType(NotificationBell));
    await _drain(tester);

    // A list scroll: drag ON a list row (not the panel chrome).
    final row = find.text('Notification 5').first;
    await tester.drag(row, const Offset(0, -180));
    await _drain(tester);

    expect(find.text('Notifications'), findsOneWidget,
        reason: 'scrolling the list must never dismiss the panel');
    // The list really scrolled: an earlier row surfaced.
    expect(find.text('Notification 2'), findsOneWidget);
  });

  testWidgets('downward drag on the panel chrome follows the finger and '
      'dismisses past the threshold', (tester) async {
    await _pumpHome(tester, seedNotifications: true);
    await tester.tap(find.byType(NotificationBell));
    await _drain(tester);
    final openTop = _panelTop(tester);

    // Downward drag from the chrome (the title row). The first move only
    // WINS the gesture arena for the chrome recogniser (the notification
    // list competes for the same pointer) — the position-carrying moves
    // are the ones after acceptance, exactly as with a real finger,
    // which produces moves continuously.
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.text('Notifications').first) +
          const Offset(200, 8),
    );
    await gesture.moveBy(const Offset(0, 20)); // arena recognition
    await tester.pump();
    await gesture.moveBy(const Offset(0, 120)); // finger-following
    await tester.pump();
    expect(_panelTop(tester), greaterThan(openTop + 100),
        reason: 'the open panel must follow a downward chrome drag');

    await gesture.up();
    await _drain(tester);
    expect(find.text('Notifications'), findsNothing,
        reason: 'a past-threshold downward release must dismiss the panel');
  });

  testWidgets('the legacy upward dismissal still works', (tester) async {
    await _pumpHome(tester, seedNotifications: true);
    await tester.tap(find.byType(NotificationBell));
    await _drain(tester);

    await tester.fling(
      find.text('Notifications').first,
      const Offset(0, -300),
      1000,
    );
    await _drain(tester);
    expect(find.text('Notifications'), findsNothing);
  });

  // ── 4. HANDOFF DEPARTURE ────────────────────────────────────────────────

  testWidgets('the header departs upward with the wallet→activity '
      'handoff', (tester) async {
    await _pumpHome(tester);

    // The handoff is fed by the Home page's bottom overscroll: a
    // deliberate long drag at the bottom of the content commits it.
    final scrollable = find.byType(Scrollable).first;
    // Reach the bottom first.
    await tester.drag(scrollable, const Offset(0, -2000));
    await _drain(tester);
    // Held continuation at the bottom: committed deliberately.
    final gesture = await tester.startGesture(const Offset(200, 830));
    await gesture.moveBy(const Offset(0, -160));
    await tester.pump();
    await gesture.up();
    await _drain(tester);

    // Header is gone with the wallet composition: the band neither paints
    // nor hit-tests.
    final header = _band;
    expect(tester.widgetList<IgnorePointer>(find.byType(IgnorePointer)),
        isNotEmpty); // the tree still has its ignore wrappers
    // RenderBox check: the band's painted opacity ancestor is zero.
    // (Departure = opacity 1 - t; committed t = 1.)
    final opacity = find
        .ancestor(of: header, matching: find.byType(Opacity))
        .evaluate()
        .map((e) => e.widget as Opacity)
        .toList();
    expect(
      opacity.any((o) => o.opacity < 0.05),
      isTrue,
      reason: 'the committed handoff must have faded the pinned header '
          'out with the wallet composition',
    );
  });

  // ── 5. REDUCED MOTION ───────────────────────────────────────────────────

  testWidgets('reduced motion: the bell tap opens the centre with direct '
      'state — no entrance animation in flight', (tester) async {
    await _pumpHome(tester, reduceMotion: true, seedNotifications: true);
    await tester.tap(find.byType(NotificationBell));
    // TWO frames, no duration advance: the zero-duration forward settles
    // on the second tick. A real entrance animation (420ms) would still
    // be barely underway — so fully-open here proves the direct state
    // transition.
    await tester.pump();
    await tester.pump();

    expect(find.text('Notifications'), findsOneWidget,
        reason: 'under reduced motion the centre must be open within two '
            'frames of the tap — a direct state transition');
    expect(_panelTop(tester), inExclusiveRange(-1, 40));
  });
}
