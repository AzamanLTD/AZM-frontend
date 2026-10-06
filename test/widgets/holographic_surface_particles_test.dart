// =============================================================================
// REACTIVE PARTICLE FIELD — the balance card's opt-in touch response.
//
// Follow-up to the Antigravity-inspired brief + the 2026-10-06 correction:
// on the balance card the reactive particle field REPLACES the touch-driven
// specular sheen (it is not a second competing effect). The surface API keeps
// both effects independently disableable:
//
//   HolographicSurface(showSheen: true, showReactiveParticles: false)  // default
//   HolographicSurface(showSheen: false, showReactiveParticles: true)  // balance card
//
// Laws pinned here:
//   • default surfaces are visually unchanged (no particle painter, sheen on)
//   • showSheen:false removes the moving band; particles do NOT replace it as
//     another moving band — the field DEFORMS around the finger, spatially
//     (distance-based falloff, near leans away, mid-band leans toward)
//   • the ambient clock is a single shared controller: ~9s, running only when
//     travel is allowed, fully static under reduced motion
//   • release settles through the EXISTING rest spring — no second animation
//   • the pointer mechanism stays Listener (no gesture arena entry)
//   • positions are deterministic (fixed spec table, no per-frame randomness)
// =============================================================================

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/holographic_surface.dart';

const _base = Color(0xFF1E242B);

Widget _wrap(
  Widget child, {
  bool reduceMotion = false,
}) {
  return ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, navigatorChild) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
        ),
        child: navigatorChild ?? const SizedBox.shrink(),
      ),
      theme: ThemeProvider.getThemeData(AzamanTheme.dark),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

