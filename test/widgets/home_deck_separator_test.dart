// =============================================================================
// PR #142 VISUAL PASS (2026-10-06) — the Home deck separator.
//
// Laws pinned here:
//   • a small premium section separator (centered gray label, hairlines
//     fading outward) renders immediately ABOVE the reminder cards
//   • it lives INSIDE the deck, so it collapses with the deck when there
//     are no real signals — never a stranded label above empty space
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/home_deck_separator.dart';
import 'package:azaman/widgets/home/home_reminder_deck.dart';

const _surfaceSize = Size(400, 900);

class _FakeSusuListNotifier extends SusuListNotifier {
  _FakeSusuListNotifier(this.groups);
  final List<SusuSummary> groups;
  @override
  Future<List<SusuSummary>> build() async => groups;
}

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

Future<void> _pumpDeck(WidgetTester tester, {List<SusuSummary> susu = const []}) async {
  await tester.binding.setSurfaceSize(_surfaceSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        susuListProvider.overrideWith(() => _FakeSusuListNotifier(susu)),
      ],
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: MediaQuery(
          data: const MediaQueryData(size: _surfaceSize),
          child: const Scaffold(body: HomeReminderDeck()),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('with real signals: the separator renders immediately above '
      'the cards — quiet label, fading hairlines', (tester) async {
    final runAt = DateTime.now().add(const Duration(days: 2));
    await _pumpDeck(tester, susu: [_activeSusu(runAt)]);

    expect(find.byType(HomeDeckSeparator), findsOneWidget);
    expect(find.text('Reminders'), findsOneWidget);

    // Quiet by construction: the label is SMALL (≤12) and gray-tier, never
    // a heading.
    final style = tester.widget<Text>(find.text('Reminders')).style!;
    expect(style.fontSize!, lessThanOrEqualTo(12));
    expect(style.decoration, TextDecoration.none);

    // Immediately ABOVE the cards: separator bottom < card top, and the
    // separator is inside the deck subtree (collapses with it).
    final card = tester.getRect(find.byKey(const ValueKey('reminder-card-susu-s1')));
    final sep = tester.getRect(find.byType(HomeDeckSeparator));
    expect(sep.bottom, lessThanOrEqualTo(card.top + 1));
  });

  testWidgets('with NO real signals: the separator stays above the '
      'PLACEHOLDER deck — never stranded, never blank', (tester) async {
    await _pumpDeck(tester);
    // PLACEHOLDER PASS (owner direction): the slot is never blank, so the
    // separator is never stranded above nothing — it labels the honest
    // placeholder exactly as it labels the living deck.
    expect(find.byKey(const ValueKey('reminder-deck-placeholder')),
        findsOneWidget);
    expect(find.byType(HomeDeckSeparator), findsOneWidget);
    expect(find.text('Reminders'), findsOneWidget);
    // Still immediately above the (placeholder) front card — the front
    // face is the last of the three fanned copies in the stack.
    final card = tester
        .getRect(find.byKey(const ValueKey('reminder-card-placeholder')).last);
    final sep = tester.getRect(find.byType(HomeDeckSeparator));
    expect(sep.bottom, lessThanOrEqualTo(card.top + 1));
  });
}
