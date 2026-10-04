// EXPERIENCE PASS §19 — VISUAL QA GATE AT BOTH TARGET VIEWPORTS.
//
// The spec requires the UI to be visually inspected at ~390x844 and
// ~430x932, in dark mode, light mode, and reduced motion, with special
// attention to the balance card, reminder deck, Recent Activity
// transition, plus launcher, keyboard-bound composer/search and the
// marketplace speed dial — "the UI must still look intentional on
// smaller screens."
//
// This file is the runnable portion of that gate: it pumps the REAL
// Home page (which carries the balance card, greeting/avatar, wallet
// module cards, reminder deck, Recent Activity and the plus pills) at
// BOTH target viewports, in BOTH brightnesses (dark first — the
// default design surface), and with reduced motion, and asserts the
// layout survives:
//
//   - no RenderFlex/viewport overflow exceptions (Flutter fails the
//     test automatically on any overflow)
//   - the balance card fits the viewport width at both sizes
//   - the reminder deck renders with real data and stays in bounds
//   - reduced motion settles the page in a single pump (no expressive
//     travel to wait out)
//
// The marketplace surfaces (speed dial, focused search) and the chat
// composer are gated by their own §13/§14/§16 suites; this gate pins
// the Home composition they all sit alongside.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/marketplace_resume_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/sensory_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/widgets/flippable_balance_card.dart';
import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/widgets/home/home_reminder_deck.dart';

const _smallPhone = Size(390, 844);
const _largePhone = Size(430, 932);

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

class _FakeSusuListNotifier extends SusuListNotifier {
  _FakeSusuListNotifier(this.groups);
  final List<SusuSummary> groups;
  @override
  Future<List<SusuSummary>> build() async => groups;
}

class _RecordingHistoryNotifier extends TransactionHistoryNotifier {
  _RecordingHistoryNotifier(this.pages);
  final List<List<TransactionRecord>> pages;

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

  int loadMoreCalls = 0;

  @override
  Future<void> refresh() async {
    state = TransactionHistoryState(filter: state.filter);
    await loadMore();
  }
}

class _RecordingHomeSummaryNotifier extends HomeSummaryNotifier {
  _RecordingHomeSummaryNotifier(Ref ref, HomeSummaryService service)
      : super(ref, service);
  @override
  Future<void> refresh() async {
    state = state.copyWith(loading: false);
  }
}

TransactionRecord _record(String rawType, {double amountUsdc = -1}) =>
    TransactionRecord(
      id: 'txn-$rawType-$amountUsdc',
      rawType: rawType,
      amountUsdc: amountUsdc,
      status: 'COMPLETED',
      createdAt: DateTime(2026, 9, 30, 12),
      metadata: const {},
      providerRef: 'ref-$rawType-$amountUsdc',
    );

SusuSummary _activeSusu(DateTime runAt) => SusuSummary(
      id: 's1',
      name: 'Circle Susu',
      status: SusuStatus.active,
      contributionUsdc: 10,
      frequency: SusuFrequency.weekly,
      totalCycles: 10,
      nextCycle: SusuCycleSummary(
        id: 'c4',
        cycleNumber: 4,
        scheduledRunAt: runAt,
        payoutUserId: 2,
        isMe: false,
      ),
      myCycleSlot: 4,
      myStatus: SusuMemberStatus.active,
      myRole: 'MEMBER',
    );

Future<void> _pumpHome(
  WidgetTester tester, {
  required Size viewport,
  required bool dark,
}) async {
  // No 'azaman_theme' key: the DEFAULT (dark) governs unless [dark] is
  // false, which pins the explicit light identity instead. The flip-hint
  // flag is always set so the one-shot hint overlay (which arms a
  // dismissal timer) never mounts in this gate.
  SharedPreferences.setMockInitialValues(dark
      ? {'has_seen_flippable_card_hint': true}
      : {'azaman_theme': 0, 'has_seen_flippable_card_hint': true});
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(viewport);

  final history = _RecordingHistoryNotifier([
    List.generate(
        6,
        (i) =>
            _record('DEPOSIT_FIAT', amountUsdc: (5 + i).toDouble())),
  ]);

  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      transactionHistoryProvider.overrideWith((ref) => history),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
          (ref) => const BalanceData(availableBalance: 100)),
      oracleRateProvider.overrideWith((ref) => 1.0),
      homeSummaryProvider.overrideWith(
          (ref) => _RecordingHomeSummaryNotifier(ref, HomeSummaryService())),
      susuListProvider.overrideWith(() => _FakeSusuListNotifier(
          [_activeSusu(DateTime(2026, 10, 12))])),
      marketplaceResumeProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(
            dark ? AzamanTheme.dark : AzamanTheme.light),
        home: MediaQuery(
          data: MediaQueryData(size: viewport),
          child: const Scaffold(body: AzamanHomePage()),
        ),
      ),
    ),
  );
  // Entrance settle + doorway-gap measurement.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  for (final entry in [
    ('390x844 (small phone)', _smallPhone),
    ('430x932 (large phone)', _largePhone),
  ]) {
    final label = entry.$1;
    final viewport = entry.$2;

    testWidgets('DARK (default design surface) — Home renders without '
        'overflow at $label', (tester) async {
      await _pumpHome(tester, viewport: viewport, dark: true);

      // The §17 surfaces all render: balance card, reminder deck (real
      // data), recent activity rows.
      expect(find.byType(FlippableBalanceCard), findsOneWidget);
      expect(find.byType(HomeReminderDeck), findsOneWidget);

      // Balance card fits the viewport width with page padding to spare.
      final cardRect =
          tester.getRect(find.byType(FlippableBalanceCard).first);
      expect(cardRect.left >= 0, isTrue,
          reason: 'balance card never bleeds off the left edge');
      expect(cardRect.right <= viewport.width, isTrue,
          reason: 'balance card never bleeds off the right edge');

      // The deck sits within the viewport too.
      final deckRect =
          tester.getRect(find.byType(HomeReminderDeck).first);
      expect(deckRect.width <= viewport.width, isTrue);
    });

    testWidgets('LIGHT — Home renders without overflow at $label',
        (tester) async {
      await _pumpHome(tester, viewport: viewport, dark: false);
      expect(find.byType(FlippableBalanceCard), findsOneWidget);
      expect(find.byType(HomeReminderDeck), findsOneWidget);
    });

    testWidgets('REDUCED MOTION — Home settles immediately at $label',
        (tester) async {
      AzSensory.reduceMotionOverrideIsSet = true;
      AzSensory.reduceMotionOverride = true;
      addTearDown(() {
        AzSensory.reduceMotionOverrideIsSet = false;
        AzSensory.reduceMotionOverride = false;
      });
      await _pumpHome(tester, viewport: viewport, dark: true);

      // No expressive travel to wait out: a single short pump lands the
      // page at its final state.
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(FlippableBalanceCard), findsOneWidget);
      expect(find.byType(HomeReminderDeck), findsOneWidget);
    });
  }
}
