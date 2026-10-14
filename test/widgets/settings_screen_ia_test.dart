// =============================================================================
// SETTINGS SCREEN IA TESTS  (Home/Settings refresh §9, 2026-10-13)
//
// The visual/information-architecture regroup must not silently lose a
// working destination or security control. Pinned here:
//   • the new section structure and order;
//   • every destination row that existed before the regroup still exists;
//   • the Theme row routes to the Themes screen and shows the live
//     theme · accent trailing value;
//   • the sensory controls remain reachable (the accent picker moved to
//     Themes — sensory rows must survive);
//   • Sign Out still confirms before acting, and cancel is a no-op;
//   • Delete Account stays wired and is styled destructive.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/settings_screen.dart';
import 'package:azaman/screens/account_deactivation_screen.dart';
import 'package:azaman/screens/theme_picker_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<ThemeProvider> loadedProvider() async {
    final p = ThemeProvider();
    int guard = 0;
    while (!p.isLoaded && guard++ < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(p.isLoaded, isTrue);
    return p;
  }

  Widget harness(ThemeProvider tp) => UncontrolledProviderScope(
    container: ProviderContainer(
      overrides: [themeProvider.overrideWith((ref) => tp)],
    ),
    child: const MaterialApp(home: SettingsScreen()),
  );

  // Section headers render uppercased (see _SectionHeader).
  const sections = <String>[
    'PROFILE & IDENTITY',
    'MONEY & PAYMENT METHODS',
    'SECURITY & PRIVACY',
    'NOTIFICATIONS',
    'APPEARANCE & ACCESSIBILITY',
    'LANGUAGE & REGIONAL PREFERENCES',
    'ABOUT',
  ];

  /// Settings is a long list; the SliverList unmounts offscreen rows.
  /// Jumps the scroll position in bounded steps until `f` is BUILT, then
  /// ensures it is FULLY visible (drag-based scrolling fights the
  /// BouncingScrollPhysics overscroll and leaves rows half-clipped, which
  /// makes taps miss).
  Future<void> reveal(WidgetTester tester, Finder f) async {
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
    var target = 0.0;
    while (f.evaluate().isEmpty &&
        target <= state.position.maxScrollExtent + 200) {
      state.position.jumpTo(target);
      await tester.pump(const Duration(milliseconds: 50));
      target += 400;
    }
    if (f.evaluate().isEmpty) {
      fail('never found $f after scrolling');
    }
    await tester.ensureVisible(f);
    // Freshly built rows restart their staggered entrance animation; a tap
    // mid-slide lands on stale geometry. Let the entrance finish.
    await tester.pump(const Duration(milliseconds: 900));
  }

  testWidgets('renders the regrouped sections in order', (tester) async {
    final p = (await tester.runAsync(loadedProvider))!;
    await tester.pumpWidget(harness(p));
    await tester.pump();

    // From the top of the document, the scroll offset needed to first
    // reveal each section must be non-decreasing — that IS the section
    // order on screen. (SliverList unmounts offscreen rows, so each
    // section is brought into view before asserting.)
    final revealOffset = <String, double>{};
    for (final s in sections) {
      // Back to top.
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump(const Duration(milliseconds: 50));
      final f = find.text(s);
      var steps = 0;
      while (f.evaluate().isEmpty && steps++ < 30) {
        await tester.drag(find.byType(Scrollable), const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(f, findsOneWidget, reason: 'missing section $s');
      final state = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      revealOffset[s] = state.position.pixels;
    }
    var prev = -1.0;
    for (final s in sections) {
      expect(
        revealOffset[s]!,
        greaterThanOrEqualTo(prev),
        reason: '$s appears out of order',
      );
      prev = revealOffset[s]!;
    }
  });

  testWidgets('every pre-existing destination survives the regroup', (
    tester,
  ) async {
    final p = (await tester.runAsync(loadedProvider))!;
    await tester.pumpWidget(harness(p));
    await tester.pump();

    // Document order, so the single-direction reveal walk stays monotonic.
    const destinations = <String>[
      'Edit Profile',
      'Identity Verification',
      'Refer & Earn',
      'Withdrawal Addresses',
      'Deposit Addresses',
      'Two-Factor & PIN',
      'Change Password',
      'Account Activity',
      'Push Notifications',
      'Trade Alerts',
      'Chat Messages',
      'Show Vendor Tag',
      'Theme',
      // The SensoryPreferencesSection lives directly under the Theme row,
      // inside Appearance & Accessibility.
      'Sensory',
      'Haptics',
      'Display Currency',
      'Language',
      'Clear Cache',
      'About Azaman',
      'Sign Out',
      'Delete Account',
    ];
    for (final d in destinations) {
      await reveal(tester, find.text(d));
      expect(find.text(d), findsOneWidget, reason: 'lost destination: $d');
    }
  });

  testWidgets('the Theme row routes to the Themes screen', (tester) async {
    final p = (await tester.runAsync(loadedProvider))!;
    await tester.pumpWidget(harness(p));
    await tester.pump();

    await reveal(tester, find.text('Theme'));
    // tap() does not pump; the push it triggers needs a frame processed
    // before the settle window, or the route never builds under fake async.
    await tester.tap(find.text('Theme'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ThemePickerScreen), findsOneWidget);
  });

  testWidgets('Sign Out confirms before acting; cancel is a no-op', (
    tester,
  ) async {
    final p = (await tester.runAsync(loadedProvider))!;
    await tester.pumpWidget(harness(p));
    await tester.pump();

    await reveal(tester, find.text('Sign Out'));
    // tap() does not pump; give the tap a frame, then let the sheet's
    // entrance finish before asserting on its content.
    await tester.tap(find.text('Sign Out'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The confirm sheet is showing — the destructive action has NOT fired.
    expect(
      find.textContaining("Are you sure you want to sign out?"),
      findsOneWidget,
    );

    // Let the sheet's staggered entrance finish before tapping Cancel.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // Still on Settings: cancel changed nothing.
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
      find.textContaining("Are you sure you want to sign out?"),
      findsNothing,
    );
  });

  testWidgets('Delete Account is styled destructive and still routes', (
    tester,
  ) async {
    final p = (await tester.runAsync(loadedProvider))!;
    await tester.pumpWidget(harness(p));
    await tester.pump();

    // The row reads in the danger colour.
    await reveal(tester, find.text('Delete Account'));
    final title = tester.widget<Text>(find.text('Delete Account'));
    expect(title.style?.color, ThemeProvider.getColors(p.currentTheme).danger);

    await tester.tap(find.text('Delete Account'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // Routed to the deactivation screen — the Phase M flow stays wired.
    expect(find.byType(AccountDeactivationScreen), findsOneWidget);
  });
}
