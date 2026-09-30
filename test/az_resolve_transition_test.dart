import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

import 'package:azaman/providers/sensory_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/widgets/az_resolve_transition.dart';
import 'package:azaman/widgets/az_skeleton.dart';
import 'package:azaman/widgets/skeleton_loader.dart';

Widget wrap({
  AzResolvePhase phase = AzResolvePhase.resolved,
  int index = 0,
  bool skip = false,
  bool announce = false,
  bool reduced = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: AzResolveTransition(
      phase: phase,
      index: index,
      skipEntrance: skip,
      announce: announce,
      child: const Text('Arrived'),
    ),
  ),
);

Finder within(Type type) => find.descendant(
  of: find.byType(AzResolveTransition),
  matching: find.byType(type),
);
double opacity(WidgetTester tester) =>
    tester.widget<Opacity>(within(Opacity)).opacity;

void main() {
  var haptics = 0;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AzSensory.hapticsEnabled = true;
    haptics = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics++;
          return null;
        });
  });
  tearDown(() {
    AzSensory.hapticsEnabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('loading hides content; resolved fades and rises 6px', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(phase: AzResolvePhase.loading));
    expect(opacity(tester), 0);
    expect(
      tester.widget<Transform>(within(Transform)).transform.storage[13],
      6,
    );
    expect(
      tester.widget<IgnorePointer>(within(IgnorePointer)).ignoring,
      isTrue,
    );
    await tester.pumpWidget(wrap());
    await tester.pump(); // deliver the zero-stagger callback
    await tester.pump(); // establish the ticker epoch
    await tester.pump(const Duration(milliseconds: 175));
    expect(opacity(tester), greaterThan(0));
    expect(opacity(tester), lessThan(1));
    await tester.pump(MotionTokens.emphasized);
    expect(opacity(tester), 1);
    expect(
      tester.widget<Transform>(within(Transform)).transform.storage[13],
      0,
    );
  });

  testWidgets('initial resolved content gets one entrance', (tester) async {
    await tester.pumpWidget(wrap(announce: true));
    expect(opacity(tester), 0);
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
    expect(haptics, 1);
    await tester.pumpWidget(wrap(announce: true));
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
    expect(haptics, 1);
  });

  testWidgets('skipEntrance lands immediately in both motion modes', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(skip: true, announce: true));
    expect(opacity(tester), 1);
    expect(haptics, 0);
    await tester.pumpWidget(wrap(skip: true, reduced: true, announce: true));
    expect(tester.widget<AnimatedOpacity>(within(AnimatedOpacity)).opacity, 1);
    expect(
      tester.widget<AnimatedOpacity>(within(AnimatedOpacity)).duration,
      Duration.zero,
    );
    expect(haptics, 0);
  });

  testWidgets(
    'reduced motion cross-fades 180ms with no translation or stagger',
    (tester) async {
      await tester.pumpWidget(
        wrap(phase: AzResolvePhase.loading, reduced: true, index: 999),
      );
      expect(
        tester.widget<AnimatedOpacity>(within(AnimatedOpacity)).opacity,
        0,
      );
      await tester.pumpWidget(wrap(reduced: true, index: 999));
      await tester.pump();
      final fade = tester.widget<AnimatedOpacity>(within(AnimatedOpacity));
      expect(fade.duration, const Duration(milliseconds: 180));
      expect(fade.opacity, 1);
      expect(within(Transform), findsNothing);
      await tester.pump(const Duration(milliseconds: 90));
      final transition = tester.widget<FadeTransition>(within(FadeTransition));
      expect(transition.opacity.value, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester.widget<FadeTransition>(within(FadeTransition)).opacity.value,
        1,
      );
    },
  );

  testWidgets('normal stagger follows draw order and caps high indices', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(index: 999));
    await tester.pump(MotionTokens.staggerDelay(999));
    await tester.pump();
    await tester.pump(MotionTokens.emphasized);
    expect(opacity(tester), 1);
    expect(
      MotionTokens.staggerDelay(999),
      lessThanOrEqualTo(MotionTokens.staggerMax),
    );
  });

  testWidgets('index 5 waits 200ms, then finishes within 550ms', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(index: 5));
    await tester.pump(const Duration(milliseconds: 199));
    expect(opacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump(MotionTokens.emphasized);
    expect(opacity(tester), 1);
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'announcement once across phase/dependency updates (reduced=$reduced)',
      (tester) async {
        await tester.pumpWidget(
          wrap(phase: AzResolvePhase.loading, reduced: reduced, announce: true),
        );
        expect(haptics, 0);
        await tester.pumpWidget(wrap(reduced: reduced, announce: true));
        await tester.pumpAndSettle();
        expect(haptics, 1);
        await tester.pumpWidget(
          wrap(phase: AzResolvePhase.loading, reduced: reduced, announce: true),
        );
        await tester.pumpWidget(wrap(reduced: reduced, announce: true));
        await tester.pumpAndSettle();
        await tester.pumpWidget(wrap(reduced: !reduced, announce: true));
        await tester.pumpAndSettle();
        expect(haptics, 1);
      },
    );
  }

  testWidgets('nonzero index and disabled haptics never announce', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(index: 1, announce: true));
    await tester.pump(MotionTokens.staggerDelay(1));
    await tester.pumpAndSettle();
    expect(haptics, 0);
    await tester.pumpWidget(const SizedBox());
    AzSensory.hapticsEnabled = false;
    await tester.pumpWidget(wrap(announce: true, reduced: true));
    await tester.pumpAndSettle();
    expect(haptics, 0);
  });

  testWidgets('loading or disposal cancels a pending entrance', (tester) async {
    await tester.pumpWidget(wrap(index: 5, announce: true));
    await tester.pumpWidget(
      wrap(index: 5, phase: AzResolvePhase.loading, announce: true),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(opacity(tester), 0);
    expect(haptics, 0);
    await tester.pumpWidget(wrap(index: 5));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  for (final theme in AzamanTheme.values) {
    testWidgets('skeleton palette follows ${theme.name} theme', (tester) async {
      SharedPreferences.setMockInitialValues({'azaman_theme': theme.index});
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AzSkeleton())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      final element = tester.element(find.byType(AzSkeleton));
      final colors = ProviderScope.containerOf(
        element,
      ).read(themeProvider).colors;
      expect(colors.isDark, theme == AzamanTheme.dark);
      final shimmer = tester.widget<Shimmer>(find.byType(Shimmer));
      final gradient = shimmer.gradient as LinearGradient;
      expect(gradient.colors, contains(colors.softSurface));
      expect(
        gradient.colors,
        contains(colors.isDark ? colors.card : colors.background),
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'SkeletonBlock stops and resumes shimmer when reduced motion changes',
    (tester) async {
      Widget skeleton(bool reduced) => ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const SkeletonBlock(),
          ),
        ),
      );
      await tester.pumpWidget(skeleton(true));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(skeleton(false));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(skeleton(true));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
