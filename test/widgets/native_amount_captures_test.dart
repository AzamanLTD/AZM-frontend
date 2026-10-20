// =============================================================================
// AZAMAN — D1 NATIVE-AMOUNT SURFACES: VISUAL CAPTURES (Workstream D1)
//
// Deliberate, reviewable goldens for every money-display surface the D1
// review corrections touched, in BOTH themes:
//
//   • Susu configuration (estimate line under the editable contribution)
//   • Smart Route creation (estimate under the amount field)
//   • Vault creation (estimate under the target, behind the real rules gate)
//   • A money-surfaces gallery: the stacked susu pool headline, the
//     same-unit vault progress comparison + labelled estimate line, the
//     collapsed escrow panel with its estimate strip, and the Smart Route
//     card caption.
//
// Widths 320 / 360 / 390 dp, short-height pairs where vertical layout is
// the risk. GHS display preference (the case the review blockers were
// about: estimates must stay labelled and native amounts must survive).
//
// Same hard rules as the Send and Card Transfer sets:
//   1. REAL FONTS — every face loaded through FontLoader before the first
//      pump; the cedi glyph falls through to DejaVuSans exactly as the
//      on-device OS fallback supplies it.
//   2. The rate is PINNED (fxRateProvider → 15.38, fresh) so every
//      estimate is deterministic: 20 USDC → GH₵ 307.60, 500 → GH₵ 7,690.00.
//   3. disableAnimations: entrances land at their end state.
//
// Generated with `flutter test --update-goldens`; any later regeneration
// must be a reviewable diff, never a green-maker.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/models/escrow_models.dart';
import 'package:azaman/providers/currency_provider.dart';
import 'package:azaman/providers/smart_route_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/vault_provider.dart' show Vault;
import 'package:azaman/screens/smart_route/smart_route_create_screen.dart';
import 'package:azaman/screens/susu/susu_config_screen.dart';
import 'package:azaman/screens/vault/vault_create_screen.dart';
import 'package:azaman/widgets/escrow_status_panel.dart';
import 'package:azaman/widgets/money/native_amount_display.dart';
import 'package:azaman/widgets/smart_route/smart_route_card.dart';
import 'package:azaman/widgets/vault/vault_progress_card.dart';

const _storageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

// ── Real fonts (FontLoader pattern; see test/goldens/README.md) ─────────────

bool _fontsLoaded = false;

Future<void> _loadFace(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(
      ByteData.view(Uint8List.fromList(bytes).buffer),
    ));
  await loader.load();
}

Future<void> _loadAppFonts() async {
  if (_fontsLoaded) return;
  await _loadFace('Inter', 'assets/fonts/Inter-Variable.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Regular.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Bold.ttf');
  await _loadFace(
      'MaterialIcons', 'test/goldens/fonts/MaterialIcons-Regular.otf');
  await _loadFace('DejaVuSans', 'test/goldens/fonts/DejaVuSans.ttf');
  _fontsLoaded = true;
}

ThemeData _harnessTheme(bool dark) {
  final base = ThemeProvider.getThemeData(
    dark ? AzamanTheme.dark : AzamanTheme.light,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: const ['DejaVuSans']),
  );
}

// ── Fixtures (same shapes as native_amount_surfaces_test.dart) ──────────────

FxRateSnapshot _pinnedRate() {
  final now = DateTime.now().toUtc();
  return FxRateSnapshot(
    ghsPerUsdc: 15.38,
    source: 'KOTANI',
    lastSync: now,
    fetchedAt: now,
    serverFresh: true,
    lastExternalSync: now,
    externalRateAgeSeconds: 0,
    rateFreshnessMaxAgeSeconds: 60,
  );
}

