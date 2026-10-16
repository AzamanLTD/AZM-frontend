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
import 'package:azaman/screens/accounts_screen.dart';
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
        home: Scaffold(
          key: scaffoldKey,
          endDrawer: const SettingsDrawer(),
          body: const SizedBox.expand(),
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
      expect(find.text('VERIFIED'), findsOneWidget);
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
      expect(find.text('AZM-—'), findsOneWidget);
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

    testWidgets('redesigned groups, quick actions and real chips render', (
      tester,
    ) async {
      // The Security chip reads the REAL biometric pref — turn it on so
      // the chip renders; the drawer loads it asynchronously after mount.
      SharedPreferences.setMockInitialValues({
        'biometric_lock_enabled': true,
      });
      await _pumpDrawer(tester, user: _verifiedUser());
      await tester.pump(const Duration(milliseconds: 120));

      // Sentence-case groups (the ALL-CAPS enterprise labels are gone).
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
      expect(find.text('Security'), findsOneWidget);
      expect(find.text('PROFILE & IDENTITY'), findsNothing);
      expect(find.text('MONEY & PAYMENT METHODS'), findsNothing);
      expect(find.text('SECURITY & PRIVACY'), findsNothing);
      expect(find.text('APPEARANCE & PREFERENCES'), findsNothing);
      expect(find.text('AZMAN PROTOCOL V3.0 — THEMED'), findsNothing);

      // Quick actions: the four things the drawer is opened for.
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.text('Deposit'), findsOneWidget);
      expect(find.text('QR'), findsOneWidget);
      expect(find.text('Refer'), findsOneWidget);

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

    testWidgets('the Deposit quick action opens the CANONICAL deposit flow',
        (tester) async {
      await _pumpDrawer(tester, user: _verifiedUser());

      // "Deposit" must deliver deposits — the STK-push MoMo screen the
      // /deposit route serves — not the saved-accounts surface.
      await tester.tap(find.text('Deposit'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(DepositScreen), findsOneWidget);
      expect(find.byType(AccountsScreen), findsNothing);
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

  group('scroll-driven morph', () {
    testWidgets('pinned hero collapses and keeps username + QR visible', (
      tester,
    ) async {
      await _pumpDrawer(
        tester,
        user: _verifiedUser(),
        // The drawer content now fits a tall phone without scrolling, so the
        // collapse contract is exercised on a shorter viewport where the
        // scroll actually happens.
        surface: const Size(420, 650),
      );

      // Expanded: hero content visible.
      expect(find.text('AZM-8273941'), findsOneWidget);

      // Scroll the drawer content up — the pinned header must shrink to
      // its compact bar, not scroll away.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(
        find.text('@kofi'),
        findsOneWidget,
        reason: 'collapsed bar keeps the username visible',
      );
      expect(
        find.byKey(const ValueKey('profile_hero_qr_icon')),
        findsOneWidget,
        reason: 'collapsed bar keeps a QR affordance',
      );

      // Scroll back — expanded hero returns.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('AZM-8273941'), findsOneWidget);
    });
  });
}
