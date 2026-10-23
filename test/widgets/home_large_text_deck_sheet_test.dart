// LARGE-TEXT DECK DETAIL SHEET (PR #186 visual-accessibility review).
//
// The deck's fixed-geometry faces clamp visible text at measured maxima
// (1.25x front / 1.3x visa / 1.8x reminder). That clamp is correct for
// the geometry — but the review's requirement stands: a low-vision user
// at 2.0x system text needs the AMOUNT AND UNIT to actually appear
// larger, not merely be announced correctly by the screen reader.
//
// The large-text deck sheet is the fix; this suite pins its contract:
//
//   1.  the expand affordance is on the balance card at EVERY scale
//       (a low-vision user must be able to find it, not have it appear
//       only once they are already struggling);
//   2.  tapping it opens the sheet WITHOUT flipping the card
//       (the nested-gesture mark contract);
//   3.  THE REVIEW'S CORE TEST: inside the sheet, the amount AND the
//       unit visibly enlarge at 2.0x — measurably, ~2x the 1.0x line
//       height — with no RenderFlex overflow, because the sheet reflows
//       instead of clamping (a clamped implementation would measure at
//       the clamp's cap and fail the ratio);
//   4.  the sheet keeps the card's honesty contract: no fabricated
//       FX equivalent when the rate is unavailable, no fabricated
//       amount when readiness is unresolved;
//   5.  the sheet renders the deck's reminders from the SAME shared
//       derivation the deck renders from — the two surfaces cannot
//       drift apart;
//   6.  the sheet closes cleanly.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderBox, RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/theme_provider.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/marketplace_relevance_provider.dart';
import 'package:azaman/providers/marketplace_resume_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/widgets/hologram_balance_card.dart';
import 'package:azaman/widgets/home/wallet_card_deck.dart';

bool _fontsLoaded = false;
Future<void> _loadFace(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  await loader.load();
}

/// The app's REAL bundled faces (metrics from the app's own fonts —
/// this suite MEASURES laid-out heights, so Ahem would falsify them)
/// plus the icon fonts and the glyph-complete DejaVuSans fallback for
/// the cedi sign. Same contract as the capture harness.
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  await _loadFace('Inter', 'assets/fonts/Inter-Variable.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Regular.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Bold.ttf');
  await _loadFace(
      'MaterialIcons', 'test/goldens/fonts/MaterialIcons-Regular.otf');
  await _loadFace('packages/hugeicons_pro/HugeIconsSolid',
      'test/goldens/fonts/hugeicons-solid.ttf');
  await _loadFace('packages/hugeicons_pro/HugeIconsStroke',
      'test/goldens/fonts/hugeicons-stroke.ttf');
  await _loadFace('DejaVuSans', 'test/goldens/fonts/DejaVuSans.ttf');
  _fontsLoaded = true;
}

ThemeData _harnessTheme() {
  final base = ThemeProvider.getThemeData(AzamanTheme.dark);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: const ['DejaVuSans']),
  );
}

class _NoopHistoryNotifier extends TransactionHistoryNotifier {
  @override
  Future<void> loadMore() async {}
}

class _NoopHomeSummaryNotifier extends HomeSummaryNotifier {
  _NoopHomeSummaryNotifier(super.ref, super.service);
}

class _FakeSusuListNotifier extends SusuListNotifier {
  _FakeSusuListNotifier(this.groups);
  final List<SusuSummary> groups;
  @override
  Future<List<SusuSummary>> build() async => groups;
}

SusuSummary _activeSusu(DateTime runAt) => SusuSummary(
      id: 's1',
      name: 'Circle Susu',
      status: SusuStatus.active,
      contributionUsdc: 10,
      frequency: SusuFrequency.weekly,
      totalCycles: 10,
      nextCycle: SusuCycleSummary(
        id: 'c4',
        cycleNumber: 4,
        scheduledRunAt: runAt,
        payoutUserId: 2,
        isMe: false,
      ),
      myCycleSlot: 4,
      myStatus: SusuMemberStatus.active,
      myRole: 'MEMBER',
    );

