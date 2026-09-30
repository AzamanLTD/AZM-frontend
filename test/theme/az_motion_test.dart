import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/sensory_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/motion_tokens.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AzSensory.apply(const SensoryPreferences());
  });
  tearDown(() => AzSensory.apply(const SensoryPreferences()));

  for (final os in [false, true]) {
    for (final forced in <bool?>[null, true, false]) {
      testWidgets('OS=$os, override=$forced resolves all helpers', (
        tester,
      ) async {
        AzSensory.apply(SensoryPreferences(forceReduceMotion: forced));
        final travel = !(forced ?? os);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: os),
              child: Builder(
                builder: (context) {
                  expect(AzMotion.of(context).travel, travel);
                  expect(
                    AzMotion.duration(
                      context,
                      MotionTokens.emphasized,
                    ).inMicroseconds,
                    travel ? MotionTokens.emphasized.inMicroseconds : 0,
                  );
                  final info = AzMotion.informational(
                    context,
                    MotionTokens.emphasized,
                  );
                  expect(
                    info.inMicroseconds,
                    travel
                        ? MotionTokens.emphasized.inMicroseconds
                        : MotionTokens.control.inMicroseconds,
                  );
                  expect(info, greaterThan(Duration.zero));
                  expect(
                    AzMotion.informational(context, Duration.zero),
                    MotionTokens.control,
                  );
                  for (final index in [-1, 0, 2, 999]) {
                    final stagger = AzMotion.stagger(context, index);
                    expect(
                      stagger.inMicroseconds,
                      travel
                          ? MotionTokens.staggerDelay(index).inMicroseconds
                          : 0,
                    );
                    expect(stagger, lessThanOrEqualTo(MotionTokens.staggerMax));
                  }
                  expect(AzMotion.scale(context, 0.5), travel ? 0.5 : 0);
                  expect(AzMotion.scale(context, -6), travel ? -6 : 0);
                  expect(
                    AzMotion.pick(context, moving: 'move', still: 'still'),
                    travel ? 'move' : 'still',
                  );
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
      });
    }
  }

  testWidgets(
    'mounted consumers observe notifier updates without parent rebuilds',
    (tester) async {
      final sensory = SensoryProvider();
      addTearDown(sensory.dispose);
      final child = Builder(
        builder: (context) =>
            Text(AzMotion.of(context).travel ? 'move' : 'still'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(),
            child: AzMotionScope(notifier: sensory, child: child),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('move'), findsOneWidget);
      await sensory.setForceReduceMotion(true);
      await tester.pump();
      expect(find.text('still'), findsOneWidget);
      await sensory.setForceReduceMotion(false);
      await tester.pump();
      expect(find.text('move'), findsOneWidget);
      await sensory.setForceReduceMotion(null);
      await tester.pump();
      expect(find.text('move'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
