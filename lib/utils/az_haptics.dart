import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Centralized haptic feedback for Azaman.
/// Every haptic call in the app goes through here — never call
/// HapticFeedback directly from UI code.
abstract class AzHaptics {
  /// Tab switch, checkbox toggle, segmented control, selection change
  static void selection() => HapticFeedback.selectionClick();

  /// Threshold crossed mid-gesture (swipe-to-reply trigger, pull-to-refresh)
  static void thresholdCrossed() => HapticFeedback.mediumImpact();

  /// Success — payment sent, order placed, susu contribution confirmed
  static void success() => HapticFeedback.lightImpact();

  /// Warning / destructive confirm — delete message, cancel trade
  static void warning() => HapticFeedback.heavyImpact();

  /// Double pulse for special moments (AZM reward received, vault goal hit)
  static Future<void> celebrationPulse() async {
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 120));
    HapticFeedback.lightImpact();
  }

  /// Long transaction pattern (used on high-value money movements
  /// to create a sense of "something significant just happened")
  static Future<void> moneyMoved() async {
    final hasVibrator = (await Vibration.hasVibrator()) == true;
    if (hasVibrator) {
      Vibration.vibrate(pattern: [0, 50, 100, 80, 100, 50], intensities: [0, 128, 0, 200, 0, 128]);
    } else {
      HapticFeedback.heavyImpact();
    }
  }
}
