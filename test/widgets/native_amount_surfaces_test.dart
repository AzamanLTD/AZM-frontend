// =============================================================================
// NATIVE AMOUNT SURFACE TESTS — Workstream D1 permanent guards
//
// The honest-display rule for every personal-money surface: USDC is the
// native denomination of record; a GHS reading may appear only as a
// labelled current estimate at a usable oracle rate, and NO editable
// surface may offer a currency wheel (an authoritative GHS principal
// awaits the reviewed GHS-authority backend contract — plan v3 §7).
//
// The money-truth of NativeAmountText / AmountEntryEquivalent themselves
// is guarded by test/widgets/native_amount_display_test.dart (11 cases).
// These tests pin the SURFACE wiring: the estimate line renders under the
// editable USDC fields, tracks typing, honestly omits at a stale rate,
// and no editable surface ever grows a wheel or a settlement claim.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/models/escrow_models.dart';
import 'package:azaman/providers/currency_provider.dart';
import 'package:azaman/providers/smart_route_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/vault_provider.dart' show Vault;
import 'package:azaman/screens/smart_route/smart_route_create_screen.dart';
import 'package:azaman/screens/susu/susu_config_screen.dart';
import 'package:azaman/screens/vault/vault_create_screen.dart';
import 'package:azaman/widgets/currency_wheel_toggle.dart';
import 'package:azaman/widgets/escrow_status_panel.dart';
import 'package:azaman/widgets/escrow_vault_rail.dart';
import 'package:azaman/widgets/money/native_amount_display.dart';
import 'package:azaman/widgets/smart_route/smart_route_card.dart';
import 'package:azaman/widgets/vault/vault_progress_card.dart';

DateTime get _nowUtc => DateTime.now().toUtc();

/// A snapshot observed seconds ago: usable for the duration of a test tick.
/// Mirrors the canonical KOTANI retail shape (serverFresh verdict + external
/// observation metadata), per test/widgets/native_amount_display_test.dart.
FxRateSnapshot _freshSnapshot({double ghsPerUsdc = 15.38}) {
  final now = _nowUtc;
  return FxRateSnapshot(
    ghsPerUsdc: ghsPerUsdc,
    source: 'KOTANI',
    lastSync: now,
    fetchedAt: now,
    serverFresh: true,
    lastExternalSync: now,
    externalRateAgeSeconds: 0,
    rateFreshnessMaxAgeSeconds: 60,
  );
}

/// A server-FRESH verdict whose external observation is long past its
/// threshold: must yield NO estimate (the observation, not the response,
/// carries freshness — PR #165 review §2).
FxRateSnapshot _staleSnapshot() {
  final now = _nowUtc;
  return FxRateSnapshot(
    ghsPerUsdc: 15.38,
    source: 'KOTANI',
    lastSync: now,
    fetchedAt: now,
    serverFresh: true,
    lastExternalSync: now.subtract(const Duration(hours: 72)),
    externalRateAgeSeconds: 72 * 3600,
    rateFreshnessMaxAgeSeconds: 60,
  );
}

Widget _host(Widget child, {FxRateSnapshot? snapshot}) => ProviderScope(
  overrides: [fxRateProvider.overrideWith((ref) async => snapshot)],
  child: MaterialApp(
    home: Scaffold(body: SizedBox(width: 390, child: child)),
  ),
);

/// The Semantics label of the first AmountEntryEquivalent's wrapper —
/// the a11y tree must carry the same truthful context as the pixels.
String _semanticsLabel(WidgetTester tester) {
  final props = tester
      .widgetList<Semantics>(
        find.descendant(
          of: find.byType(AmountEntryEquivalent),
          matching: find.byType(Semantics),
        ),
      )
      .map((s) => s.properties.label ?? '')
      .where((l) => l.isNotEmpty)
      .join(' ');
  return props;
}

/// All Text data inside the first AmountEntryEquivalent on the surface.
String _equivalentText(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(AmountEntryEquivalent),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data ?? '')
      .join(' ');
  return texts;
}

// ═════════════════════════════════════════════════════════════════════════════
// D1 REVIEW CORRECTIONS — every changed display path, pinned.
//
// The 2026-10-20 review found two blockers: an estimate could render without
// its visible label (primary-only inline), and Vault comparisons could mix
// denominations. These tests pin the corrected contracts on the real
// widgets: same-unit comparison rows, labelled estimate lines, native-only
// narrow rails, no-wheel, and preference-flip invariance.
// ═════════════════════════════════════════════════════════════════════════════

