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
import 'package:azaman/providers/transaction_history_provider.dart';
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

/// Records fetches for BOTH lazy-load boundaries. No network in tests.
class _RecordingHistoryNotifier extends TransactionHistoryNotifier {
  _RecordingHistoryNotifier(this.pages);

  /// Pages handed out per loadMore() call: page 0 = first page, etc.
  final List<List<TransactionRecord>> pages;
  int loadMoreCalls = 0;
  int refreshCalls = 0;

  @override
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    if (loadMoreCalls >= pages.length) {
      state = state.copyWith(isLoading: false, hasMore: false);
      return;
    }
    loadMoreCalls++;
    final page = pages[loadMoreCalls - 1];
    state = state.copyWith(
      items: [...state.items, ...page],
      isLoading: false,
      hasMore: loadMoreCalls < pages.length,
    );
  }

  @override
  Future<void> refresh() async {
    refreshCalls++;
    state = TransactionHistoryState(filter: state.filter);
    await loadMore();
  }
}

TransactionRecord _record(String rawType,
    {double amountUsdc = -1,
    Map<String, dynamic> metadata = const {},
    String providerRef = 'ref-x',
    String status = 'COMPLETED'}) {
  return TransactionRecord(
    id: 'txn-$rawType',
    rawType: rawType,
    amountUsdc: amountUsdc,
    status: status,
    createdAt: DateTime(2026, 9, 30, 12),
    metadata: metadata,
    providerRef: providerRef,
  );
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

Future<
    (
      _RecordingHomeSummaryNotifier,
      _RecordingHistoryNotifier,
      ProviderContainer
    )> _pumpHome(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(
      {'has_seen_flippable_card_hint': true});
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(_surfaceSize);

  _RecordingHomeSummaryNotifier? notifier;
  // Two pages. The FIRST page is long enough to overflow the test
  // viewport (8 rows ≈ 850px > ~740px), so the trailing load-more tile
  // starts below the fold — the cursor page loads only when the user
  // actually scrolls to the bottom, not eagerly on entry.
  final history = _RecordingHistoryNotifier([
    [
      _record('DEPOSIT_FIAT', amountUsdc: 5),
      _record('INTERNAL_TRANSFER',
          amountUsdc: -2,
          metadata: {'recipientAzamId': 'azm-77',
              'recipientName': 'Ama'}),
      _record('SUSU_CONTRIBUTION',
          amountUsdc: -1, metadata: {'susuGroupId': 'susu-9'}),
      _record('P2P_TRADE_SETTLED', amountUsdc: -3, providerRef: 'trade-77'),
      _record('DEPOSIT_FIAT', amountUsdc: 10, providerRef: 'd5'),
      _record('DEPOSIT_FIAT', amountUsdc: 11, providerRef: 'd6'),
      _record('DEPOSIT_FIAT', amountUsdc: 12, providerRef: 'd7'),
      _record('DEPOSIT_FIAT', amountUsdc: 13, providerRef: 'd8'),
      // 12 rows ≈ 1280px — comfortably past the ~740px viewport PLUS the
      // 250px default cacheExtent, so the trailing load-more tile is
      // genuinely NOT built at entry (no prefetch) and only appears when
      // the user scrolls toward the bottom.
      _record('DEPOSIT_FIAT', amountUsdc: 14, providerRef: 'd9'),
      _record('DEPOSIT_FIAT', amountUsdc: 15, providerRef: 'd10'),
      _record('DEPOSIT_FIAT', amountUsdc: 16, providerRef: 'd11'),
      _record('DEPOSIT_FIAT', amountUsdc: 17, providerRef: 'd12'),
      _record('DEPOSIT_FIAT', amountUsdc: 18, providerRef: 'd13'),
      _record('DEPOSIT_FIAT', amountUsdc: 19, providerRef: 'd14'),
      _record('DEPOSIT_FIAT', amountUsdc: 20, providerRef: 'd15'),
      _record('DEPOSIT_FIAT', amountUsdc: 21, providerRef: 'd16'),
      ...List.generate(
          8,
          (i) => _record('DEPOSIT_FIAT',
              amountUsdc: (22 + i).toDouble(), providerRef: 'filler-$i')),
    ],
    [_record('WITHDRAWAL_CRYPTO', amountUsdc: -4)],
  ]);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      transactionHistoryProvider.overrideWith((ref) => history),
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
  return (notifier!, history, container);
}

/// The activity layer's opacity — 0 at wallet rest, ~1 in the activity
/// resting state. (The surface is mounted at rest, so presence in the tree
/// is NOT the signal; opacity + the fetch boundary are.)

/// Enters the activity state from the wallet rest: scroll the doorway into
/// view, WAIT OUT the ensureVisible scroll animation (dragging mid-scroll
/// lands the pointer on the wrong widget), then a deliberate 120px pull.
/// Self-verifies the commit so a flaky hit can never poison the assertions
/// downstream: a drag that somehow missed is retried once.
Future<void> _enterActivity(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(RecentActivityDoorway));
  // Scroll animation (600ms) + any settle frames.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  for (var attempt = 0; attempt < 2; attempt++) {
    await tester.drag(
        find.byType(RecentActivityDoorway), const Offset(0, 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    if (_activityOpacity(tester) > 0.99) return;
  }
  fail('the deliberate entry drag never committed the activity state');
}

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
    // Titles never exist in the record model at all — the resolver reads
    // ONLY the structured rawType + metadata.
    ActivityAction resolve(TransactionRecord t) =>
        ActivityActionResolver.resolve(t);

    test('maps the structured rawType, never the title', () {
      expect(resolve(_record('SUSU_CONTRIBUTION')).type,
          ActivityActionType.viewSusu);
    });

    test('deposit / withdrawal / trade mapping', () {
      expect(resolve(_record('DEPOSIT_FIAT')).type,
          ActivityActionType.viewDeposit);
      expect(resolve(_record('WITHDRAWAL_CRYPTO')).type,
          ActivityActionType.viewWithdrawal);
    });

    test('a trade with a real reference opens the trade route; without one '
        'it falls back to details (never guesses)', () {
      expect(
          resolve(_record('P2P_TRADE_SETTLED', providerRef: 'trade-77'))
              .type,
          ActivityActionType.viewTrade);
      expect(
          resolve(_record('P2P_TRADE_SETTLED', providerRef: 'trade-77'))
              .reference,
          'trade-77');
      expect(
          resolve(_record('P2P_TRADE_SETTLED', providerRef: ''))
              .type,
          ActivityActionType.viewDetails);
    });

    test('SEND AGAIN: only an outbound transfer WITH authoritative '
        'recipient metadata — a display title never counts', () {
      // Outbound + recipient AZM ID in metadata → the action carries the
      // payload explicitly.
      final outbound = _record('INTERNAL_TRANSFER',
          amountUsdc: -2,
          metadata: {
            'recipientAzamId': 'azm-77',
            'recipientName': 'Ama',
            'description': 'A misleading display description',
          });
      final resolvedOut = resolve(outbound);
      expect(resolvedOut.type, ActivityActionType.sendAgain);
      expect(resolvedOut.recipient, isNotNull);
      expect(resolvedOut.recipient!.azamanId, 'azm-77');
      expect(resolvedOut.recipient!.displayName, 'Ama');

      // Outbound WITHOUT any recipient metadata → Details. Never guess.
      final anonymous = _record('INTERNAL_TRANSFER', amountUsdc: -2);
      expect(resolve(anonymous).type, ActivityActionType.viewDetails);

      // INCOMING transfer (credit) → never Send Again without a contract.
      final incoming = _record('INTERNAL_TRANSFER',
          amountUsdc: 2,
          metadata: {'counterpartyAzamId': 'azm-77'});
      expect(resolve(incoming).type, ActivityActionType.viewDetails);
    });

    test('unknown kinds resolve to the safe details fallback', () {
      expect(resolve(_record('WEIRD_THING')).type,
          ActivityActionType.viewDetails);
    });
  });

  group('Home — two resting states + the lazy-load boundary', () {
    testWidgets('resting Home: doorway present, no rows, no extra fetch',
        (tester) async {
      final (notifier, history, _) = await _pumpHome(tester);

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
      expect(history.refreshCalls, 0,
          reason: 'AUDIT §12: the transaction history fetch happens ONLY '
              'on entry — resting Home never pre-fetches activity data');
      expect(history.loadMoreCalls, 0);
    });

    testWidgets('below-threshold pull returns to the wallet state',
        (tester) async {
      final (notifier, history, _) = await _pumpHome(tester);

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
      expect(history.refreshCalls, 0,
          reason: 'no activity fetch without an actual entry');
    });

    testWidgets('crossing the threshold commits the activity state and '
        'fetches exactly once', (tester) async {
      final (notifier, history, _) = await _pumpHome(tester);

      // 120px > ~94px threshold — a deliberate pull.
      await _enterActivity(tester);
      // The entry fetch runs in a post-frame callback; the rows render on
      // the NEXT frame.
      await tester.pump(const Duration(milliseconds: 100));

      expect(_activityOpacity(tester), greaterThan(0.99),
          reason: 'the activity surface snaps into focus');
      expect(find.text('Wallet'), findsOneWidget,
          reason: 'the back affordance to the wallet composition');
      expect(notifier.refreshCalls, 1,
          reason: 'AUDIT §12: entering the activity state does NOT touch '
              'the home summary (rates/friend requests/notifications are '
              'not the activity data source)');
      expect(history.refreshCalls, 1,
          reason: 'AUDIT §12: the REAL lazy-load boundary — entering the '
              'activity state fetches the real transaction history '
              '(/finance/transactions) exactly once');
      expect(find.byType(HomeActivitySurface), findsOneWidget);
      expect(find.text('Send again'), findsOneWidget,
          reason: 'the outbound transfer with recipient metadata carries '
              'the Send Again action');
    });

    testWidgets('AUDIT §12: cursor pagination — the list continues beyond '
        'the first page (nothing hard-stops after four items)',
        (tester) async {
      final (_, history, _) = await _pumpHome(tester);

      await _enterActivity(tester);
      await tester.pump(const Duration(milliseconds: 100));

      // Entered: the first page (4 records) shows, a next page exists.
      expect(history.refreshCalls, 1);
      expect(history.loadMoreCalls, 1);
      expect(find.byKey(const ValueKey('home-activity-list')), findsOneWidget);

      // Scroll the list to its bottom: the load-more tile builds and
      // pulls the second cursor page.
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byKey(const ValueKey('home-activity-list')),
            const Offset(0, -600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(history.loadMoreCalls, 2,
          reason: 'the cursor pagination (hasMore/nextCursor) continues '
              'the list beyond the first page');
      expect(find.text('View withdrawal'), findsOneWidget,
          reason: 'the second page record rendered');
    });

    testWidgets('AUDIT §1: pulling down from the top of the activity '
        'surface hands back to the wallet state (the reverse handoff)',
        (tester) async {
      final (_, history, _) = await _pumpHome(tester);

      // Enter the activity state.
      await _enterActivity(tester);
      expect(_activityOpacity(tester), greaterThan(0.99));

      // Pull DOWN on the SURFACE's header (outside the list — the same
      // gesture path real users have on the "Recent Activity" header).
      // The faded-out doorway also says 'Recent Activity', so scope to the
      // activity surface.
      final header = find.descendant(
          of: find.byType(HomeActivitySurface),
          matching: find.text('Recent Activity'));
      expect(header, findsOneWidget);
      await tester.drag(header, const Offset(0, 120));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(_activityOpacity(tester), lessThan(0.05),
          reason: 'the reverse handoff collapses the activity state back '
              'to the wallet resting state');
      // The activity surface still exists (mounted, dormant) and the
      // data is still cached: no re-fetch from a collapse.
      expect(history.refreshCalls, 1);
    });

    testWidgets('AUDIT §1: a small reverse pull springs back to the '
        'activity state (same deliberate threshold grammar)', (tester) async {
      final (_, history, _) = await _pumpHome(tester);

      await _enterActivity(tester);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.drag(
          find.descendant(
              of: find.byType(HomeActivitySurface),
              matching: find.text('Recent Activity')),
          const Offset(0, 60));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(_activityOpacity(tester), greaterThan(0.99),
          reason: 'a sub-threshold reverse pull stays in the activity '
              'state — the same commit threshold as the forward handoff');
      expect(history.refreshCalls, 1);
    });
  });
}
