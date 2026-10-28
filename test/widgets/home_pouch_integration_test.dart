// WALLET POUCH — Home host integration (2026-10-16).
//
// The deck suite (home_card_deck_test.dart) pins the deck's own geometry,
// physics and semantics contracts in isolation. This file pins what the
// HOST does with the deck on the real Home page:
//
//   1. The tucked default: the real Home mounts the deck tucked, with no
//      balance-visibility eye anywhere (the pouch is the privacy state)
//      and no card-details panel.
//   2. The balance card needs NO gate: selecting it out leaves the flip
//      gesture alive — breakdown is one tap away once the card is out.
//   3. The Visa card runs the PIN gate: a pass mounts the details panel
//      below the deck; a dismissal re-tucks the deck (never a lingering
//      out card with locked details).
//   4. App-backgrounding re-locks: any out card and unlocked details
//      drop back to the tucked pouch the moment the app loses focus.
import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/widgets/home/home_balance_card.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/widgets/home/azm_visa_card.dart';
import 'package:azaman/widgets/home/wallet_card_deck.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _surfaceSize = Size(400, 900);

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final inter = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final interLoader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(inter).buffer)),
    );
  await interLoader.load();
  _fontsLoaded = true;
}

class _NoopHistoryNotifier extends TransactionHistoryNotifier {
  @override
  Future<void> loadMore() async {}
}

/// A programme whose PIN already exists in-session, so the integration can
/// exercise the "Enter your card PIN" gate path without the two-stage
/// first-PIN confirmation flow (that flow is pinned in home_pin_gate_test).
class _PinnedProgramme implements AzmCardProgramme {
  String? _pin;

  // The transfer surface ships inert: no fake programme may claim support.
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
  String get maskedNumber => 'SAMPLE •••• 4242';

  @override
  String get expiryLabel => 'MM/YY';

  @override
  String get cardholderLabel => 'SAMPLE HOLDER';
}

/// Pumps the real Home page (real entrance choreography) at the canonical
/// test surface, advancing past the entrance and the doorway-gap
/// measurement window so the measured layout is settled.
Future<ProviderContainer> _pumpHome(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
  });
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(_surfaceSize);

  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      transactionHistoryProvider.overrideWith((ref) => _NoopHistoryNotifier()),
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
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: const MediaQuery(
          data: MediaQueryData(size: _surfaceSize),
          child: Scaffold(body: AzamanHomePage()),
        ),
      ),
    ),
  );
  // Entrance + prime microtask + §6 measurement window.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 1400));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

class _NoopHomeSummaryNotifier extends HomeSummaryNotifier {
  _NoopHomeSummaryNotifier(super.ref, super.service);
}

