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

import 'package:azaman/experience/demo/demo_guard.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/marketplace_relevance_provider.dart';
import 'package:azaman/providers/marketplace_resume_provider.dart';
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


/// PR #142 close-out — a REAL relevance signal (real business, real category).
const _relevance = MarketplaceRelevance(
  worldWire: 'FOOD_BEVERAGE',
  categoryLabel: 'Restaurants',
  business: BusinessProfile(
    id: 'biz-rel-1',
    bizId: 'BIZ-rel1',
    businessName: 'Auntie Muni',
    category: 'FOOD_BEVERAGE',
    isVerified: true,
    isSuspended: false,
    kybStatus: 'VERIFIED',
    totalEscrows: 5,
    completedEscrows: 5,
    userId: 7,
    totalVolume: 900,
    averageRating: 4.6,
    username: 'auntie-muni',
  ),
);

Future<void> _pumpDeck(
  WidgetTester tester, {
  List<SusuSummary> susu = const [],
  ResumeIntent? intent,
  MarketplaceRelevance? relevance,
  bool reduceMotion = false,
}) async {
  await tester.binding.setSurfaceSize(_surfaceSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        susuListProvider.overrideWith(
            () => _FakeSusuListNotifier(susu)),
        marketplaceResumeProvider.overrideWithValue(intent),
        marketplaceRelevanceProvider.overrideWithValue(relevance),
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

/// The pagination-dot keys (pass B3): one per REAL card, in rail order.
Iterable<Key> _dotKeys(WidgetTester tester) => tester
    .widgetList<Container>(
      find.byWidgetPredicate((w) =>
          w is Container &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('reminder-deck-dot-')),
    )
    .map((c) => c.key!);

void main() {
  testWidgets('§4 — no legitimate signal: the deck collapses out of the '
      'layout cleanly (pass D — production never fabricates reminders)',
      (tester) async {
    await _pumpDeck(tester, susu: [_inactiveSusu('d1')], intent: null);
    // PASS D — truthfulness: no placeholder fan, no fabricated copy, no
    // ghost slots pretending content exists behind nothing.
    expect(find.text('Your reminders will appear here'), findsNothing);
    expect(find.text('REMINDERS'), findsNothing);
    expect(find.byKey(const ValueKey('reminder-ghost')), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    // The collapse stub renders zero height — the slot is simply gone.
    final stub = tester
        .element(find.byKey(const ValueKey('reminder-deck-empty')))
        .findRenderObject() as RenderBox;
    expect(stub.size.height, 0);
    expect(stub.size.width, 0);
  });

  testWidgets('§4 — demo build: a signal-less deck seeds from the demo '
      'data (real builds never see a seeded card)', (tester) async {
    DemoGuard.override(true);
    addTearDown(() => DemoGuard.override(null));
    await _pumpDeck(tester, susu: [_inactiveSusu('d1')], intent: null);
    expect(find.text('Susu Circle - August'), findsOneWidget);
    expect(find.text("Chef Abby's"), findsOneWidget);
    // PASS B — the visual stack shows hero + ONE peek edge: only two
    // cards are MOUNTED; the third lives in the order (never a fan of
    // stale cards). The dot rail carries one dot per REAL card (3).
    expect(find.byKey(const ValueKey('reminder-ghost')), findsNothing);
    expect(find.text('Coastline Suites'), findsNothing,
        reason: 'the third card stays virtual until the deck advances');
    expect(_dotKeys(tester).length, 3);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
  });

  testWidgets('pass B5 — the deck geometry is FIXED: hero 96, one 16px '
      'peek, a 12px dot rail, band 132 + the 26px PR #142 separator '
      '(158 total) on any screen', (tester) async {
    await _pumpDeck(
      tester,
      susu: [ _activeSusu(DateTime(2026, 10, 12), id: 's1', name: 'Circle Susu') ],
      intent: _cartIntent,
    );

    // The band is a constant: hero + peek + dots gap + dot rail = 132.
    // The PR #142 visual pass adds the fixed 26px section separator above
    // it (inside the deck, collapsing with it) → deck total = 158.
    final deckSize = tester.getSize(find.byType(HomeReminderDeck));
    expect(deckSize.height, 132 + homeDeckSeparatorHeight);
    expect(deckSize.height, 158);

    final front = tester.getSize(
        find.byKey(const ValueKey('reminder-card-susu-s1')));
    expect(front.height, 96,
        reason: 'the hero card is fully readable at the fixed height');

    // PASS B2 — exactly ONE peek edge behind the hero, at the 16px step.
    // Three cards exist, but the stack shows only the next edge.
    final tops = tester
        .widgetList<Positioned>(find.byWidgetPredicate(
            (w) => w is Positioned && w.top != null))
        .map((p) => p.top)
        .toSet();
    expect(tops, <double?>{0.0, 16.0},
        reason: 'front at 0, the single peek at 16 — never a fan');

    // PASS B3 — the dot rail carries one dot per real card (2: the susu
    // hero + the marketplace peek), the active dot tracking the front.
    expect(_dotKeys(tester).length, 2);
    final active = tester.widget<Container>(
        find.byKey(const ValueKey('reminder-deck-dot-0')));
    final rest = tester.widget<Container>(
        find.byKey(const ValueKey('reminder-deck-dot-1')));
    expect((active.decoration as BoxDecoration).color,
        isNot((rest.decoration as BoxDecoration).color),
        reason: 'the active dot must read distinct from the rest');
  });

  testWidgets('pass B1 — the front card is STRAIGHT at rest: no tilt, no '
      'scale, no rotation (the readable hero)', (tester) async {
    await _pumpDeck(tester,
        susu: [ _activeSusu(DateTime(2026, 10, 12), id: 's1', name: 'Circle Susu') ],
        intent: _cartIntent);

    // At rest the front card carries an IDENTITY transform — straight,
    // scale 1.0, rotation 0: nothing is rotated while the user reads.
    final transforms =
        tester.widgetList<Transform>(find.descendant(
            of: find.byKey(const ValueKey('reminder-card-susu-s1')),
            matching: find.byType(Transform)));
    for (final t in transforms) {
      expect(t.transform.isIdentity(), isTrue,
          reason: 'the resting hero must be straight (pass B1)');
    }

    // One peek edge exists and one dot per card (2 cards, 2 dots).
    expect(_dotKeys(tester).length, 2);
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

  testWidgets('relevance — a real business in a visited category renders '
      'honestly, with no fabricated newness claim', (tester) async {
    await _pumpDeck(tester, relevance: _relevance);
    expect(find.text('MARKETPLACE'), findsOneWidget);
    expect(find.text('Auntie Muni'), findsOneWidget);
    expect(find.text('Relevant in Restaurants'), findsOneWidget);
    // Relevance, never "new" — the data model has no trustworthy newness.
    expect(find.textContaining(RegExp(r'\bnew\b', caseSensitive: false)),
        findsNothing);
    expect(_cardKeys(tester), [const ValueKey('reminder-card-relevance-biz-rel-1')]);
  });

  testWidgets('relevance — suppressed when the resume card already speaks '
      'for the same world (one memory, one card)', (tester) async {
    await _pumpDeck(
      tester,
      intent: const ResumeIntent(
        kind: ResumeKind.worldSearch,
        title: 'Back to "jollof"',
        subtitle: 'in Restaurants',
        worldWire: 'FOOD_BEVERAGE',
      ),
      relevance: _relevance,
    );
    expect(find.text('Back to "jollof"'), findsOneWidget);
    expect(find.text('Auntie Muni'), findsNothing);
  });

  testWidgets('relevance — coexists with a different-world resume card',
      (tester) async {
    await _pumpDeck(
      tester,
      intent: const ResumeIntent(
        kind: ResumeKind.worldSearch,
        title: 'Back to "sneakers"',
        subtitle: 'in Retail',
        worldWire: 'RETAIL',
      ),
      relevance: _relevance,
    );
    expect(find.text('Back to "sneakers"'), findsOneWidget);
    expect(find.text('Auntie Muni'), findsOneWidget);
    expect(_cardKeys(tester).length, 2);
  });

  testWidgets('relevance — participates in the shuffle: committed swipe '
      'rotates the deck, nothing is deleted', (tester) async {
    await _pumpDeck(tester, relevance: _relevance);

    final before = _cardKeys(tester).toList();
    expect(before.length, 1);

    await tester.drag(
        find.byKey(const ValueKey('reminder-card-relevance-biz-rel-1')),
        const Offset(260, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // Single-card deck: the shuffle keeps the same card (nothing deleted).
    final after = _cardKeys(tester).toSet();
    expect(after, equals(before.toSet()));
  });

  testWidgets('relevance — participates in the multi-card shuffle with the '
      'susu card', (tester) async {
    await _pumpDeck(
      tester,
      susu: [_activeSusu(DateTime(2026, 10, 12), id: 's1', name: 'Circle Susu')],
      relevance: _relevance,
    );

    final before = _cardKeys(tester).toList();
    expect(before.length, 2);
    expect(before.last, const ValueKey('reminder-card-susu-s1'));

    await tester.drag(
        find.byKey(const ValueKey('reminder-card-susu-s1')),
        const Offset(260, -20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    final after = _cardKeys(tester).toSet();
    expect(after.length, 2);
    expect(after, equals(before.toSet()));
    // Front rotated to the relevance card — same deck, same system.
    expect(_cardKeys(tester).toList().last,
        const ValueKey('reminder-card-relevance-biz-rel-1'));
  });

  testWidgets('relevance — reduced motion: a committed swipe reorders '
      'instantly', (tester) async {
    await _pumpDeck(
      tester,
      reduceMotion: true,
      susu: [_activeSusu(DateTime(2026, 10, 12), id: 's1', name: 'Circle Susu')],
      relevance: _relevance,
    );

    await tester.drag(
        find.byKey(const ValueKey('reminder-card-susu-s1')),
        const Offset(260, 0));
    await tester.pump();

    final orderAfter = _cardKeys(tester).toList();
    expect(orderAfter.length, 2);
    expect(orderAfter.last,
        const ValueKey('reminder-card-relevance-biz-rel-1'));
  });

  testWidgets('relevance — the semantics action advances a deck that '
      'contains the relevance card', (tester) async {
    await _pumpDeck(
      tester,
      susu: [_activeSusu(DateTime(2026, 10, 12), id: 's1', name: 'Circle Susu')],
      relevance: _relevance,
    );

    final labels = tester
        .widgetList<Semantics>(find.descendant(
            of: find.byType(HomeReminderDeck),
            matching: find.byType(Semantics)))
        .expand((s) => s.properties.customSemanticsActions?.keys ?? const <CustomSemanticsAction>{})
        .map((a) => a.label ?? '')
        .toList();
    expect(labels, contains('Next reminder'));
  });
}