Vault _vault({double current = 500, double target = 1000}) => Vault(
  id: 'v1',
  name: 'Emergency fund',
  targetAmountUsdc: target,
  currentAmountUsdc: current,
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

SmartEscrow _escrow({double amount = 20}) => SmartEscrow(
  id: 'esc_1',
  ticketId: 'tkt_1',
  payerId: 10,
  payeeId: 20,
  amountUsdc: amount,
  feeUsdc: 0.5,
  status: EscrowStatus.funded,
  payerSatisfied: false,
  payeeSatisfied: false,
  fundedAt: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(days: 3)),
);

/// A fresh container with the pinned rate snapshot and the display
/// preference set on the REAL CurrencyNotifier (the loader's prefs call
/// cannot resolve in the test env, so the assigned state stands).
ProviderContainer _container({
  FxRateSnapshot? snapshot,
  DisplayCurrency pref = DisplayCurrency.usdc,
}) => ProviderContainer(
  overrides: [fxRateProvider.overrideWith((ref) async => snapshot)],
)..read(currencyProvider.notifier).state = pref;

Widget _surface(ProviderContainer c, Widget child) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(
    home: Scaffold(body: SizedBox(width: 390, child: child)),
  ),
);

/// Wraps a colors-dependent widget with the live theme provider, exactly the
/// way the real screens feed their cards.
class _Themed extends ConsumerWidget {
  final Widget Function(AzamanColors colors) make;
  const _Themed(this.make);
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      make(ref.watch(themeProvider).colors);
}

String _texts(WidgetTester tester, Finder of) => tester
    .widgetList<Text>(find.descendant(of: of, matching: find.byType(Text)))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join(' § ');

