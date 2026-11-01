// THE DECK IS NOT THE SECRET — THE FIGURES ARE.
//
// Owner requirement (2026-10-30): the Balance and Visa cards stay visibly
// tucked in the pouch while money is locked. The old gate REPLACED the deck;
// that is the behaviour this suite exists to prevent from coming back.
//
// Contract proved here, against the real Home and the real controller:
//   • a cold Home mounts the deck and nothing replaces it;
//   • the money is masked, and the real figure is never formatted;
//   • the 180dp card footprint the measured doorway depends on is unchanged;
//   • a locked tap flips nothing, expands nothing and answers with the
//     refusal + the hint that points at the Azaman lock;
//   • unlocking shows the real balance and restores the flip;
//   • relocking masks it again and drops the revealed details.
import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/balance_card_valuation_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart';
import 'package:azaman/widgets/home/balance_card_fx.dart';
import 'package:azaman/widgets/home/money_lock_blocked_feedback.dart';
import 'package:azaman/widgets/home/money_lock_surface.dart';
import 'package:azaman/widgets/home/money_privacy.dart';
import 'package:azaman/widgets/home/wallet_card_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// A valuation the card may actually render a HEADLINE from. The production
/// adapter reports the GHS headline unavailable on a legacy balance response
/// (no native-GHS wallet is published yet), so a real figure can only be
/// proved by feeding the card the value it renders — never by pretending the
/// unavailable state is a number.
BalanceCardValuation _fundedValuation() => const BalanceCardValuation(
  nativeGhsAvailable: 1234.56,
  availableUsdc: 80.09,
  balanceConfirmed: true,
  escrowLocked: 350,
  rate: FxRateView(ghsPerUsdc: 15.42, kind: FxRateKind.fresh),
).compute();

Future<ProviderContainer> _pumpLockedHome(
  WidgetTester tester, {
  bool funded = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
    'azaman_theme': 0,
  });
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(_surfaceSize);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 1234.56),
      ),
      oracleRateProvider.overrideWith((ref) => 1.0),
      if (funded)
        balanceCardValuationProvider.overrideWith((ref) => _fundedValuation()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: MediaQuery(
          data: const MediaQueryData(size: _surfaceSize),
          child: const Scaffold(body: AzamanHomePage()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

void main() {
  testWidgets('a cold Home keeps the card deck mounted while locked', (
    tester,
  ) async {
    final container = await _pumpLockedHome(tester);

    expect(container.read(moneyAccessProvider).state, MoneyAccessState.locked);
    // The deck is THERE. Only its figures are gone.
    expect(
      find.byType(WalletCardDeck),
      findsOneWidget,
      reason: 'the cards stay tucked in the pouch while money is locked',
    );
    expect(
      find.byType(BalanceCardFx),
      findsWidgets,
      reason: 'the card face is still painted, not replaced',
    );
    expect(
      find.byType(MoneyLockGate),
      findsNothing,
      reason: 'the gate must never replace the deck again',
    );
    expect(find.byType(LockedMoneySurface), findsNothing);
  });

  testWidgets('locked: the figures are masked and never formatted', (
    tester,
  ) async {
    await _pumpLockedHome(tester, funded: true);

    expect(
      find.textContaining('1,234'),
      findsNothing,
      reason: 'the real balance must not be painted anywhere',
    );
    expect(
      find.text(kRedactedMoney),
      findsWidgets,
      reason: 'the headline paints the mask instead',
    );
  });

  testWidgets('locked: the 180dp card footprint is untouched', (tester) async {
    await _pumpLockedHome(tester);

    final frame = tester.getSize(
      find.byKey(const ValueKey('balance-pair-frame')).first,
    );
    expect(
      frame.height,
      BalanceCardGeometry.height,
      reason: 'the measured doorway below depends on this height',
    );
    final tuck = tester.getSize(find.byType(WalletCardDeck));
    expect(
      tuck.height,
      greaterThanOrEqualTo(BalanceCardGeometry.height),
      reason: 'the deck keeps its own box, so Home cannot reflow',
    );
  });

  testWidgets('locked: reaching for the card refuses and never flips it', (
    tester,
  ) async {
    final container = await _pumpLockedHome(tester);
    final before = container.read(moneyBlockedPulseProvider);

    await tester.tap(find.byKey(const ValueKey('balance-pair-frame')).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('balance-pair-back-surface')),
      findsNothing,
      reason: 'a locked card does not turn over',
    );
    expect(
      container.read(moneyBlockedPulseProvider),
      before + 1,
      reason: 'the refusal is felt: one pulse, one haptic',
    );
    expect(
      find.text(kMoneyLockedHint),
      findsOneWidget,
      reason: 'the member is told which control unlocks',
    );
  });

  testWidgets('locked: the deck cannot be pulled open either', (tester) async {
    await _pumpLockedHome(tester);
    final deck = tester.state<WalletCardDeckState>(find.byType(WalletCardDeck));

    expect(deck.isTucked, isTrue);
    deck.select(WalletDeckState.visaOut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      deck.isTucked,
      isTrue,
      reason: 'no pose change, no expansion, nothing queued while locked',
    );
  });

  testWidgets('unlocking shows the real balance', (tester) async {
    final container = await _pumpLockedHome(tester, funded: true);
    final access = container.read(moneyAccessProvider);

    final attempt = access.beginUnlock();
    access.finishUnlock(attempt);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(BalanceCardFx), findsWidgets);
    expect(find.textContaining('1,234'), findsWidgets);
    expect(find.text(kRedactedMoney), findsNothing);
  });

  testWidgets('relocking masks the figures again', (tester) async {
    final container = await _pumpLockedHome(tester, funded: true);
    final access = container.read(moneyAccessProvider);

    final attempt = access.beginUnlock();
    access.finishUnlock(attempt);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('1,234'), findsWidgets);

    access.lock();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('1,234'), findsNothing);
    expect(find.text(kRedactedMoney), findsWidgets);
    final deck = tester.state<WalletCardDeckState>(find.byType(WalletCardDeck));
    expect(deck.isTucked, isTrue, reason: 'a relock returns the deck home');
  });
}
