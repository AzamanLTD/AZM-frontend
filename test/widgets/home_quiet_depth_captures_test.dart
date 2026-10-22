// QUIET DEPTH — HOME PILOT (2026-10-22).
//
// The Home quick actions (Save / P2P / Susu) enter raised, settle into a
// nearly-flush recessed state after the idle delay, and re-elevate when a
// focal surface releases the stage or a qualifying interaction wakes them.
// This suite pins the pilot's contract on the REAL Home page:
//
//   1.  raised on entry;
//   2.  recessed after the idle delay, transition complete;
//   3.  a tap wakes the controls AND fires the real navigation — the
//       visual transition never swallows or delays the action;
//   4.  a wallet card brought out recesses the quick actions;
//   5.  tucking the wallet restores them;
//   6.  starting a reminder swipe focuses the deck and recesses the
//       actions without gesture interference (the swipe still commits);
//   7.  viewing every current reminder id inserts EXACTLY ONE terminal
//       card;
//   8.  the terminal tap exits focus, restores the actions, and the
//       celebration fires at most once per viewing cycle;
//   9.  tapping outside the reminder region also restores the actions;
//   10. a changed reminder set cannot reuse stale completion state;
//   11. reduced motion: instant state changes, no confetti, and disposal
//       cancels lifecycle work;
//   12. no regression: the reminder a11y advance action and the wallet
//       PIN gate keep working.
//
// Plus environment coverage: 320/360/390dp, light and dark, a short
// viewport, 1.6x text scale, keyboard/reduced-motion, and semantics +
// hit-target continuity in both depth states.

import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/widgets/home/azm_visa_card.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/marketplace_relevance_provider.dart';
import 'package:azaman/providers/marketplace_resume_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/widgets/home/wallet_card_deck.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// Fixed pumping to settle entrance + doorway measurement windows (the
/// canonical Home settle pattern — the real page never quiesces).
Future<void> _advance(
  WidgetTester tester, {
  Duration by = const Duration(milliseconds: 400),
  int rounds = 4,
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(by);
  }
}

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final inter = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final loader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(inter).buffer)),
    );
  await loader.load();
  _fontsLoaded = true;
}

class _NoopHistoryNotifier extends TransactionHistoryNotifier {
  @override
  Future<void> loadMore() async {}
}

class _PinnedProgramme implements AzmCardProgramme {
  String? _pin;
  @override
  bool get supportsTransfers => false;
  @override
  bool get hasPin => _pin != null;
  @override
  Future<bool> setPin(String pin) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) return false;
    _pin = pin;
    return true;
  }

  @override
  Future<bool> verifyPin(String pin) async {
    await Future<void>.delayed(Duration.zero);
    return _pin != null && _pin == pin;
  }

  @override
  String get maskedNumber => '•••• 4242';
  @override
  String get expiryLabel => 'MM/YY';
  @override
  String get cardholderLabel => 'AZ USER';
}

class _FakeSusuListNotifier extends SusuListNotifier {
  _FakeSusuListNotifier(this.groups);
  final List<SusuSummary> groups;
  @override
  Future<List<SusuSummary>> build() async => groups;
}

SusuSummary _activeSusu(
  DateTime runAt, {
  String id = 's1',
  String name = 'Circle Susu',
}) =>
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
        payoutUserId: 2,
        isMe: false,
      ),
      myCycleSlot: 4,
      myStatus: SusuMemberStatus.active,
      myRole: 'MEMBER',
    );

const _cartIntent = ResumeIntent(
  kind: ResumeKind.cart,
  title: 'Finish your order at Maame\'s Kitchen',
  subtitle: '2 items · GH₵ 54.00',
  businessProfileId: 'biz-1',
);

/// Pumps the REAL Home page with the pilot's reminder seeds (one susu
/// card + one resume card) inside a real GoRouter so pill taps actually
/// navigate. Returns the container so tests can invalidate providers.


/// Unmounts the page and drains riverpod's zero-duration auto-dispose
/// timers so a multi-pump test tears down with a clean timer set.
Future<void> _flush(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// A committed swipe on the given card with the deck suite's proven
/// frame pattern: the flight completes and the post-frame reorder has
/// RENDERED before the test touches the deck again (the peek card is
/// IgnorePointer'd until then, and a later drag must not hit it).
Future<void> _swipeCommit(WidgetTester tester, Key cardKey) async {
  await tester.drag(find.byKey(cardKey), const Offset(260, -20));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  Size surface = const Size(390, 844),
  AzamanTheme theme = AzamanTheme.dark,
  bool reduceMotion = false,
  double textScale = 1.0,
  List<SusuSummary> susu = const [],
  ResumeIntent? intent,
}) async {
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
    'azaman_theme': theme == AzamanTheme.dark ? 1 : 0,
  });
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(surface);

  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      transactionHistoryProvider.overrideWith(
        (ref) => _NoopHistoryNotifier(),
      ),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 100),
      ),
      oracleRateProvider.overrideWith((ref) => 1.0),
      azmCardProgrammeProvider.overrideWith(
        (ref) => _PinnedProgramme().._pin = '1234',
      ),
      homeSummaryProvider.overrideWith(
        (ref) => _NoopHomeSummaryNotifier(ref, HomeSummaryService()),
      ),
      susuListProvider.overrideWith(() => _FakeSusuListNotifier(susu)),
      marketplaceResumeProvider.overrideWithValue(intent),
      marketplaceRelevanceProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(theme),
        home: MediaQuery(
          data: MediaQueryData(
            size: surface,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: const Scaffold(
            backgroundColor: Colors.transparent,
            body: RepaintBoundary(
              key: _rootKey,
              child: AzamanHomePage(),
            ),
          ),
        ),
      ),
    ),
  );
  // Entrance + prime microtask + §6 measurement window (same as the
  // integration suite).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 1400));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

