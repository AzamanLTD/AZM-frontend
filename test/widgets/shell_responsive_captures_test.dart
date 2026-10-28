// =============================================================================
// PR-B CLOSEOUT — SHELL RESPONSIVE + REDUCED-MOTION CAPTURES
//
// The promised responsive evidence for the shell swipe workstream: the
// REAL MainWrapper (Home tab, initial state) rasterised at the three
// supported content widths (320/360/390dp) in BOTH themes, plus the
// reduced-motion variants at 360dp. The captures pin:
//
//   * the shell body ShellSwipeDetector wiring (the shell's own page
//     stack — NOT a PageView — so PR-B's layout contract is the thing
//     captured);
//   * the bottom nav pill's responsive fit at each width;
//   * the home surface's responsive arrangement at each width;
//   * the reduced-motion rest state (entrance one-shots completed).
//
// Every capture goes through [pumpShell] so the five flakiness sources
// are pinned in one place (the same list the golden harness documents,
// test/goldens/golden_harness.dart): surface size, DPR, animations,
// typography and (externally) the pinned engine in CI.
//
// Rule: goldens are added deliberately, never regenerated to make a
// suite green. `--update-goldens` on this suite is reserved for a
// deliberate, reviewable rebaseline.
// =============================================================================

import 'dart:io';
import 'dart:typed_data' show ByteData, Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/main.dart' show MainWrapper;
import 'package:azaman/providers/auth_provider.dart' as auth_pkg;
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/screens/home_screen.dart' show AzamanHomePage;

/// Pinned device pixel ratio for every capture (matches the golden
/// harness's kGoldenPixelRatio).
const double _dpr = 3.0;

/// One-off first-mount UX that would otherwise sit mid-animation in the
/// capture; NOT part of the shell's layout contract.
const Map<String, Object> _seededPrefs = {
  'has_seen_flippable_card_hint': true,
  'has_seen_drawer_peek_hint': true,
};

bool _fontsLoaded = false;

Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final bytes = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final loader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  await loader.load();
  _fontsLoaded = true;
}

class _InertSearchNotifier extends BusinessSearchNotifier {
  _InertSearchNotifier() : super(BusinessService());

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    // Recorded, not fired — no network in a capture.
  }
}

/// Pumps the REAL shell at [size] in [theme], with [reducedMotion]
/// switching MediaQuery.disableAnimations (the platform's reduced-motion
/// signal). Returns after the entrance one-shots have completed, at a
/// deterministic fake-clock instant (fixed pumps → identical raster
/// every run, on every machine, under the pinned engine).
Future<void> _pumpShell(
  WidgetTester tester, {
  required Size size,
  required AzamanTheme theme,
  bool reducedMotion = false,
}) async {
  // The theme provider reads the SAVED preference (dark is the missing-key
  // default; light is an explicit choice, see _loadSavedTheme).
  SharedPreferences.setMockInitialValues({
    ..._seededPrefs,
    'azaman_theme': AzamanTheme.values.indexOf(theme),
  });
  await tester.runAsync(_loadFonts);
  tester.view
    ..physicalSize = size * _dpr
    ..devicePixelRatio = _dpr;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      auth_pkg.authProvider.overrideWith((ref) => auth_pkg.AuthProvider()),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 100),
      ),
      oracleRateProvider.overrideWith((ref) => 1.0),
      businessSearchProvider.overrideWith((ref) => _InertSearchNotifier()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeProvider.getThemeData(theme),
        home: RepaintBoundary(
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
            ).copyWith(disableAnimations: reducedMotion),
            child: const MainWrapper(),
          ),
        ),
      ),
    ),
  );
  // Deterministic settle: first frame, entrance one-shots (600ms), then
  // a fixed rest pump so the raster is identical every run.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  const widths = {
    '320': Size(320, 692),
    '360': Size(360, 800),
    '390': Size(390, 844),
  };

  for (final entry in widths.entries) {
    for (final dark in [false, true]) {
      final theme = dark ? AzamanTheme.dark : AzamanTheme.light;
      final mode = dark ? 'dark' : 'light';
      testWidgets('shell ${entry.key} $mode', (tester) async {
        await _pumpShell(tester, size: entry.value, theme: theme);
        // The PR-B wiring itself is part of the evidence: the real home
        // page is mounted (the shell's own page stack, not a PageView).
        expect(find.byType(AzamanHomePage), findsOneWidget);
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('goldens/shell/shell_${entry.key}_$mode.png'),
        );
      });
    }
  }

  // Reduced-motion rest states at the reference width, both themes — the
  // entrance choreography must resolve to the same rest arrangement,
  // never a half-transition frame.
  for (final dark in [false, true]) {
    final theme = dark ? AzamanTheme.dark : AzamanTheme.light;
    final mode = dark ? 'dark' : 'light';
    testWidgets('shell 360 $mode reduced-motion rest state', (tester) async {
      await _pumpShell(
        tester,
        size: const Size(360, 800),
        theme: theme,
        reducedMotion: true,
      );
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('goldens/shell/shell_360_${mode}_rm.png'),
      );
    });
  }
}
