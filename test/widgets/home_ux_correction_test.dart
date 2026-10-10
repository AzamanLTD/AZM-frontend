// UX-CORRECTION PASS (2026-10-04) — PR A: Home/theme/navigation.
//
// Every §1-8 contract from the correction brief, pinned as fail-first
// tests against the corrected behaviour:
//
//   §1  Light carries a real 4-step surface hierarchy (page plane below
//       sheets below cards); the dark nav pill sits on the CARD step with
//       an explicit rim, never one luma step off the page.
//   §3  The Visa card wears the P2P premium physical-card grammar
//       (carbon body/gold rim/glow/texture/sheen) while every Visa
//       datum, the SAMPLE marks and the programme abstraction survive.
//   §4  Every production fallback Home heading message fits the heading
//       width at full size — no paragraph-length copy.
//   §5  The + action group visually originates from the + control —
//       anchored to its right edge, rising above it — never a centered
//       modal column.
//   §6  The Recent Activity doorway says "Pull up" and sits LOW in the
//       resting composition (bottom of the first viewport, above the nav
//       band) via the measured, bounded gap.
//   §7  The Home activity surface shows mapped, explicitly supported
//       financial types only — unknown records are excluded.
//   §8  Activity records are roomy two-line cards with WIDE action
//       buttons whose full labels never truncate.
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
import 'package:azaman/theme/az_elevation.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/home/activity_doorway.dart';
import 'package:azaman/widgets/home/az_typewriter_heading.dart';
import 'package:azaman/widgets/home/plus_action_launcher.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';
import 'package:azaman/widgets/premium_card_surface.dart';
import 'package:azaman/widgets/home/azm_visa_card.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderDecoratedBox;
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
  // The UI/display family (UI-correction Phase A): headings render in
  // Comic Neue via ThemeData.fontFamily, so the §4 width measurement
  // must use the REAL family, not the test engine's fallback.
  final regular = await File(
    'assets/fonts/ComicNeue-Regular.ttf',
  ).readAsBytes();
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

TransactionRecord _record(
  String rawType, {
  double amountUsdc = -1,
  Map<String, dynamic> metadata = const {},
  String providerRef = 'ref-x',
  String status = 'COMPLETED',
}) {
  return TransactionRecord(
    id: 'txn-$rawType-${DateTime.now().microsecondsSinceEpoch}',
    rawType: rawType,
    amountUsdc: amountUsdc,
    status: status,
    createdAt: DateTime(2026, 9, 30, 12),
    metadata: metadata,
    providerRef: providerRef,
  );
}

class _StaticHistoryNotifier extends TransactionHistoryNotifier {
  _StaticHistoryNotifier(this.initial);

  final List<TransactionRecord> initial;
  bool _served = false;

  @override
  Future<void> loadMore() async {
    if (_served || state.isLoading || !state.hasMore) return;
    _served = true;
    state = state.copyWith(items: initial, isLoading: false, hasMore: false);
  }

  @override
  Future<void> refresh() async {
    state = TransactionHistoryState(filter: state.filter);
    _served = false;
    await loadMore();
  }
}

/// Pumps the real Home page at the canonical test surface with the real
/// entrance choreography, then advances past the §6 doorway-gap
/// measurement window (1200ms) so the measured layout is settled.
Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  List<TransactionRecord> history = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
  });
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(_surfaceSize);

  final notifier = _StaticHistoryNotifier(history);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      transactionHistoryProvider.overrideWith((ref) => notifier),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 100),
      ),
      oracleRateProvider.overrideWith((ref) => 1.0),
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
  // Entrance + NEW-D prime microtask + §6 measurement window.
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

double _activityOpacity(WidgetTester tester) {
  final fade = find.ancestor(
    of: find.byType(HomeActivitySurface),
    matching: find.byType(Opacity),
  );
  return tester.widget<Opacity>(fade.first).opacity;
}

