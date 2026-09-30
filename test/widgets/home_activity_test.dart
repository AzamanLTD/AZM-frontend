// NEW-HOME §10-13 — the Recent Activity doorway, the two-resting-state
// handoff, the lazy-load boundary, and typed activity actions.
//
// * the resting Home renders the doorway heading and NO transaction rows
// * pulling the doorway is physical: resisted progress, deliberate
//   threshold, commit snaps the activity surface into focus
// * entering the activity state triggers the fetch (the REAL lazy-load
//   boundary); the resting Home does not fetch to decorate a preview
// * typed actions come from structured rawType metadata, never titles,
//   and unsafe/missing payloads fall back to details
import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/widgets/home/activity_actions.dart';
import 'package:azaman/widgets/home/activity_doorway.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _surfaceSize = Size(400, 900);

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final bytes = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final loader = FontLoader('Inter')
    ..addFont(Future<ByteData>.value(
        ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
  _fontsLoaded = true;
}

/// Records refresh() calls so the lazy-load boundary is assertable. The
/// Home's NEW-D "prime" mount fetch still happens (existing behaviour,
/// preserved); what matters is that the RESTING page fetches nothing
/// EXTRA, and entering the activity state fetches exactly once.
class _RecordingHomeSummaryNotifier extends HomeSummaryNotifier {
  _RecordingHomeSummaryNotifier(Ref ref, HomeSummaryService service)
      : super(ref, service);

  int refreshCalls = 0;

  @override
  Future<void> refresh() async {
    refreshCalls++;
    state = state.copyWith(loading: false);
  }
}

Future<(_RecordingHomeSummaryNotifier, ProviderContainer)> _pumpHome(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues(
      {'has_seen_flippable_card_hint': true});
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(_surfaceSize);

  _RecordingHomeSummaryNotifier? notifier;
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
          (ref) => const BalanceData(availableBalance: 100)),
      oracleRateProvider.overrideWith((ref) => 1.0),
      homeSummaryProvider.overrideWith((ref) {
        notifier ??=
            _RecordingHomeSummaryNotifier(ref, HomeSummaryService());
        return notifier!;
      }),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: const MediaQuery(
          data: MediaQueryData(size: _surfaceSize),
          child: Scaffold(body: AzamanHomePage()),
        ),
      ),
    ),
  );
  // Entrance + the NEW-D prime microtask.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 200));
  return (notifier!, container);
}

/// The activity layer's opacity — 0 at wallet rest, ~1 in the activity
/// resting state. (The surface is mounted at rest, so presence in the tree
/// is NOT the signal; opacity + the fetch boundary are.)
double _activityOpacity(WidgetTester tester) {
  final fade = find.ancestor(
    of: find.byType(HomeActivitySurface),
    matching: find.byType(Opacity),
  );
  return tester.widget<Opacity>(fade.first).opacity;
}

void main() {
  group('ActivityHandoffPhysics (pure)', () {
    test('resisted progress + deliberate threshold', () {
      expect(ActivityHandoffPhysics.revealFor(0.25), lessThan(0.25),
          reason: 'the handoff resists early movement');
      expect(ActivityHandoffPhysics.commits(0.3), isFalse);
      expect(ActivityHandoffPhysics.commits(0.5), isFalse);
      expect(
          ActivityHandoffPhysics.commits(
              ActivityHandoffPhysics.commitThreshold),
          isTrue);
      expect(ActivityHandoffPhysics.progressFor(-10), 0);
      expect(
          ActivityHandoffPhysics.progressFor(
              ActivityHandoffPhysics.travelPx * 4),
          1.0);
    });
  });

  group('ActivityActionResolver — typed actions from structured metadata', () {
    ActivityAction resolve(String raw, {String? reference}) =>
        ActivityActionResolver.resolve(TransactionSummary(
            id: 'x',
            title: 'A completely misleading display title',
            amount: 1,
            isCredit: false,
            status: 'COMPLETED',
            symbol: 'USDC',
            createdAt: null,
            rawType: raw,
            reference: reference));

    test('maps the structured rawType, never the title', () {
      expect(resolve('SUSU_CONTRIBUTION').type,
          ActivityActionType.viewSusu);
    });

    test('deposit / withdrawal / send mapping', () {
      expect(resolve('DEPOSIT_FIAT').type, ActivityActionType.viewDeposit);
      expect(resolve('WITHDRAWAL_CRYPTO').type,
          ActivityActionType.viewWithdrawal);
      expect(resolve('INTERNAL_TRANSFER').type, ActivityActionType.sendAgain);
    });

    test('a trade with a real reference opens the trade route; without one '
        'it falls back to details (never guesses)', () {
      final withRef = resolve('P2P_TRADE_SETTLED', reference: 'trade-77');
      final withoutRef = resolve('P2P_TRADE_SETTLED');
      expect(withRef.type, ActivityActionType.viewTrade);
      expect(withRef.reference, 'trade-77');
      expect(withoutRef.type, ActivityActionType.viewDetails);
    });

    test('unknown kinds resolve to the safe details fallback', () {
      expect(resolve('WEIRD_THING').type, ActivityActionType.viewDetails);
    });
  });

  group('Home — two resting states + the lazy-load boundary', () {
    testWidgets('resting Home: doorway present, no rows, no extra fetch',
        (tester) async {
      final (notifier, _) = await _pumpHome(tester);

      expect(find.byType(RecentActivityDoorway), findsOneWidget);
      // Two "Recent Activity" headings exist at rest: the doorway's and
      // the (opacity-0) activity surface's — the surface is mounted but
      // faded out, exactly like the deck's under-card at rest.
      expect(find.text('Recent Activity'), findsNWidgets(2));
      // No transaction rows, no skeletons on the resting Home.
      expect(find.byType(SkeletonBlock), findsNothing);
      // The surface is mounted (it fades in during the drag) but not
      // entered: opacity 0 and NO fetch beyond the NEW-D prime.
      expect(_activityOpacity(tester), 0.0);
      expect(notifier.refreshCalls, 1,
          reason: 'only the NEW-D prime fetch — the resting Home fetches '
              'nothing to decorate a preview');
    });

    testWidgets('below-threshold pull returns to the wallet state',
        (tester) async {
      final (notifier, _) = await _pumpHome(tester);

      // 60px < 0.55 × 170px travel — below the commit threshold.
      // NOTE: pumpAndSettle can never terminate on the new Home — the
      // pre-existing hologram provider polls on a recurring timer, so
      // explicit pumps are the contract here (same as the old Home tests).
      await tester.ensureVisible(find.byType(RecentActivityDoorway));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.drag(
          find.byType(RecentActivityDoorway), const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 900));

      expect(_activityOpacity(tester), lessThan(0.05),
          reason: 'a sub-threshold pull must return to rest');
      expect(notifier.refreshCalls, 1,
          reason: 'no entry fetch below the threshold');
    });

    testWidgets('crossing the threshold commits the activity state and '
        'fetches exactly once', (tester) async {
      final (notifier, _) = await _pumpHome(tester);

      // 120px > ~94px threshold — a deliberate pull.
      await tester.ensureVisible(find.byType(RecentActivityDoorway));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.drag(
          find.byType(RecentActivityDoorway), const Offset(0, 120));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(_activityOpacity(tester), greaterThan(0.99),
          reason: 'the activity surface snaps into focus');
      expect(find.text('Wallet'), findsOneWidget,
          reason: 'the back affordance to the wallet composition');
      expect(notifier.refreshCalls, 2,
          reason: 'the REAL lazy-load boundary: entering the activity '
              'state triggers its fetch');
    });
  });
}
