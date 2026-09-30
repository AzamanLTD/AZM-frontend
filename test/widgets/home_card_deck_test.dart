// NEW-HOME §4 — the pull-reveal card deck contract.
//
// The deck is NOT a PageView: it needs resistance (small movement reveals
// only slightly), a deliberate commit threshold, a spring snap on commit,
// one threshold haptic, the same grammar in reverse, and reduced-motion
// direct transitions. The physics are pure and unit-tested; the gesture
// feel is pinned at the widget layer via the bottom card's laid-out
// position.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/home/pull_reveal_card_deck.dart';

const _surface = Size(400, 900);
const _deckKey = Key('home-card-deck');

Future<void> _pumpDeck(
  WidgetTester tester, {
  bool reducedMotion = false,
  ValueChanged<bool>? onRevealChanged,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: _surface)
          .copyWith(disableAnimations: reducedMotion),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: PullRevealCardDeck(
              key: _deckKey,
              cardHeight: 180,
              onRevealChanged: onRevealChanged,
              topCard: Container(
                key: const Key('deck-top'),
                color: const Color(0xFF111111),
              ),
              bottomCard: Container(
                key: const Key('deck-bottom'),
                color: const Color(0xFF444444),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _bottomTop(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const Key('deck-bottom'))).dy;
double _topTop(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const Key('deck-top'))).dy;

void main() {
  group('PullRevealPhysics (pure)', () {
    test('resistance: small movement reveals only slightly', () {
      // A quarter of the drag travel maps to a SIXTEENTH of the reveal —
      // the deck pushes back early.
      expect(PullRevealPhysics.revealFor(0.25), closeTo(0.0625, 1e-9));
      expect(PullRevealPhysics.revealFor(0.25),
          lessThan(0.25),
          reason: 'reveal must lag the drag (resistance)');
    });

    test('progress clamps to [0, 1]', () {
      expect(PullRevealPhysics.progressFor(-50), 0);
      expect(PullRevealPhysics.progressFor(0), 0);
      expect(
          PullRevealPhysics.progressFor(PullRevealPhysics.travelPx * 3), 1.0);
    });

    test('commit threshold is deliberate — accidental micro-drags never '
        'open the card', () {
      expect(PullRevealPhysics.commits(0.1), isFalse);
      expect(PullRevealPhysics.commits(0.3), isFalse);
      expect(PullRevealPhysics.commits(0.5), isFalse);
      expect(PullRevealPhysics.commits(PullRevealPhysics.commitThreshold),
          isTrue);
      expect(PullRevealPhysics.commits(1.0), isTrue);
    });
  });

  group('PullRevealCardDeck widget — the physical gesture feel', () {
    testWidgets('resting state: the bottom card peeks beneath the hero',
        (tester) async {
      await _pumpDeck(tester);

      final peek = PullRevealPhysics.restPeekPx;
      final heroTop = _topTop(tester);
      final bottomTop = _bottomTop(tester);
      // The hero is fully visible; the Visa card sits directly under it
      // with exactly the intended peek visible.
      expect(bottomTop - heroTop, 180 - peek);
    });

    testWidgets('a micro-drag reveals only slightly and returns to rest',
        (tester) async {
      var commits = 0;
      await _pumpDeck(tester, onRevealChanged: (r) {
        if (r) commits++;
      });
      final restBottom = _bottomTop(tester);

      // 15px pull — an accidental micro-drag.
      await tester.drag(
          find.byKey(_deckKey), const Offset(0, -15));
      await tester.pump();
      final midPull = _bottomTop(tester);
      expect(midPull, lessThan(restBottom),
          reason: 'the pull must reveal the card slightly');

      // Releasing below the threshold returns the deck to rest.
      await tester.pumpAndSettle();
      expect(_bottomTop(tester), closeTo(restBottom, 0.5));
      expect(commits, 0, reason: 'no commit may fire below the threshold');
    });

    testWidgets('crossing the threshold commits: the Visa card snaps into '
        'place', (tester) async {
      final events = <bool>[];
      await _pumpDeck(tester, onRevealChanged: events.add);
      final heroTop = _topTop(tester);

      // Pull past the threshold (travel 150 · threshold 0.55 → ~83px; 160px
      // is a deliberate full pull).
      await tester.drag(
          find.byKey(_deckKey), const Offset(0, -160));
      await tester.pumpAndSettle();

      expect(events, [true], reason: 'exactly one commit event');
      // The Visa card now occupies the hero's slot (snapped into place).
      expect(_bottomTop(tester), closeTo(heroTop, 0.5));
    });

    testWidgets('pulled back: the same grammar in reverse returns safely',
        (tester) async {
      final events = <bool>[];
      await _pumpDeck(tester, onRevealChanged: events.add);

      // Commit first.
      await tester.drag(
          find.byKey(_deckKey), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(events, [true]);

      final restBottom =
          _bottomTop(tester) + 180 - PullRevealPhysics.restPeekPx;

      // Pull back down past the threshold and release: collapse.
      await tester.drag(find.byKey(_deckKey), const Offset(0, 160));
      await tester.pumpAndSettle();

      expect(events, [true, false], reason: 'the collapse reports once');
      expect(_bottomTop(tester), closeTo(restBottom, 0.5),
          reason: 'the deck returns to its resting peek');
    });

    testWidgets('reduced motion: no spring traversal, direct transition',
        (tester) async {
      await _pumpDeck(tester, reducedMotion: true);
      final heroTop = _topTop(tester);

      await tester.drag(
          find.byKey(_deckKey), const Offset(0, -160));
      // ONE pump — under reduced motion the commit must land directly on
      // the final state; a spring would need many.
      await tester.pump();

      expect(_bottomTop(tester), closeTo(heroTop, 0.5),
          reason: 'reduced motion commits without spring traversal');
      await tester.pump(const Duration(milliseconds: 50));
      expect(_bottomTop(tester), closeTo(heroTop, 0.5));
    });
  });
}
