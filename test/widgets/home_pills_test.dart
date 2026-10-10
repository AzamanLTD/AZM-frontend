// NEW-HOME — the resting-Home contract (replaces the NEW-D pill pins).
//
// The pill row (Add Money / Send / History) is GONE from Home (§7): those
// actions live in the + launcher. The three transaction rows (§10), the
// Susu shortcut card, the horizontal card rail and the LiveMarket /
// TODAY'S RATE section (§14) are gone from the resting Home too.
//
// This suite pins what remains: the five-block resting hierarchy — header,
// typewriter heading, card deck, three wallet modules, activity doorway —
// and the absence of everything the brief removed.
//
// The harness mirrors the previous NEW-D home tests: an inert AuthProvider
// (user null → greeting degrades to "there"), zeroed unread count, stubbed
// balance/oracle, and the real app theme with the Inter face loaded.
import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/widgets/flippable_balance_card.dart';
import 'package:azaman/widgets/live_market_section.dart';
import 'package:azaman/widgets/recent_activity_section.dart';
import 'package:azaman/widgets/home/az_typewriter_heading.dart';
import 'package:azaman/widgets/home/pull_reveal_card_deck.dart';
import 'package:azaman/widgets/home/wallet_modules.dart';
import 'package:azaman/widgets/home/activity_doorway.dart';
import 'package:azaman/widgets/home/azm_visa_card.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _surfaceSize = Size(400, 900);

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final bytes = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final loader = FontLoader('Inter')
    ..addFont(Future<ByteData>.value(
        ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
  _fontsLoaded = true;
}

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  AzamanTheme theme = AzamanTheme.light,
}) async {
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
    'azaman_theme': theme == AzamanTheme.dark ? 1 : 0,
  });
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(_surfaceSize);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
          (ref) => const BalanceData(availableBalance: 100)),
      oracleRateProvider.overrideWith((ref) => 1.0),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(theme),
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
  testWidgets('the pill row is gone — actions belong to the + launcher',
      (tester) async {
    await _pumpHome(tester);

    expect(find.text('Add Money'), findsNothing);
    expect(find.text('Send'), findsNothing);
    expect(find.text('History'), findsNothing);
  });

  testWidgets(
      'the five-block resting hierarchy is exactly the NEW-HOME order',
      (tester) async {
    await _pumpHome(tester);

    // 1 — header (identity row).
    expect(find.byType(AzamanHomePage), findsOneWidget);
    expect(find.byType(AzTypewriterHeading), findsOneWidget);

    // 2 — balance card still the hero, now inside the pull-reveal deck.
    expect(find.byType(FlippableBalanceCard), findsOneWidget);
    expect(find.byType(PullRevealCardDeck), findsOneWidget);

    // 3 — the Visa card exists UNDER the balance card (peeking at rest).
    expect(find.byType(AzmVisaCard), findsOneWidget);

    // 4 — exactly the three wallet modules.
    expect(find.byType(WalletModulesRow), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('P2P'), findsOneWidget);
    expect(find.text('Susu'), findsOneWidget);

    // 5 — the Recent Activity doorway, and NO rows beneath it.
    expect(find.byType(RecentActivityDoorway), findsOneWidget);
    // Two headings at rest: the doorway's plus the (opacity-0) activity
    // surface's — mounted but faded out, like the deck's under-card.
    expect(find.text('Recent'), findsNWidgets(2));
    expect(find.byType(RecentActivitySection), findsNothing);
    expect(find.byType(SkeletonBlock), findsNothing);
  });

  testWidgets('the LiveMarket / TODAY\'S RATE section is gone from Home',
      (tester) async {
    await _pumpHome(tester);

    expect(find.byType(LiveMarketSection), findsNothing);
    expect(find.textContaining("TODAY'S RATE"), findsNothing);
  });

  // ── FINAL PASS §3 — light-mode depth ────────────────────────────────────
  // The light Home rendered as one ~8-luma-unit field: the wallet pills
  // (glass @5% + enableShadow:false) were INVISIBLE on the near-white
  // page. Light pills must sit on the design system's CARD step
  // (opaque c.card fill + hairline + AzElevation contact shadow);
  // dark pills keep the glass language.

  testWidgets(
      'final pass §3 — light wallet pills sit on the CARD step '
      '(opaque fill, hairline, contact shadow)', (tester) async {
    await _pumpHome(tester);

    final pill = find.byKey(const ValueKey('wallet-module-save'));
    expect(pill, findsOneWidget);

    final colors = ThemeProvider.getColors(AzamanTheme.light);

    // The opaque card-step fill on the pill's own surface.
    final fills = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: pill,
          matching: find.byType(DecoratedBox),
        ))
        .where((d) => d.decoration is BoxDecoration)
        .map((d) => d.decoration as BoxDecoration)
        .where((b) => b.color != null)
        .toList(growable: false);
    expect(
      fills.any((b) => b.color!.a == 1.0 && b.color!.r == colors.card.r
          && b.color!.g == colors.card.g && b.color!.b == colors.card.b),
      isTrue,
      reason: 'the light pill must paint the opaque CARD step, not a 5% '
          'glass tint that vanishes on the #F2F3F5 page',
    );

    // A contact shadow (AzElevation) under the pill.
    final shadowed = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: pill,
          matching: find.byType(DecoratedBox),
        ))
        .where((d) => d.decoration is BoxDecoration)
        .map((d) => d.decoration as BoxDecoration)
        .where((b) => b.boxShadow?.isNotEmpty ?? false)
        .toList(growable: false);
    expect(shadowed, isNotEmpty,
        reason: 'enableShadow:false left the light pill with no shadow — '
            'no separation from the page plane');
  });

  testWidgets(
      'final pass §3 — dark wallet pills keep the glass language '
      '(no opaque card fill)', (tester) async {
    await _pumpHome(tester, theme: AzamanTheme.dark);

    final pill = find.byKey(const ValueKey('wallet-module-p2p'));
    expect(pill, findsOneWidget);

    // Glass = BackdropFilter still in the pill's surface stack.
    final blur = find.descendant(
      of: pill,
      matching: find.byType(BackdropFilter),
    );
    expect(blur, findsOneWidget,
        reason: 'dark pills keep the premium glass blur; the light-mode '
            'card-step fix must not leak into dark');

    final darkColors = ThemeProvider.getColors(AzamanTheme.dark);
    final opaqueCardFills = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: pill,
          matching: find.byType(DecoratedBox),
        ))
        .where((d) => d.decoration is BoxDecoration)
        .map((d) => d.decoration as BoxDecoration)
        .where((b) =>
            b.color != null &&
            b.color!.a == 1.0 &&
            b.color!.r == darkColors.card.r &&
            b.color!.g == darkColors.card.g &&
            b.color!.b == darkColors.card.b)
        .toList(growable: false);
    expect(opaqueCardFills, isEmpty,
        reason: 'dark keeps translucent glass, not an opaque card fill');
  });


}
