// =============================================================================
// EXPERIENCE PASS §2 — the holographic material's mode-aware hierarchy.
//
// Dark mode is the primary target: a deeper three-facet base, a lit rim, a
// figure plate for contrast behind the balance. Light mode is NOT an inverted
// dark card: a damped iridescence gate, a crisp neutral rim stroke (a white
// rim is invisible on near-white), and a tight contact shadow so the card
// survives a near-white page.
//
// NOTE: each test pumps its own tree exactly once. Sequential pumpWidget calls
// with different themes inside a single testWidgets proved unreliable in this
// flutter_tester build (stale inherited theme state), so mode assertions are
// separated into dedicated tests.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/holographic_surface.dart';

const _base = Color(0xFF1E242B);

Future<void> _pumpSurface(WidgetTester tester, AzamanTheme theme) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(theme),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 180,
              child: HolographicSurface(
                base: _base,
                tint: Color(0xFFD4AF37),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

List<BoxDecoration> _boxes(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.descendant(
        of: find.byType(HolographicSurface), matching: find.byType(DecoratedBox)))
    .map((d) => d.decoration)
    .whereType<BoxDecoration>()
    .toList();

/// The base material (layer 1) — the first LinearGradient in the surface.
LinearGradient _baseGradient(WidgetTester tester) => _boxes(tester)
    .map((d) => d.gradient)
    .whereType<LinearGradient>()
    .first;

/// The specular band (layer 3) — the gradient with the 0.34/0.50/0.66 stops.
LinearGradient _sheen(WidgetTester tester) => _boxes(tester)
    .map((d) => d.gradient)
    .whereType<LinearGradient>()
    .firstWhere((g) => g.stops?.first == 0.34);

/// The surface's outer rim border (layer 4).
Border _rim(WidgetTester tester) =>
    _boxes(tester).map((d) => d.border).whereType<Border>().first;

BoxDecoration _outerContainerDecoration(WidgetTester tester) => tester
    .widgetList<Container>(find.descendant(
        of: find.byType(HolographicSurface), matching: find.byType(Container)))
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .firstWhere((d) => d.boxShadow != null);

double _dist(Color a, Color b) =>
    (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

void main() {
  testWidgets(
      'dark: the base falls away 22% toward black — a slab, not a flat fill',
      (tester) async {
    await _pumpSurface(tester, AzamanTheme.dark);
    final bottom = _baseGradient(tester).colors.last;
    final expected = Color.lerp(_base, Colors.black, 0.22)!;
    expect(_dist(bottom, expected), lessThan(0.001));
  });

  testWidgets(
      'light: the base keeps its own hierarchy — lit top, soft 6% shade',
      (tester) async {
    await _pumpSurface(tester, AzamanTheme.light);
    final g = _baseGradient(tester);
    final top = g.colors.first;
    final bottom = g.colors.last;
    expect(_dist(top, Color.lerp(_base, Colors.white, 0.14)!), lessThan(0.001));
    expect(
        _dist(bottom, Color.lerp(_base, Colors.black, 0.06)!), lessThan(0.001));
  });

  testWidgets('dark: the rim is a LIT highlight — light catching the edge',
      (tester) async {
    await _pumpSurface(tester, AzamanTheme.dark);
    final top = _rim(tester).top.color;
    expect(top.r, greaterThan(0.9)); // white
    expect(top.a, closeTo(0x33 / 255, 0.01)); // 1.0px at 20% white
  });

  testWidgets(
      'light: the rim is a visible neutral stroke, not invisible white-on-white',
      (tester) async {
    await _pumpSurface(tester, AzamanTheme.light);
    final top = _rim(tester).top.color;
    expect(top.r, lessThan(0.2)); // neutral dark, not a white highlight
    expect(top.a, closeTo(0x14 / 255, 0.01)); // clearly visible
  });

  testWidgets('dark: a figure-plate vignette renders behind the balance',
      (tester) async {
    await _pumpSurface(tester, AzamanTheme.dark);
    final radials = _boxes(tester)
        .map((d) => d.gradient)
        .whereType<RadialGradient>()
        .toList();
    // ceiling light + figure plate.
    expect(radials.length, 2);
    expect(radials.any((g) => g.colors.first == Colors.black.withValues(alpha: 0.14)),
        isTrue);
  });

  testWidgets('light: no figure plate — a dark vignette on white reads as a '
      'stain', (tester) async {
    await _pumpSurface(tester, AzamanTheme.light);
    final radials = _boxes(tester)
        .map((d) => d.gradient)
        .whereType<RadialGradient>()
        .toList();
    // Ceiling light only.
    expect(radials.length, 1);
    expect(radials.single.colors.first.r, greaterThan(0.9)); // white light
  });

  testWidgets('dark: the specular band runs at full sheenPeak', (tester) async {
    await _pumpSurface(tester, AzamanTheme.dark);
    final peak = _sheen(tester).colors[1];
    expect(peak.a, closeTo(0.18, 0.001)); // sheenPeak 0.18 × gate 1.0
  });

  testWidgets('light: the iridescence gate damps the band to 55%',
      (tester) async {
    await _pumpSurface(tester, AzamanTheme.light);
    final peak = _sheen(tester).colors[1];
    expect(peak.a, closeTo(0.18 * 0.55, 0.001));
  });

  testWidgets('light: the hero gains a tight contact shadow so it does not '
      'float on white', (tester) async {
    await _pumpSurface(tester, AzamanTheme.light);
    final shadows = _outerContainerDecoration(tester).boxShadow!;
    // Level-3 recipe (2) + the light-mode contact shadow.
    expect(shadows.length, 3);
    expect(shadows.last.blurRadius, 2);
    expect(shadows.last.offset, const Offset(0, 1));
  });

  testWidgets('dark: keeps the unmodified level-3 shadow recipe', (tester) async {
    await _pumpSurface(tester, AzamanTheme.dark);
    final shadows = _outerContainerDecoration(tester).boxShadow!;
    expect(shadows.length, 2);
  });
}