Vault _vault() => Vault(
      id: 'v1',
      name: 'Emergency fund',
      targetAmountUsdc: 1000,
      currentAmountUsdc: 500,
      status: 'ACTIVE',
      startDate: DateTime.now().subtract(const Duration(days: 10)),
      maturityDate: DateTime.now().add(const Duration(days: 80)),
      isLocked: true,
      earlyBreakPenaltyPct: 5,
      autoRuleEnabled: false,
      streakCount: 3,
      longestStreak: 3,
      missedCount: 0,
      consistencyScore: 1,
      totalAzmEarned: 12,
    );

SmartEscrow _escrow() => SmartEscrow(
      id: 'esc_1',
      ticketId: 'tkt_1',
      payerId: 10,
      payeeId: 20,
      amountUsdc: 20,
      feeUsdc: 0.5,
      status: EscrowStatus.funded,
      payerSatisfied: false,
      payeeSatisfied: false,
      fundedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 3)),
    );

SmartRoute _route() => SmartRoute(
      id: 'sr1',
      name: 'Rent savings',
      action: 'TRANSFER',
      amountUsdc: 20,
      frequency: 'MONTHLY',
      status: 'ACTIVE',
      startDate: DateTime.now(),
      nextRunAt: DateTime.now().add(const Duration(days: 7)),
      totalRuns: 3,
      totalRoutedUsdc: 60,
    );

