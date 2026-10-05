// CORRECTION E — the Save / P2P / Susu wallet pills.
//
// The Home resting surface shows three compact pill controls — [icon] Save,
// [icon] P2P, [icon] Susu — and NOTHING else. The notice boards are gone;
// the pill communicates the product name only. Icon identity, accents and
// the glass language are preserved, and every destination is unchanged:
//   SAVE → /savings
//   P2P  → the canonical /marketplace route (UX-CORRECTION §10 — the
//          legacy P2PMarketplaceScreen is gone from this surface)
//   SUSU → the DETERMINISTIC most-relevant active group, or the hub.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/router/route_registry.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/wallet_modules.dart';

class _FakeSusuListNotifier extends SusuListNotifier {
  _FakeSusuListNotifier(this.groups);
  final List<SusuSummary> groups;
  @override
  Future<List<SusuSummary>> build() async => groups;
}

SusuSummary _activeSusu(DateTime runAt,
        {String id = 's1', String name = 'Circle Susu'}) =>
    SusuSummary(
      id: id,
      name: name,
      status: SusuStatus.active,
      contributionUsdc: 10,
      frequency: SusuFrequency.weekly,
      totalCycles: 10,
      nextCycle: SusuCycleSummary(
        id: 'c4',
        cycleNumber: 4,
        scheduledRunAt: runAt,
        payoutUserId: 1,
        isMe: false,
      ),
      myCycleSlot: 4,
      myStatus: SusuMemberStatus.active,
      myRole: 'MEMBER',
    );

SusuSummary _inactiveSusu(String id) => SusuSummary(
      id: id,
      name: 'Dormant Susu',
      status: SusuStatus.completed,
      contributionUsdc: 5,
      frequency: SusuFrequency.monthly,
      totalCycles: 2,
      nextCycle: null,
      myCycleSlot: 1,
      myStatus: SusuMemberStatus.active,
      myRole: 'MEMBER',
    );

Future<void> _pumpRow(
  WidgetTester tester, {
  SusuListNotifier? susuNotifier,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (susuNotifier != null)
          susuListProvider.overrideWith(() => susuNotifier),
      ],
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: const MediaQuery(
          data: MediaQueryData(size: Size(400, 900)),
          child: Scaffold(body: WalletModulesRow()),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('§10 — tapping P2P opens the CANONICAL /marketplace route, '
      'not the legacy P2P screen', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          name: AzRouteNames.home,
          builder: (_, __) => const Scaffold(body: WalletModulesRow()),
        ),
        GoRoute(
          path: '/marketplace',
          name: AzRouteNames.marketplace,
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('MARKETPLACE PAGE')),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: ThemeProvider.getThemeData(AzamanTheme.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('wallet-module-p2p')));
    await tester.pumpAndSettle();

    expect(find.text('MARKETPLACE PAGE'), findsOneWidget,
        reason: 'the P2P pill must route to the canonical /marketplace '
            'page — no second P2P destination');
  });

  testWidgets('the row renders exactly the three pills — no descriptions',
      (tester) async {
    await _pumpRow(tester);

    expect(find.byKey(const ValueKey('wallet-module-save')), findsOneWidget);
    expect(find.byKey(const ValueKey('wallet-module-p2p')), findsOneWidget);
    expect(find.byKey(const ValueKey('wallet-module-susu')), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('P2P'), findsOneWidget);
    expect(find.text('Susu'), findsOneWidget);

    // The old educational/progress sentences are GONE from Home space.
    expect(find.text("Put money aside for something you're building."),
        findsNothing);
    expect(find.text('Buy or sell directly with verified vendors.'),
        findsNothing);
    expect(find.text('Save together with your circle.'), findsNothing);
  });

  test('chooseMostRelevantSusu picks the active group with the earliest '
      'scheduled run — deterministically', () {
    final early = _activeSusu(DateTime(2026, 10, 5),
        id: 'early', name: 'Early Susu');
    final late = _activeSusu(DateTime(2026, 11, 1),
        id: 'late', name: 'Late Susu');
    final dormant = _inactiveSusu('dormant');
    // No groups → null.
    expect(chooseMostRelevantSusu(const []), isNull);

    // Dormant-only → null.
    expect(chooseMostRelevantSusu([dormant]), isNull);

    // Two active groups: the EARLIEST scheduled run wins.
    expect(chooseMostRelevantSusu([late, early])?.id, 'early');
    expect(chooseMostRelevantSusu([early, late])?.id, 'early');

    // An active group with NO scheduled run still beats nothing, but loses
    // to any scheduled one.
    final unscheduledGroup = SusuSummary(
      id: 'unsched',
      name: 'Unscheduled',
      status: SusuStatus.active,
      contributionUsdc: 3,
      frequency: SusuFrequency.weekly,
      totalCycles: 1,
      nextCycle: null,
      myCycleSlot: 1,
      myStatus: SusuMemberStatus.active,
      myRole: 'MEMBER',
    );
    expect(chooseMostRelevantSusu([unscheduledGroup])?.id, 'unsched');
    expect(
      chooseMostRelevantSusu([unscheduledGroup, late])?.id,
      'late',
    );
  });
}
