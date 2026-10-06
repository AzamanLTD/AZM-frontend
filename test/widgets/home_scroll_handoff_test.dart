// =============================================================================
// EXPERIENCE PASS §6 + §7 + §8 — the scroll-driven activity handoff, the
// reminder-deck peek, and the activity row stagger.
//
// §6: the doorway no longer owns a drag gesture. The Home page's own
// vertical scroll drives the forward handoff — continued downward page
// scroll at the end of the Home content feeds the SAME resisted physics,
// with an intentional commit threshold, a clean release on reversal, and
// the doorway tap kept as the explicit fallback.
// §7: on commit the reminder deck parks in a small peek band above the
// activity surface (visible context: there is still a layer above
// Activity). No deck signal → no peek band.
// §8: rows enter with a tiny shared-controller stagger; completed
// controller → rows render at their final state immediately.
// =============================================================================

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/marketplace_resume_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/widgets/home/activity_doorway.dart';
import 'package:azaman/widgets/home/home_reminder_deck.dart';

const _surfaceSize = Size(400, 900);

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final bytes = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final loader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
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

/// Pumps the full Home page. [withDeck] plants a real susu signal so the
/// reminder deck exists (§7 peek tests); without it the deck renders
/// nothing.
Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required bool withDeck,
}) async {
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
  });
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(_surfaceSize);

  final history = _RecordingHistoryNotifier([
    List.generate(
      6,
      (i) => _record('DEPOSIT_FIAT', amountUsdc: (5 + i).toDouble()),
    ),
  ]);

  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      transactionHistoryProvider.overrideWith((ref) => history),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 100),
      ),
      oracleRateProvider.overrideWith((ref) => 1.0),
      homeSummaryProvider.overrideWith(
        (ref) => _RecordingHomeSummaryNotifier(ref, HomeSummaryService()),
      ),
      if (withDeck) ...[
        susuListProvider.overrideWith(
          () => _FakeSusuListNotifier([_activeSusu(DateTime(2026, 10, 12))]),
        ),
        marketplaceResumeProvider.overrideWithValue(null),
      ],
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
  // Entrance + the prime microtask + the doorway-gap measurement.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 700));
  return container;
}

double _activityOpacity(WidgetTester tester) {
  final fade = find.ancestor(
    of: find.byType(HomeActivitySurface),
    matching: find.byType(Opacity),
  );
  if (fade.evaluate().isEmpty) return 0;
  return tester.widget<Opacity>(fade.first).opacity;
}

Future<void> _scrollToBottom(WidgetTester tester) async {
  // Drag the Home page's own scroll view to its end (content is taller
  // than the viewport by design — the doorway lands at the first-viewport
  // bottom). Small, held steps — a real finger — and it STOPS at the end
  // without piling up enough overscroll to commit the handoff.
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(SingleChildScrollView).first),
  );
  for (var i = 0; i < 20; i++) {
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump(const Duration(milliseconds: 16));
    if (_atBottomPixels(tester) ?? false) break;
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 200));
}

/// A deliberate, held overscroll at the bottom: the "continued downward
/// page scroll" that crosses the handoff threshold.
Future<void> _overscrollPastEnd(WidgetTester tester, double px) async {
  // A real finger, not a teleport: -20px held steps. (A single giant
  // moveBy gets its first delta consumed as the drag start when the
  // pointer lands on any tappable card — the reminder deck fills the
  // old blank space now — because dragStartBehavior.start resolves the
  // arena on that first move. Stepped deltas are what a real gesture
  // delivers, and they accumulate into the same overscroll budget.)
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(SingleChildScrollView).first),
  );
  var left = px;
  while (left > 0) {
    final step = math.min(20.0, left);
    left -= step;
    await gesture.moveBy(Offset(0, -step));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
}

