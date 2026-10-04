// =============================================================================
// EXPERIENCE PASS §4 + §5 — the Home reminder deck.
//
// §4: cards come from REAL signals only (susuListProvider,
// marketplaceResumeProvider). No signal → the deck does not render, and
// the copy never claims anything the data does not say.
// §5: a committed swipe SHUFFLES the deck (curved flight, order
// rotation, nothing deleted). Reduced motion: instant reorder/settle.
// Accessibility: a custom semantics action advances the deck without a
// swipe.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/marketplace_resume_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/home_reminder_deck.dart';

const _surfaceSize = Size(400, 900);

class _FakeSusuListNotifier extends SusuListNotifier {
  _FakeSusuListNotifier(this.groups);
  final List<SusuSummary> groups;
  @override
  Future<List<SusuSummary>> build() async => groups;
}

SusuSummary _activeSusu(DateTime runAt,
        {String id = 's1',
        String name = 'Circle Susu',
        bool payoutToMe = false}) =>
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
        payoutUserId: payoutToMe ? 1 : 2,
        isMe: payoutToMe,
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

const _cartIntent = ResumeIntent(
  kind: ResumeKind.cart,
  title: 'Finish your order at Maame\'s Kitchen',
  subtitle: '2 items · GH₵ 54.00',
  businessProfileId: 'biz-1',
);

