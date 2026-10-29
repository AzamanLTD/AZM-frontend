import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/az_intent.dart';
import 'package:azaman/experience/az_spatial_mode.dart';
import 'package:azaman/experience/az_surface.dart';
import 'package:azaman/experience/demo/demo_guard.dart';
import 'package:azaman/theme/az_radius.dart';

void main() {
  test('every surface kind resolves to a tokenised radius', () {
    const ladder = <double>[
      AzRadius.xs,
      AzRadius.sm,
      AzRadius.md,
      AzRadius.lg,
      AzRadius.xl,
      AzRadius.xxl,
      AzRadius.pill,
    ];
    for (final kind in AzSurfaceKind.values) {
      final spec = AzSurfaceSpec.of(kind);
      expect(ladder, contains(spec.radius), reason: kind.name);
    }
  });

  test('cards are flat: no border, no shadow, no blur', () {
    final card = AzSurfaceSpec.of(AzSurfaceKind.card);
    expect(card.radius, AzRadius.lg);
    expect(card.hasBorder, isFalse);
    expect(card.hasShadow, isFalse);
    expect(card.hasBlur, isFalse);
  });

  test('trays float, sheets use the sheet step, chips are pills', () {
    expect(AzSurfaceSpec.of(AzSurfaceKind.tray).hasShadow, isTrue);
    expect(AzSurfaceSpec.of(AzSurfaceKind.sheet).radius, AzRadius.xxl);
    expect(AzSurfaceSpec.of(AzSurfaceKind.chip).radius, AzRadius.pill);
  });

  test('calm spatial modes', () {
    expect(AzSpatialMode.transactionalConfirmation.isCalm, isTrue);
    expect(AzSpatialMode.focusedAction.isCalm, isTrue);
    expect(AzSpatialMode.social.isCalm, isFalse);
    expect(AzSpatialMode.fullScreenMedia.isImmersive, isTrue);
  });

  test('intent presentation flags', () {
    expect(AzIntent.report.isDestructive, isTrue);
    expect(AzIntent.block.isDestructive, isTrue);
    expect(AzIntent.save.isDestructive, isFalse);
    expect(AzIntent.pay.movesMoney, isTrue);
    expect(AzIntent.chat.movesMoney, isFalse);
  });

  test('DemoGuard delegates to AppConfig and honours the test override', () {
    // Default compile-time demo mode is off in tests.
    DemoGuard.override(null);
    expect(DemoGuard.enabled, isFalse);
    DemoGuard.override(true);
    expect(DemoGuard.enabled, isTrue);
    DemoGuard.override(null);
    expect(DemoGuard.enabled, isFalse);
  });
}