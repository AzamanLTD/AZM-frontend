// PR-B — Settings drawer profile hero, QR popup, declutter & regrouping.
//
// Pins the binding acceptance criteria from the refresh spec §5:
//   • real user data renders in the hero with a fallback when absent;
//   • the QR preview + popup encode the `azaman://user/$username` payload
//     that qr_scanner_screen.dart parses (add-friend contract), the popup
//     dismisses back to the SAME drawer state, and the close button works;
//   • the hero opens the genuine profile EDIT flow (ProfileScreen —
//     audited: ProfileDetailsScreen is read-only);
//   • HQ SHORTCUTS / Vaults / Rewards are gone from the drawer while the
//     canonical destinations stay reachable via the regrouped sections;
//   • the pinned hero collapses under scroll and keeps @username + a QR
//     affordance visible in the compact bar.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/providers/worker_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/screens/profile_screen.dart';
import 'package:azaman/widgets/qr_profile_popup.dart';
import 'package:azaman/widgets/settings_drawer.dart';

User _verifiedUser() => User(
  id: 'u1',
  username: 'kofi',
  email: 'kofi@example.com',
  token: 't',
  role: 'USER',
  azamanId: 'AZM-8273941',
  kycStatus: KycStatus.verified,
);

/// Idle stub so the drawer's business-prefetch postFrameCallback never
/// starts network work under test.
class _IdleBusinessNotifier extends MyBusinessNotifier {
  _IdleBusinessNotifier() : super(BusinessService());

  @override
  Future<void> load() async {}
}

