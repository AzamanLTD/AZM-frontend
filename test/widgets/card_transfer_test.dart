// =============================================================================
// AZAMAN — CARD TRANSFER (Balance ↔ Visa) widget suite
//
// Pins the contract of the full-height transfer surface and its Home seam
// control:
//
//   1. OPENING / DISMISSING — the clasp exists on the tucked pouch's
//      pocket mouth (clear of both header-band tap targets and every card
//      mark), only while tucked, opens the surface via the real route,
//      and the surface dismisses via both the close button and the
//      committed pull-down (with the review stage consuming a pull first).
//   2. BOTH DIRECTIONS — "To Visa" / "From Visa" swap source and
//      destination everywhere they appear.
//   3. TAB-SWIPE SYNCHRONISATION — taps and horizontal swipes drive the
//      SAME controller; the tab bar and the pages can never disagree.
//   4. ANIMATION DIRECTION — the money flow travels toward the chosen
//      destination and honours reduced motion.
//   5. AMOUNT ENTRY — the shared AmountKeypad feeds the state machine; the
//      amount/currency and the review statement agree.
//   6. RESPONSIVE LAYOUT — the composition survives narrow and short
//      viewports with no layout exception.
//   7. THE CAPABILITY GATE — the demo programme keeps submission disabled
//      with truthful copy: no success state, no endpoint, no mutation.
// =============================================================================

import 'dart:async';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/screens/card_transfer_screen.dart';
import 'package:azaman/widgets/home/visa_transfer_seam_control.dart';
import 'package:azaman/widgets/home/wallet_card_deck.dart';
import 'package:azaman/widgets/flippable_balance_card.dart';
import 'package:azaman/widgets/home/azm_visa_card.dart';
import 'package:azaman/widgets/amount_keypad.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A programme that CLAIMS `supportsTransfers` — a real issuer seam behind
/// it would still need the backend transfer ledger, settlement and
/// idempotency contract and the funding rail. The screen must not let the
/// flag alone imply that a transfer can be made here.
class _ProgrammeClaimingTransfers extends DemoCardProgramme {
  @override
  bool get supportsTransfers => true;
}

/// A susu list that never resolves — the FlippableBalanceCard watcher must
/// degrade silently (the F-023 failure path behaving as designed); no test
/// traffic ever leaves the process.
class _SusuListNeverLoads extends SusuListNotifier {
  @override
  Future<List<SusuSummary>> build() => Completer<List<SusuSummary>>().future;
}

const _standInDeckKey = ValueKey('stand-in-deck');

/// The Home wiring in miniature: the real seam anchor over a deck-sized
/// stand-in, wired to the real route exactly as home_screen.dart wires it.
GoRouter _router() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: VisaTransferSeamAnchor(
                            onTransfer: () => context.push(AzRoutes.cardTransfer),
              child: const SizedBox(
                key: _standInDeckKey,
                width: 400,
                height: 261, // top pad + Visa peek + card height + pouch lip
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: AzRoutes.cardTransfer,
        builder: (context, state) => const CardTransferScreen(),
      ),
    ],
  );
}

Widget _app(
  ProviderContainer container,
  GoRouter router, {
  bool reduceMotion = false,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      routerConfig: router,
    ),
  );
}

ProviderContainer _container({AzmCardProgramme? programme}) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 100),
      ),
      oracleRateProvider.overrideWith((ref) => 1.0),
      susuListProvider.overrideWith(_SusuListNeverLoads.new),
      if (programme != null)
        azmCardProgrammeProvider.overrideWith((ref) => programme),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Pumps the app at the given surface with the surface route ALREADY open
