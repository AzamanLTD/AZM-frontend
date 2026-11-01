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
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/settings_screen.dart';
import 'package:azaman/screens/profile_screen.dart';
import 'package:azaman/screens/support_screen.dart';
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

  User testUser() => User(
    id: 'u1',
    username: 'kofi',
    email: 'kofi@example.com',
    token: 't',
    role: 'USER',
    azamanId: 'AZM-8273941',
    kycStatus: KycStatus.verified,
  );

  Widget harness(ThemeProvider tp, {User? user}) => UncontrolledProviderScope(
    container: ProviderContainer(
      overrides: [
        themeProvider.overrideWith((ref) => tp),
        // The redesign reads identity (AZM ID + KYC chip) from the
        // auth stream — stub it so no network work runs under test.
        currentUserProvider.overrideWith((ref) => Stream.value(user)),
      ],
    ),
    child: const MaterialApp(home: SettingsScreen()),
  );

  // The redesign renders sentence-case headers (see _SectionHeader).
  const sections = <String>[
    'Account',
    'Money',
    'Notifications',
    'Appearance',
    'Preferences',
    'Security',
    'Support',
    'About',
  ];

  /// Settings is a long list; the SliverList unmounts offscreen rows.
  /// Jumps the scroll position in bounded steps until `f` is BUILT, then
  /// ensures it is FULLY visible (drag-based scrolling fights the
  /// BouncingScrollPhysics overscroll and leaves rows half-clipped, which
  /// makes taps miss).
  Future<void> reveal(WidgetTester tester, Finder f) async {
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
    var target = 0.0;
    while (f.evaluate().isEmpty && target < state.position.maxScrollExtent) {
      // Clamp each step to the extent — short pages (fewer rows) must
      // still reach their bottom instead of skipping past the cap.
      state.position.jumpTo(math.min(target, state.position.maxScrollExtent));
      await tester.pump(const Duration(milliseconds: 50));
      target += 400;
    }
    if (f.evaluate().isEmpty && state.position.maxScrollExtent > 0) {
      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 50));
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
    await tester.pumpWidget(harness(p, user: testUser()));
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
    await tester.pumpWidget(harness(p, user: testUser()));
    await tester.pump();

    // Document order, so the single-direction reveal walk stays monotonic.
    const destinations = <String>[
      // Account header card + Account group.
      '@kofi',
      'AZM-8273941',
      'Edit Profile',
      'Identity Verification',
      'Verified',
      'Refer & Earn',
      // Money group — the ONE Accounts entry (mockup contract).
      'Accounts',
      // Notifications group.
      'Push Notifications',
      'Trade Alerts',
      'Chat Messages',
      'Vendor tools',
      // Appearance group.
      'Theme',
      // SensoryPreferencesSection sits under the Theme row, retitled.
      'Motion & feedback',
      'Haptics',
      // Preferences group.
      'Display Currency',
      'Language',
      // Security group.
      'Security & PIN',
      'Change Password',
      'Account Activity',
      // Support group.
      'Help & FAQ',
      // About group.
      'About Azaman',
      'Version',
      'Clear Cache',
      // Danger zone.
      'Sign Out',
      'Delete Account',
    ];
    for (final d in destinations) {
      await reveal(tester, find.text(d));
      expect(find.text(d), findsOneWidget, reason: 'lost destination: $d');
    }
  });

  testWidgets('the account header card routes to the edit flow', (
    tester,
  ) async {
    final p = (await tester.runAsync(loadedProvider))!;
    await tester.pumpWidget(harness(p, user: testUser()));
    await tester.pump();

    // The identity moment: @username + AZM ID chip open the page.
    expect(find.text('@kofi'), findsOneWidget);
    expect(find.text('AZM-8273941'), findsOneWidget);

    await tester.tap(find.text('@kofi'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('the Two-Factor chip reads the REAL biometric store', (
    tester,
  ) async {
    // Enabled → the chip says so.
    SharedPreferences.setMockInitialValues({'biometric_lock_enabled': true});
    final p = (await tester.runAsync(loadedProvider))!;
    await tester.pumpWidget(harness(p, user: testUser()));
    await tester.pump(const Duration(milliseconds: 300));

    await reveal(tester, find.text('Security & PIN'));
    expect(find.text('Biometrics on'), findsOneWidget);
  });

  testWidgets('the security chip never claims 2FA status', (tester) async {
    // Biometrics OFF: the row renders with NO chip — 'PIN only' would be a
    // fake two-factor claim (a biometric preference is not 2FA, and the
    // app reads no authoritative user 2FA status).
    SharedPreferences.setMockInitialValues({'biometric_lock_enabled': false});
    final p = (await tester.runAsync(loadedProvider))!;
    await tester.pumpWidget(harness(p, user: testUser()));
    await tester.pump(const Duration(milliseconds: 300));

    await reveal(tester, find.text('Security & PIN'));
    expect(find.text('Biometrics on'), findsNothing);
    expect(find.text('PIN only'), findsNothing);
  });

  testWidgets('the Language row shows the supported truth — English only', (
    tester,
  ) async {
    // The app has NO localization layer: the row must not open a picker
    // that persists a preference the locale never follows.
    final p = (await tester.runAsync(loadedProvider))!;
    await tester.pumpWidget(harness(p, user: testUser()));
    await tester.pump();

    await reveal(tester, find.text('Language'));
    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.text('Language'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('French'),
      findsNothing,
      reason: 'no locale picker may render',
    );
    expect(find.text('Twi'), findsNothing);
  });

  testWidgets('Clear Cache performs a REAL clear and reports the truth', (
    tester,
  ) async {
    final p = (await tester.runAsync(loadedProvider))!;
    await tester.pumpWidget(harness(p, user: testUser()));
    await tester.pump();

    await reveal(tester, find.text('Clear Cache'));
    await tester.tap(find.text('Clear Cache'));
    await tester.pump();

    // The honest result of a REAL image-cache clear (empty cache → the
    // neutral truth). The fabricated '42 MB freed' must never render.
    expect(find.text('Cache is already empty.'), findsOneWidget);
    expect(find.textContaining('MB freed'), findsNothing);
  });

  testWidgets('the Edit Profile row opens the GENUINE editor', (tester) async {
    final p = (await tester.runAsync(loadedProvider))!;
    await tester.pumpWidget(harness(p, user: testUser()));
    await tester.pump();

    // "Edit Profile" must deliver an editing experience — ProfileScreen
    // (name, photo, bio, phone with save). The read-only KYC identity
    // view (ProfileDetailsScreen) must never answer to "Edit Profile".
    await reveal(tester, find.text('Edit Profile'));
    await tester.tap(find.text('Edit Profile'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('the Help & FAQ row routes to the Support screen', (
    tester,
  ) async {
    final p = (await tester.runAsync(loadedProvider))!;
    await tester.pumpWidget(harness(p, user: testUser()));
    await tester.pump();

    await reveal(tester, find.text('Help & FAQ'));
    await tester.tap(find.text('Help & FAQ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SupportScreen), findsOneWidget);
  });

  testWidgets('the Theme row routes to the Themes screen', (tester) async {
    final p = (await tester.runAsync(loadedProvider))!;
    await tester.pumpWidget(harness(p, user: testUser()));
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
    await tester.pumpWidget(harness(p, user: testUser()));
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
    await tester.pumpWidget(harness(p, user: testUser()));
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