Future<void> _pumpDeck(
  WidgetTester tester, {
  List<SusuSummary> susu = const [],
  ResumeIntent? intent,
  bool reduceMotion = false,
}) async {
  await tester.binding.setSurfaceSize(_surfaceSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        susuListProvider.overrideWith(
            () => _FakeSusuListNotifier(susu)),
        marketplaceResumeProvider.overrideWithValue(intent),
      ],
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: MediaQuery(
          data: MediaQueryData(
            size: _surfaceSize,
            disableAnimations: reduceMotion,
          ),
          child: const Scaffold(body: HomeReminderDeck()),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The reminder-card keys, in tree order. The FRONT card is always the
/// last Stack child at rest, so tree order = [behind..., front].
Iterable<Key> _cardKeys(WidgetTester tester) => tester
    .widgetList<Container>(
      find.byWidgetPredicate((w) =>
          w is Container &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('reminder-card-')),
    )
    .map((c) => c.key!);

void main() {
  testWidgets('§4 — no legitimate signal: the deck renders NOTHING',
      (tester) async {
    await _pumpDeck(tester, susu: [_inactiveSusu('d1')], intent: null);
    expect(find.text('SUSU'), findsNothing);
    expect(find.text('MARKETPLACE'), findsNothing);
    expect(_cardKeys(tester), isEmpty);
  });

  testWidgets('§4 — the SOONEST pending susu cycle is the one shown, with '
      'honest copy', (tester) async {
    await _pumpDeck(tester, susu: [
      _activeSusu(DateTime(2026, 10, 12), id: 'early', name: 'Early Susu'),
      _activeSusu(DateTime(2026, 11, 1), id: 'late', name: 'Late Susu'),
      _inactiveSusu('done'),
    ]);
    expect(find.text('Susu contribution due Oct 12'), findsOneWidget);
    expect(find.text('Early Susu'), findsOneWidget);
    // The later cycle and the dormant group do NOT earn a card.
    expect(find.text('Late Susu'), findsNothing);
    expect(find.text('Dormant Susu'), findsNothing);
  });

  testWidgets('§4 — when the cycle pays out to ME, the copy says so',
      (tester) async {
    await _pumpDeck(tester,
        susu: [_activeSusu(DateTime(2026, 10, 12),
            id: 'mine', name: 'My Payout', payoutToMe: true)]);
    expect(find.text('Your payout cycle runs Oct 12'), findsOneWidget);
    expect(find.text('Susu contribution due Oct 12'), findsNothing);
  });

  testWidgets('§4 — the marketplace resume intent is a real-signal card',
      (tester) async {
    await _pumpDeck(tester, intent: _cartIntent);
    expect(find.text('MARKETPLACE'), findsOneWidget);
    expect(find.text('Finish your order at Maame\'s Kitchen'), findsOneWidget);
    expect(find.text('2 items · GH₵ 54.00'), findsOneWidget);
  });

  testWidgets('§5 — a committed swipe SHUFFLES: order rotates, nothing is '
      'deleted', (tester) async {
    await _pumpDeck(tester, susu: [
      _activeSusu(DateTime(2026, 10, 12), id: 's1', name: 'Circle Susu'),
    ], intent: _cartIntent);

    final before = _cardKeys(tester).toList();
    expect(before.length, 2);
    // Front = last in tree = the susu card.
    expect(before.last, const ValueKey('reminder-card-susu-s1'));

    // Committed swipe on the front card.
    await tester.drag(
        find.byKey(const ValueKey('reminder-card-susu-s1')),
        const Offset(260, -20));
    await tester.pump(); // flight frames
    await tester.pump(const Duration(milliseconds: 500)); // flight completes
    await tester.pump(); // post-frame reorder

    // Both cards still exist (shuffle, not delete)…
    final after = _cardKeys(tester).toSet();
    expect(after.length, 2);
    expect(after, equals(before.toSet()));
    // …and the front card is now the marketplace one.
    final orderAfter = _cardKeys(tester).toList();
    expect(orderAfter.last, const ValueKey(
        'reminder-card-resume-biz-1'));
  });

  testWidgets('§5 — an under-threshold swipe settles back, order unchanged',
      (tester) async {
    await _pumpDeck(tester, susu: [
      _activeSusu(DateTime(2026, 10, 12), id: 's1', name: 'Circle Susu'),
    ], intent: _cartIntent);

    // A short, slow drag never reaches the commit threshold.
    final gesture = await tester.startGesture(tester
        .getCenter(find.byKey(const ValueKey('reminder-card-susu-s1'))));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    final orderAfter = _cardKeys(tester).toList();
    expect(orderAfter.last, const ValueKey('reminder-card-susu-s1'));
  });

  testWidgets('§5 — reduced motion: instant reorder, no expressive travel',
      (tester) async {
    await _pumpDeck(
      tester,
      reduceMotion: true,
      susu: [_activeSusu(DateTime(2026, 10, 12),
          id: 's1', name: 'Circle Susu')],
      intent: _cartIntent,
    );

    await tester.drag(
        find.byKey(const ValueKey('reminder-card-susu-s1')),
        const Offset(260, 0));
    await tester.pump();

    // Instant: no pending flight frames — the order already advanced.
    final orderAfter = _cardKeys(tester).toList();
    expect(orderAfter.length, 2);
    expect(orderAfter.last, const ValueKey('reminder-card-resume-biz-1'));
  });

  testWidgets('accessibility — the deck exposes a semantics action to '
      'advance without a swipe', (tester) async {
    await _pumpDeck(tester, susu: [
      _activeSusu(DateTime(2026, 10, 12), id: 's1', name: 'Circle Susu'),
    ], intent: _cartIntent);

    final labels = tester
        .widgetList<Semantics>(find.descendant(
            of: find.byType(HomeReminderDeck),
            matching: find.byType(Semantics)))
        .expand((s) => s.properties.customSemanticsActions?.keys ?? const <CustomSemanticsAction>{})
        .map((a) => a.label ?? '')
        .toList();
    expect(labels, contains('Next reminder'));
  });

  testWidgets('single signal — one honest card, no deck affordance',
      (tester) async {
    await _pumpDeck(tester,
        susu: [_activeSusu(DateTime(2026, 10, 12), id: 's1')]);
    expect(_cardKeys(tester).length, 1);
    // No advance action when there is nothing to shuffle to.
    final sem = tester.widgetList<Semantics>(find.descendant(
        of: find.byType(HomeReminderDeck),
        matching: find.byType(Semantics)));
    for (final s in sem) {
      expect(s.properties.customSemanticsActions, isNull);
    }
  });
}