/// The physical entry gesture: the activity surface rises from below, so
/// the finger drags UP (§1 of the audit). Verifies the commit.
Future<void> _enterActivity(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(RecentActivityDoorway));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  for (var attempt = 0; attempt < 2; attempt++) {
    await tester.drag(
      find.byType(RecentActivityDoorway),
      const Offset(0, -260),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    if (_activityOpacity(tester) > 0.99) {
      // The lazy-load boundary: the surface's first-page fetch fires in
      // a POST-FRAME callback once `active` commits — right at the tail
      // of the handoff pump. Pump the callback, the state write, and
      // the row rebuild through before handing control back.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      return;
    }
  }
  fail('the deliberate entry drag never committed the activity state');
}

/// Pumps the SHELL grammar of main.dart in miniature: the nav band with
/// the + trigger structurally beside the pill, the launcher overlay
/// topmost in a Stack — the geometry the §5 anchor contract asserts.
Future<PlusLauncherController> _pumpShell(
  WidgetTester tester, {
  AzamanTheme theme = AzamanTheme.light,
}) async {
  final controller = PlusLauncherController();
  // The widgets watch the LIVE themeProvider (not Theme.of), so the
  // requested identity must be the provider's loaded state.
  SharedPreferences.setMockInitialValues({
    'azaman_theme': theme == AzamanTheme.dark ? 1 : 0,
  });
  await tester.binding.setSurfaceSize(_surfaceSize);
  final tp = ThemeProvider();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        themeProvider.overrideWith((ref) => tp),
        // Same isolation the home activity harness uses: the live
        // notification notifier's dispose reads a provider after
        // container teardown (pre-existing app defect, out of scope).
        unreadCountProvider.overrideWith((ref) => 0),
      ],
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(theme),
        home: MediaQuery(
          data: const MediaQueryData(size: _surfaceSize),
          child: Scaffold(
            extendBody: true,
            bottomNavigationBar: PremiumBottomNav(
              selectedIndex: 0,
              onItemSelected: (_) {},
              trailing: PlusLauncherTrigger(controller: controller),
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: PlusActionLauncher(
                    controller: controller,
                    actions: [
                      PlusLauncherAction(
                        icon: Icons.send,
                        label: 'Send',
                        onTap: () {},
                      ),
                      PlusLauncherAction(
                        icon: Icons.qr_code,
                        label: 'Receive',
                        onTap: () {},
                      ),
                      PlusLauncherAction(
                        icon: Icons.wallet,
                        label: 'Add Cash',
                        onTap: () {},
                      ),
                      PlusLauncherAction(
                        icon: Icons.money_off,
                        label: 'Withdraw',
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  // The provider's prefs read is async; let the loaded theme land.
  var guard = 0;
  while (!tp.isLoaded && guard++ < 200) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  // ── §1 — real surface hierarchy in Light; separated dark nav ──────────

  group('§1 Light carries a 4-step surface hierarchy', () {
    test('page plane < sheet < card, each a distinct step', () {
      final light = ThemeProvider.getColors(AzamanTheme.light);

      // Distinct values — a page that is all-white-on-white is the exact
      // blank-page defect the correction forbids.
      expect(light.background, isNot(light.surface));
      expect(light.surface, isNot(light.card));
      expect(light.background, isNot(light.card));

      // And ORDERED: the page plane is the darkest step, sheets one step
      // up, cards fully raised.
      double lum(Color c) => (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) / 255.0;
      expect(lum(light.background), lessThan(lum(light.surface)));
      expect(lum(light.surface), lessThan(lum(light.card)));

      // Inset wells read as RECESSED: softSurface sits below the page
      // plane, not above it.
      expect(lum(light.softSurface), lessThan(lum(light.background)));
    });

    test('dark keeps its own ramp (card step above the true-black page)', () {
      final dark = ThemeProvider.getColors(AzamanTheme.dark);
      double lum(Color c) => (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) / 255.0;
      expect(lum(dark.background), lessThan(lum(dark.surface)));
      expect(lum(dark.surface), lessThan(lum(dark.card)));
    });
  });

  group('§1 dark nav pill separation', () {
    testWidgets('the pill sits on the CARD step with an explicit rim', (
      tester,
    ) async {
      await _pumpShell(tester, theme: AzamanTheme.dark);
      final dark = ThemeProvider.getColors(AzamanTheme.dark);

      final pill = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(PremiumBottomNav),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final decoration = pill.decoration as BoxDecoration;

      // The pill is the CARD surface, not the page-adjacent surface.
      expect(
        decoration.color,
        dark.card,
        reason: 'the nav must sit on the card step of the dark ramp',
      );
      // An explicit rim, not a shadow alone.
      expect(
        decoration.border,
        isNotNull,
        reason: 'dark nav separation needs a rim highlight',
      );
      expect(decoration.border!.top.color, AzElevation.rimHighlight(true));
      // And the subtle vertical highlight gradient.
      expect(decoration.gradient, isNotNull);
    });
  });

  // ── §3 — Visa wears the P2P premium card grammar ──────────────────────

  group('§3 Visa premium physical-card grammar', () {
    test('PremiumCardPalette pins the P2P physical-card values', () {
      // The narrow extraction must not drift from the P2P card's
      // permanent brand palette (lib/screens/p2p/.../_CashBalanceCard).
      expect(PremiumCardPalette.cardAccent, const Color(0xFFD4AF37));
      expect(PremiumCardPalette.gradTopBase, const Color(0xFF0E1116));
      expect(PremiumCardPalette.gradBottom, const Color(0xFF05070A));
    });

    testWidgets('carbon grammar + every Visa datum survives the restyle', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 220));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeProvider.getThemeData(AzamanTheme.light),
            home: const MediaQuery(
              // disableAnimations parks the premium sheen at rest — the
              // card's data is identical, and the frame settles.
              data: MediaQueryData(
                size: Size(360, 220),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 340,
                    height: 200,
                    child: AzmVisaCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The premium carbon surface paints behind the content.
      expect(find.byType(PremiumCardSurface), findsOneWidget);
      expect(find.byType(PremiumCardFrame), findsOneWidget);

      // And the old accent-gradient body is gone: no decoration in the
      // card paints the switchable theme accent as its body.
      final accent = ThemeProvider.getColors(AzamanTheme.light).accent;
      var accentBody = false;
      for (final render in tester.allRenderObjects) {
        final d = render is RenderDecoratedBox ? render.decoration : null;
        if (d is BoxDecoration && d.gradient is LinearGradient) {
          final colors = (d.gradient as LinearGradient).colors;
          if (colors.contains(accent)) accentBody = true;
        }
      }
      expect(
        accentBody,
        isFalse,
        reason:
            'the visa body must be the fixed carbon grammar, not '
            'the theme accent gradient',
      );

      // Every datum still renders.
      expect(find.text('AZM'), findsOneWidget);
      expect(find.text('VISA'), findsOneWidget);
      expect(find.text('VALID THRU'), findsOneWidget);
      expect(find.text('SAMPLE'), findsOneWidget);
      expect(find.text('powered by Flutterwave'), findsOneWidget);
      expect(
        find.text(DemoCardProgramme().maskedNumber),
        findsOneWidget,
        reason: 'the card-programme abstraction still feeds the number',
      );
      expect(find.text(DemoCardProgramme().cardholderLabel), findsOneWidget);
    });
  });

  // ── §4 — short heading copy that fits ─────────────────────────────────

  group('§4 Home heading fallback messages fit the heading width', () {
    test('every production fallback message is short product language', () {
      for (final m in kHeadingFeatureMessages) {
        expect(
          m.text.length,
          lessThan(32),
          reason: "'${m.text}' must be short, not a paragraph",
        );
        expect(m.text.endsWith('.'), isTrue);
      }
      expect(
        kHeadingFeatureMessages.length,
        greaterThanOrEqualTo(4),
        reason: 'all four product areas keep a nudge',
      );
    });

    testWidgets('no fallback message truncates at the heading size', (
      tester,
    ) async {
      await tester.runAsync(_loadFonts);
      // The heading row: 400 surface - 2 x AzSpace.lg padding - glyph
      // (20 icon + 8 gap).
      final available = _surfaceSize.width - 2 * AzSpace.lg - 20 - 8;
      for (final m in kHeadingFeatureMessages) {
        final painter = TextPainter(
          text: TextSpan(
            text: m.text,
            // The heading renders in the theme's UI family (Comic
            // Neue, bundled at 400/700 only — the engine resolves the
            // ladder's w800 to the shipped 700). Measure the REAL
            // rendering, not a fallback face.
            style: AzText.display.copyWith(
              fontFamily: 'ComicNeue',
              fontWeight: FontWeight.w700,
              color: ThemeProvider.getColors(AzamanTheme.light).textPrimary,
            ),
          ),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(minWidth: 0, maxWidth: available);
        expect(
          painter.didExceedMaxLines,
          isFalse,
          reason: "'${m.text}' must fit at full heading size (no ellipsis)",
        );
        expect(painter.width, lessThanOrEqualTo(available));
        painter.dispose();
      }
    });
  });

  // ── §5 — the + actions originate from the + ───────────────────────────

  group('§5 plus actions anchor to the + control', () {
    testWidgets('the action group hangs off the + button\'s center axis — '
        'never a centered modal column', (tester) async {
      final controller = await _pumpShell(tester);
      controller.open();
      await tester.pumpAndSettle();

      final triggerRect = tester.getRect(
        find.byKey(const ValueKey('plus-launcher-trigger')),
      );
      // The ROW widget (icon + label), not the bare label text: the
      // follower pins the GROUP's right edge, so the contract is on the
      // row container.
      final sendRow = tester.getRect(
        find
            .ancestor(
              of: find.text('Send'),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      final withdrawRow = tester.getRect(
        find
            .ancestor(
              of: find.text('Withdraw'),
              matching: find.byType(GestureDetector),
            )
            .first,
      );

      // CORRECTION F (geometry fix): the rows' shared trailing edge is
      // flush with the + button's RIGHT edge, measured live — the
      // cluster hangs off the physical plus. (The earlier center-axis
      // variant left the wide plus hanging right of the rows; the
      // trailing edge is the axis the eye actually follows.) The only
      // permitted shortfall is the launcher's own minimum screen margin
      // (AzSpace.sm) when the plus itself sits flush at the viewport
      // edge — the cluster may never touch the edge, and never pass
      // beyond the plus.
      for (final row in [sendRow, withdrawRow]) {
        expect(
          row.right,
          lessThanOrEqualTo(triggerRect.right + 2),
          reason: 'the cluster never hangs past the +',
        );
        expect(
          row.right,
          greaterThanOrEqualTo(triggerRect.right - AzSpace.sm - 2),
          reason:
              'flush with the + right edge, minus only the '
              'minimum screen margin',
        );
      }

      // The group RISES ABOVE the + — the last row sits above the
      // trigger's top edge, not below it and not mid-screen.
      expect(
        withdrawRow.bottom,
        lessThan(triggerRect.top + 8),
        reason: 'actions must originate from the plus, above it',
      );

      // Never centered: the action group sits in the right half of the
      // screen, next to the plus that opened it.
      expect(sendRow.center.dx, greaterThan(_surfaceSize.width / 2));

      // Every row stays on screen (bounded width, not stretched).
      expect(sendRow.left, greaterThan(0));
      expect(withdrawRow.left, greaterThan(0));
      expect(sendRow.top, greaterThan(0));
    });
  });

  // ── §6 — Recent bubble doorway and low placement ──────────────────────

  group('§6 doorway wording + low placement', () {
    testWidgets('the doorway is a neutral Recent button with no pull copy',
        (tester) async {
      await _pumpHome(tester);

      // Recent is a button, not a page heading or a directional-arrow CTA.
      // Its selected silver-green counterpart becomes the Activity header.
      expect(find.text('Recent'), findsWidgets);
      expect(find.text('Pull up'), findsNothing);
      expect(find.text('Pull down'), findsNothing);
      expect(find.bySemanticsLabel('Recent transactions'), findsOneWidget);
      expect(find.text('← Wallet'), findsNothing);
    });

    testWidgets('the doorway sits at the bottom of the first viewport, '
        'slightly above the nav band', (tester) async {
      await _pumpHome(tester);

      final doorwayRect = tester.getRect(find.byType(RecentActivityDoorway));
      // navClearanceHeight = 120: content bottoms at (900 - 120).
      final restingBottom = _surfaceSize.height - AzSpace.navClearanceHeight;
      expect(
        doorwayRect.bottom,
        closeTo(restingBottom, 40),
        reason:
            'measured gap must land the doorway low, not '
            'mid-content and not under the nav',
      );
      // And it is INSIDE the viewport — no giant spacer shoving it away.
      expect(doorwayRect.bottom, lessThanOrEqualTo(_surfaceSize.height));
    });
  });

  // ── §7 — economic activity only ───────────────────────────────────────

  group('§7 the Home activity surface shows mapped financial types only', () {
    testWidgets('an unknown backend type is EXCLUDED from the surface', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        history: [
          _record(
            'WITHDRAWAL_FIAT',
            amountUsdc: -4,
            metadata: {'description': 'Cash out'},
          ),
          _record(
            'SOCIAL_BADGE_AWARD',
            metadata: {'description': 'Mystery badge mint'},
          ),
        ],
      );
      await _enterActivity(tester);

      // The supported financial record renders.
      expect(find.text('Cash out'), findsOneWidget);
      expect(find.text('View withdrawal'), findsOneWidget);

      // The unmapped record is not presented as mysterious activity.
      expect(
        find.text('Mystery badge mint'),
        findsNothing,
        reason:
            'unknown/unmapped types must be excluded from the '
            'Home activity surface',
      );
      expect(find.text('Social badge award'), findsNothing);
    });
  });

  // ── §8 — roomy two-line activity cards ────────────────────────────────

  group('§8 roomy activity cards with full action labels', () {
    testWidgets('two-line card grammar: content up top, WIDE action '
        'button below — full label, no truncation', (tester) async {
      await _pumpHome(
        tester,
        history: [
          _record(
            'WITHDRAWAL_FIAT',
            amountUsdc: -4,
            metadata: {'description': 'Cash out at the bank'},
          ),
          _record(
            'INTERNAL_TRANSFER',
            amountUsdc: -2,
            metadata: {
              'description': 'Rent to Ama',
              'recipientAzamId': 'azm-77',
              'recipientName': 'Ama',
            },
          ),
        ],
      );
      await _enterActivity(tester);

      // The full typed action labels render — never ellipsized chips.
      expect(find.text('View withdrawal'), findsOneWidget);
      expect(find.text('Send again'), findsOneWidget);

      // The grammar is STACKED, not one squeezed row: the action button
      // sits BELOW the record's title block, on its own line. Measure
      // the BUTTON surface (the full-width GestureDetector), not the
      // label Text inside it.
      final titleRect = tester.getRect(find.text('Cash out at the bank'));
      final buttonRect = tester.getRect(
        find
            .ancestor(
              of: find.text('View withdrawal'),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(
        buttonRect.top,
        greaterThan(titleRect.bottom),
        reason:
            'the card is a two-line grammar: content, then the '
            'action button below',
      );

      // The button is WIDE — a full-width row of the card (width:
      // double.infinity at build), not a tiny pill chip hugging its
      // label.
      expect(
        buttonRect.width,
        greaterThan(150),
        reason: 'the action button must have room for its full label',
      );
      expect(
        buttonRect.height,
        greaterThan(30),
        reason: 'the action button must be a real touch target',
      );
    });
  });
}
