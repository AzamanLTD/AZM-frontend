// =============================================================================
// WALLET POUCH — visual evidence suite (2026-10-16 follow-up review).
//
// Captures PNG screenshots of the REAL Home composition (not isolated
// sample cards) for the PR review record:
//
//   dark/tucked.png        — both cards tucked, both exposed headers natural
//   dark/balance_out.png   — the balance card out; the SAME brand header
//                            that was visible while tucked, now travelling
//   dark/visa_out.png      — Visa out + unlocked details panel; proof the
//                            concealed balance card cannot spill below the
//                            deck into Home content
//   light/tucked.png      + light/balance_out.png — the shared PremiumCardRim
//                            edge treatment in light mode
//
// The captures land in .screenshots/ (untracked, ephemeral — reviewers get
// them attached to the PR). Each capture also asserts the expected deck
// state so the file doubles as a state-pose regression guard.
// =============================================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/providers/auth_provider.dart';
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
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _surfaceSize = Size(400, 900);
const _rootKey = Key('shot-root');

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final inter = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final interLoader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(inter).buffer)),
    );
  await interLoader.load();
  final regular =
      await File('assets/fonts/ComicNeue-Regular.ttf').readAsBytes();
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

class _NoopHistoryNotifier extends TransactionHistoryNotifier {
  @override
  Future<void> loadMore() async {}
}

/// A programme whose PIN is already set, so the Visa capture can unlock the
/// details panel without the two-stage first-PIN flow.
class _PinnedProgramme implements AzmCardProgramme {
  String? _pin;

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

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required AzamanTheme theme,
}) async {
  // The Home composition reads its colours from themeProvider (NOT the
  // MaterialApp theme), so the theme is seeded through the provider with
  // the same persisted index the real app boots from:
  //   0 = light, 1 = dark (see ThemeProvider._loadSavedTheme).
  SharedPreferences.setMockInitialValues({
    'azaman_theme': theme == AzamanTheme.dark ? 1 : 0,
  });
  final themeProviderInstance = ThemeProvider();
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(_surfaceSize);

  final container = ProviderContainer(
    overrides: [
      themeProvider.overrideWith((ref) => themeProviderInstance),
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
        theme: ThemeProvider.getThemeData(theme),
        home: const MediaQuery(
          data: MediaQueryData(size: _surfaceSize),
          child: Scaffold(
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

class _NoopHomeSummaryNotifier extends HomeSummaryNotifier {
  _NoopHomeSummaryNotifier(super.ref, super.service);
}

/// Fixed-duration settle (the real Home loops ambient animations forever).
Future<void> _settle(WidgetTester tester, {int rounds = 3}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Captures the RepaintBoundary around the Home page to a PNG on disk.
///
/// `toImage`/file IO need REAL async — the test's FakeAsync zone never
/// completes them, so the capture runs inside `tester.runAsync`.
Future<void> _capture(WidgetTester tester, String name) async {
  var ok = false;
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_rootKey));
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = (await image.toByteData(format: ImageByteFormat.png))!;
    final dir = Directory('.screenshots')..createSync(recursive: true);
    final file = File('${dir.path}/$name.png');
    await file.writeAsBytes(data.buffer.asUint8List());
    ok = file.lengthSync() > 1000;
  });
  expect(ok, isTrue, reason: '$name.png must contain real image bytes');
}

WalletDeckState _deckState(WidgetTester tester) =>
    tester.state<WalletCardDeckState>(find.byType(WalletCardDeck)).state;

void main() {
  testWidgets('dark mode: tucked → balance-out → visa-out captures',
      (tester) async {
    await _pumpHome(tester, theme: AzamanTheme.dark);

    // 1. TUCKED — both cards in the pouch, both headers exposed.
    expect(_deckState(tester), WalletDeckState.tucked);
    expect(find.text('Azaman Balance'), findsOneWidget);
    await _settle(tester);
    await _capture(tester, 'dark_tucked');

    // 2. BALANCE OUT — the same brand header, now travelling with the
    //    extracted card.
    await tester.tap(find.bySemanticsLabel('Reveal balance card').first);
    await _settle(tester, rounds: 5);
    expect(_deckState(tester), WalletDeckState.balanceOut);
    expect(find.text('Azaman Balance'), findsOneWidget,
        reason: 'the header is the card\'s own — one widget in both states');
    await _capture(tester, 'dark_balance_out');

    // Return to tucked, then open the Visa card.
    tester.state<WalletCardDeckState>(find.byType(WalletCardDeck)).tuck();
    await _settle(tester, rounds: 5);

    // 3. VISA OUT + UNLOCKED PANEL — the full end state; the concealed
    //    balance card must not bleed below the deck.
    await tester.tap(find.bySemanticsLabel('Open AZM Visa card').first);
    await _settle(tester, rounds: 5);
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Unlock card details'));
    await _settle(tester, rounds: 5);
    expect(_deckState(tester), WalletDeckState.visaOut);

    // Geometry proof inside the capture: the concealed balance card's
    // bottom sits at or above the deck window's floor.
    final windowBottom =
        tester.getBottomLeft(find.byKey(const ValueKey('wallet-deck-window'))).dy;
    final balanceBottom =
        tester.getBottomLeft(find.byKey(const ValueKey('wallet-deck-balance-slot'))).dy;
    expect(balanceBottom, lessThanOrEqualTo(windowBottom + 0.5));
    await _capture(tester, 'dark_visa_out');
  });

  testWidgets('light mode: the shared rim edge treatment', (tester) async {
    await _pumpHome(tester, theme: AzamanTheme.light);

    expect(_deckState(tester), WalletDeckState.tucked);
    await _settle(tester);
    await _capture(tester, 'light_tucked');

    await tester.tap(find.bySemanticsLabel('Reveal balance card').first);
    await _settle(tester, rounds: 5);
    expect(_deckState(tester), WalletDeckState.balanceOut);
    await _capture(tester, 'light_balance_out');
  });
}