/// (the opening tests drive the seam control themselves).
Future<void> _pumpTransfer(
  WidgetTester tester, {
  Size surface = const Size(400, 890),
  bool reduceMotion = false,
  AzmCardProgramme? programme,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = _router();
  await tester.pumpWidget(
    _app(_container(programme: programme), router, reduceMotion: reduceMotion),
  );
  router.go(AzRoutes.cardTransfer);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}


/// Taps a keypad key, scoped INSIDE the keypad — the balance card renders
/// its own digits and must never race the tap target.
Future<void> _tapKey(WidgetTester tester, String label) async {
  final cell = find.descendant(
    of: find.byType(AmountKeypad),
    matching: label == 'del'
        ? find.byIcon(Icons.backspace_outlined)
        : find.text(label),
  );
  await tester.tap(cell.first);
  await tester.pump();
}

void main() {
  setUpAll(() {
    // ThemeProvider/currency constructors read SharedPreferences.
    SharedPreferences.setMockInitialValues({});
  });

  // ── 1. OPENING / DISMISSING ────────────────────────────────────────────

  group('the Home seam control', () {
    testWidgets('rides the tucked pouch\'s pocket mouth, clear of both '
        'header-band tap targets', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var tapped = 0;
      final container = _container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: VisaTransferSeamAnchor(
                                    onTransfer: () => tapped++,
                  child: const SizedBox(
                    key: _standInDeckKey,
                    width: 400,
                    height: 261,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final control = find.byKey(const ValueKey('visa-transfer-seam-control'));
      expect(control, findsOneWidget);

      // The clasp rides the tucked pouch's POCKET MOUTH — fully on the
      // absorbing pouch surface, tangent to the balance header's bottom
      // edge. It must NOT touch either header band's tap target (the
      // Visa strip at visaHeaderTop..+visaPeek, the balance brand header
      // below it) nor cover any AZM / SAMPLE / VISA mark.
      final rect = tester.getRect(control);
      final deckRect = tester.getRect(find.byKey(_standInDeckKey));
      const pocketMouthY =
          WalletCardDeckState.visaHeaderTop +
          WalletCardDeckState.visaPeek +
          WalletCardDeckState.balanceHeaderBand;
      expect(rect.top - deckRect.top,
          moreOrLessEquals(pocketMouthY, epsilon: 0.5),
          reason: 'the clasp starts exactly at the pocket mouth — below it, '
              'the balance header band must stay fully tappable');
      expect(rect.bottom - deckRect.top,
          moreOrLessEquals(pocketMouthY + kSeamControlSize, epsilon: 0.5));
      expect(rect.center.dx - deckRect.left,
          moreOrLessEquals(deckRect.width / 2, epsilon: 0.5),
          reason: 'the clasp sits in the pocket mouth\'s clear center — '
              'AZM / SAMPLE / VISA marks stay visible at the sides');

      await tester.tap(control);
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('exists only while the deck is tucked (the clasp never '
        'fights an out card\'s own gestures)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: _container(),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: VisaTransferSeamAnchor(
                  visible: false,
                  onTransfer: () {},
                  child: const SizedBox(
                    key: _standInDeckKey,
                    width: 400,
                    height: 261,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('visa-transfer-seam-control')),
        findsNothing,
        reason: 'an out card owns the deck surface — the clasp must not '
            'mount over it',
      );
    });

    testWidgets('opens the transfer surface via the real route', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 890));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(_container(), _router()));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CardTransferScreen), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('visa-transfer-seam-control')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(CardTransferScreen), findsOneWidget);
      expect(find.text('Card Transfer'), findsOneWidget);
      expect(find.text('To Visa'), findsOneWidget);
      expect(find.text('From Visa'), findsOneWidget);
    });
  });

  group('dismissing the surface', () {
    testWidgets('the close button returns to the opener', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 890));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(_container(), _router()));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(
        find.byKey(const ValueKey('visa-transfer-seam-control')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CardTransferScreen), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('card-transfer-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(CardTransferScreen), findsNothing);
      expect(find.byKey(_standInDeckKey), findsOneWidget);
    });

    testWidgets('a committed pull-down dismisses the amount stage', (
      tester,
    ) async {
      await _pumpTransfer(tester);
      // A committed pull: past the 110px threshold with fling velocity.
      await tester.fling(
        find.byType(CardTransferScreen),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(CardTransferScreen), findsNothing);
    });

    testWidgets('the review stage consumes a pull before the surface closes',
        (tester) async {
      await _pumpTransfer(tester);

      // Type an amount, reach the review stage.
      await _tapKey(tester, '1');
      await _tapKey(tester, '2');
      await tester.tap(find.byKey(const ValueKey('card-transfer-review-cta')));
      await tester.pump();
      expect(find.byKey(const ValueKey('card-transfer-review-title')),
          findsOneWidget);

      await tester.fling(
        find.byType(CardTransferScreen),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Still open — the pull returned to the amount stage, not home.
      expect(find.byType(CardTransferScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('card-transfer-amount')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('card-transfer-review-title')),
          findsNothing);
    });
  });

  // ── 2/3. DIRECTIONS + TAB-SWIPE SYNCHRONISATION ─────────────────────────

  group('both directions, one controller', () {
    testWidgets('To Visa shows balance → card by default', (tester) async {
      await _pumpTransfer(tester);

      final route = find.byKey(const ValueKey('card-transfer-route-to-visa'));
      expect(route, findsOneWidget);
      // TWO 'Azaman Balance' texts are expected post-pouch (#163): the route
      // row states the source once, and HologramBalanceCard's face carries
      // the deck's own established label. No third instance may exist.
      expect(find.text('Azaman Balance'), findsNWidgets(2));

      // The Home card renderers themselves — never duplicates.
      expect(find.byType(FlippableBalanceCard), findsOneWidget);
      expect(find.byType(AzmVisaCard), findsOneWidget);
    });

    testWidgets('tapping From Visa flips source and destination', (
      tester,
    ) async {
      await _pumpTransfer(tester);

      await tester.tap(find.text('From Visa'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('card-transfer-route-from-visa')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('card-transfer-route-to-visa')),
          findsNothing);
      // From Visa: the CARD is the source, the balance the destination.
      final routeText = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('card-transfer-route-from-visa')),
              matching: find.byType(Text),
            ).first,
          )
          .data;
      expect(routeText, 'AZM Visa card');
    });

    testWidgets('a horizontal swipe moves the tab bar with the page', (
      tester,
    ) async {
      await _pumpTransfer(tester);

      // Swipe the content: the tab bar must follow (one controller).
      await tester.fling(
        find.byKey(const ValueKey('card-transfer-pane-to-visa')),
        const Offset(-400, 0),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byKey(const ValueKey('card-transfer-route-from-visa')),
          findsOneWidget);

      // And back: tap the first tab, the page returns.
      await tester.tap(find.text('To Visa'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('card-transfer-route-to-visa')),
          findsOneWidget);
    });
  });

  // ── 4. ANIMATION DIRECTION ──────────────────────────────────────────────

  group('the money-flow animation', () {
    testWidgets('travels toward the chosen destination and reverses', (
      tester,
    ) async {
      await _pumpTransfer(tester);

      final toVisaFlow = find.byKey(
        const ValueKey('card-transfer-flow-to-visa'),
      );
      expect(toVisaFlow, findsOneWidget);
      expect(
        tester.widget<DirectionalMoneyFlow>(toVisaFlow).toVisa,
        isTrue,
      );

      // Switch direction: the flow reverses.
      await tester.tap(find.text('From Visa'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final fromVisaFlow = find.byKey(
        const ValueKey('card-transfer-flow-from-visa'),
      );
      expect(fromVisaFlow, findsOneWidget);
      expect(
        tester.widget<DirectionalMoneyFlow>(fromVisaFlow).toVisa,
        isFalse,
      );
    });

    testWidgets('reduced motion keeps the direction, drops the travel', (
      tester,
    ) async {
      await _pumpTransfer(tester, reduceMotion: true);

      final flow = tester.widget<DirectionalMoneyFlow>(
        find.byKey(const ValueKey('card-transfer-flow-to-visa')),
      );
      expect(flow.reduceMotion, isTrue);
      expect(flow.toVisa, isTrue);
    });

    testWidgets('only the ACTIVE pane loops — the loop follows the selection',
        (tester) async {
      await _pumpTransfer(tester);

      final toVisa = find.byKey(const ValueKey('card-transfer-flow-to-visa'));
      expect(tester.state<DirectionalMoneyFlowState>(toVisa).isLooping,
          isTrue,
          reason: 'the selected pane (To Visa at mount) owns the loop');

      // A fling builds the neighboring pane MID-TRANSITION: while it is
      // merely traveling into view — not yet the selected direction —
      // its loop must NOT start. (Off-screen, TabBarView disposes the
      // pane entirely; the transition is the only window where a hidden
      // loop could exist.)
      await tester.fling(
        find.byKey(const ValueKey('card-transfer-pane-to-visa')),
        const Offset(-400, 0),
        1000,
      );
      await tester.pump(const Duration(milliseconds: 150));

      final fromVisaMid =
          find.byKey(const ValueKey('card-transfer-flow-from-visa'));
      expect(
          tester.state<DirectionalMoneyFlowState>(fromVisaMid).isLooping,
          isFalse,
          reason: 'a pane that is only traveling into view does not loop');
      // The STILL-selected pane keeps the loop through the transition.
      expect(tester.state<DirectionalMoneyFlowState>(toVisa).isLooping,
          isTrue);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Settled on From Visa: the loop has FOLLOWED the selection. The
      // previous page is disposed WITH its controller — there is never a
      // hidden second loop.
      final fromVisa =
          find.byKey(const ValueKey('card-transfer-flow-from-visa'));
      expect(
          tester.state<DirectionalMoneyFlowState>(fromVisa).isLooping,
          isTrue,
          reason: 'the newly selected pane now owns the loop');
      expect(find.byKey(const ValueKey('card-transfer-flow-to-visa')),
          findsNothing,
          reason: 'the previous pane is fully disposed with its controller');
    });

    testWidgets('a runtime reduced-motion change stops — and re-allows — the loop',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 890));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = _router();
      final container = _container();
      await tester.pumpWidget(_app(container, router, reduceMotion: false));
      router.go(AzRoutes.cardTransfer);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final toVisa = find.byKey(const ValueKey('card-transfer-flow-to-visa'));
      expect(tester.state<DirectionalMoneyFlowState>(toVisa).isLooping,
          isTrue);

      // The preference flips at runtime (settings → AzMotion rebuild).
      // The widget state persists; only the inherited motion changes —
      // didUpdateWidget must react by stopping the loop.
      await tester.pumpWidget(_app(container, router, reduceMotion: true));
      await tester.pump();
      expect(tester.state<DirectionalMoneyFlowState>(toVisa).isLooping,
          isFalse,
          reason: 'reduced motion lands mid-flight: the loop stops');

      // And back: re-allowing motion resumes the loop.
      await tester.pumpWidget(_app(container, router, reduceMotion: false));
      await tester.pump();
      expect(tester.state<DirectionalMoneyFlowState>(toVisa).isLooping,
          isTrue,
          reason: 'the loop resumes when motion is re-allowed');
    });
  });

  // ── 5. AMOUNT ENTRY ─────────────────────────────────────────────────────

  group('amount entry', () {
    testWidgets('the shared keypad drives the amount and currency', (
      tester,
    ) async {
      await _pumpTransfer(tester);

      // '12.50'
      await _tapKey(tester, '1');
      await _tapKey(tester, '2');
      await _tapKey(tester, '.');
      await _tapKey(tester, '5');
      await _tapKey(tester, '0');
      expect(find.byType(AmountKeypad), findsOneWidget); // keypad shared

      // The key sits on the amount Text itself.
      expect(
        find.byKey(const ValueKey('card-transfer-amount')),
        findsOneWidget,
      );
      expect(find.text('12.50 USDC'), findsOneWidget);

      // Backspace works through the state machine.
      await _tapKey(tester, 'del');
      expect(find.text('12.5 USDC'), findsOneWidget);
    });

    testWidgets('the review CTA demands a positive amount', (tester) async {
      await _pumpTransfer(tester);

      final cta = find.byKey(const ValueKey('card-transfer-review-cta'));
      // Zero amount: the CTA must not open the review stage.
      await tester.tap(cta);
      await tester.pump();
      expect(find.byKey(const ValueKey('card-transfer-review-title')),
          findsNothing);
    });

    testWidgets('the review statement restates the transfer truthfully', (
      tester,
    ) async {
      await _pumpTransfer(tester);

      await _tapKey(tester, '1');
      await _tapKey(tester, '2');
      await tester.tap(find.byKey(const ValueKey('card-transfer-review-cta')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('card-transfer-review-title')),
          findsOneWidget);
      // The review title restates the chosen direction (the tab carries
      // the same words, so this is two matches).
      expect(find.text('To Visa'), findsWidgets);
      expect(find.text('12 USDC'), findsOneWidget);

      // Source and destination rows, the chosen direction.
      expect(find.text('From'), findsOneWidget);
      expect(find.text('To'), findsOneWidget);
      // The review From-row names the balance once; the mounted card's own
      // hologram face (#163) carries the deck label — and only those two.
      expect(find.text('Azaman Balance'), findsNWidgets(2));

      // THE GATE: truthful copy, disabled submission, never a success.
      expect(
        find.text("Card transfers aren't available yet"),
        findsOneWidget,
      );
      final submit = find.byKey(const ValueKey('card-transfer-submit'));
      expect(tester.widget<Semantics>(
        find.ancestor(of: submit, matching: find.byType(Semantics)).first,
      ).properties.enabled, isFalse);
      expect(find.text('Transfer unavailable'), findsOneWidget);
      expect(find.text('Transfer sent'), findsNothing);
      expect(find.text('Success'), findsNothing);
      expect(find.textContaining('sample preview'), findsOneWidget);
    });

    testWidgets('a programme CLAIMING supportsTransfers still cannot imply '
        'that a transfer can be made here', (tester) async {
      await _pumpTransfer(
        tester,
        programme: _ProgrammeClaimingTransfers(),
      );

      // Drive to the review stage so the gate is visible.
      await _tapKey(tester, '1');
      await _tapKey(tester, '2');
      await tester
          .tap(find.byKey(const ValueKey('card-transfer-review-cta')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The flag alone NEVER flips the copy or the submit: this build has
      // no transfer execution path, so it cannot claim enablement.
      expect(find.textContaining('transfers are enabled'), findsNothing);
      expect(find.textContaining('programme is ready'), findsNothing);
      expect(find.textContaining('sample preview'), findsOneWidget,
          reason: 'the honest gate copy is state-independent');
      final submit = find.byKey(const ValueKey('card-transfer-submit'));
      expect(
        tester.widget<Semantics>(
          find.ancestor(of: submit, matching: find.byType(Semantics)).first,
        ).properties.enabled,
        isFalse,
        reason: 'submit stays structurally disabled regardless of the flag');
    });
  });

  // ── 6. RESPONSIVE LAYOUT ────────────────────────────────────────────────

  group('responsive layout', () {
    for (final surface in [
      const Size(320, 700),
      const Size(390, 844),
      const Size(400, 600),
    ]) {
      testWidgets('no layout exception at ${surface.width}x${surface.height}',
          (tester) async {
        await _pumpTransfer(tester, surface: surface);

        expect(tester.takeException(), isNull);
        // Both card renderers survive every width.
        expect(find.byType(FlippableBalanceCard), findsOneWidget);
        expect(find.byType(AzmVisaCard), findsOneWidget);
        // The amount stage is reachable at every width.
        expect(find.byType(AmountKeypad), findsOneWidget);
      });
    }
  });
}
