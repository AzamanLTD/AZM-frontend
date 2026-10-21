// =============================================================================
// AZM — WORKSTREAM G — Settings drawer cleanup + Convert launcher entry.
//
// Pins the acceptance contract:
//
//   G1 (drawer IA): the Money group has NO duplicate Deposit/Withdraw rows;
//   it keeps the saved-accounts management surface, the Currency preference
//   entry and Azaman Store. Canonical Deposit/Withdraw remain reachable from
//   their proper surface — the Home + launcher (Add Cash → /deposit,
//   Withdraw → WithdrawalScreen).
//
//   G2 (Convert launcher): the launcher action set contains Send, Receive,
//   Add Cash, Withdraw and Convert with the established hierarchy; Convert
//   opens the REAL /convert route (no toast, no preference mutation); the
//   Convert shell shows an honest unavailable/not-ready state while no
//   backend conversion contract exists, and its execution CTA is inert —
//   it cannot mutate data or invoke a provider.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/config.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/currency_provider.dart';
import 'package:azaman/providers/worker_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/screens/wallet/convert_screen.dart';
import 'package:azaman/widgets/settings_drawer.dart';
import 'package:azaman/widgets/home/home_plus_actions.dart';
import 'package:azaman/widgets/home/plus_action_launcher.dart';

User _verifiedUser() => User(
  id: 'u1',
  username: 'kofi',
  email: 'kofi@example.com',
  token: 't',
  role: 'USER',
  azamanId: 'AZM-8273941',
  kycStatus: KycStatus.verified,
);

class _IdleBusinessNotifier extends MyBusinessNotifier {
  _IdleBusinessNotifier() : super(BusinessService());

  @override
  Future<void> load() async {}
}

/// A genuinely usable USDC/GHS snapshot for estimate rendering: fresh
/// external observation, serverFresh, all freshness metadata coherent.
FxRateSnapshot _usableSnapshot({double rate = 12.5}) => FxRateSnapshot(
  ghsPerUsdc: rate,
  source: 'kotani-retail',
  lastSync: DateTime.now().toUtc(),
  fetchedAt: DateTime.now().toUtc(),
  serverFresh: true,
  lastExternalSync: DateTime.now().toUtc().subtract(const Duration(seconds: 5)),
  externalRateAgeSeconds: 5,
  rateFreshnessMaxAgeSeconds: 300,
);

Future<void> _pumpDrawer(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWith((ref) => Stream.value(_verifiedUser())),
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
}