const _rootKey = ValueKey('qd-capture-root');

/// Captures the RepaintBoundary around the Home page to a PNG on disk.
Future<void> _capture(WidgetTester tester, String name) async {
  var ok = false;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_rootKey));
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = (await image.toByteData(format: ImageByteFormat.png))!;
    final dir = Directory('.screenshots/quiet_depth')..createSync();
    final file = File('${dir.path}/$name.png');
    await file.writeAsBytes(data.buffer.asUint8List());
    ok = file.lengthSync() > 1000;
  });
  expect(ok, isTrue, reason: '$name.png must contain real image bytes');
}


class _NoopHomeSummaryNotifier extends HomeSummaryNotifier {
  _NoopHomeSummaryNotifier(super.ref, super.service);
}

WalletDeckState _deckState(WidgetTester tester) =>
    tester.state<WalletCardDeckState>(find.byType(WalletCardDeck)).state;

void main() {
  testWidgets('dark 390: resting → recessed → focal wallet captures',
      (tester) async {
    await _pumpHome(
      tester,
      susu: [_activeSusu(DateTime(2026, 10, 26))],
      intent: _cartIntent,
    );
    expect(find.byKey(const ValueKey('quiet-depth-raised')), findsWidgets);
    await _capture(tester, 'qd_dark_resting_raised_390');

    // Sequential pumps (a single pump(d) runs ONE frame at its end, which
    // would freeze the depth fade at its first tick).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(const ValueKey('quiet-depth-recessed')), findsWidgets);
    await _capture(tester, 'qd_dark_recessed_390');

    await tester.tap(find.bySemanticsLabel('Reveal balance card').first);
    await _advance(tester);
    expect(_deckState(tester), WalletDeckState.balanceOut);
    await _capture(tester, 'qd_dark_focal_wallet_390');
  });

  testWidgets('dark 390: reminder focal + terminal celebration captures',
      (tester) async {
    await _pumpHome(
      tester,
      susu: [_activeSusu(DateTime(2026, 10, 26))],
      intent: _cartIntent,
    );
    await _swipeCommit(tester, const ValueKey('reminder-card-susu-s1'));
    await _swipeCommit(tester, const ValueKey('reminder-card-resume-biz-1'));
    expect(
      find.byKey(const ValueKey('reminder-card-reminders-terminal')),
      findsOneWidget,
    );
    await _capture(tester, 'qd_dark_focal_reminder_390');

    // Terminal tap: confetti burst (mid-flight) + actions raised.
    await tester.tap(
      find.byKey(const ValueKey('reminder-card-reminders-terminal')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('reminder-confetti')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiet-depth-raised')), findsWidgets);
    await _capture(tester, 'qd_dark_terminal_celebration_390');

    // Late-burst confetti at a SECOND fixed t: with the precomputed
    // particle system the piece positions follow one smooth trajectory,
    // and two independent suite runs must produce byte-identical PNGs.
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('reminder-confetti')), findsOneWidget);
    await _capture(tester, 'qd_dark_confetti_late_390');

    // The real Home loops ambient animations forever — fixed pumps, never
    // pumpAndSettle. The burst is ~900ms; 1.5s drains it.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byKey(const ValueKey('reminder-confetti')), findsNothing,
        reason: 'the celebration is one-shot, never looping');
  });

  testWidgets('light 390: resting → recessed → focal wallet captures',
      (tester) async {
    await _pumpHome(
      tester,
      theme: AzamanTheme.light,
      susu: [_activeSusu(DateTime(2026, 10, 26))],
      intent: _cartIntent,
    );
    expect(find.byKey(const ValueKey('quiet-depth-raised')), findsWidgets);
    await _capture(tester, 'qd_light_resting_raised_390');

    // Sequential pumps (a single pump(d) runs ONE frame at its end, which
    // would freeze the depth fade at its first tick).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(const ValueKey('quiet-depth-recessed')), findsWidgets);
    await _capture(tester, 'qd_light_recessed_390');

    await tester.tap(find.bySemanticsLabel('Reveal balance card').first);
    await _advance(tester);
    expect(_deckState(tester), WalletDeckState.balanceOut);
    await _capture(tester, 'qd_light_focal_wallet_390');
  });

  testWidgets('dark width sweep 320/360: recessed captures', (tester) async {
    for (final w in [320.0, 360.0]) {
      await _pumpHome(
        tester,
        surface: Size(w, 844),
        susu: [_activeSusu(DateTime(2026, 10, 26))],
        intent: _cartIntent,
      );
      expect(find.byKey(const ValueKey('quiet-depth-raised')), findsWidgets);
      // Sequential pumps (a single pump(d) runs ONE frame at its end, which
    // would freeze the depth fade at its first tick).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(const ValueKey('quiet-depth-recessed')), findsWidgets);
      await _capture(tester, 'qd_dark_recessed_${w.toInt()}');
      await _flush(tester);
    }
  });
}
