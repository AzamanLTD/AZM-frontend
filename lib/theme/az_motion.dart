import 'package:flutter/widgets.dart';

import 'package:azaman/providers/sensory_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';

/// Shared decision for spatial travel versus a still, informational state.
class AzMotion {
  final bool travel;
  const AzMotion._travel(this.travel);

  static AzMotion of(BuildContext context) {
    // The static sink supplies the answer; the optional scope subscribes mounted
    // consumers to the existing notifier, including persisted preference loads.
    context.dependOnInheritedWidgetOfExactType<AzMotionScope>();
    final osOff = MediaQuery.of(context).disableAnimations;
    final reduce = AzSensory.reduceMotionOverrideIsSet
        ? AzSensory.reduceMotionOverride
        : osOff;
    return reduce
        ? const AzMotion._travel(false)
        : const AzMotion._travel(true);
  }

  static Duration duration(BuildContext context, Duration normal) =>
      of(context).travel ? normal : Duration.zero;

  /// Information remains perceivable, even if a caller supplied zero tempo.
  static Duration informational(BuildContext context, Duration normal) =>
      of(context).travel && normal > Duration.zero
      ? normal
      : MotionTokens.control;

  static Duration stagger(BuildContext context, int index) =>
      of(context).travel ? MotionTokens.staggerDelay(index) : Duration.zero;

  static double scale(BuildContext context, double amount) =>
      of(context).travel ? amount : 0.0;

  static T pick<T>(
    BuildContext context, {
    required T moving,
    required T still,
  }) => of(context).travel ? moving : still;
}

/// Notification bridge only. It owns no preferences and performs no resolution.
/// Root installation lets unchanged Stateful/Stateless consumers observe the
/// TASK-026 notifier without adding Riverpod dependencies to their public APIs.
class AzMotionScope extends InheritedNotifier<SensoryProvider> {
  const AzMotionScope({
    super.key,
    required SensoryProvider super.notifier,
    required super.child,
  });
}