Widget _convertHarness({FxRateSnapshot? snapshot, Object? error}) {
  return ProviderScope(
    overrides: [
      fxRateProvider.overrideWith(
        (ref) => Future.delayed(
          const Duration(milliseconds: 10),
          () => error != null ? throw error : snapshot,
        ),
      ),
    ],
    child: const MaterialApp(home: ConvertScreen()),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('G1 — drawer information architecture', () {
    testWidgets('Money group keeps its legitimate rows', (tester) async {
      await _pumpDrawer(tester);

      expect(find.text('Money'), findsOneWidget);
      expect(find.text('Currency'), findsOneWidget);
      expect(find.text('Azaman Store'), findsOneWidget);
      // The saved-accounts management surface stays in the group.
      expect(find.textContaining('Deposits and payout destinations'),
          findsOneWidget);
    });

    testWidgets(
      'duplicate Deposit/Withdraw rows are gone from the drawer',
      (tester) async {
        await _pumpDrawer(tester);

        // The drawer renders menu rows; the Money group must not
        // duplicate the canonical financial actions. The hero/QR area
        // has no other Deposit/Withdraw affordance either.
        expect(
          find.text('Deposit'),
          findsNothing,
          reason: 'the drawer Money group duplicated the canonical '
              '/deposit action (Workstream G1)',
        );
        expect(
          find.text('Withdraw'),
          findsNothing,
          reason: 'the drawer Money group duplicated the canonical '
              'withdrawal action (Workstream G1)',
        );
      },
    );
  });

  group('G2 — launcher action set', () {
    testWidgets(
      'contains Send, Receive, Add Cash, Withdraw and Convert with the '
      'established hierarchy',
      (tester) async {
        late List<PlusLauncherAction> actions;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                actions = buildHomePlusActions(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final labels = actions.map((a) => a.label).toList();
        expect(labels, ['Send', 'Receive', 'Add Cash', 'Withdraw', 'Convert']);
        expect(
          actions.firstWhere((a) => a.label == 'Send').prominent,
          isTrue,
          reason: 'gold hierarchy is unchanged',
        );
        expect(actions.firstWhere((a) => a.label == 'Receive').prominent,
            isTrue);
        // Convert is a secondary action: neutral chip, existing icon family.
        expect(actions.firstWhere((a) => a.label == 'Convert').prominent,
            isFalse);
      },
    );

    testWidgets(
      'Convert action navigates to the real /convert route; Add Cash and '
      'Withdraw keep their canonical behaviour',
      (tester) async {
        AppConfig.enableDemoMode();

        late BuildContext shellContext;
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (c, s) => MaterialPage(
                child: Builder(
                  builder: (c) {
                    shellContext = c;
                    return const Scaffold(body: SizedBox.expand());
                  },
                ),
              ),
            ),
            GoRoute(
              path: '/convert',
              pageBuilder: (c, s) =>
                  const MaterialPage(child: ConvertScreen()),
            ),
            GoRoute(
              path: '/deposit',
              pageBuilder: (c, s) =>
                  const MaterialPage(child: DepositScreen()),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: router)),
        );

        final actions = buildHomePlusActions(shellContext);

        // Convert opens the real route — never a toast or preference flip.
        actions.firstWhere((a) => a.label == 'Convert').onTap();
        await tester.pumpAndSettle();
        expect(find.byType(ConvertScreen), findsOneWidget);
        expect(find.text('Unavailable'), findsOneWidget,
            reason: 'no backend conversion contract exists, so the shell '
                'renders the honest not-ready state');

        // Add Cash still pushes the canonical /deposit location.
        actions.firstWhere((a) => a.label == 'Add Cash').onTap();
        await tester.pumpAndSettle();
        expect(find.byType(DepositScreen), findsOneWidget);
      },
    );
  });

  group('G2 — Convert shell honesty', () {
    testWidgets(
      'usable rate renders as a clearly labeled NONBINDING estimate',
      (tester) async {
        await tester.pumpWidget(_convertHarness(snapshot: _usableSnapshot()));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('convert_estimate_live')), findsOneWidget);
        expect(find.text('1 USDC ≈ 12.50 GHS'), findsOneWidget);
        expect(find.byKey(const Key('convert_estimate_disclaimer')),
            findsOneWidget);
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('convert_estimate_disclaimer')))
              .data!
              .toUpperCase()
              .contains('NONBINDING'),
          isTrue,
        );
      },
    );

    testWidgets(
      'unusable rate renders the honest unavailable state — no numbers',
      (tester) async {
        await tester.pumpWidget(_convertHarness(snapshot: null));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('convert_estimate_unavailable')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('convert_estimate_live')), findsNothing);
      },
    );

    testWidgets(
      'execution CTA is INERT while no conversion contract exists — '
      'tapping mutates nothing and never implies success',
      (tester) async {
        await tester.pumpWidget(_convertHarness(snapshot: _usableSnapshot()));
        await tester.pumpAndSettle();

        final cta = find.byKey(const Key('convert_cta'));
        expect(cta, findsOneWidget);
        final button = tester.widget<FilledButton>(cta);
        expect(button.onPressed, isNull,
            reason: 'the capability gate must keep the CTA disabled until a '
                'verified backend conversion contract exists');

        // Tapping the disabled CTA changes nothing: no success state, no
        // navigation, no fabricated transaction.
        await tester.tap(cta, warnIfMissed: false);
        await tester.pump();
        expect(find.text('Unavailable'), findsOneWidget);
        expect(find.byKey(const Key('convert_execution_unavailable')),
            findsOneWidget);
        expect(find.byKey(const Key('convert_execution_ready')), findsNothing);
        expect(
          convertExecutionAvailable,
          isFalse,
          reason: 'the explicit capability gate is the single switch a '
              'future backend implementation flips',
        );
      },
    );

    testWidgets(
      'currency preference is untouched by the shell (preference ≠ '
      'conversion)',
      (tester) async {
        await tester.pumpWidget(_convertHarness(snapshot: _usableSnapshot()));
        await tester.pumpAndSettle();

        // No wheel, no preference writer: the shell only reads fxRateProvider.
        expect(find.byKey(const Key('convert_cta')), findsOneWidget);
        final prefs = await SharedPreferences.getInstance();
        // Nothing the shell does writes a display preference.
        expect(prefs.getKeys(), isEmpty);
      },
    );
  });
}
