// =============================================================================
// AZAMAN — WALLET POUCH PR #154 FOLLOW-UP REGRESSION SUITE.
//
// Pins the four review contracts of the follow-up pass:
//
//   1. SELECTOR TOGGLE-TO-TUCK — tapping the selector of the card that is
//      already out returns the deck to tucked, through the SAME
//      onStateChanged callback the Home host uses to clear the PIN gate
//      and sensitive details. Selecting the other card still switches
//      directly.
//
//   2. VISA CHIP LABEL — the visible selector chip reads "Visa"; the
//      meaningful screen-reader labels ("Open AZM Visa card" /
//      "Reveal balance card") are preserved.
//
//   3. STABLE HEADING FOOTPRINT — the typewriter heading's height and the
//      Y of everything below it cannot move while the string is empty,
//      typing, or fully typed (ConstrainedBox minHeight + a reserved
//      glyph slot).
//
//   4. FIRST-VIEWPORT FIT — at 320x667, 360x740, 390x844 and 412x915 the
//      greeting, the card deck, the Balance/Visa selectors and the
//      Save/P2P/Susu row land above the fold (bottom nav + system inset
//      included). The reminder/recent-activity area stays scrollable.
// =============================================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/widgets/home/az_typewriter_heading.dart';
import 'package:azaman/widgets/home/azm_visa_card.dart';
import 'package:azaman/widgets/home/wallet_card_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _fontsLoaded = false;

/// The app's REAL font (Inter) so height measurements reflect device
/// metrics (same loader as the pouch screenshot suite).
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

// ─── DECK HARNESS (isolated deck, no Home dependencies) ─────────────────────

const _deckKey = Key('wallet-card-deck');
const _surface = Size(400, 900);

Widget _plainCard(Key key, Color color) => Container(
  key: key,
  color: color,
  alignment: Alignment.topLeft,
  padding: const EdgeInsets.all(12),
  child: const Text('CARD'),
);

