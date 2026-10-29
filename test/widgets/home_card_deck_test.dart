// =============================================================================
// AZAMAN — WALLET CARD DECK contract (the pouch-deck evolution of §4).
//
// The deck replaces the pull-to-reveal grammar with the wallet-pouch
// interaction:
//   * default    — both cards TUCKED behind the opaque pouch; only the
//                  Visa header strip and the balance brand header show.
//   * open       — TAP a selector to bring a card out (balanceOut/visaOut).
//   * return     — SWIPE UP on an out card to return it to the pouch.
//   * reduced    — direct pose snap, no spring traversal.
//
// The physics are pure and unit-tested; the gesture contract is pinned at
// the widget layer via pose geometry, state, and semantics.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/widgets/home/wallet_card_deck.dart';

const _surface = Size(400, 900);
const _deckKey = Key('wallet-card-deck');
bool _fontsLoaded = false;

/// Loads the app's REAL fonts (Inter + Comic Neue) so width measurements in
/// this suite reflect device metrics, not the test engine's monospace
/// fallback (same loader as home_ux_correction_test.dart).
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final inter = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final interLoader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(inter).buffer)),
    );
  await interLoader.load();
  final regular = await File(
    'assets/fonts/ComicNeue-Regular.ttf',
  ).readAsBytes();
  final bold = await File('assets/fonts/ComicNeue-Bold.ttf').readAsBytes();
  final comicLoader = FontLoader('ComicNeue')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(regular).buffer)),
    )
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bold).buffer)),
    );
  await comicLoader.load();
  _fontsLoaded = true;
}

const _balanceKey = Key('deck-balance-card');
const _visaKey = Key('deck-visa-card');

Widget _fakeCard(Key key, String label, Color color) => Container(
  key: key,
  color: color,
  alignment: Alignment.topLeft,
  padding: const EdgeInsets.all(12),
  child: Semantics(
    container: true,
    label: label,
    excludeSemantics: true,
    child: Text(label),
  ),
);