bool? _atBottomPixels(WidgetTester tester) {
  // The Home scroll's own Scrollable state (maybeOf from the
  // SingleChildScrollView context looks UP the tree, not into its child).
  final scrollable = find
      .descendant(
        of: find.byType(SingleChildScrollView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  if (scrollable.evaluate().isEmpty) return null;
  final pos = tester.state<ScrollableState>(scrollable).position;
  if (!pos.hasContentDimensions) return null;
  return pos.pixels >= pos.maxScrollExtent - 0.5;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

void main() {
  testWidgets('§6 — continued downward page scroll at the Home end COMMITS the '
      'activity surface (no finger over the doorway needed)', (tester) async {
    await _pumpHome(tester, withDeck: true);
    await _scrollToBottom(tester);

    // The user is NOT over the doorway: held on the Home page surface,
    // continue past the end of the content (260px of overscroll — well
    // past the 170px travel / 0.55 commit threshold).
    await _overscrollPastEnd(tester, 260);
    await _settle(tester);

    expect(_activityOpacity(tester), greaterThan(0.99));
  });

  testWidgets('§6 — a SHORT overscroll stays below the commit threshold and '
      'springs back to the wallet', (tester) async {
    await _pumpHome(tester, withDeck: true);
    await _scrollToBottom(tester);

    // ~60px of held overscroll → progress ≈ 0.35 < 0.55 commit threshold.
    await _overscrollPastEnd(tester, 60);
    await _settle(tester);

    expect(_activityOpacity(tester), lessThan(0.02));
  });

  testWidgets(
    '§6 — reversing the page scroll mid-handoff releases cleanly: the '
    'scroll wins, no fight',
    (tester) async {
      await _pumpHome(tester, withDeck: true);
      await _scrollToBottom(tester);

      // A HELD gesture: accumulate deep overscroll, then drag back UP
      // (ordinary Home scrolling) before lifting.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SingleChildScrollView).first),
      );
      for (var i = 0; i < 7; i++) {
        await gesture.moveBy(const Offset(0, -20)); // deep overscroll, held
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        _activityOpacity(tester),
        greaterThan(0.2),
        reason: 'the held overscroll must visibly move the handoff',
      );

      await gesture.moveBy(const Offset(0, 40)); // reverse: scroll up
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await _settle(tester);

      // Released mid-reverse → the handoff sprang back to the wallet.
      expect(_activityOpacity(tester), lessThan(0.02));
      // And the Home scroll is still usable (moved off the end).
      expect(_atBottomPixels(tester) ?? true, isFalse);
    },
  );

  testWidgets('§7 — on commit the reminder deck parks in the peek band above '
      'Activity (visible context, not gone)', (tester) async {
    await _pumpHome(tester, withDeck: true);
    await _scrollToBottom(tester);
    await _overscrollPastEnd(tester, 260);
    await _settle(tester);
    expect(_activityOpacity(tester), greaterThan(0.99));

    // The deck peek: the reminder deck's visible bottom sits within the
    // 96px top band, with a meaningful sliver actually on screen.
    final deckCtx = tester.element(find.byType(HomeReminderDeck));
    final deckBox = deckCtx.findRenderObject() as RenderBox;
    final deckBottom =
        deckBox.localToGlobal(Offset.zero).dy + deckBox.size.height;
    final pos = Scrollable.maybeOf(deckCtx)?.position;
    expect(deckBottom, lessThan(98));
    expect(
      deckBottom,
      greaterThan(60),
      reason: 'the peek must show a meaningful part of the deck',
    );

    // PASS A5 — the surface parks below the 96px peek band and the
    // heading sits a further structural inset into the surface: the
    // committed state reads as a layer pulled over Home, never a
    // flat route swap.
    final header = tester.getTopLeft(
      find.byKey(const ValueKey('home-activity-header-title')),
    );
    // ~144: the 96px peek band + the 48px heading inset (text metrics sit
    // a hair above the padded inset).
    expect(header.dy, closeTo(144, 3));
  });

  testWidgets('§7 — no deck signal: the honest PLACEHOLDER deck still parks in '
      'the peek band (the slot is never blank)', (tester) async {
    await _pumpHome(tester, withDeck: false);
    await _scrollToBottom(tester);
    await _overscrollPastEnd(tester, 260);
    await _settle(tester);
    expect(_activityOpacity(tester), greaterThan(0.99));

    // PLACEHOLDER PASS (owner direction): production never fabricates
    // signal content — but the slot is never blank either. The honest
    // placeholder renders at the same band and parks in the peek band
    // above Activity, exactly like the living deck.
    expect(find.text('Your reminders will appear here'), findsNWidgets(3));
    final deckCtx = tester.element(find.byType(HomeReminderDeck));
    final deckBox = deckCtx.findRenderObject() as RenderBox;
    final deckBottom =
        deckBox.localToGlobal(Offset.zero).dy + deckBox.size.height;
    expect(deckBottom, lessThan(98));
    expect(
      deckBottom,
      greaterThan(60),
      reason: 'the placeholder peek must show a meaningful sliver',
    );

    // PASS A5 — the peek band exists (the placeholder deck occupies
    // it), so the surface parks below the band and its heading sits
    // the structural inset into the surface — the same committed
    // resting geometry as a deck with real signals.
    final header = tester.getTopLeft(
      find.byKey(const ValueKey('home-activity-header-title')),
    );
    // ~144: the 96px peek band + the 48px heading inset.
    expect(header.dy, closeTo(144, 3));
  });

  testWidgets(
    '§8 — rows enter with a stagger: the first row is still mid-flight '
    'right after entry and ALL rows settle to their final state',
    (tester) async {
      await _pumpHome(tester, withDeck: false);
      await _scrollToBottom(tester);
      await _overscrollPastEnd(tester, 260);
      // Pump just enough for the surface to take over (commit spring) but
      // NOT the full 900ms entrance controller.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final list = find.byKey(const ValueKey('home-activity-list'));
      expect(list, findsOneWidget);
      final rows = tester
          .widgetList<Opacity>(
            find.descendant(
              of: list,
              matching: find.byWidgetPredicate(
                (w) => w is Opacity && w.opacity < 1.0,
              ),
            ),
          )
          .toList();
      // The stagger is mid-flight: some row is still not fully opaque.
      expect(
        rows,
        isNotEmpty,
        reason: 'right after entry the stagger must still be running',
      );

      // And it COMPLETES — no endless animation, no timers.
      await tester.pump(const Duration(milliseconds: 1000));
      final unsettled = tester
          .widgetList<Opacity>(
            find.descendant(
              of: list,
              matching: find.byWidgetPredicate(
                (w) => w is Opacity && w.opacity < 1.0,
              ),
            ),
          )
          .toList();
      expect(
        unsettled,
        isEmpty,
        reason: 'the entrance must complete and leave rows at rest',
      );
    },
  );
}