Future<void> _pumpSurface(
  WidgetTester tester, {
  bool showSheen = true,
  bool showReactiveParticles = false,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    _wrap(
      reduceMotion: reduceMotion,
      SizedBox(
        width: 320,
        height: 180,
        child: HolographicSurface(
          base: _base,
          tint: const Color(0xFFD4AF37),
          showSheen: showSheen,
          showReactiveParticles: showReactiveParticles,
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
  await tester.pump();
}

ReactiveParticlePainter? _painter(WidgetTester tester) {
  final painters = tester
      .widgetList<CustomPaint>(find.descendant(
        of: find.byType(HolographicSurface),
        matching: find.byType(CustomPaint),
      ))
      .map((c) => c.painter)
      .whereType<ReactiveParticlePainter>()
      .toList();
  return painters.isEmpty ? null : painters.first;
}

List<BoxDecoration> _boxes(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.descendant(
        of: find.byType(HolographicSurface), matching: find.byType(DecoratedBox)))
    .map((d) => d.decoration)
    .whereType<BoxDecoration>()
    .toList();

/// The specular band — the LinearGradient with the 0.34/0.50/0.66 stops.
LinearGradient? _sheen(WidgetTester tester) {
  final gradients = _boxes(tester)
      .map((d) => d.gradient)
      .whereType<LinearGradient>()
      .toList();
  for (final g in gradients) {
    if (g.stops?.first == 0.34) return g;
  }
  return null;
}

void main() {
  testWidgets('default surface: no particle painter, sheen remains',
      (tester) async {
    await _pumpSurface(tester);
    expect(_painter(tester), isNull);
    expect(_sheen(tester), isNotNull,
        reason: 'every other consumer must keep its existing appearance');
  });

  testWidgets('balance card profile: showSheen:false removes the moving band, '
      'particles are the sole touch response', (tester) async {
    await _pumpSurface(
      tester,
      showSheen: false,
      showReactiveParticles: true,
    );
    expect(_sheen(tester), isNull,
        reason: 'no moving white specular band on the balance card');
    expect(_painter(tester), isNotNull);
  });

  testWidgets('the particle canvas is isolated in a RepaintBoundary',
      (tester) async {
    await _pumpSurface(tester, showReactiveParticles: true);
    final boundary = find.descendant(
      of: find.byType(HolographicSurface),
      matching: find.byType(RepaintBoundary),
    );
    expect(tester.widgetList(boundary), isNotEmpty);
  });

  testWidgets('the ambient clock runs while travel is allowed', (tester) async {
    await _pumpSurface(tester, showReactiveParticles: true);
    final before = _painter(tester)!.phase.value;
    await tester.pump(const Duration(seconds: 2));
    final after = _painter(tester)!.phase.value;
    expect(after, greaterThan(before),
        reason: 'a single shared ~9s ambient clock gives idle life');
  });

  testWidgets('pointer move deforms the field through the existing Listener',
      (tester) async {
    await _pumpSurface(tester, showReactiveParticles: true);
    expect(_painter(tester)!.dx, 0.0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HolographicSurface)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(60, 20));
    await tester.pump();

    expect(_painter(tester)!.dx, greaterThan(0.0));
    expect(
      find.descendant(
        of: find.byType(HolographicSurface),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
      reason: 'particles must never enter the gesture arena',
    );
    await gesture.up();
  });

  testWidgets('release settles through the EXISTING rest spring',
      (tester) async {
    await _pumpSurface(tester, showReactiveParticles: true);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HolographicSurface)),
    );
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();

    final moved = _painter(tester)!.dx;
    expect(moved, greaterThan(0.0));

    await gesture.up();
    // MotionTokens.emphasized = 350ms; the shared _rest spring drives the
    // settle, so pumping it fully must return the field to rest — there is
    // no second independent release animation.
    // Step at 60fps-style frames: the spring needs its tick sequence, and this
    // mirrors how a real device runs it. 700ms covers the 350ms spring fully.
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final settledDx = _painter(tester)!.dx;
    expect(settledDx.abs(), lessThan(0.02));
  });

  testWidgets('reduced motion: fully static — no ambient clock, no response',
      (tester) async {
    await _pumpSurface(
      tester,
      showReactiveParticles: true,
      reduceMotion: true,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(_painter(tester)!.phase.value, 0.0,
        reason: 'the ambient controller must stop under reduced motion');

    // The Listener (and therefore any particle response) is also gone.
    expect(
      find.descendant(
        of: find.byType(HolographicSurface),
        matching: find.byType(Listener),
      ),
      findsNothing,
    );
    expect(_painter(tester)!.dx, 0.0);
  });

  testWidgets('the field remains deterministic — fixed spec table',
      (tester) async {
    const specs = ReactiveParticlePainter.particleSpecs;
    expect(specs.length, inInclusiveRange(18, 28));
    final seen = <String>{};
    for (final s in specs) {
      expect(s.x, inInclusiveRange(0.0, 1.0));
      expect(s.y, inInclusiveRange(0.0, 1.0));
      expect(s.radius, inInclusiveRange(0.5, 3.0));
      expect(s.phase, inInclusiveRange(0.0, 1.0));
      expect(s.speed, inInclusiveRange(0.3, 1.2));
      expect(s.colorIndex, inInclusiveRange(0, 2));
      expect(seen.add('${s.x.toStringAsFixed(3)}:${s.y.toStringAsFixed(3)}'),
          isTrue,
          reason: 'no duplicate positions');
    }
  });

  test('the response deforms spatially, it does not translate the field', () {
    const radius = 90.0;
    const pointer = Offset(160, 90);
    final near = ReactiveParticlePainter.particleLean(
      const Offset(175, 100),
      pointer,
      radius,
    );
    final mid = ReactiveParticlePainter.particleLean(
      const Offset(220, 90),
      pointer,
      radius,
    );
    final far = ReactiveParticlePainter.particleLean(
      const Offset(300, 150),
      pointer,
      radius,
    );

    // Distance-based falloff: far particles barely move.
    expect(
      (far - const Offset(300, 150)).distance,
      lessThan(0.5),
    );

    // The nearest points lean AWAY from the finger (material displaced
    // around the touch), the mid-band leans TOWARD it (attraction) — a
    // deformation, not a uniform translation.
    final nearVec = near - const Offset(175, 100);
    final toPointer = (pointer - const Offset(175, 100)).normalized;
    expect(nearVec.dot(toPointer), lessThan(0.0),
        reason: 'nearest particles lean away from the finger');

    final midVec = mid - const Offset(220, 90);
    final midToPointer = (pointer - const Offset(220, 90)).normalized;
    expect(midVec.dot(midToPointer), greaterThan(0.0),
        reason: 'mid-band particles lean toward the finger');

    // Spatial, not uniform: two particles get different offsets.
    expect(
      (near - const Offset(175, 100)).distance,
      isNot(equals((mid - const Offset(220, 90)).distance)),
    );
  });

  test('paint handles zero and invalid dimensions safely', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = ReactiveParticlePainter(
      phase: const AlwaysStoppedAnimation<double>(0.4),
      dx: 0.2,
      dy: -0.1,
      colors: const [Color(0xFFE0AE3A), Color(0xFFF59E0B), Color(0xFFB8860B)],
      intensity: 1.0,
      isDark: true,
    );

    // Must not throw on a degenerate canvas.
    painter.paint(canvas, Size.zero);
    painter.paint(canvas, const Size(320, 0));
    painter.paint(canvas, const Size(-5, -5));
    recorder.endRecording();
  });
}

extension on Offset {
  Offset get normalized =>
      distance == 0 ? Offset.zero : Offset(dx / distance, dy / distance);
  double dot(Offset other) => dx * other.dx + dy * other.dy;
  double get distance => math.sqrt(dx * dx + dy * dy);
}
