// TASK-008 follow-ups — Home entrance choreography (spec sections 2c, 3):
//
//   1. The entrance completes: every choreographed fade is fully painted by
//      550ms (last block: staggerDelay(6)=240ms + standard=220ms = 460ms),
//      and nothing on the page keeps animating once it lands.
//   2. The camera move is correct: header from the LEFT, balance rail from
//      the RIGHT (opposite), pills from BELOW. This is the one block that
//      travels against the others, so the deck feels slid into view.
//   3. Reduced motion: with MediaQuery.disableAnimations, Home simply IS
//      there on the first frame — no fade, no slide, no avatar pop.
//
// The host is minimal: an inert AuthProvider (no socket), a zeroed unread
// count (no badge, no notification fetch), and a stubbed balance/oracle pair
// so the hero card renders deterministically. The network-facing summary
// fetch fails fast in tests, so the sections below the rail render in their
// idle states — no timers, no sockets, nothing to settle but the entrance.
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/widgets/flippable_balance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderTransform, Vector4;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _surfaceSize = Size(400, 900);

/// The `tap` hand hint shows for first-time users and pulses on a repeating
/// controller — real UX, but not part of the entrance. Seed it as seen so
/// these tests observe only the choreography under test.
Future<void> _pumpHome(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  SharedPreferences.setMockInitialValues(
      {'has_seen_flippable_card_hint': true});
  await tester.binding.setSurfaceSize(_surfaceSize);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      // A derived Provider: overriding it keeps NotificationNotifier (and its
      // initial fetch) out of the tree entirely.
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
          (ref) => BalanceData(availableBalance: 100)),
      oracleRateProvider.overrideWith((ref) => 1.0),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: _surfaceSize)
              .copyWith(disableAnimations: reduceMotion),
          child: const Scaffold(body: AzamanHomePage()),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Every `RenderTransform` in [finder]'s ancestor chain, nearest first —
/// flutter_animate's slides render as Transforms, and widgets may nest their
/// own (the flippable card's flip, ScaleTap's press), so tests must look at
/// the whole chain rather than the nearest one.
List<RenderTransform> _ancestorTransforms(WidgetTester tester, Finder finder) {
  final renders =
      tester.renderObjectList(finder).cast<RenderObject>().toList();
  expect(renders, isNotEmpty, reason: 'nothing matched $finder');
  final out = <RenderTransform>[];
  for (final start in renders) {
    RenderObject? node = start;
    while (node != null) {
      if (node is RenderTransform) out.add(node);
      node = node.parent as RenderObject?;
    }
  }
  return out;
}

Vector4? _netTranslation(List<RenderTransform> transforms) {
  Vector4? net;
  for (final t in transforms) {
    final pos = t.transform.getTranslation();
    if (pos.x.abs() > 0.5 || pos.y.abs() > 0.5) {
      net = pos;
      break;
    }
  }
  return net;
}

void main() {
  testWidgets('entrance completes: fully painted by 550ms, nothing left '
      'moving', (tester) async {
    await _pumpHome(tester);

    // t=0: the choreography is real — at least one block is still invisible.
    final fades0 = tester
        .widgetList<FadeTransition>(find.byType(FadeTransition))
        .toList();
    expect(
      fades0.any((f) => f.opacity.value < 0.99),
      isTrue,
      reason: 'home should still be entering at the first frame',
    );

    // t=550ms: last block lands at 460ms; everything must be fully painted.
    await tester.pump(const Duration(milliseconds: 550));
    final fades = tester
        .widgetList<FadeTransition>(find.byType(FadeTransition))
        .toList();
    expect(fades, isNotEmpty);
    for (final f in fades) {
      expect(f.opacity.value, greaterThan(0.999),
          reason: 'a fade is still running at 550ms');
    }

    // And nothing keeps moving: no active animation callbacks remain.
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(SchedulerBinding.instance.transientCallbackCount, 0,
        reason: 'something started animating after the entrance');
  });

  testWidgets('entrance direction: header from the left, rail from the '
      'right, pills from below', (tester) async {
    await _pumpHome(tester);

    // First frame: every block sits exactly at its begin offset.
    // Header (block 0) travels from the LEFT: negative x.
    final gift = _netTranslation(
        _ancestorTransforms(tester, find.byIcon(HugeIconsSolid.gift)));
    expect(gift, isNotNull, reason: 'header gift icon has no entrance offset');
    expect(gift!.x, lessThan(-2));

    // The rail (block 3) travels from the RIGHT: positive x, opposite the
    // header — the deck is slid in, not dropped.
    final rail = _netTranslation(_ancestorTransforms(
        tester, find.byType(FlippableBalanceCard)));
    expect(rail, isNotNull, reason: 'balance rail has no entrance offset');
    expect(rail!.x, greaterThan(2));

    // The action pills (block 2) rise from BELOW: positive y.
    final pill = _netTranslation(
        _ancestorTransforms(tester, find.byIcon(HugeIconsSolid.plusSign)));
    expect(pill, isNotNull, reason: 'action pill has no entrance offset');
    expect(pill!.y, greaterThan(2));
  });

  testWidgets('reduced motion: Home is fully painted on the first frame',
      (tester) async {
    await _pumpHome(tester, reduceMotion: true);

    // No fade in flight anywhere on the page…
    final fades = tester
        .widgetList<FadeTransition>(find.byType(FadeTransition))
        .toList();
    for (final f in fades) {
      expect(f.opacity.value, greaterThan(0.999),
          reason: 'a fade is still running under reduced motion');
    }

    // …and no entrance slide or avatar pop: nothing sits offset anywhere in
    // the header, rail or pills' transform chains.
    for (final finder in [
      find.byIcon(HugeIconsSolid.gift),
      find.byIcon(HugeIconsSolid.plusSign),
      find.byType(FlippableBalanceCard),
    ]) {
      expect(_netTranslation(_ancestorTransforms(tester, finder)), isNull,
          reason: '$finder carries an offset under reduced motion');
    }

    // The page is instantly at rest — no entrance to wait out.
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('reduced motion: no avatar pop-in scale', (tester) async {
    await _pumpHome(tester, reduceMotion: true);

    // The avatar (the tree's only Hero) simply IS there: no non-identity
    // scale in its transform chain. The entrance pop-in would be a 0.8
    // scale on the first frames.
    for (final t in _ancestorTransforms(tester, find.byType(Hero))) {
      expect((t.transform.getMaxScaleOnAxis() - 1).abs(), lessThan(0.01),
          reason: 'avatar is scale-popping in under reduced motion');
    }
  });
}