const _cartIntent = ResumeIntent(
  kind: ResumeKind.cart,
  title: "Finish your order at Maame's Kitchen",
  subtitle: '2 items · GH₵ 54.00',
  businessProfileId: 'biz-1',
);

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  Size surface = const Size(320, 540),
  double textScale = 1.0,
  double rate = 1.0,
  BalanceReadiness readiness = BalanceReadiness.loaded,
  List<SusuSummary> susu = const [],
  ResumeIntent? intent,
}) async {
  // pumpWidget reuses the element tree when the root widget type
  // matches, and the Navigator is STATEFUL: a bottom-sheet route pushed
  // in an earlier session of this test would otherwise still be open on
  // the next _pumpHome — the second tap would land under a stale sheet.
  // Unmounting everything first guarantees each session starts clean.
  await tester.pumpWidget(const SizedBox.shrink());
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
    'azaman_theme': 1, // dark
  });
  // FontLoader.load() parks on the REAL engine message loop — inside
  // the fake-async test zone a bare await would deadlock forever (same
  // reason every other real-font suite here wraps it in runAsync).
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(surface);

  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      transactionHistoryProvider.overrideWith((ref) => _NoopHistoryNotifier()),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 100),
      ),
      balanceReadinessProvider.overrideWith((ref) => readiness),
      oracleRateProvider.overrideWith((ref) => rate),
      homeSummaryProvider.overrideWith(
        (ref) => _NoopHomeSummaryNotifier(ref, HomeSummaryService()),
      ),
      susuListProvider.overrideWith(() => _FakeSusuListNotifier(susu)),
      marketplaceResumeProvider.overrideWithValue(intent),
      marketplaceRelevanceProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: _harnessTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: surface,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const AzamanHomePage(),
        ),
      ),
    ),
  );
  // Entrance + settle windows (the canonical Home settle pattern).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 1400));
  await tester.pump(const Duration(milliseconds: 300));
  // Extract the balance card from the tucked pouch so its full face —
  // including the header affordance — is visible and hittable.
  tester
      .state<WalletCardDeckState>(find.byType(WalletCardDeck))
      .select(WalletDeckState.balanceOut);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

/// The amount paragraph's laid-out height inside the opened sheet.
// The keyed Texts carry semanticsLabels, so their ELEMENT's render
// object is a RenderSemanticsAnnotations box — measure the RichText
// INSIDE instead.
RenderParagraph _paragraphOf(WidgetTester tester, Key key) {
  return tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.byKey(key),
      matching: find.byType(RichText),
    ),
  );
}

double _sheetAmountHeight(WidgetTester tester) {
  return _paragraphOf(tester, const ValueKey('deck-sheet-balance-amount'))
      .size
      .height;
}

double _sheetUnitHeight(WidgetTester tester) {
  return _paragraphOf(tester, const ValueKey('deck-sheet-balance-unit'))
      .size
      .height;
}