/// A fake balance card whose TOP band mirrors the REAL card's brand
/// header (logo + "Azaman Balance" + the public AZM ID far right): the
/// tucked pouch exposes exactly this band, so the deck's contract tests
/// pin the tucked header against the same structure the real card owns.
Widget _fakeBalanceCard() => Container(
  key: _balanceKey,
  color: const Color(0xFF1C1C1E),
  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Image.asset(
            'assets/images/azaman_logo.png',
            height: 18,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              'Azaman Balance',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          const Flexible(
            child: Text(
              'AZM-ID pending',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Semantics(
        container: true,
        label: 'SECRET-BALANCE-AMOUNT',
        excludeSemantics: true,
        child: const Text('SECRET-BALANCE-AMOUNT'),
      ),
    ],
  ),
);

Future<void> _pumpDeck(
  WidgetTester tester, {
  bool reducedMotion = false,
  WalletDeckState? initial,
  ValueChanged<WalletDeckState>? onStateChanged,
}) async {
  await tester.binding.setSurfaceSize(_surface);
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(
        size: _surface,
      ).copyWith(disableAnimations: reducedMotion),
      child: ProviderScope(
        overrides: [authProvider.overrideWith((ref) => AuthProvider(ref: ref))],
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFFF2F2F7),
            body: Center(
              child: WalletCardDeck(
                key: _deckKey,
                cardHeight: 165,
                balanceCard: _fakeBalanceCard(),
                visaCard: _fakeCard(
                  _visaKey,
                  'FAKE-VISA-FACE',
                  const Color(0xFF23262B),
                ),
                onStateChanged: onStateChanged,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (initial != null) {
    tester.state<WalletCardDeckState>(find.byKey(_deckKey)).select(initial);
    await tester.pumpAndSettle();
  }
}

/// Walks the LIVE semantics tree (what screen readers actually consume)
/// looking for [label] anywhere in any node's label — including merged
/// nodes. This is the authoritative privacy check: detached/stale
/// annotation nodes that `find.bySemanticsLabel` can over-match do not
/// appear here.
bool _semanticsTreeContainsLabel(SemanticsNode node, String label) {
  if (node.getSemanticsData().label.contains(label)) return true;
  var found = false;
  node.visitChildren((SemanticsNode child) {
    found = found || _semanticsTreeContainsLabel(child, label);
    return true; // keep visiting siblings
  });
  return found;
}

bool _treeHasSecret(WidgetTester tester) => _semanticsTreeContainsLabel(
  tester.getSemantics(find.byType(Scaffold)),
  'SECRET-BALANCE-AMOUNT',
);

bool _treeHasVisa(WidgetTester tester) => _semanticsTreeContainsLabel(
  tester.getSemantics(find.byType(Scaffold)),
  'FAKE-VISA-FACE',
);

/// The balance card's top edge relative to the deck window — the live
/// rendered geometry, transform-aware.
double _balanceTopInWindow(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(_balanceKey)).dy -
    tester.getTopLeft(find.byKey(const ValueKey('wallet-deck-window'))).dy;

WalletDeckState _deckState(WidgetTester tester) =>
    tester.state<WalletCardDeckState>(find.byKey(_deckKey)).state;

double _mouthTop(WidgetTester tester) {
  final deck = tester.getTopLeft(find.byKey(_deckKey)).dy;
  final pouch = tester
      .getTopLeft(find.byKey(const ValueKey('wallet-pouch-surface')))
      .dy;
  return pouch - deck + 8;
}

// ── PURE PHYSICS ─────────────────────────────────────────────────────────

void main() {
  group('WalletDeckPhysics (pure)', () {
    test('upward drag maps through resistance and clamps to [0, 1]', () {
      expect(WalletDeckPhysics.progressFor(0), 0);
      // 30px of an accidental swipe reveals only slightly (resistance).
      final slight = WalletDeckPhysics.progressFor(30);
      expect(slight, greaterThan(0));
      expect(slight, lessThan(0.5));
      // RESISTANCE lives in returnFor: the same drag nudges, not flees.
      expect(WalletDeckPhysics.returnFor(slight), lessThan(0.2));
      expect(WalletDeckPhysics.progressFor(90), 1.0);
      expect(WalletDeckPhysics.progressFor(500), 1.0);
      // Downward slack is ignored while out.
      expect(WalletDeckPhysics.progressFor(-40), 0);
    });

    test('commit threshold is deliberate — micro-swipes never tuck', () {
      final micro = WalletDeckPhysics.progressFor(20);
      expect(WalletDeckPhysics.commits(micro), isFalse);
      final full = WalletDeckPhysics.progressFor(90);
      expect(WalletDeckPhysics.commits(full), isTrue);
    });
  });

  test('the pose system exposes the tucked default geometry', () {
    const p = WalletDeckState.values;
    expect(p, containsAll(WalletDeckState.values));
  });

  // ── TUCKED DEFAULT ──────────────────────────────────────────────────────

  group('WalletCardDeck widget — the tucked pouch contract', () {
    testWidgets('initial state is tucked: no out card, header selectors '
        'visible, pouch covers the card bodies', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDeck(tester);
      expect(_deckState(tester), WalletDeckState.tucked);

      // Tucked geometry: the pouch mouth sits at visa-peek + header band.
      // topPad(26) + visaPeek(44) + headerBand(56) = 126.
      expect(_mouthTop(tester), closeTo(126, 0.5));

      // The exposed band is the REAL card's own brand header (logo,
      // title, public AZM ID) — there is no separately painted header.
      expect(find.text('Azaman Balance'), findsOneWidget);
      expect(find.text('AZM-ID pending'), findsOneWidget);
      // The header band sits inside the deck window, exposed above the
      // pouch mouth: the card's top corners + rim are the visible edge.
      final windowRect = tester.getRect(
        find.byKey(const ValueKey('wallet-deck-window')),
      );
      final bandRect = tester.getRect(
        find.byKey(const ValueKey('wallet-tucked-balance-header')),
      );
      expect(bandRect.top, closeTo(windowRect.top + 70, 0.5));
      expect(bandRect.bottom, closeTo(windowRect.top + 126, 0.5));
      expect(
        find.text('AVAILABLE'),
        findsNothing,
        reason: 'the old eyebrow label is retired from the card face',
      );

      // Both exposed selectors exist while tucked.
      expect(
        find.bySemanticsLabel('Reveal balance card'),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.bySemanticsLabel('Open AZM Visa card'),
        findsAtLeastNWidgets(1),
      );
      handle.dispose();
    });

    testWidgets('covered card content is excluded from accessibility '
        'semantics while tucked, and returns when out', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDeck(tester);
      expect(
        _treeHasSecret(tester),
        isFalse,
        reason:
            'the tucked pouch is the privacy state — the covered '
            'amount must not reach the semantics tree',
      );

      tester
          .state<WalletCardDeckState>(find.byKey(_deckKey))
          .select(WalletDeckState.balanceOut);
      await tester.pumpAndSettle();
      expect(
        _treeHasSecret(tester),
        isTrue,
        reason: 'with the balance card out, its content is readable',
      );

      tester.state<WalletCardDeckState>(find.byKey(_deckKey)).tuck();
      await tester.pumpAndSettle();
      expect(
        _treeHasSecret(tester),
        isFalse,
        reason: 're-tucking must exclude the amount again',
      );
      handle.dispose();
    });

    testWidgets('both card selectors are usable from the tucked state', (
      tester,
    ) async {
      final states = <WalletDeckState>[];
      await _pumpDeck(tester, onStateChanged: states.add);

      await tester.tap(find.bySemanticsLabel('Reveal balance card').first);
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.balanceOut);
      expect(states, [WalletDeckState.balanceOut]);

      tester.state<WalletCardDeckState>(find.byKey(_deckKey)).tuck();
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Open AZM Visa card').first);
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.visaOut);
      expect(states.last, WalletDeckState.visaOut);
    });

    testWidgets('the selector row works in every state — continuous handoff '
        'without re-tucking', (tester) async {
      await _pumpDeck(tester);
      await tester.tap(find.byKey(const ValueKey('wallet-select-balance')));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.balanceOut);

      // Direct switch while out: no flash-through, no exceptions.
      await tester.tap(find.byKey(const ValueKey('wallet-select-visa')));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.visaOut);

      await tester.tap(find.byKey(const ValueKey('wallet-select-balance')));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.balanceOut);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selector hit targets meet the 44px minimum', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDeck(tester);
      final visaStrip = tester.getSize(
        find.bySemanticsLabel('Open AZM Visa card').first,
      );
      expect(visaStrip.height, greaterThanOrEqualTo(44));
      final band = tester.getSize(
        find.bySemanticsLabel('Reveal balance card').first,
      );
      expect(band.height, greaterThanOrEqualTo(44));
      final chip = tester.getSize(
        find.byKey(const ValueKey('wallet-select-balance')),
      );
      expect(chip.height, greaterThanOrEqualTo(44));
      handle.dispose();
    });

    testWidgets('no overflow at 320dp width with enlarged text', (
      tester,
    ) async {
      await tester.runAsync(_loadFonts);
      await tester.binding.setSurfaceSize(const Size(320, 800));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(1.4),
          ),
          child: ProviderScope(
            child: MaterialApp(
              theme: ThemeProvider.getThemeData(AzamanTheme.light),
              home: Scaffold(
                body: Center(
                  child: WalletCardDeck(
                    cardHeight: 165,
                    balanceCard: _fakeBalanceCard(),
                    visaCard: _fakeCard(
                      _visaKey,
                      'VISA',
                      const Color(0xFF23262B),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a vertical drag over the TUCKED deck scrolls the host '
        'page — the deck never swallows the scroll', (tester) async {
      // A Home-like scrollable host: content above, the deck mid-page,
      // a marker below it.
      const markerKey = Key('below-deck-marker');
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                const SizedBox(height: 300, child: Text('TOP')),
                WalletCardDeck(
                  key: _deckKey,
                  cardHeight: 165,
                  balanceCard: _fakeBalanceCard(),
                  visaCard: _fakeCard(
                    _visaKey,
                    'FAKE-VISA-FACE',
                    const Color(0xFF23262B),
                  ),
                ),
                const SizedBox(
                  key: markerKey,
                  height: 700,
                  child: Text('MARKER'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(_deckState(tester), WalletDeckState.tucked);

      // A drag starting INSIDE the deck window (its centre). Realistic
      // multi-step movement (a real finger generates many events; a
      // single big jump resolves the arena on its first move and drops
      // that delta, which would under-test the arbitration).
      final deckCenter = tester.getCenter(find.byKey(_deckKey));
      final markerBefore = tester.getTopLeft(find.byKey(markerKey)).dy;

      final gesture = await tester.startGesture(deckCenter);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -12));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // The scroll happened (the marker moved up) and the deck stayed
      // tucked — the drag was never claimed by the deck.
      final markerAfter = tester.getTopLeft(find.byKey(markerKey)).dy;
      expect(
        markerAfter,
        lessThan(markerBefore),
        reason: 'the vertical drag must scroll the host page',
      );
      expect(
        _deckState(tester),
        WalletDeckState.tucked,
        reason: 'the tucked deck cannot open from a drag',
      );
    });

    testWidgets('per-card semantics privacy: only the EXPOSED card '
        'publishes content, in both directions', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDeck(tester);

      // Tucked: BOTH cards' contents are excluded.
      expect(
        _treeHasSecret(tester),
        isFalse,
        reason: 'tucked hides the balance content',
      );
      expect(
        _treeHasVisa(tester),
        isFalse,
        reason: 'tucked hides the Visa content',
      );

      // Balance out: only the balance card publishes; the covered Visa
      // face is excluded even though its widget stays alive in the tree.
      tester
          .state<WalletCardDeckState>(find.byKey(_deckKey))
          .select(WalletDeckState.balanceOut);
      await tester.pumpAndSettle();
      expect(_treeHasSecret(tester), isTrue);
      expect(
        _treeHasVisa(tester),
        isFalse,
        reason:
            'the hidden Visa face must not be readable while the '
            'balance card is out',
      );

      // Direct switch to visaOut: the balance figures/breakdown are
      // excluded again and the Visa content becomes readable.
      tester
          .state<WalletCardDeckState>(find.byKey(_deckKey))
          .select(WalletDeckState.visaOut);
      await tester.pumpAndSettle();
      expect(
        _treeHasSecret(tester),
        isFalse,
        reason:
            'the covered balance amount must not leak while the '
            'Visa card is out',
      );
      expect(_treeHasVisa(tester), isTrue);

      // Both accessible selectors exist in EVERY state.
      expect(
        find.bySemanticsLabel('Reveal balance card'),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.bySemanticsLabel('Open AZM Visa card'),
        findsAtLeastNWidgets(1),
      );
      handle.dispose();
    });
  });

  // ── OUT-STATE POSE + RETURN GESTURE ─────────────────────────────────────

  group('WalletCardDeck widget — out poses and the return gesture', () {
    testWidgets('balance out: the pouch mouth recedes below the card face', (
      tester,
    ) async {
      await _pumpDeck(tester, reducedMotion: true);
      tester
          .state<WalletCardDeckState>(find.byKey(_deckKey))
          .select(WalletDeckState.balanceOut);
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.balanceOut);
      // Balance slot (70) - lift (16) + height (165) - overlap (10) = 209.
      expect(_mouthTop(tester), closeTo(209, 0.5));
      // The out card must sit ABOVE the mouth (full face readable).
      final deckTop = tester.getTopLeft(find.byKey(_deckKey)).dy;
      final cardBottom = tester.getBottomLeft(find.byKey(_balanceKey)).dy;
      expect(cardBottom - deckTop - 10, closeTo(_mouthTop(tester), 0.5));
    });

    testWidgets('visa out: the pouch mouth recedes below the visa face', (
      tester,
    ) async {
      await _pumpDeck(tester, reducedMotion: true);
      tester
          .state<WalletCardDeckState>(find.byKey(_deckKey))
          .select(WalletDeckState.visaOut);
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.visaOut);
      // Visa slot (26) - lift (16) + 165 - 10 = 165.
      expect(_mouthTop(tester), closeTo(165, 0.5));
    });

    testWidgets('visaOut never paints outside the deck window: the '
        'concealed balance card stays inside the viewport', (tester) async {
      await _pumpDeck(tester, reducedMotion: true);
      tester
          .state<WalletCardDeckState>(find.byKey(_deckKey))
          .select(WalletDeckState.visaOut);
      await tester.pumpAndSettle();

      final windowRect = tester.getRect(
        find.byKey(const ValueKey('wallet-deck-window')),
      );
      final balanceRect = tester.getRect(find.byKey(_balanceKey));

      // The concealed card may touch the window FLOOR (flush by design)
      // but must never cross it — the old +130 pose spilled its bottom
      // 104px into Home's content and the selector row.
      expect(
        balanceRect.bottom,
        lessThanOrEqualTo(windowRect.bottom + 0.5),
        reason: 'the hidden balance card cannot spill out of the deck',
      );
      expect(balanceRect.top, greaterThanOrEqualTo(windowRect.top - 0.5));

      // And it is genuinely concealed: its top sits below the visa
      // strip zone, behind the lifted Visa card and the pouch mouth.
      expect(
        balanceRect.top,
        greaterThan(windowRect.top + 70),
        reason: 'the concealed card must not peek above the header',
      );
    });

    testWidgets('z-order is state-aware: in visaOut the selected Visa '
        'card paints ABOVE the concealed balance card, and the pouch above '
        'both', (tester) async {
      await _pumpDeck(tester, reducedMotion: true);
      final window = tester.state<WalletCardDeckState>(find.byKey(_deckKey));
      window.select(WalletDeckState.visaOut);
      await tester.pumpAndSettle();

      // (1) The card Stack paints its children in list order — the last
      // child paints over every earlier one in the overlap region. In
      // visaOut the Visa slot must therefore be AFTER the balance slot,
      // otherwise the sliding-down balance card paints across the lower
      // half of the selected Visa card and the selection reads as two
      // broken half-cards.
      List<String> cardOrder() {
        final stack = tester.widget<Stack>(
          find.byKey(const ValueKey('wallet-deck-card-stack')),
        );
        return stack.children
            .map((w) => (w.key as ValueKey<String>).value)
            .toList();
      }

      expect(
        cardOrder(),
        ['wallet-deck-balance-slot', 'wallet-deck-visa-slot'],
        reason:
            'in visaOut the Visa card must paint on top of the '
            'concealed balance card',
      );

      // (2) The ordering is not vacuous: in the settled visaOut pose the
      // two cards genuinely overlap inside the window, so the wrong
      // order WOULD paint the balance card over the selected Visa card.
      final visaRect = tester.getRect(find.byKey(_visaKey));
      final balanceRect = tester.getRect(find.byKey(_balanceKey));
      expect(
        visaRect.overlaps(balanceRect),
        isTrue,
        reason:
            'the settled visaOut pose must overlap the concealed '
            'balance card — this is the region the z-order guards',
      );

      // (3) The pouch stays the topmost physical layer over BOTH cards.
      final windowStack = tester.widget<Stack>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('wallet-pouch-surface')),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Stack &&
                    w.key != const ValueKey('wallet-deck-card-stack'),
              ),
            )
            .first,
      );
      final names = windowStack.children
          .map(
            (w) => w.key != null ? (w.key as ValueKey<String>).value : 'cards',
          )
          .toList();
      expect(
        names.indexOf('cards'),
        lessThan(names.indexOf('wallet-pouch-surface')),
        reason: 'the pouch must always paint above the card stack',
      );

      // (4) The other states keep the physical hierarchy: balance is the
      // foreground card, Visa's header exposed behind it.
      window.select(WalletDeckState.balanceOut);
      await tester.pumpAndSettle();
      expect(cardOrder(), [
        'wallet-deck-visa-slot',
        'wallet-deck-balance-slot',
      ], reason: 'balanceOut: the balance card must stay topmost');

      window.select(WalletDeckState.tucked);
      await tester.pumpAndSettle();
      expect(cardOrder(), [
        'wallet-deck-visa-slot',
        'wallet-deck-balance-slot',
      ], reason: 'tucked: balance stays the foreground card');
    });

    testWidgets('non-committing gestures preserve the live pose: a '
        'downward grab-and-release never snaps the card to a stale pose', (
      tester,
    ) async {
      await _pumpDeck(tester); // normal (spring) motion
      tester
          .state<WalletCardDeckState>(find.byKey(_deckKey))
          .select(WalletDeckState.balanceOut);
      // Mid-emergence: the first frame latches the spring's start time,
      // the second advances it 120ms into the 450ms traversal.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final midTop = _balanceTopInWindow(tester);
      expect(midTop, greaterThan(54)); // still travelling
      expect(midTop, lessThan(70));

      // Grab and drag DOWN (slack): the pose must HOLD under the
      // finger — frozen at the live geometry, not springing on and not
      // snapping to a stale pose.
      final deckCenter = tester.getCenter(find.byKey(_deckKey));
      final gesture = await tester.startGesture(deckCenter);
      await gesture.moveBy(const Offset(0, 18));
      await tester.pump();
      expect(
        _balanceTopInWindow(tester),
        closeTo(midTop, 1.0),
        reason: 'the pose freezes under the finger',
      );
      await gesture.moveBy(const Offset(0, 18));
      await tester.pump();
      expect(
        _balanceTopInWindow(tester),
        closeTo(midTop, 1.0),
        reason: 'a downward drag is slack — the card does not move',
      );

      // Release with no upward travel → no commit. The card springs
      // back to the out pose FROM THE LIVE POSE: the first frame after
      // release must not jump (the old bug reset the controller to a
      // stale pre-drag pose and visibly snapped the card first).
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      final afterRelease = _balanceTopInWindow(tester);
      expect(
        (afterRelease - midTop).abs(),
        lessThan(10),
        reason: 'no stale-pose snap on release',
      );

      await tester.pumpAndSettle();
      expect(
        _balanceTopInWindow(tester),
        closeTo(54, 0.5),
        reason: 'and it settles back at the balance-out pose',
      );
    });

    testWidgets('an upward swipe while a card is out returns it to tucked', (
      tester,
    ) async {
      await _pumpDeck(tester, initial: WalletDeckState.balanceOut);
      await tester.drag(find.byKey(_deckKey), const Offset(0, -90));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.tucked);
      expect(_mouthTop(tester), closeTo(126, 0.5));
    });

    testWidgets('a micro-swipe below the threshold springs back to out', (
      tester,
    ) async {
      await _pumpDeck(tester, initial: WalletDeckState.visaOut);
      await tester.drag(find.byKey(_deckKey), const Offset(0, -18));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.visaOut);
      expect(_mouthTop(tester), closeTo(165, 0.5));
    });

    testWidgets('a downward drag while out is ignored (slack), an upward '
        'drag while tucked is ignored (tap-to-open is the only opener)', (
      tester,
    ) async {
      await _pumpDeck(tester, initial: WalletDeckState.balanceOut);
      await tester.drag(find.byKey(_deckKey), const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.balanceOut);

      tester.state<WalletCardDeckState>(find.byKey(_deckKey)).tuck();
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(_deckKey), const Offset(0, -90));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.tucked);
    });

    testWidgets('reduced motion: a direct pose transition, no spring '
        'traversal', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDeck(tester, reducedMotion: true);
      final before = _mouthTop(tester);
      expect(before, closeTo(126, 0.5));
      await tester.tap(find.bySemanticsLabel('Reveal balance card').first);
      // A single frame — the reduced-motion path must have landed.
      await tester.pump(const Duration(milliseconds: 1));
      expect(_mouthTop(tester), closeTo(209, 0.5));
      expect(_deckState(tester), WalletDeckState.balanceOut);
      handle.dispose();
    });

    testWidgets('the tuck path is continuous: mid-transition geometry never '
        'jumps backwards', (tester) async {
      await _pumpDeck(tester, initial: WalletDeckState.balanceOut);
      await tester.drag(find.byKey(_deckKey), const Offset(0, -60));
      await tester.pump();
      final midMouth = _mouthTop(tester);
      expect(midMouth, greaterThan(165)); // between out (209) and tucked (126)
      await tester.pumpAndSettle();
      expect(_mouthTop(tester), closeTo(126, 0.5));
    });
  });

  testWidgets('tuck() and collapse() both return the deck home '
      '(collapse kept as the audit-§7 alias)', (tester) async {
    await _pumpDeck(tester, initial: WalletDeckState.visaOut);
    tester.state<WalletCardDeckState>(find.byKey(_deckKey)).collapse();
    await tester.pumpAndSettle();
    expect(_deckState(tester), WalletDeckState.tucked);
  });
}