Future<void> _pumpDeck(
  WidgetTester tester, {
  ValueChanged<WalletDeckState>? onStateChanged,
}) async {
  await tester.binding.setSurfaceSize(_surface);
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: _surface),
      child: ProviderScope(
        overrides: [authProvider.overrideWith((ref) => AuthProvider(ref: ref))],
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFFF2F2F7),
            body: Center(
              child: WalletCardDeck(
                key: _deckKey,
                cardHeight: 165,
                balanceCard: _plainCard(
                  const Key('deck-balance-card'),
                  const Color(0xFF1C1C1E),
                ),
                visaCard: _plainCard(
                  const Key('deck-visa-card'),
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
  await tester.pumpAndSettle();
}

WalletDeckState _deckState(WidgetTester tester) =>
    tester.state<WalletCardDeckState>(find.byKey(_deckKey)).state;

// ─── 1. TOGGLE-TO-TUCK ─────────────────────────────────────────────────────

// ─── FAKES for the Home viewport pump (same contracts as the pouch
// screenshot suite's fakes) ──────────────────────────────────────────────────

class _NoopHistoryNotifier extends TransactionHistoryNotifier {
  @override
  Future<void> loadMore() async {}
}

class _PinnedProgramme implements AzmCardProgramme {
  String? _pin;

  // The transfer surface ships inert: no fake programme may claim support.
  @override
  bool get supportsTransfers => false;

  @override
  bool get hasPin => _pin != null;

  @override
  Future<bool> setPin(String pin) async => false;

  @override
  Future<bool> verifyPin(String pin) async {
    await Future<void>.delayed(Duration.zero);
    return _pin != null && _pin == pin;
  }

  @override
  String get maskedNumber => 'SAMPLE •••• 4242';

  @override
  String get expiryLabel => 'MM/YY';

  @override
  String get cardholderLabel => 'SAMPLE HOLDER';
}

class _NoopHomeSummaryNotifier extends HomeSummaryNotifier {
  _NoopHomeSummaryNotifier(super.ref, super.service);
}

void main() {
  group('PR #154 — selector toggle-to-tuck', () {
    testWidgets('tapping the ACTIVE Balance selector re-tucks the deck and '
        'notifies the host (sensitive details clear path)', (tester) async {
      final states = <WalletDeckState>[];
      await _pumpDeck(tester, onStateChanged: states.add);
      expect(_deckState(tester), WalletDeckState.tucked);

      // Open the balance card via its selector chip.
      await tester.tap(find.byKey(const ValueKey('wallet-select-balance')));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.balanceOut);
      expect(states, [WalletDeckState.balanceOut]);

      // Tap the SAME (now active) selector: the deck returns to tucked and
      // the host's callback fires — the same path the swipe-up return uses,
      // so the Home host clears the PIN gate / sensitive details.
      await tester.tap(find.byKey(const ValueKey('wallet-select-balance')));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.tucked);
      expect(states, [WalletDeckState.balanceOut, WalletDeckState.tucked]);
    });

    testWidgets('tapping the ACTIVE Visa selector re-tucks the deck '
        '(same toggle behaviour on both selectors)', (tester) async {
      final states = <WalletDeckState>[];
      await _pumpDeck(tester, onStateChanged: states.add);

      await tester.tap(find.byKey(const ValueKey('wallet-select-visa')));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.visaOut);

      await tester.tap(find.byKey(const ValueKey('wallet-select-visa')));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.tucked);
      expect(
        states,
        [WalletDeckState.visaOut, WalletDeckState.tucked],
        reason:
            'the re-tuck must reach the host callback exactly like the '
            'swipe-up return, so sensitive details clear',
      );
    });

    testWidgets('selecting the OTHER card still switches directly '
        '(no accidental tuck)', (tester) async {
      await _pumpDeck(tester);

      await tester.tap(find.byKey(const ValueKey('wallet-select-balance')));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.balanceOut);

      // Balance is active; tapping VISA switches straight to the Visa card.
      await tester.tap(find.byKey(const ValueKey('wallet-select-visa')));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.visaOut);

      // And back the other way.
      await tester.tap(find.byKey(const ValueKey('wallet-select-balance')));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.balanceOut);
    });

    testWidgets('from tucked, a selector tap still OPENS (tucked is never '
        '"active")', (tester) async {
      await _pumpDeck(tester);
      expect(_deckState(tester), WalletDeckState.tucked);

      // Both selectors must open from tucked — the toggle only applies to
      // the card that is already OUT.
      await tester.tap(find.byKey(const ValueKey('wallet-select-balance')));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.balanceOut);

      final deck = tester.state<WalletCardDeckState>(find.byKey(_deckKey));
      deck.tuck();
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.tucked);

      await tester.tap(find.byKey(const ValueKey('wallet-select-visa')));
      await tester.pumpAndSettle();
      expect(_deckState(tester), WalletDeckState.visaOut);
    });
  });

  // ─── 2. VISA CHIP LABEL ────────────────────────────────────────────────

  group('PR #154 — Visa selector label', () {
    testWidgets('the visible chip reads "Visa"; "AZM Visa" is retired from '
        'the selector row', (tester) async {
      await _pumpDeck(tester);
      expect(find.text('Visa'), findsOneWidget);
      expect(find.text('AZM Visa'), findsNothing);
      expect(find.text('Balance'), findsOneWidget);
    });

    testWidgets('screen-reader labels keep the meaningful long forms', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpDeck(tester);
      // NOTE: a Semantics(button:) chip matches on BOTH its gesture node
      // and its annotation node — the contract is EXISTENCE of the label,
      // not a single node (same matcher style as the tucked-contract suite).
      expect(
        find.bySemanticsLabel('Open AZM Visa card'),
        findsWidgets,
        reason:
            'the accessible name stays "Open AZM Visa card" even though '
            'the visible chip now reads "Visa"',
      );
      expect(find.bySemanticsLabel('Reveal balance card'), findsWidgets);
      handle.dispose();
    });
  });

  // ─── 3. STABLE HEADING FOOTPRINT ───────────────────────────────────────

  group('PR #154 — stable typewriter heading footprint', () {
    Future<void> pumpHeading(WidgetTester tester, {Key? markerKey}) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => AuthProvider()),
          unreadCountProvider.overrideWith((ref) => 0),
        ],
      );
      addTearDown(container.dispose);
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeProvider.getThemeData(AzamanTheme.light),
            home: MediaQuery(
              data: const MediaQueryData(size: Size(400, 900)),
              child: Scaffold(
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AzTypewriterHeading(),
                    Expanded(
                      child: Container(
                        key: markerKey,
                        color: const Color(0xFF123456),
                        alignment: Alignment.topLeft,
                        child: const Text('BELOW'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('heading height and the content Y below it are IDENTICAL '
        'while empty, mid-typing and fully typed', (tester) async {
      await tester.runAsync(_loadFonts);
      const markerKey = Key('below-heading-marker');
      await pumpHeading(tester, markerKey: markerKey);

      // Frame 1: the machine has not typed yet — the string is EMPTY.
      final emptyHeading = tester.getSize(find.byType(AzTypewriterHeading));
      final emptyMarkerY = tester.getTopLeft(find.byKey(markerKey)).dy;

      // Mid-typing: a partial string.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final typingHeading = tester.getSize(find.byType(AzTypewriterHeading));
      final typingMarkerY = tester.getTopLeft(find.byKey(markerKey)).dy;
      expect(typingHeading, emptyHeading);
      expect(typingMarkerY, emptyMarkerY);

      // Fully typed: the complete greeting.
      await tester.pump(const Duration(seconds: 2));
      final fullHeading = tester.getSize(find.byType(AzTypewriterHeading));
      final fullMarkerY = tester.getTopLeft(find.byKey(markerKey)).dy;
      expect(fullHeading, emptyHeading);
      expect(
        fullMarkerY,
        emptyMarkerY,
        reason:
            'the deck/content below the greeting must not move when '
            'the typewriter text changes',
      );
    });

    testWidgets('the glyph slot is reserved even with an empty string, so '
        'the text start edge never shifts', (tester) async {
      await tester.runAsync(_loadFonts);
      await pumpHeading(tester);

      bool hasGlyphSlot() => find
          .byWidgetPredicate(
            (w) => w is SizedBox && w.width == 28 && w.height == 20,
          )
          .evaluate()
          .isNotEmpty;

      // Empty (frame 1): the slot exists as a reserved empty box.
      expect(
        hasGlyphSlot(),
        isTrue,
        reason:
            'the icon slot must be RESERVED, not conditional — '
            'otherwise the text jumps when a glyph appears',
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(hasGlyphSlot(), isTrue);

      await tester.pump(const Duration(seconds: 2));
      expect(hasGlyphSlot(), isTrue);
    });

    testWidgets('the heading meets its minimum height contract (>= 32) at '
        'every phase — a floor, never a hard height', (tester) async {
      await tester.runAsync(_loadFonts);
      await pumpHeading(tester);
      final h1 = tester.getSize(find.byType(AzTypewriterHeading)).height;
      expect(h1, greaterThanOrEqualTo(32));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      final h2 = tester.getSize(find.byType(AzTypewriterHeading)).height;
      expect(h2, greaterThanOrEqualTo(32));
      expect(h2, h1);
    });
  });

  // ─── 4. FIRST-VIEWPORT FIT ─────────────────────────────────────────────

  group('PR #154 — first-viewport fit (bottom nav + system inset)', () {
    /// Bottom nav + system inset emulate the real MainWrapper chrome so
    /// "above the fold" means above the ACTUAL available viewport.
    Future<void> pumpHomeAt(WidgetTester tester, Size size) async {
      SharedPreferences.setMockInitialValues({'azaman_theme': 1});
      final themeProviderInstance = ThemeProvider();
      await tester.runAsync(_loadFonts);
      await tester.binding.setSurfaceSize(size);
      final container = ProviderContainer(
        overrides: [
          themeProvider.overrideWith((ref) => themeProviderInstance),
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
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeProvider.getThemeData(AzamanTheme.dark),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                padding: const EdgeInsets.only(bottom: 34),
              ),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                bottomNavigationBar: Container(
                  key: const Key('test-bottom-nav'),
                  height: 64,
                  color: const Color(0xFF0B0B0D),
                ),
                body: AzamanHomePage(),
              ),
            ),
          ),
        ),
      );
      // Entrance + prime microtask + measurement window (same cadence as
      // the pouch integration suite).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    // The fold boundary is where the Home body meets the bottom nav —
    // derived from the LAYOUT itself, never hand-computed.
    double foldBottom(WidgetTester tester) =>
        tester.getRect(find.byType(AzamanHomePage)).bottom;

    for (final size in const [
      Size(320, 667),
      Size(360, 740),
      Size(390, 844),
      Size(412, 915),
    ]) {
      testWidgets('greeting + deck + selectors + modules fit above the '
          'fold at ${size.width}x${size.height}', (tester) async {
        await pumpHomeAt(tester, size);
        final fold = foldBottom(tester);

        // The greeting is on screen.
        final greeting = find
            .textContaining(RegExp('Good (morning|afternoon|evening)'))
            .evaluate()
            .first;
        final greetingRect = tester.getRect(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.data!.contains(RegExp('Good (morning|afternoon|evening)')),
          ),
        );
        expect(greetingRect.top, greaterThan(0));
        expect(greetingRect.bottom, lessThan(fold));

        // The card deck window is fully visible.
        final deckRect = tester.getRect(
          find.byKey(const ValueKey('wallet-deck-window')),
        );
        expect(
          deckRect.bottom,
          lessThanOrEqualTo(fold + 0.5),
          reason: 'the whole deck (cards + pouch) must be above the fold',
        );

        // Both selectors are above the fold.
        final balanceChip = tester.getRect(
          find.byKey(const ValueKey('wallet-select-balance')),
        );
        expect(balanceChip.bottom, lessThanOrEqualTo(fold + 0.5));

        // The Save/P2P/Susu module row is above the fold.
        final savePill = tester.getRect(
          find.byKey(const ValueKey('wallet-module-save')),
        );
        expect(
          savePill.bottom,
          lessThanOrEqualTo(fold + 0.5),
          reason: 'Save/P2P/Susu must be reachable without scrolling',
        );

        // The reminder/recent-activity area remains scrollable — the page
        // itself is NOT forced non-scrollable.
        expect(find.byType(SingleChildScrollView), findsWidgets);
      });
    }
  });
}