/// The real Home loops ambient animations forever (hologram particles,
/// shimmer sweeps), so pumpAndSettle never quiesces on this page. Fixed
/// duration pumping is the canonical settle pattern here (the same one
/// home_entrance_test.dart uses); 3 x 400ms covers the deck spring, the
/// sheet's enter/exit transition and the flip animation with margin.
Future<void> _settle(WidgetTester tester, {int rounds = 3}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

WalletDeckState _deckState(WidgetTester tester) =>
    tester.state<WalletCardDeckState>(find.byType(WalletCardDeck)).state;

void main() {
  testWidgets(
    'the real Home mounts the deck tucked — no eye control, no details '
    'panel',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpHome(tester);

      expect(find.byType(WalletCardDeck), findsOneWidget);
      expect(_deckState(tester), WalletDeckState.tucked);
      expect(find.byType(AzmCardDetailsPanel), findsNothing,
          reason: 'the details panel only mounts after the PIN gate');

      // The eye is retired everywhere: neither the widget nor its old
      // semantics control may appear on the real page.
      expect(find.bySemanticsLabel('Toggle balance visibility'), findsNothing);
      expect(find.text('••••••••'), findsNothing,
          reason: 'no mask dots — privacy is the physical pouch');
      handle.dispose();
    },
  );

  testWidgets(
    'the balance card needs no gate — and the flip stays alive once out',
    (tester) async {
      await _pumpHome(tester);

      await tester.tap(find.bySemanticsLabel('Reveal balance card').first);
      await _settle(tester);
      expect(_deckState(tester), WalletDeckState.balanceOut);
      expect(find.byType(AzmCardDetailsPanel), findsNothing);

      // Flip-when-out: the balance card's own flip gesture works while
      // it is out of the pouch. The back face is the section-paged
      // breakdown — its first section (AVAILABLE) is the marker.
      await tester.tap(find.byType(HomeBalanceCard));
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('balance-pair-back-surface')),
        findsOneWidget,
        reason: 'the out card flips to its breakdown face',
      );
      expect(find.text('AVAILABLE'), findsOneWidget);

      // Returning to the pouch covers the card again: the still-flipped
      // back face is EXCLUDED from the semantics tree (the deck's
      // covered-content privacy contract) even though the widget stays
      // in the tree with its state.
      final semantics = tester.ensureSemantics();
      tester.state<WalletCardDeckState>(
        find.byType(WalletCardDeck),
      ).tuck();
      await _settle(tester);
      expect(_deckState(tester), WalletDeckState.tucked);
      expect(find.bySemanticsLabel('Available'), findsNothing,
          reason: 'the tucked pouch must cover the breakdown face too — '
              'privacy is physical, so a flipped card cannot leak');
      semantics.dispose();
    },
  );

  testWidgets(
    'the Visa gate: a passed PIN mounts the details panel below the deck',
    (tester) async {
      await _pumpHome(tester);

      await tester.tap(find.bySemanticsLabel('Open AZM Visa card').first);
      await _settle(tester);

      // The gate sheet is up BEFORE any details exist.
      expect(_deckState(tester), WalletDeckState.visaOut);
      expect(find.byType(AzmCardDetailsPanel), findsNothing);
      expect(find.text('Unlock card details'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock card details'));
      await _settle(tester);

      expect(find.byType(CardPinGateSheet), findsNothing);
      expect(find.byType(AzmCardDetailsPanel), findsOneWidget,
          reason: 'a verified PIN mounts the sensitive details panel');
      expect(find.textContaining('SAMPLE'), findsWidgets,
          reason: 'the panel renders the demo programme data');
    },
  );

  testWidgets(
    'a dismissed gate re-tucks the deck — the Visa card never lingers out '
    'with locked details',
    (tester) async {
      await _pumpHome(tester);

      await tester.tap(find.bySemanticsLabel('Open AZM Visa card').first);
      await _settle(tester);
      expect(find.text('Unlock card details'), findsOneWidget);

      // Cancel without entering anything — dismiss the sheet via the
      // modal barrier (there is no cancel button; barrier tap and system
      // back are the only dismissal paths).
      await tester.tapAt(const Offset(200, 20));
      await _settle(tester);

      expect(_deckState(tester), WalletDeckState.tucked,
          reason: 'a cancelled gate must return the deck to the pouch');
      expect(find.byType(AzmCardDetailsPanel), findsNothing);
    },
  );

  testWidgets(
    'a PIN result arriving AFTER a re-lock never unlocks: backgrounding '
    'while the gate is pending invalidates the attempt',
    (tester) async {
      await _pumpHome(tester);

      // Open the Visa card — the gate sheet is up, the result pending.
      await tester.tap(find.bySemanticsLabel('Open AZM Visa card').first);
      await _settle(tester);
      expect(find.text('Unlock card details'), findsOneWidget);
      expect(_deckState(tester), WalletDeckState.visaOut);

      // The app loses focus while the gate is STILL pending: the deck
      // re-tucks and the in-flight attempt is invalidated.
      tester
          .binding
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _settle(tester);
      expect(_deckState(tester), WalletDeckState.tucked);

      // Canonical resume sequence (paused→hidden→inactive→resumed — the
      // framework's lifecycle state machine rejects a direct jump).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester
          .binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester
          .binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);

      // The sheet is still up; the user now completes the STALE gate
      // with the correct PIN — the attempt itself verifies fine...
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock card details'));
      await _settle(tester);

      // ...but the deck must stay tucked and the details panel must
      // never mount: a successful PIN can only unlock the deck state
      // it was entered for.
      expect(_deckState(tester), WalletDeckState.tucked,
          reason: 'the stale gate cannot re-open the deck');
      expect(find.byType(AzmCardDetailsPanel), findsNothing,
          reason: 'a PIN resolved after a re-lock must not unlock '
              'details');
    },
  );

  testWidgets(
    'app backgrounding re-locks: an out card with unlocked details drops '
    'back to the tucked pouch',
    (tester) async {
      await _pumpHome(tester);

      // Unlock the Visa details first (as in the passing-gate test).
      await tester.tap(find.bySemanticsLabel('Open AZM Visa card').first);
      await _settle(tester);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock card details'));
      await _settle(tester);
      expect(find.byType(AzmCardDetailsPanel), findsOneWidget);
      expect(_deckState(tester), WalletDeckState.visaOut);

      // The app loses focus — notification shade, app switcher, anything.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _settle(tester);

      expect(_deckState(tester), WalletDeckState.tucked,
          reason: 'backgrounding must tuck the deck');
      expect(find.byType(AzmCardDetailsPanel), findsNothing,
          reason: 'backgrounding must drop unlocked card details');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(_deckState(tester), WalletDeckState.tucked,
          reason: 'resuming does NOT re-open anything');
    },
  );
}
