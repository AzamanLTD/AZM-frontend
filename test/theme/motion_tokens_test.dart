import 'package:azaman/theme/motion_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MotionTokens', () {
    test('staggerDelay is monotonic and capped', () {
      expect(MotionTokens.staggerDelay(-1), Duration.zero);
      expect(MotionTokens.staggerDelay(0), Duration.zero);
      expect(MotionTokens.staggerDelay(1), const Duration(milliseconds: 40));
      expect(MotionTokens.staggerDelay(8), const Duration(milliseconds: 300));
      expect(MotionTokens.staggerDelay(100), const Duration(milliseconds: 300));
      expect(
        MotionTokens.staggerDelay(100, cap: 3),
        const Duration(milliseconds: 120),
      );
    });

    testWidgets('accessibleDuration respects disableAnimations', (tester) async {
      Duration? enabledDuration;
      Duration? disabledDuration;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              enabledDuration = MotionTokens.accessibleDuration(
                context,
                MotionTokens.standard,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              disabledDuration = MotionTokens.accessibleDuration(
                context,
                MotionTokens.standard,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(enabledDuration, MotionTokens.standard);
      expect(disabledDuration, Duration.zero);
    });

    testWidgets('ReducedMotion compatibility delegates to canonical helper',
        (tester) async {
      Duration? result;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              result = ReducedMotion.respectReducedMotion(
                context,
                MotionTokens.emphasized,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(result, Duration.zero);
    });
  });
}