void main() {
  group('SusuConfig contribution field', () {
    testWidgets('shows the labelled GHS estimate under a usable rate', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SusuConfigScreen(groupChatId: 'gc_1'),
          snapshot: _freshSnapshot(),
        ),
      );
      await tester.enterText(find.byType(TextField).first, '20');
      await tester.pump();
      expect(find.byType(AmountEntryEquivalent), findsOneWidget);
      expect(_equivalentText(tester), contains('USDC'));
      expect(_equivalentText(tester), contains('estimate'));
      // 20 USDC × 15.38 — the estimate tracks typing at the pinned rate.
      expect(_equivalentText(tester), contains('307.60'));
      // Configuration context, NOT a settlement claim: the note says the
      // contribution is DENOMINATED in USDC — nothing has settled yet.
      expect(
        _equivalentText(tester),
        contains('contribution amount denominated in USDC'),
      );
      expect(_equivalentText(tester), isNot(contains('settled')));
      // Accessibility semantics carry the same truthful context.
      final semantics = _semanticsLabel(tester);
      expect(semantics, contains('contribution amount denominated in USDC'));
      expect(semantics, isNot(contains('settled')));
    });

    testWidgets('honestly omits the estimate when the rate is stale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SusuConfigScreen(groupChatId: 'gc_1'),
          snapshot: _staleSnapshot(),
        ),
      );
      await tester.enterText(find.byType(TextField).first, '20');
      await tester.pump();
      expect(find.byType(AmountEntryEquivalent), findsOneWidget);
      // Honest fallback: names the unavailability, shows NO figure — the
      // absence is a labelled state, not a blank space (F-052 style).
      expect(_equivalentText(tester), contains('unavailable'));
      expect(_equivalentText(tester), isNot(contains('307')));
      expect(_equivalentText(tester), isNot(contains('GH\u2085')));
    });

    testWidgets('never offers a currency wheel', (tester) async {
      await tester.pumpWidget(
        _host(
          const SusuConfigScreen(groupChatId: 'gc_1'),
          snapshot: _freshSnapshot(),
        ),
      );
      expect(find.byType(CurrencyWheelToggle), findsNothing);
    });
  });

  group('SmartRouteCreate amount field', () {
    testWidgets('shows the labelled GHS estimate under a usable rate', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const SmartRouteCreateScreen(), snapshot: _freshSnapshot()),
      );
      // Field order: Name, Amount — target the amount by its hint.
      final amountField = find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText ?? '') == '100.00',
      );
      await tester.enterText(amountField, '100');
      await tester.pump();
      expect(find.byType(AmountEntryEquivalent), findsOneWidget);
      // 100 USDC × 15.38.
      expect(_equivalentText(tester), contains('1,538'));
      expect(_equivalentText(tester), contains('estimate'));
      // Planned route, not a settlement: the note is denominated-only.
      expect(
        _equivalentText(tester),
        contains('planned amount denominated in USDC'),
      );
      expect(_equivalentText(tester), isNot(contains('settled')));
      expect(
        _semanticsLabel(tester),
        contains('planned amount denominated in USDC'),
      );
      expect(find.byType(CurrencyWheelToggle), findsNothing);
    });

    testWidgets('honestly omits the estimate when the rate is stale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const SmartRouteCreateScreen(), snapshot: _staleSnapshot()),
      );
      final amountField = find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText ?? '') == '100.00',
      );
      await tester.enterText(amountField, '100');
      await tester.pump();
      expect(_equivalentText(tester), contains('unavailable'));
      expect(_equivalentText(tester), isNot(contains('1,538')));
    });
  });

  group('VaultCreate target and auto-deposit fields', () {
    /// The rules sheet auto-opens on first build and pointer-absorbs the
    /// form until accepted: every Vault test must walk the REAL gate
    /// (scroll the contract, consent, agree) exactly as a user does.
    Future<void> acceptRules(WidgetTester tester) async {
      final rulesScroll = find.ancestor(
        of: find.text('1. Lockup'),
        matching: find.byType(Scrollable),
      );
      // Scroll to the CONTRACT'S BOTTOM, not merely until the last rule
      // is visible: the consent gate reads maxScrollExtent, and stopping
      // early leaves the checkbox disabled (flaky on font metric shifts).
      // Drive the scroll position directly: drag gestures here are eaten by
      // the sheet's own drag-dismiss system, and tree-existence-based
      // helpers stop ~3px short of the gate. jumpTo hits the exact
      // maxScrollExtent the gate reads, deterministically on every run.
      final position = tester.state<ScrollableState>(rulesScroll).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      // The gate is honest: consent only arms once fully scrolled.
      final consent = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(
        consent.onChanged,
        isNotNull,
        reason: 'consent checkbox must arm after scrolling the contract',
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
        reason: 'consent checkbox must flip on tap',
      );
      final agree = tester
          .widget<ElevatedButton>(
            find.ancestor(
              of: find.text('I Agree — Continue'),
              matching: find.byType(ElevatedButton),
            ),
          )
          .onPressed;
      expect(
        agree,
        isNotNull,
        reason: 'accept button must arm once scrolled + consented',
      );
      await tester.tap(find.text('I Agree — Continue'));
      // The sheet's exit route animation needs elapsed frames; explicit pumps.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(
        find.text('I Agree — Continue'),
        findsNothing,
        reason: 'rules sheet must close after agreement',
      );
    }

    testWidgets('shows the labelled estimate under both editable amounts', (
      tester,
    ) async {
      // A real Ghanaian phone surface (390x844 @3x): the rules sheet's
      // consent row sits below the fold on the default 800x600 test
      // surface. tester.view (not binding.setSurfaceSize — whose metrics
      // never reach the modal route here) keeps the screen and the sheet
      // measuring one viewport.
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(const VaultCreateScreen(), snapshot: _freshSnapshot()),
      );
      // Frame 1 pushes the rules route via a post-frame callback; the
      // entrance then needs real elapsed frames to settle. Explicit pumps,
      // never pumpAndSettle — the screen behind runs perpetual animations.
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await acceptRules(tester);
      // Field order: name, target, auto-deposit amount.
      final targetField = find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText ?? '') == '500.00',
      );
      await tester.enterText(targetField, '500');
      await tester.pump();
      expect(find.byType(AmountEntryEquivalent), findsAtLeast(1));
      // 500 USDC × 15.38.
      expect(_equivalentText(tester), contains('7,690'));
      expect(_equivalentText(tester), contains('estimate'));
      // Entry context: the target note is denominated-only — no
      // settlement claim at creation time.
      expect(_equivalentText(tester), contains('target denominated in USDC'));
      expect(_equivalentText(tester), isNot(contains('settled')));
      expect(_semanticsLabel(tester), contains('target denominated in USDC'));
      expect(find.byType(CurrencyWheelToggle), findsNothing);

      // The auto-deposit rule sits behind its enable switch and below
      // the fold: flip the rule on, bring the amount field on-screen,
      // and give it a value so its own estimate line builds.
      final ruleSwitch = find.byType(Switch);
      expect(ruleSwitch, findsOneWidget);
      await tester.ensureVisible(ruleSwitch);
      await tester.tap(ruleSwitch);
      await tester.pump();
      final autoField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText ?? '') == 'Amount per deposit (USDC)',
      );
      expect(autoField, findsOneWidget);
      await tester.ensureVisible(autoField);
      await tester.pump();
      await tester.enterText(autoField, '50');
      await tester.pump();
      expect(find.byType(AmountEntryEquivalent), findsAtLeast(2));
      expect(
        _equivalentText(tester),
        contains('auto-deposit amount denominated in USDC'),
      );
      expect(_equivalentText(tester), isNot(contains('settled')));
    });

    testWidgets('honestly omits the estimate when the rate is stale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(const VaultCreateScreen(), snapshot: _staleSnapshot()),
      );
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await acceptRules(tester);
      final targetField = find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText ?? '') == '500.00',
      );
      await tester.enterText(targetField, '500');
      await tester.pump();
      // A stale observation must yield NO converted figure: the honest
      // answer is "unavailable", never a silently wrong number.
      expect(_equivalentText(tester), contains('unavailable'));
      expect(_equivalentText(tester), isNot(contains('7,690')));
    });
  });

  // ── Vault comparison surfaces stay same-unit (review blocker B) ──────────
  group('VaultProgressCard comparison row', () {
    testWidgets('GHS preference: both comparison slots stay USDC; the GHS '
        'estimate is its own labelled line', (tester) async {
      await tester.pumpWidget(
        _surface(
          _container(snapshot: _freshSnapshot(), pref: DisplayCurrency.ghs),
          _Themed(
            (colors) => VaultProgressCard(
              vault: _vault(),
              colors: colors,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final row = _texts(tester, find.byType(VaultProgressCard));
      // The comparison itself never mixes denominations.
      expect(row, contains('500.00 USDC'));
      expect(row, contains('1000.00 USDC'));
      // The GHS estimate exists, is labelled, and mentions the vault's
      // balance — never posed as comparable to the USDC target.
      expect(row, contains('7,690.00'));
      expect(row, contains('current estimate'));
      expect(row, contains('vault balance held in USDC'));
      // No wheel ever appears on these read-only surfaces.
      expect(find.byType(CurrencyWheelToggle), findsNothing);
    });

    testWidgets('stale rate: no GHS figure anywhere, equivalence named '
        'unavailable, comparison intact', (tester) async {
      await tester.pumpWidget(
        _surface(
          _container(snapshot: _staleSnapshot(), pref: DisplayCurrency.ghs),
          _Themed(
            (colors) => VaultProgressCard(
              vault: _vault(),
              colors: colors,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final row = _texts(tester, find.byType(VaultProgressCard));
      expect(row, contains('500.00 USDC'));
      expect(row, contains('1000.00 USDC'));
      expect(row, contains('GHS equivalent unavailable'));
      expect(row, isNot(contains('GH₵')));
    });
  });

  // ── Susu pool composition: stacked, honest under GHS-first (blocker A) ────
  group('Susu pool stacked composition', () {
    testWidgets('GHS preference leads with the estimate, secondary names the '
        'native amount', (tester) async {
      await tester.pumpWidget(
        _surface(
          _container(snapshot: _freshSnapshot(), pref: DisplayCurrency.ghs),
          const NativeAmountDisplay(
            amountUsdc: 20,
            primaryStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
        ),
      );
      await tester.pump();

      final t = _texts(tester, find.byType(NativeAmountDisplay));
      expect(t, contains('GH₵'));
      expect(t, contains('307.60'));
      expect(t, contains('current estimate'));
      expect(t, contains('20.00 USDC'));
    });

    testWidgets('stale rate: native amount leads and the omission is named', (
      tester,
    ) async {
      await tester.pumpWidget(
        _surface(
          _container(snapshot: _staleSnapshot(), pref: DisplayCurrency.ghs),
          const NativeAmountDisplay(amountUsdc: 20),
        ),
      );
      await tester.pump();

      final t = _texts(tester, find.byType(NativeAmountDisplay));
      expect(t, contains('20.00 USDC'));
      expect(t, contains('GHS equivalent unavailable'));
      expect(t, isNot(contains('GH₵')));
    });
  });

  // ── Escrow surfaces: labelled estimate on the panel, native-only rail ────
  group('Escrow money surfaces', () {
    testWidgets('collapsed panel keeps a native title and a labelled '
        'estimate line under GHS preference', (tester) async {
      await tester.pumpWidget(
        _surface(
          _container(snapshot: _freshSnapshot(), pref: DisplayCurrency.ghs),
          _Themed(
            (colors) => EscrowStatusPanel(
              escrow: _escrow(),
              currentUserId: 10,
              isLoading: false,
              onFund: () async {},
              onSatisfy: () async => true,
              onDispute: (String reason, List<String> files) async {},
              onUpdateTerms: (String terms) async {},
              onCancel: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final panel = _texts(tester, find.byType(EscrowStatusPanel));
      // The tight title row stays native (no truncation risk for the label).
      expect(panel, contains('Escrow · '));
      expect(panel, contains('20.00 USDC'));
      // The estimate is present, labelled, and names the rail.
      expect(panel, contains('307.60'));
      expect(panel, contains('current estimate'));
      expect(panel, contains('held in USDC'));
    });

    testWidgets('rail slots stay native-only under GHS preference — a '
        'truncated estimate would be worse than none', (tester) async {
      await tester.pumpWidget(
        _surface(
          _container(snapshot: _freshSnapshot(), pref: DisplayCurrency.ghs),
          EscrowVaultRail(
            escrow: _escrow(amount: 20),
            currentUserId: 10,
            isLoading: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final amount = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(const ValueKey('escrow-rail-amount')),
          matching: find.byType(RichText),
        ),
      );
      expect(amount.text.toPlainText(), '20.00 USDC');
    });
  });

  // ── Smart route card: native caption, never a silent conversion ──────────
  group('SmartRouteCard caption', () {
    testWidgets('the card names the native denomination and shows no '
        'conversion claim or wheel', (tester) async {
      await tester.pumpWidget(
        _surface(
          _container(snapshot: _freshSnapshot(), pref: DisplayCurrency.ghs),
          _Themed(
            (colors) => SmartRouteCard(
              route: SmartRoute(
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
              ),
              colors: colors,
            ),
          ),
        ),
      );
      await tester.pump();

      final card = _texts(tester, find.byType(SmartRouteCard));
      expect(card, contains('20.00 USDC'));
      expect(card, isNot(contains('estimate')));
      expect(find.byType(CurrencyWheelToggle), findsNothing);
    });
  });

  // ── Preference flip: presentation only, never a payload mutation ─────────
  group('Preference flip invariance', () {
    testWidgets('flipping the display preference re-renders both honest '
        'forms without changing the amount', (tester) async {
      final c = _container(
        snapshot: _freshSnapshot(),
        pref: DisplayCurrency.usdc,
      );
      await tester.pumpWidget(
        _surface(
          c,
          const NativeAmountText(key: ValueKey('flip-target'), amountUsdc: 20),
        ),
      );
      await tester.pump();

      // The inline widget keeps BOTH parts verbatim: one RichText when
      // the composed line fits, lead + tail as two nodes when it wraps.
      // The truth test must read the whole rendered surface, not one node.
      String read() => tester
          .widgetList<RichText>(
            find.descendant(
              of: find.byKey(const ValueKey('flip-target')),
              matching: find.byType(RichText),
            ),
          )
          .map((r) => r.text.toPlainText())
          .join(' ');

      final usdcFirst = read();
      expect(usdcFirst, contains('20.00 USDC'));
      expect(usdcFirst, contains('estimate'));

      c.read(currencyProvider.notifier).state = DisplayCurrency.ghs;
      await tester.pump();
      final ghsFirst = read();
      expect(ghsFirst, contains('307.60'));
      expect(ghsFirst, contains('estimate'));
      // The native amount survives the flip — the estimate never replaces it.
      expect(ghsFirst, contains('20.00 USDC'));

      c.read(currencyProvider.notifier).state = DisplayCurrency.usdc;
      await tester.pump();
      expect(read(), usdcFirst); // deterministic, reversible, display-only
    });
  });

  // ── Deposit rows (vault detail): native amount only, type stays beside ───
  group('Vault deposit row composition', () {
    testWidgets('forceNative + no equivalent renders the plain USDC amount', (
      tester,
    ) async {
      await tester.pumpWidget(
        _surface(
          _container(snapshot: _freshSnapshot(), pref: DisplayCurrency.ghs),
          const NativeAmountText(
            amountUsdc: 20,
            forceNative: true,
            showEquivalent: false,
          ),
        ),
      );
      await tester.pump();

      final t = _texts(tester, find.byType(NativeAmountText));
      expect(t, '20.00 USDC');
    });
  });
}
