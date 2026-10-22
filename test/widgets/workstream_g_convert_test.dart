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
import 'package:azaman/widgets/pull_down_dismissible_surface.dart';
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
      'live estimate DISCLOSES the rate source and observation age from '
      'lastExternalSync — never client fetchedAt',
      (tester) async {
        // fetchedAt is NOW; the external observation is 5s old. The
        // disclosure must report the OBSERVATION age (5s), proving it
        // never substitutes fetchedAt (0s).
        final snap = _usableSnapshot();
        expect(snap.lastExternalSync!.isBefore(snap.fetchedAt), isTrue);
        await tester.pumpWidget(_convertHarness(snapshot: snap));
        await tester.pumpAndSettle();

        final disclosure = tester.widget<Text>(
            find.byKey(const Key('convert_estimate_source_disclosure')));
        expect(disclosure.data, contains(snap.source),
            reason: 'the rate source must be visible next to the rate');
        expect(disclosure.data, contains('5s ago'),
            reason: 'freshness derives from the server market '
                'observation, not from when this client fetched it');
        expect(disclosure.data, contains('300s'),
            reason: 'the freshness window must be disclosed');
      },
    );

    testWidgets(
      'STALE observation (past the freshness window) renders the honest '
      'unavailable state WITH the stale reason',
      (tester) async {
        final snap = _usableSnapshot().copyWith(
          lastExternalSync:
              DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
        );
        await tester.pumpWidget(_convertHarness(snapshot: snap));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('convert_estimate_live')), findsNothing,
            reason: 'a stale rate must never render a numeric estimate');
        final reason = tester.widget<Text>(find
            .byKey(const Key('convert_estimate_unavailable_reason')))
            .data!;
        expect(reason, contains('older than'),
            reason: 'staleness is disclosed, not hidden behind a generic '
                'unavailable');
        expect(reason, contains('300s'));
      },
    );

    testWidgets(
      'MISSING observation time (no lastExternalSync) discloses the '
      'missing-metadata reason',
      (tester) async {
        final snap = _usableSnapshot().copyWith(lastExternalSync: null);
        await tester.pumpWidget(_convertHarness(snapshot: snap));
        await tester.pumpAndSettle();

        final reason = tester.widget<Text>(find
            .byKey(const Key('convert_estimate_unavailable_reason')))
            .data!;
        expect(reason, contains('observation time is missing'),
            reason: 'missing metadata is disclosed honestly');
      },
    );

    testWidgets(
      'CONTRADICTORY server age vs ours discloses the contradiction reason',
      (tester) async {
        final snap = _usableSnapshot().copyWith(externalRateAgeSeconds: 4000);
        await tester.pumpWidget(_convertHarness(snapshot: snap));
        await tester.pumpAndSettle();

        final reason = tester.widget<Text>(find
            .byKey(const Key('convert_estimate_unavailable_reason')))
            .data!;
        expect(reason, contains('contradicts'),
            reason: 'contradictory metadata is disclosed honestly');
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
      '§6 amount entry computes a live estimate at the displayed rate — '
      'and none without one',
      (tester) async {
        await tester.pumpWidget(_convertHarness(snapshot: _usableSnapshot()));
        await tester.pumpAndSettle();

        // The amount panel is real entry, not a static display.
        final field = find.byKey(const Key('convert_amount_field'));
        expect(field, findsOneWidget);
        expect(find.byKey(const Key('convert_amount_estimate')), findsNothing,
            reason: 'no estimate before an amount is entered');

        await tester.enterText(field, '2');
        await tester.pump();

        expect(find.text('≈ GH₵ 25.00 GHS'), findsOneWidget,
            reason: '2 USDC at the displayed 12.50 rate');
        expect(
            find.byKey(const Key('convert_amount_estimate')), findsOneWidget);
        expect(
            find
                .byKey(const Key('convert_amount_estimate_disclaimer'))
                .evaluate()
                .isNotEmpty,
            isTrue,
            reason: 'the computed estimate is labeled nonbinding');

        // Fresh entry resets cleanly.
        await tester.enterText(field, '0');
        await tester.pump();
        expect(find.byKey(const Key('convert_amount_estimate')), findsNothing,
            reason: 'a zero amount renders no estimate');
      },
    );

    testWidgets(
      '§6 no usable rate → no fabricated estimate from amount entry',
      (tester) async {
        await tester.pumpWidget(_convertHarness(snapshot: null));
        await tester.pumpAndSettle();

        final field = find.byKey(const Key('convert_amount_field'));
        expect(field, findsOneWidget);
        await tester.enterText(field, '5');
        await tester.pump();

        expect(find.byKey(const Key('convert_amount_estimate')), findsNothing,
            reason: 'arithmetic on an unusable rate would be a fabricated '
                'number');
        expect(
          tester
              .widget<Text>(
                  find.byKey(const Key('convert_amount_estimate_pending')))
              .data!
              .contains('usable rate'),
          isTrue,
        );
      },
    );

    testWidgets(
      '§6 Convert is a pull-down-dismissible transient surface',
      (tester) async {
        await tester.pumpWidget(_convertHarness(snapshot: _usableSnapshot()));
        await tester.pumpAndSettle();

        expect(find.byType(PullDownDismissibleSurface), findsOneWidget,
            reason: 'the screen must be dismissible the same way as '
                'Receive, per the §6 review');
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

    testWidgets(
      'FRESHNESS EDGE — a usable estimate EXPIRES HONESTLY while the '
      'screen stays open',
      (tester) async {
        // Tight window: the observation was made 5s ago and is only
        // considered fresh for 6s — it lapses ~1s after the screen has
        // fully rendered and is sitting idle.
        final snap = FxRateSnapshot(
          ghsPerUsdc: 12.5,
          source: 'kotani-retail',
          lastSync: DateTime.now().toUtc(),
          fetchedAt: DateTime.now().toUtc(),
          serverFresh: true,
          lastExternalSync:
              DateTime.now().toUtc().subtract(const Duration(seconds: 5)),
          externalRateAgeSeconds: 5,
          rateFreshnessMaxAgeSeconds: 6,
        );

        // The screen's freshness verdicts derive from kConvertNow, so
        // the test OWNS the wall clock: the observation ages only when
        // this test advances it, exactly as the device clock would.
        var now = DateTime.now().toUtc();
        final realNow = kConvertNow;
        addTearDown(() => kConvertNow = realNow);
        kConvertNow = () => now;

        await tester.pumpWidget(_convertHarness(snapshot: snap));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump();
        expect(find.byKey(const Key('convert_estimate_live')), findsOneWidget,
            reason: 'the estimate is live while the observation is fresh');

        // The screen stays open with no interaction. 1.3s passes: the
        // clock advances past the 6s window and the one-shot staleness
        // re-check fires (fake timers advance with the pump). The clock
        // moves FIRST so the rebuild the timer triggers already sees
        // the expired observation.
        now = now.add(const Duration(milliseconds: 1300));
        await tester.pump(const Duration(milliseconds: 1300));
        await tester.pump();

        // The panel stops LOOKING fresh at the moment the observation
        // expires — the honest unavailable state with the real reason,
        // never a stale number dressed up as a live estimate.
        expect(find.byKey(const Key('convert_estimate_live')), findsNothing);
        expect(
            find.byKey(const Key('convert_estimate_unavailable')),
            findsOneWidget);
        expect(
          find.byKey(const Key('convert_estimate_unavailable_reason')).last,
          isNotNull,
        );
        final reason = tester
            .widget<Text>(
                find.byKey(const Key('convert_estimate_unavailable_reason')))
            .data!;
        expect(reason, contains('older than the 6s freshness window'),
            reason: 'the disclosed reason names the lapsed window');
      },
    );

    testWidgets(
      'SERVER-AGE EDGE — a consistent observation stays consistent past '
      'the contradiction tolerance while inside its window',
      (tester) async {
        // The server reported the observation age (5s) at fetch time and
        // our own clock agrees: everything is coherent at receipt.
        var now = DateTime.now().toUtc();
        final realNow = kConvertNow;
        addTearDown(() => kConvertNow = realNow);
        kConvertNow = () => now;

        final fetchedAt = now;
        final snap = FxRateSnapshot(
          ghsPerUsdc: 12.5,
          source: 'kotani-retail',
          lastSync: fetchedAt,
          fetchedAt: fetchedAt,
          serverFresh: true,
          lastExternalSync: fetchedAt.subtract(const Duration(seconds: 5)),
          externalRateAgeSeconds: 5,
          rateFreshnessMaxAgeSeconds: 300,
        );

        // MODEL: usable at receipt...
        expect(snap.isUsableAt(now), isTrue);
        // ...and STILL usable 60s later — well past the 30s
        // contradiction tolerance, far inside the 300s window. The
        // server's reported age is a POINT-IN-TIME observation: it
        // ages in lockstep with our own age, so the discrepancy stays
        // constant instead of turning false merely because time
        // passes.
        expect(
          snap.isUsableAt(now.add(const Duration(seconds: 60))),
          isTrue,
          reason: 'a consistent-at-receipt snapshot must not become '
              '"contradictory" after the tolerance elapses',
        );
        // A GENUINELY contradictory reported age is still rejected.
        final contradictory = snap.copyWith(externalRateAgeSeconds: 60);
        expect(contradictory.isUsableAt(now), isFalse);

        // SCREEN: the panel agrees with the model for the whole window.
        await tester.pumpWidget(_convertHarness(snapshot: snap));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump();
        expect(
            find.byKey(const Key('convert_estimate_live')), findsOneWidget);

        // 60s pass with the screen open; a rebuild happens (typing in
        // the amount field). Display and isUsableAt may not diverge:
        // the estimate is still honestly live.
        now = now.add(const Duration(seconds: 60));
        await tester.enterText(find.byType(TextField).first, '5');
        await tester.pump();
        expect(
          find.byKey(const Key('convert_estimate_live')),
          findsOneWidget,
          reason: 'past the contradiction tolerance but inside the '
              'window, the panel must still read fresh — the verdict '
              'and the display may not disagree',
        );
        expect(
          snap.isUsableAt(now),
          isTrue,
          reason: 'and the model agrees with what the screen shows',
        );
      },
    );

    test(
      'staleAt preserves fractional precision on either side of a '
      'half-second boundary',
      () {
        final sync = DateTime.now().toUtc();
        FxRateSnapshot withWindow(double window) => FxRateSnapshot(
              ghsPerUsdc: 12.5,
              source: 'kotani-retail',
              lastSync: sync,
              fetchedAt: sync,
              serverFresh: true,
              lastExternalSync: sync,
              externalRateAgeSeconds: 0,
              rateFreshnessMaxAgeSeconds: window,
            );

        // 6.4s rounds DOWN to 6 with a whole-second Duration — the old
        // defect let the timer fire while the snapshot was still usable.
        expect(
          withWindow(6.4).staleAt!.difference(sync).inMilliseconds,
          6400,
          reason: 'a 6.4s window expires at exactly 6.4s',
        );
        // 6.6s rounds UP to 7 — the old defect delayed the honest flip.
        expect(
          withWindow(6.6).staleAt!.difference(sync).inMilliseconds,
          6600,
          reason: 'a 6.6s window expires at exactly 6.6s',
        );
        // isUsableAt compares against the exact double on both sides
        // of the boundary, and staleAt must agree with it exactly.
        expect(withWindow(6.4).isUsableAt(
            sync.add(const Duration(milliseconds: 6399))), isTrue);
        expect(withWindow(6.4).isUsableAt(
            sync.add(const Duration(milliseconds: 6401))), isFalse);
        expect(withWindow(6.6).isUsableAt(
            sync.add(const Duration(milliseconds: 6599))), isTrue);
        expect(withWindow(6.6).isUsableAt(
            sync.add(const Duration(milliseconds: 6601))), isFalse);
      },
    );

    testWidgets(
      'FRACTIONAL WINDOW — the staleness re-check fires at the exact '
      'expiry, neither early (re-arming churn) nor late',
      (tester) async {
        // Observation made 5s ago with a 6.6s window: whole-second
        // rounding would arm the timer at 7s, delaying the honest flip
        // 0.4s PAST the true expiry. The fix arms at 6.6s + slack.
        var now = DateTime.now().toUtc();
        final realNow = kConvertNow;
        addTearDown(() => kConvertNow = realNow);
        kConvertNow = () => now;

        final fetchedAt = now;
        final snap = FxRateSnapshot(
          ghsPerUsdc: 12.5,
          source: 'kotani-retail',
          lastSync: fetchedAt,
          fetchedAt: fetchedAt,
          serverFresh: true,
          lastExternalSync: fetchedAt.subtract(const Duration(seconds: 5)),
          externalRateAgeSeconds: 5,
          rateFreshnessMaxAgeSeconds: 6.6,
        );

        await tester.pumpWidget(_convertHarness(snapshot: snap));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump();
        expect(
            find.byKey(const Key('convert_estimate_live')), findsOneWidget);

        // The observation expires 1.6s from now; the one-shot timer
        // was armed at staleAt + 50ms scheduling slack. Advance past
        // it: the panel flips to unavailable ON TIME.
        now = now.add(const Duration(milliseconds: 1700));
        await tester.pump(const Duration(milliseconds: 1700));
        await tester.pump();
        expect(
            find.byKey(const Key('convert_estimate_live')), findsNothing);
        expect(find.byKey(const Key('convert_estimate_unavailable')),
            findsOneWidget);
        final reason = tester
            .widget<Text>(
                find.byKey(const Key('convert_estimate_unavailable_reason')))
            .data!;
        expect(reason, contains('older than the 6.6s freshness window'),
            reason: 'the disclosed window preserves its fractional '
                'precision — never a rounded 7s');

        // No zero-delay re-arm churn after the flip: the panel STAYS
        // unavailable across subsequent frames.
        for (var i = 0; i < 5; i++) {
          now = now.add(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(const Key('convert_estimate_live')), findsNothing);
        expect(find.byKey(const Key('convert_estimate_unavailable')),
            findsOneWidget);
      },
    );

    testWidgets(
      'TIMER DISPOSAL — popping the screen with a pending expiry timer '
      'triggers no post-dispose update or error',
      (tester) async {
        // A tight window arms the one-shot staleness re-check: the
        // timer is pending from the moment the estimate renders.
        var now = DateTime.now().toUtc();
        final realNow = kConvertNow;
        addTearDown(() => kConvertNow = realNow);
        kConvertNow = () => now;

        final fetchedAt = now;
        final snap = FxRateSnapshot(
          ghsPerUsdc: 12.5,
          source: 'kotani-retail',
          lastSync: fetchedAt,
          fetchedAt: fetchedAt,
          serverFresh: true,
          lastExternalSync: fetchedAt.subtract(const Duration(seconds: 5)),
          externalRateAgeSeconds: 5,
          rateFreshnessMaxAgeSeconds: 6,
        );

        await tester.pumpWidget(_convertHarness(snapshot: snap));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump();
        expect(find.byKey(const Key('convert_estimate_live')), findsOneWidget,
            reason: 'the estimate renders — the expiry timer is pending');

        // The screen is popped with the timer still armed...
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        // ...and the clock runs far past the armed expiry.
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'the disposed staleness timer must be cancelled — '
                'never a post-dispose setState or framework error');
        expect(find.byKey(const Key('convert_estimate_live')), findsNothing);
      },
    );

    testWidgets(
      'CLOCK-SKEW EDGE — a tolerated future observation is disclosed as '
      "'just now', never a negative age",
      (tester) async {
        // The observation timestamp sits 2s in the FUTURE — inside the
        // model's 5s clock-skew allowance, so the rate is usable.
        final snap = FxRateSnapshot(
          ghsPerUsdc: 12.5,
          source: 'kotani-retail',
          lastSync: DateTime.now().toUtc(),
          fetchedAt: DateTime.now().toUtc(),
          serverFresh: true,
          lastExternalSync:
              DateTime.now().toUtc().add(const Duration(seconds: 2)),
          externalRateAgeSeconds: 0,
          rateFreshnessMaxAgeSeconds: 300,
        );

        await tester.pumpWidget(_convertHarness(snapshot: snap));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump();

        expect(find.byKey(const Key('convert_estimate_live')), findsOneWidget);
        final disclosure = tester
            .widget<Text>(
                find.byKey(const Key('convert_estimate_source_disclosure')))
            .data!;
        expect(disclosure, contains('just now'),
            reason: 'a tolerated future observation reads as fresh, never '
                'as a negative age');
        expect(RegExp(r'-\d+s? ago| -').hasMatch(disclosure), isFalse,
            reason: 'no negative "seconds ago" may appear anywhere');
      },
    );
  });
}