Future<void> _openSheet(WidgetTester tester) async {
  // The affordance's interactive half — the 48x48 region mounted on
  // the flip card — owns the tap; the glyph slot is purely visual.
  await tester.tap(find.byKey(const ValueKey('deck-large-text-hit-region')));
  // Fixed pumps, never pumpAndSettle: the Home runs ambient
  // micro-animations (deck fan, delta tracker) that never settle — the
  // capture suite's contract too. The bottom-sheet entrance is a
  // ~300ms curve; two fixed windows fully lay the route out.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('the expand affordance sits on the balance card at 1.0x',
      (tester) async {
    await _pumpHome(tester);
    expect(find.byKey(const ValueKey('deck-large-text-button')), findsOneWidget);
  });

  testWidgets('the expand affordance is still present at 2.0x system text '
      '(a low-vision user must be able to find it)', (tester) async {
    await _pumpHome(tester, textScale: 2.0);
    expect(find.byKey(const ValueKey('deck-large-text-button')), findsOneWidget);
  });

  // ── THE HIT-TARGET CONTRACT (review requirement) ─────────────────
  //
  // The visible glyph is compact; the INTERACTIVE and SEMANTIC target
  // must both be a true 48x48dp, and taps anywhere in that region must
  // open the sheet — not flip the card.

  testWidgets('THE HIT-TARGET CONTRACT: the interactive region measures '
      '48x48dp at 1.0x while the painted glyph stays compact', (tester) async {
    await _pumpHome(tester);

    // The interactive region's render box — measured, not assumed.
    final region = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('deck-large-text-hit-region')),
    );
    expect(region.size.width, 48.0);
    expect(region.size.height, 48.0);

    // The painted slot stays 24x24 — the affordance did not grow.
    final slot = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('deck-large-text-button')),
    );
    expect(slot.size.width, 24.0);
    expect(slot.size.height, 24.0);
  });

  testWidgets('THE HIT-TARGET CONTRACT: the region still measures 48x48dp '
      'at 2.0x and stays inside the card face', (tester) async {
    await _pumpHome(tester, textScale: 2.0);

    final region = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('deck-large-text-hit-region')),
    );
    expect(region.size.width, 48.0);
    expect(region.size.height, 48.0);

    // The region's global rect must lie INSIDE the card face (the
    // rounded clip would otherwise kill hit tests at the edges).
    // The card's render object is its rounded-clip face.
    final face = tester.renderObject<RenderBox>(
      find.byType(HologramBalanceCard),
    );
    final faceRect = Rect.fromPoints(
      face.localToGlobal(Offset.zero),
      face.localToGlobal(Offset(face.size.width, face.size.height)),
    );
    final regionRect = Rect.fromPoints(
      region.localToGlobal(Offset.zero),
      region.localToGlobal(Offset(region.size.width, region.size.height)),
    );
    expect(faceRect.contains(regionRect.topLeft), isTrue,
        reason: 'the hit region must not escape the card face');
    expect(faceRect.contains(regionRect.bottomRight), isTrue,
        reason: 'the hit region must not escape the card face');
  });

  testWidgets('THE HIT-TARGET CONTRACT: the SEMANTIC node measures 48x48dp '
      'and owns the expand label', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    await _pumpHome(tester);

    // Resolve the node the way a screen reader reaches it: by label.
    final labelFinder =
        find.bySemanticsLabel('View deck details in large text');
    expect(labelFinder, findsOneWidget);
    final node = tester.getSemantics(labelFinder);
    // The semantic target rides the 48px overlay region — a screen
    // reader user gets the same large target, not a 24px one.
    expect(node.rect.width, greaterThanOrEqualTo(48.0));
    expect(node.rect.height, greaterThanOrEqualTo(48.0));
    expect(node.flagsCollection.isButton, isTrue,
        reason: 'the affordance must be announced as a button');
    expect(
      find.bySemanticsLabel('View deck details in large text'),
      findsOneWidget,
    );

    semanticsHandle.dispose();
  });

  testWidgets('THE HIT-TARGET CONTRACT: a tap at the REGION CORNER — far '
      'outside the 24px glyph — opens the sheet without flipping',
      (tester) async {
    await _pumpHome(tester);

    // Tap the region's BOTTOM-LEFT corner: ~6px left of the glyph slot
    // and ~20px BELOW its bottom edge. The old 24px target missed this
    // tap entirely and the card would flip instead.
    final region = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('deck-large-text-hit-region')),
    );
    // ~20px BELOW the glyph slot's bottom edge and ~6px LEFT of its
    // left edge — far outside the 24px visual slot, deep inside the
    // 48x48 target (inset 4px from the region's own bottom edge so the
    // point is unambiguously live). The old 24px target missed this tap
    // entirely and the card would flip instead.
    final farPoint = region.localToGlobal(
      const Offset(2, 44),
    );
    await tester.tapAt(farPoint);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    // The sheet opened…
    expect(
      find.byKey(const ValueKey('deck-sheet-heading')),
      findsOneWidget,
    );
    // …and the card did NOT flip to its back face.
    expect(find.text('Azaman Balance'), findsOneWidget);
    expect(find.text('BREAKDOWN'), findsNothing);
  });

  testWidgets('tapping the affordance opens the deck detail sheet WITHOUT '
      'flipping the card', (tester) async {
    await _pumpHome(tester);
    await _openSheet(tester);

    // The sheet is open…
    expect(
      find.byKey(const ValueKey('deck-sheet-heading')),
      findsOneWidget,
    );
    // …and the card did NOT flip: the FRONT face's brand title is still
    // mounted and the sheet (not the visa back face) owns the stage.
    expect(find.text('Azaman Balance'), findsOneWidget);
        // The back face's own unique marker — NOT 'CARDHOLDER', which the
    // deck's separately-mounted AzmVisaCard shows permanently.
    expect(find.text('BREAKDOWN'), findsNothing);
  });

  testWidgets('THE REVIEW REQUIREMENT: the amount visibly enlarges at 2.0x '
      'without overflow — measured, not assumed', (tester) async {
    final heights = <double, double>{};

    await _pumpHome(tester, textScale: 1.0);
    await _openSheet(tester);
    heights[1.0] = _sheetAmountHeight(tester);
    expect(find.text('100.00'), findsOneWidget);

    await _pumpHome(tester, textScale: 2.0);
    await _openSheet(tester);
    heights[2.0] = _sheetAmountHeight(tester);
    expect(find.text('100.00'), findsOneWidget);

    // Visibly enlarging: the 2.0x amount line is close to TWICE the 1.0x
    // height. A clamped implementation would cap at ~1.25x and fail this
    // ratio; the sheet has no clamp, so 2.0x means 2.0x.
    expect(heights[2.0]!, greaterThan(heights[1.0]! * 1.85));
    // Sanity floor: the 1.0x hero line is a real 40px line, not zero.
    expect(heights[1.0]!, greaterThan(36));
  });

  testWidgets('THE REVIEW REQUIREMENT: the unit mark visibly enlarges at '
      '2.0x too', (tester) async {
    final unitHeights = <double, double>{};

    await _pumpHome(tester, textScale: 1.0);
    await _openSheet(tester);
    unitHeights[1.0] = _sheetUnitHeight(tester);

    await _pumpHome(tester, textScale: 2.0);
    await _openSheet(tester);
    unitHeights[2.0] = _sheetUnitHeight(tester);

    expect(unitHeights[2.0]!, greaterThan(unitHeights[1.0]! * 1.85));
  });

  testWidgets('the sheet keeps the honest-rate contract: no rate means no '
      'fabricated FX equivalent', (tester) async {
    await _pumpHome(tester, rate: 0);
    await _openSheet(tester);

    expect(
      find.byKey(const ValueKey('deck-sheet-rate-unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('deck-sheet-rate')), findsOneWidget);
    // The rate line says unavailable — it never says "1 USDC = GH₵ 0.00".
    expect(find.text('FX rate unavailable'), findsWidgets);
  });

  testWidgets('with a usable rate the sheet shows the conversion line',
      (tester) async {
    await _pumpHome(tester, rate: 12.03);
    await _openSheet(tester);

    // Scoped to the sheet's keyed line: the card face renders its own
    // '1 USDC = GH₵' line as well, so a global find would be ambiguous.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('deck-sheet-rate')))
          .data,
      contains('1 USDC = GH₵'),
    );
    expect(
      find.byKey(const ValueKey('deck-sheet-rate-unavailable')),
      findsNothing,
    );
  });

  testWidgets('an unresolved balance never fabricates a figure in the sheet',
      (tester) async {
    await _pumpHome(tester, readiness: BalanceReadiness.unresolved);
    await _openSheet(tester);

    // The honest em-dash slot, not a fabricated "0.00".
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0.00'), findsNothing);
  });

  testWidgets('the sheet renders the deck reminders from the SAME shared '
      'derivation (deck: susu + cart intent)', (tester) async {
    final susu = [_activeSusu(DateTime(2026, 11, 14))];
    await _pumpHome(tester, susu: susu, intent: _cartIntent);
    await _openSheet(tester);

    expect(find.byKey(const ValueKey('deck-sheet-heading')), findsOneWidget);
    // Both real signals — the susu cycle and the marketplace resume
    // intent — present in the sheet's REMINDERS section, exactly as the
    // deck renders them.
    expect(find.textContaining('SUSU — Susu contribution due'), findsOneWidget);
    expect(
      find.textContaining("MARKETPLACE — Finish your order at Maame's"),
      findsOneWidget,
    );
  });

  testWidgets('the sheet closes cleanly', (tester) async {
    await _pumpHome(tester);
    await _openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('deck-sheet-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const ValueKey('deck-sheet-heading')), findsNothing);
    // The card is still on the front face after the round trip.
    expect(find.text('Azaman Balance'), findsOneWidget);
  });
}