Future<ProviderContainer> _pumpDrawer(
  WidgetTester tester, {
  User? user,
  Size surface = const Size(420, 2400),
  bool disableAnimations = false,
}) async {
  // Tall mobile surface so the regrouped sections below the hero are
  // actually laid out by the lazy sliver list.
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWith((ref) => Stream.value(user)),
      myEmployeeProvider.overrideWith((ref) => Future.value(null)),
      myBusinessProvider.overrideWith((ref) => _IdleBusinessNotifier()),
    ],
  );
  addTearDown(container.dispose);

  final scaffoldKey = GlobalKey<ScaffoldState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: container.read(themeProvider).themeData,
        home: Builder(
          // Scoped above the Scaffold; copies the REAL MediaQuery so only
          // the reduced-motion flag is overridden (a bare MediaQueryData
          // has Size.zero and silently broke the drawer).
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: Scaffold(
              key: scaffoldKey,
              endDrawer: const SettingsDrawer(),
              body: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
  scaffoldKey.currentState!.openEndDrawer();
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() {
    // ThemeProvider reads SharedPreferences in its constructor.
    SharedPreferences.setMockInitialValues({});
  });

  group('qr payload contract', () {
    test('encodes azaman://user/{username} exactly', () {
      expect(qrProfilePayload('kofi'), 'azaman://user/kofi');
    });

    testWidgets('hero thumbnail and popup encode the same payload', (
      tester,
    ) async {
      await _pumpDrawer(tester, user: _verifiedUser());

      final thumb = tester.widget<QrProfileThumbnail>(
        find.byType(QrProfileThumbnail),
      );
      expect(
        thumb.username,
        'kofi',
        reason:
            'payload is derived from the username via '
            'qrProfilePayload, which the contract test pins',
      );

      await tester.tap(find.byKey(const ValueKey('profile_hero_qr')));
      await tester.pumpAndSettle();

      final popup = tester.widget<QrProfilePopup>(find.byType(QrProfilePopup));
      expect(popup.username, 'kofi');
      expect(
        find.byType(QrImageView),
        findsWidgets,
        reason: 'the large popup QR must be present',
      );
      expect(find.text('@kofi'), findsWidgets);
      expect(find.text('Scan to add me on Azaman'), findsOneWidget);
    });

    testWidgets('popup closes back to the same open drawer', (tester) async {
      await _pumpDrawer(tester, user: _verifiedUser());
      await tester.tap(find.byKey(const ValueKey('profile_hero_qr')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Drawer is still mounted and open — the dialog popped only itself.
      expect(find.byType(QrProfilePopup), findsNothing);
      expect(find.byType(SettingsDrawer), findsOneWidget);
      // The hero is still intact behind the closed popup.
      expect(find.text('AZM-8273941'), findsOneWidget);
    });
  });

  group('hero', () {
    testWidgets('renders real user data: @username, Azaman ID, KYC badge', (
      tester,
    ) async {
      await _pumpDrawer(tester, user: _verifiedUser());

      expect(find.text('@kofi'), findsOneWidget);
      expect(find.text('AZM-8273941'), findsOneWidget);
      // Verification reads as the verified mark beside the name.
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(find.byType(QrProfileThumbnail), findsOneWidget);
    });

    testWidgets('falls back gracefully with no user', (tester) async {
      await _pumpDrawer(tester, user: null);

      expect(find.text('@Guest'), findsOneWidget);
      expect(
        find.byType(QrProfileThumbnail),
        findsOneWidget,
        reason: 'QR stays renderable with the placeholder identity',
      );
      // No Azaman ID is shown when there is none: never a placeholder.
      expect(find.byKey(const ValueKey('profile_hero_azm')), findsNothing);
    });

    testWidgets('hero tap opens the genuine profile EDIT flow', (tester) async {
      await _pumpDrawer(tester, user: _verifiedUser());

      // Tap the hero avatar (keyed for testability; semantics label
      // 'Open profile editor' is present for assistive tech).
      final avatar = find.byKey(const ValueKey('profile_hero_avatar'));
      expect(avatar, findsOneWidget);
      await tester.tap(avatar);
      // Fixed-frame pumps: ProfileScreen keeps a progress affordance
      // running while its profile fetch is outstanding (no network under
      // test), so pumpAndSettle would never settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.byType(ProfileScreen),
        findsOneWidget,
        reason:
            'ProfileScreen holds the real edit capability '
            '(photo/name/bio/phone); ProfileDetailsScreen is read-only',
      );
    });
  });

  group('declutter and regrouping', () {
    testWidgets('HQ shortcuts, Vaults and Rewards are gone from the drawer', (
      tester,
    ) async {
      await _pumpDrawer(tester, user: _verifiedUser());

      expect(find.text('HQ SHORTCUTS'), findsNothing);
      expect(find.text('Vaults'), findsNothing);
      expect(find.text('Rewards'), findsNothing);
      expect(find.text('AZM Auction'), findsNothing);
      expect(find.text('Referral Rewards'), findsNothing);
      expect(find.text('Leaderboard'), findsNothing);
      // NOTE: 'Deposit' is no longer asserted absent here — the redesign
      // deliberately reintroduces it as a quick action.
    });

    testWidgets('redesigned rows and real status chips render', (
      tester,
    ) async {
      // The Security chip reads the REAL biometric pref — turn it on so
      // the chip renders; the drawer loads it asynchronously after mount.
      SharedPreferences.setMockInitialValues({'biometric_lock_enabled': true});
      await _pumpDrawer(tester, user: _verifiedUser());
      await tester.pump(const Duration(milliseconds: 120));

      // The X-style drawer has no section labels at all (and the ALL-CAPS
      // enterprise labels stay gone).
      expect(find.text('Account'), findsNothing);
      expect(find.text('Money'), findsNothing);
      expect(find.text('PROFILE & IDENTITY'), findsNothing);
      expect(find.text('MONEY & PAYMENT METHODS'), findsNothing);
      expect(find.text('SECURITY & PRIVACY'), findsNothing);
      expect(find.text('APPEARANCE & PREFERENCES'), findsNothing);
      expect(find.text('AZMAN PROTOCOL V3.0 — THEMED'), findsNothing);

      // WORKSTREAM G1: the quick-action ROW is gone AND the duplicate
      // Withdraw/Deposit Money rows are gone too. Their canonical home
      // is the Home + launcher (pinned by workstream_g_convert_test);
      // Refer & Earn lives in the profile area, QR in the pinned hero.
      expect(find.text('Withdraw'), findsNothing);
      expect(find.text('Deposit'), findsNothing);
      expect(find.text('Refer & Earn'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile_hero_qr')), findsOneWidget);
      // And the removed row leaves no orphan labels behind.
      expect(find.text('QR'), findsNothing);

      // Account group: identity + verification with the REAL KYC state.
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Verification'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);

      // Money group: the ONE Accounts row (deposits + payouts are a
      // single concept — the mockup contract), currency, store.
      expect(find.text('Accounts'), findsOneWidget);
      expect(find.text('Currency'), findsOneWidget);
      expect(find.text('Azaman Store'), findsOneWidget);

      // Security row with the real biometric state chip.
      expect(find.text('Security & PIN'), findsOneWidget);
      expect(find.text('Biometrics on'), findsOneWidget);

      // The gear is gone; the canonical Settings entry is a labelled row.
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.text('All settings'), findsOneWidget);
      expect(find.text('Azaman 3.1'), findsOneWidget);
    });

    testWidgets('G1: no duplicate Deposit row — deposits stay canonical on the '
        'Home + launcher', (tester) async {
      await _pumpDrawer(tester, user: _verifiedUser());

      // The drawer must not duplicate the canonical deposit surface;
      // the launcher's Add Cash action owns it (pinned in
      // workstream_g_convert_test.dart: it pushes the /deposit route
      // whose builder serves the STK-push MoMo screen).
      expect(find.text('Deposit'), findsNothing);
      expect(find.byType(DepositScreen), findsNothing);
    });

    testWidgets('unverified user renders no KYC chip (no decoration)', (
      tester,
    ) async {
      final unverified = _verifiedUser().copyWith(
        kycStatus: KycStatus.unverified,
      );
      await _pumpDrawer(tester, user: unverified);

      expect(find.text('Verification'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
      expect(find.text('Pending'), findsNothing);
    });

    testWidgets('biometrics disabled renders no chip on Security row', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpDrawer(tester, user: _verifiedUser());
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('Security & PIN'), findsOneWidget);
      expect(find.text('Biometrics on'), findsNothing);
    });
  });

  // The 2026-11-27 drawer redesign (X-style) has no pinned, scroll-driven
  // hero: the header scrolls with the list. Its morph tests are retired with
  // it; the reveal mechanics are pinned in reveal_drawer_test.dart.
}