/// The gallery: every read-side D1 money surface in one scrollable column,
/// fed the way the real screens feed them (live theme colors).
class _Gallery extends ConsumerWidget {
  const _Gallery();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    Widget section(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        section('Susu pool (stacked headline)'),
        const NativeAmountDisplay(
          amountUsdc: 20,
          primaryStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        Text(
          'Pool · 12 cycles · 2.00 USDC per cycle',
          style: TextStyle(color: colors.textTertiary, fontSize: 11),
        ),
        section('Vault progress (same-unit comparison)'),
        VaultProgressCard(
          vault: _vault(),
          colors: colors,
          onTap: () {},
        ),
        section('Escrow panel (collapsed + estimate strip)'),
        EscrowStatusPanel(
          escrow: _escrow(),
          currentUserId: 10,
          isLoading: false,
          onFund: () {},
          onSatisfy: () async => true,
          onDispute: (String reason, List<String> urls) async {},
          onUpdateTerms: (String terms) async {},
          onCancel: () {},
        ),
        section('Smart Route card (native caption)'),
        SmartRouteCard(route: _route(), colors: colors),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Harness ──────────────────────────────────────────────────────────────────

Future<void> _pumpSubject(
  WidgetTester tester, {
  required Widget child,
  required Size size,
  required bool dark,
}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
    if (call.method == 'read') return 'mock-token';
    return null;
  });
  SharedPreferences.setMockInitialValues({'azaman_theme': dark ? 1 : 0});
  tester.view
    ..physicalSize = size * 3.0
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.runAsync(_loadAppFonts);

  // GHS display preference on the REAL notifier: the reviewer's blockers
  // were about exactly this preference (estimates leading must stay
  // labelled, native amounts must survive).
  final container = ProviderContainer(overrides: [
    fxRateProvider.overrideWith((ref) async => _pinnedRate()),
  ]);
  container.read(currencyProvider.notifier).state = DisplayCurrency.ghs;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _harnessTheme(dark),
        // disableAnimations must be the INNER MediaQuery — the one widgets
        // actually read (test/goldens/README.md). Outside MaterialApp it is
        // overwritten, the panel's detent never lands, and gate taps hit a
        // mid-transition surface.
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: RepaintBoundary(child: child),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Walks the REAL vault rules gate: scroll the contract to its bottom, tap
/// consent, agree. Mirrors native_amount_surfaces_test.dart.
Future<void> _acceptRules(WidgetTester tester) async {
  final rulesScroll = find
      .ancestor(of: find.text('1. Lockup'), matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(rulesScroll).position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pump();
  // Real fonts make the contract taller than the test surface; the consent
  // row can sit below the fold — bring it on-screen BEFORE tapping, or the
  // tap silently misses and the gate never arms.
  final consent = find.ancestor(
    of: find.text('I have read and accept these rules.'),
    matching: find.byType(CheckboxListTile),
  );
  await tester.ensureVisible(consent);
  await tester.pump();
  // With the one-shot prompt flag, exactly ONE sheet exists.
  expect(find.byType(DraggableScrollableSheet), findsOneWidget);
  await tester.tap(consent);
  await tester.pump();
  final agree = find.text('I Agree — Continue');
  await tester.ensureVisible(agree);
  await tester.pump();
  await tester.tap(agree);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  // The capture is only meaningful if the gate actually closed.
  expect(find.text('I Agree — Continue'), findsNothing,
      reason: 'rules sheet must close before the capture');
}

Future<void> _capture(
  WidgetTester tester, {
  required String name,
  required Widget child,
  required Size size,
  required bool dark,
  Future<void> Function(WidgetTester)? afterPump,
}) async {
  await _pumpSubject(tester, child: child, size: size, dark: dark);
  if (afterPump != null) await afterPump(tester);
  await expectLater(
    find.byType(RepaintBoundary).first,
    matchesGoldenFile('../goldens/native_amount/$name.png'),
  );
}

void main() {
  setUpAll(() {
    final goldenDir = Directory('test/goldens/native_amount');
    if (!goldenDir.existsSync()) goldenDir.createSync(recursive: true);
  });

  const sizes = {
    '320': Size(320, 692),
    '360': Size(360, 800),
    '390': Size(390, 844),
    '320short': Size(320, 540),
  };

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    // ── The gallery at every width: the responsive D1 money surfaces ─────
    for (final e in sizes.entries) {
      testWidgets('gallery ${e.key} $mode', (tester) async {
        await _capture(
          tester,
          name: 'gallery_${e.key}_$mode',
          child: const Scaffold(body: _Gallery()),
          size: e.value,
          dark: dark,
        );
      });
    }

    // ── Susu configuration: estimate line under the editable field ───────
    testWidgets('susu config 390 $mode', (tester) async {
      await _capture(
        tester,
        name: 'susu_config_390_$mode',
        child: const SusuConfigScreen(groupChatId: 'gc_1'),
        size: const Size(390, 844),
        dark: dark,
        afterPump: (t) async {
          await t.enterText(find.byType(TextField).first, '20');
          await t.pump();
        },
      );
    });

    // ── Smart Route creation: estimate under the amount field ─────────────
    testWidgets('smart route create 390 $mode', (tester) async {
      await _capture(
        tester,
        name: 'smart_route_390_$mode',
        child: const SmartRouteCreateScreen(),
        size: const Size(390, 844),
        dark: dark,
        afterPump: (t) async {
          await t.enterText(find.byType(TextField).first, '20');
          await t.pump();
        },
      );
    });

    // ── Vault creation: behind the real rules gate, target estimate live ─
    for (final e in {
      '390': sizes['390']!,
      '320short': sizes['320short']!
    }.entries) {
      testWidgets('vault create ${e.key} $mode', (tester) async {
        await _capture(
          tester,
          name: 'vault_create_${e.key}_$mode',
          child: const VaultCreateScreen(),
          size: e.value,
          dark: dark,
          afterPump: (t) async {
            await _acceptRules(t);
            // Field order: name, TARGET, auto-deposit. Target by hint.
            final targetField = find.byWidgetPredicate((w) =>
                w is TextField && (w.decoration?.hintText ?? '') == '500.00');
            await t.enterText(targetField, '500');
            await t.pump();
            await t.pump(const Duration(milliseconds: 200));
            // The capture's meaning: the form, the typed target, and the
            // labelled estimate at the pinned rate (500 × 15.38).
            expect(find.text('I Agree — Continue'), findsNothing);
            expect(find.byType(TextField).evaluate().isNotEmpty, isTrue);
            expect(find.textContaining('7,690'), findsOneWidget,
                reason: 'the GH\u2085 7,690.00 estimate must be on screen');
          },
        );
      });
    }
  }
}
