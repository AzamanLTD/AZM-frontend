// test/widgets/group_chat/group_profile_susu_preview_test.dart
// =============================================================================
// GROUP PROFILE — ACTIVE SUSU PAYOUT-WHEEL PREVIEW (Susu slice, 2026-10-21)
//
// The profile's susu section used to be a static sentence; it now renders
// the REAL payout wheel in miniature, fed by the same detail/members/
// cycles providers the dashboard renders from, and deep-links the
// dashboard on tap. These tests hold the three promises that matter:
//
//   1. LIVE — the preview shows the wheel and the next payee derived from
//      the same fixture data the dashboard would serve (never a
//      contradiction).
//   2. HONEST — while loading it shows a skeleton, on failure it falls
//      back to the plain-text badge rather than a broken wheel, and when
//      no susu id is reachable it never invents one.
//   3. CONNECTED — tapping opens the real Susu dashboard for THIS susu.
//
// The fixtures come from the demo seed itself, so a drift between the
// seed shape and the parser fails here before it ships.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/data/demo_seed_data.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart' show currentUserProvider;
import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/susu_provider.dart'
    show
        SusuCyclesNotifier,
        SusuDetailV2Notifier,
        SusuMembersNotifier,
        susuCyclesProvider,
        susuDetailV2Provider,
        susuMembersProvider;
import 'package:azaman/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:azaman/screens/group_chat/group_profile_screen.dart';
import 'package:azaman/screens/susu/susu_dashboard_screen.dart';

// ── Fixtures: the demo seed, parsed through the real factories ──────────────

SusuDetail _detail() => SusuDetail.fromJson(DemoSeedData.susuDetail());

List<SusuMemberView> _members() =>
    DemoSeedData.susuMembers().map(SusuMemberView.fromJson).toList();

List<SusuCycleView> _cycles() =>
    DemoSeedData.susuCycles().map(SusuCycleView.fromJson).toList();

GroupSummary _grp2() => GroupSummary.fromJson(
  DemoSeedData.groupChats().singleWhere((g) => g['id'] == 'grp-2'),
);

SusuInitiationStatus _status() =>
    SusuInitiationStatus.fromJson(DemoSeedData.susuGroupStatus());

User _me() => User(
  id: '1',
  username: 'me',
  email: 'me@example.com',
  token: 'demo',
  role: 'USER',
);

// ── Fake notifiers (the pattern native_amount_captures_test uses) ───────────

class _DemoDetailNotifier extends SusuDetailV2Notifier {
  @override
  Future<SusuDetail> build(String susuId) async => _detail();
}

class _DemoMembersNotifier extends SusuMembersNotifier {
  @override
  Future<List<SusuMemberView>> build(String susuId) async => _members();
}

class _DemoCyclesNotifier extends SusuCyclesNotifier {
  @override
  Future<List<SusuCycleView>> build(String susuId) async => _cycles();
}

class _BoomDetailNotifier extends SusuDetailV2Notifier {
  @override
  Future<SusuDetail> build(String susuId) =>
      Future.error(StateError('susu unreachable'));
}

// ── Harness ─────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  required GroupSummary group,
  SusuInitiationStatus? status,
  List<Override> extra = const [],
}) async {
  // Fresh ThemeProvider per pump — the ctor loads the (mocked) prefs and
  // resolves to dark by default, which notifyListeners settles on the
  // first pump below.
  final tp = ThemeProvider();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        themeProvider.overrideWith((ref) => tp),
        currentUserProvider.overrideWith((ref) => Stream.value(_me())),
        groupDetailProvider.overrideWith((ref, groupId) async => group),
        susuInitiationStatusProvider.overrideWith(
          (ref, groupId) async => status,
        ),
        ...extra,
      ],
      child: const MaterialApp(home: GroupProfileScreen(groupId: 'grp-2')),
    ),
  );
  // NEVER pumpAndSettle here: the live wheel ticks its clock forever and
  // the skeleton shimmers — the documented pattern is fixed pumps that
  // let providers resolve and entrance animations land (600ms ceiling).
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders the live wheel and the real next payee', (tester) async {
    await _pump(
      tester,
      group: _grp2(),
      status: _status(),
      extra: [
        susuDetailV2Provider.overrideWith(() => _DemoDetailNotifier()),
        susuMembersProvider.overrideWith(() => _DemoMembersNotifier()),
        susuCyclesProvider.overrideWith(() => _DemoCyclesNotifier()),
      ],
    );

    expect(find.byKey(const ValueKey('susu-preview-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('susu-wheel-canvas')), findsOneWidget);
    // The upcoming cycle pays Lamar (slot 2) — the caption must say so,
    // not a placeholder or a different payee than the dashboard shows.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('susu-preview-card')),
        matching: find.text('Next payout · Lamar · slot 2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('deep-links the Susu dashboard for this susu on tap', (
    tester,
  ) async {
    await _pump(
      tester,
      group: _grp2(),
      status: _status(),
      extra: [
        susuDetailV2Provider.overrideWith(() => _DemoDetailNotifier()),
        susuMembersProvider.overrideWith(() => _DemoMembersNotifier()),
        susuCyclesProvider.overrideWith(() => _DemoCyclesNotifier()),
      ],
    );

    expect(find.byType(SusuDashboardScreen), findsNothing);
    await tester.tap(find.byKey(const ValueKey('susu-preview-card')));
    await tester.pump(); // route pushed
    await tester.pump(const Duration(milliseconds: 600)); // transition lands
    expect(find.byType(SusuDashboardScreen), findsOneWidget);
  });

  testWidgets('fails honest: a dead detail falls back to the text badge', (
    tester,
  ) async {
    await _pump(
      tester,
      group: _grp2(),
      status: _status(),
      extra: [susuDetailV2Provider.overrideWith(() => _BoomDetailNotifier())],
    );

    // No wheel, no invented numbers — the plain-text badge remains.
    expect(find.byKey(const ValueKey('susu-wheel-canvas')), findsNothing);
    expect(
      find.textContaining('This group is an active Susu.'),
      findsOneWidget,
    );
  });

  testWidgets('an active susu with no reachable id never invents one', (
    tester,
  ) async {
    final group = _grp2();
    final orphan = GroupSummary.fromJson({
      ...DemoSeedData.groupChats().singleWhere((g) => g['id'] == 'grp-2'),
      'susuGroupId': null,
      'susuGroup': null,
    });
    expect(orphan.susuGroupId, isNull); // the fixture built what we asked
    final orphanStatus = SusuInitiationStatus.fromJson({
      ...DemoSeedData.susuGroupStatus(),
      'susuGroupId': null,
    });
    expect(orphanStatus.isActive, isTrue);
    expect(orphanStatus.susuGroupId, isNull);
    expect(group.susuGroupId, 'susu-1'); // sanity: grp-2 normally has one

    await _pump(tester, group: orphan, status: orphanStatus);

    expect(find.byKey(const ValueKey('susu-wheel-canvas')), findsNothing);
    expect(
      find.textContaining('This group is an active Susu.'),
      findsOneWidget,
    );
  });
}
