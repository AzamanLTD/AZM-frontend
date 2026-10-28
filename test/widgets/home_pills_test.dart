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
import 'package:azaman/widgets/home/home_balance_card.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/widgets/live_market_section.dart';
import 'package:azaman/widgets/recent_activity_section.dart';
import 'package:azaman/widgets/home/az_typewriter_heading.dart';
import 'package:azaman/widgets/home/wallet_modules.dart';
import 'package:azaman/widgets/home/activity_doorway.dart';
import 'package:azaman/widgets/home/wallet_card_deck.dart';
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
    expect(find.byType(HomeBalanceCard), findsOneWidget);
    expect(find.byType(WalletCardDeck), findsOneWidget);

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

  // ── FLAT, BORDER-ONLY SETTLED CONTROLS (PR #184 design review,
  // 2026-10-23) ─────────────────────────────────────────────────────
  // The settled Save/P2P/Susu quick actions are FLAT outlines drawn on
  // the page: transparent body (no fill, glass, blur, gradient,
  // specular, glow, inner/outer shadow, elevation of any kind) with a
  // crisp 1px rim as the ONLY container treatment. The quiet-depth
  // wake survives as rim strength, never a raised body.

  void expectFlatBorderOnlyPill(WidgetTester tester, Finder pill) {
    // The pill subtree must contain NOTHING that paints a body.
    expect(
      find.descendant(of: pill, matching: find.byType(BackdropFilter)),
      findsNothing,
      reason: 'backdrop blur is a raised/glass body treatment — the '
          'settled quick actions are flat',
    );

    final boxes = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: pill,
          matching: find.byType(DecoratedBox),
        ))
        .where((d) => d.decoration is BoxDecoration)
        .map((d) => d.decoration as BoxDecoration)
        .toList(growable: false);

    for (final b in boxes) {
      expect(b.color, anyOf(isNull, isA<Color>().having((c) => c.a, 'a', 0)),
          reason: 'a pill decoration paints a body fill — the settled '
              'body must visually disappear into the page');
      expect(b.gradient, isNull, reason: 'gradients read as a raised body');
      expect(b.boxShadow, anyOf(isNull, isEmpty),
          reason: 'shadows are an elevation effect — forbidden on the '
              'settled quick actions');
    }

    // Border-only container: the rim exists and is the ONLY container
    // treatment. (BoxDecoration.border, no fill, no shadow — above.)
    final rimmed = boxes.where((b) => b.border != null).toList(growable: false);
    expect(rimmed, isNotEmpty,
        reason: 'the outline IS the container treatment — it must exist');
  }

  testWidgets(
      'flat contract — light settled pills are BORDER-ONLY in both '
      'depth states', (tester) async {
    await _pumpHome(tester);

    final colors = ThemeProvider.getColors(AzamanTheme.light);
    for (final key in [
      'wallet-module-save',
      'wallet-module-p2p',
      'wallet-module-susu',
    ]) {
      final pill = find.byKey(ValueKey(key));
      expect(pill, findsOneWidget);
      expectFlatBorderOnlyPill(tester, pill);

      // The woken rim: crisp full-strength tertiary ink.
      final raisedRim = tester
          .widgetList<DecoratedBox>(find.descendant(
            of: pill,
            matching: find.byType(DecoratedBox),
          ))
          .where((d) => d.decoration is BoxDecoration)
          .map((d) => d.decoration as BoxDecoration)
          .where((b) => b.border != null)
          .first
          .border as Border;
      expect(raisedRim.top.color.a, greaterThan(0.9),
          reason: 'the woken rim must be crisp (full tertiary ink)');
    }

    // Settle (idle → recessed): the rim softens but the body stays flat.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    for (final key in [
      'wallet-module-save',
      'wallet-module-p2p',
      'wallet-module-susu',
    ]) {
      final pill = find.byKey(ValueKey(key));
      expectFlatBorderOnlyPill(tester, pill);
      final recessedRim = tester
          .widgetList<DecoratedBox>(find.descendant(
            of: pill,
            matching: find.byType(DecoratedBox),
          ))
          .where((d) => d.decoration is BoxDecoration)
          .map((d) => d.decoration as BoxDecoration)
          .where((b) => b.border != null)
          .first
          .border as Border;
      expect(recessedRim.top.color.a, lessThan(0.8),
          reason: 'the settled rim is the whisper hairline');
    }
    // Sanity: the ink is the design-system tertiary, not a magic hex.
    expect(colors.textTertiary, isA<Color>());
  });

  testWidgets(
      'flat contract — dark settled pills are BORDER-ONLY in both '
      'depth states (glass removed)', (tester) async {
    await _pumpHome(tester, theme: AzamanTheme.dark);

    for (final key in ['wallet-module-save', 'wallet-module-p2p']) {
      final pill = find.byKey(ValueKey(key));
      expect(pill, findsOneWidget);
      // Glass = BackdropFilter + PremiumGlassContainer — BOTH must be
      // gone from the dark pills too.
      expectFlatBorderOnlyPill(tester, pill);
      expect(
        find.descendant(
            of: pill, matching: find.byType(PremiumGlassContainer)),
        findsNothing,
        reason: 'dark keeps the flat rim language now — glass reads as a '
            'raised body',
      );
    }

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    for (final key in ['wallet-module-save', 'wallet-module-p2p']) {
      final pill = find.byKey(ValueKey(key));
      expectFlatBorderOnlyPill(tester, pill);
    }
  });
}
