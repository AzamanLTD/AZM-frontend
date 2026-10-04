/// Stay story indicator (Overhaul 03 §4.6): Dates → Room → Review → Confirmed.
///
/// Derived from [StayDecision] plus booking state; static under reduced
/// motion. No timers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/marketplace/experiences/hotel/stay_decision.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';

class StayStepIndicator extends ConsumerWidget {
  final StayStep current;

  const StayStepIndicator({super.key, required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final travel = AzMotion.of(context).travel;
    final duration = travel ? MotionTokens.control : Duration.zero;
    final idx = StayStep.values.indexOf(current);
    return Row(
      key: ValueKey('stay_step_${current.name}'),
      children: [
        for (var i = 0; i < StayStep.values.length; i++) ...[
          if (i > 0)
            Expanded(
              child: AnimatedContainer(
                duration: duration,
                height: 2,
                color: i <= idx ? colors.accent : colors.divider,
              ),
            ),
          AnimatedContainer(
            duration: duration,
            padding: const EdgeInsets.symmetric(horizontal: AzSpace.sm, vertical: AzSpace.xxs),
            decoration: BoxDecoration(
              color: i == idx ? colors.accentSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              StayStep.values[i].label,
              style: AzText.caption.copyWith(
                color: i <= idx ? colors.accent : colors.textTertiary,
                fontWeight: i == idx ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}