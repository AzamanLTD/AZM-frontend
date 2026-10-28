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
import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/escrow_models.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/providers/auth_provider.dart' show currentUserProvider;
import 'package:azaman/providers/currency_provider.dart';
import 'package:azaman/providers/smart_route_provider.dart';
import 'package:azaman/providers/susu_provider.dart'
    show
        SusuCyclesNotifier,
        SusuDetailV2Notifier,
        SusuMembersNotifier,
        susuCyclesProvider,
        susuDetailV2Provider,
        susuMembersProvider;
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/vault_provider.dart'
    show Vault, VaultDeposit, vaultDepositsProvider, vaultDetailProvider;
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/screens/marketplace/business_dashboard_screen.dart';
import 'package:azaman/screens/marketplace/cart_screen.dart';
import 'package:azaman/screens/marketplace/invoice_detail_screen.dart';
import 'package:azaman/screens/marketplace/receipt_screen.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/screens/smart_route/smart_route_create_screen.dart';
import 'package:azaman/screens/susu/susu_config_screen.dart';
import 'package:azaman/screens/susu/susu_dashboard_screen.dart';
import 'package:azaman/screens/vault/vault_create_screen.dart';
import 'package:azaman/screens/vault/vault_detail_screen.dart';
import 'package:azaman/widgets/escrow_status_panel.dart';
import 'package:azaman/widgets/escrow_vault_rail.dart';
import 'package:azaman/widgets/money/native_amount_display.dart';
import 'package:azaman/widgets/smart_route/smart_route_card.dart';
import 'package:azaman/widgets/vault/vault_progress_card.dart';

const _storageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

// ── Real fonts (FontLoader pattern; see test/goldens/README.md) ─────────────

bool _fontsLoaded = false;

Future<void> _loadFace(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  await loader.load();
}

Future<void> _loadAppFonts() async {
  if (_fontsLoaded) return;
  await _loadFace('Inter', 'assets/fonts/Inter-Variable.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Regular.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Bold.ttf');
  await _loadFace(
    'MaterialIcons',
    'test/goldens/fonts/MaterialIcons-Regular.otf',
  );
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
  startDate: _kGoldenNow.subtract(const Duration(days: 10)),
  maturityDate: _kGoldenNow.add(const Duration(days: 80)),
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

// ── Full-screen fixtures (susu dashboard / vault detail) ────────────────────

SusuMemberView _capMember(String id, int userId, String name, int slot) =>
    SusuMemberView(
      susuMemberId: id,
      userId: userId,
      displayName: name,
      avatar: null,
      cycleSlot: slot,
      status: SusuMemberStatus.active,
      role: 'member',
    );

// ── D2 merchant fixtures (USDC settlement surfaces) ────────────────────────

// Unpaid (sent) invoice — the payment-preparation state where wording
// must say PAYABLE, never settled.
BusinessInvoice _capUnpaidInvoice() => BusinessInvoice(
  id: 'inv_cap2',
  businessProfileId: 'biz_cap',
  customerId: 10,
  invoiceRef: 'AZ-INV-2001',
  status: InvoiceStatus.sent,
  subtotalUsdc: 1234.56,
  taxTotalUsdc: 0,
  tipUsdc: 0,
  billTotalUsdc: 1234.56,
  feeUsdc: 1.23,
  customerCoveredFee: false,
  customerPaidUsdc: null,
  paidAt: null,
  createdAt: _kGoldenNow,
  lineItems: [
    const InvoiceLineItem(
      id: 'li_1',
      description: 'Adinkra wall panel',
      quantity: 1,
      unitPriceUsdc: 1234.56,
      lineTotalUsdc: 1234.56,
    ),
  ],
  taxLines: [],
  businessName: 'Makola Trading Co.',
);

class _CapInvoiceService extends BusinessService {
  @override
  Future<BusinessInvoice> getInvoice(String invoiceId) async =>
      _capUnpaidInvoice();
}

class _CapDashboardService extends BusinessService {
  @override
  Future<BusinessStats> getBusinessStats() async => const BusinessStats(
    totalOrders: 40,
    completedOrders: 20,
    pendingOrders: 5,
    disputedOrders: 0,
    cancelledOrders: 0,
    totalRevenue: 12345.67,
    avgOrderValue: 617.28,
    recentOrders: [],
    // Backend revenueByDay: dated completed-order buckets (zero-filled).
    // Fixed dates keep the goldens clock-independent.
    revenueByDay: [
      DailyRevenue(date: '2026-10-15', label: 'Oct 15', revenue: 12.5),
      DailyRevenue(date: '2026-10-16', label: 'Oct 16', revenue: 0),
      DailyRevenue(date: '2026-10-17', label: 'Oct 17', revenue: 40.25),
      DailyRevenue(date: '2026-10-18', label: 'Oct 18', revenue: 88),
      DailyRevenue(date: '2026-10-19', label: 'Oct 19', revenue: 0),
      DailyRevenue(date: '2026-10-20', label: 'Oct 20', revenue: 6.75),
      DailyRevenue(date: '2026-10-21', label: 'Oct 21', revenue: 133.5),
    ],
  );

  @override
  Future<ProductPage> getMyProducts({int limit = 20, String? cursor}) async => (
    products: [
      const BusinessProduct(
        id: 'p1',
        businessProfileId: 'biz_cap',
        name: 'Adinkra wall panel',
        slug: 'adinkra-panel',
        priceUsdc: 1234.56,
        priceGhs: '18983.93',
        totalRevenue: 0,
        imageUrls: [],
        isActive: true,
        totalOrders: 0,
      ),
      const BusinessProduct(
        id: 'p2',
        businessProfileId: 'biz_cap',
        name: 'Kente tote (no GHS price set)',
        slug: 'kente-tote',
        priceUsdc: 42.5,
        priceGhs: null,
        totalRevenue: 0,
        imageUrls: [],
        isActive: true,
        totalOrders: 0,
      ),
    ],
    hasMore: false,
    nextCursor: null,
  );
}

class _CapBusinessNotifier extends MyBusinessNotifier {
  _CapBusinessNotifier(super.service, MyBusinessState preset) {
    state = preset;
  }
}

BusinessInvoice _capInvoice() => BusinessInvoice(
  id: 'inv_cap',
  businessProfileId: 'biz_cap',
  customerId: 10,
  invoiceRef: 'AZ-RC-1001',
  status: InvoiceStatus.paid,
  subtotalUsdc: 1234.56,
  taxTotalUsdc: 0,
  tipUsdc: 0,
  billTotalUsdc: 1234.56,
  feeUsdc: 0,
  customerCoveredFee: true,
  customerPaidUsdc: 1234.56,
  paidAt: _kGoldenNow,
  createdAt: _kGoldenNow.subtract(const Duration(hours: 2)),
  lineItems: [
    const InvoiceLineItem(
      id: 'li_1',
      description: 'Adinkra wall panel',
      quantity: 1,
      unitPriceUsdc: 1234.56,
      lineTotalUsdc: 1234.56,
    ),
  ],
  taxLines: [],
  businessName: 'Makola Trading Co.',
);

/// Pinned golden clock: the wheel countdown, the vault 'days left' and
/// deposit-history captions all render from this instant, so the goldens
/// are byte-identical forever instead of drifting across hour boundaries.
final DateTime _kGoldenNow = DateTime.utc(2026, 10, 20, 12, 0, 0);

SusuCycleView _capCycle(int n, SusuCycleStatus status) => SusuCycleView(
  id: 'cyc_$n',
  cycleNumber: n,
  scheduledRunAt: _kGoldenNow.add(Duration(days: 7 * n)),
  status: status,
  payoutUserId: 10 + (n % 2),
  paidOutAt: null,
  escrowDivertedAt: null,
  payoutAmount: null,
  graceUntil: null,
);

SusuDetail _capSusu() => SusuDetail(
  id: 's_cap',
  name: 'Market Traders Circle',
  status: SusuStatus.active,
  contributionUsdc: 2,
  frequency: SusuFrequency.weekly,
  totalCycles: 8,
  contractVersion: 'v2',
  contractHash: 'hash',
  activatedAt: DateTime.now().subtract(const Duration(days: 14)),
  completedAt: null,
  frozenAt: null,
  frozenReason: null,
  initiator: null,
  members: [
    _capMember('sm_1', 10, 'Ama Serwaa', 1),
    _capMember('sm_2', 11, 'Kwame Boadi', 2),
    _capMember('sm_3', 12, 'Efua Mensah', 3),
  ],
  cycles: [
    for (var n = 1; n <= 8; n++)
      _capCycle(n, n == 1 ? SusuCycleStatus.paidOut : SusuCycleStatus.pending),
  ],
);

class _CapSusuDetailNotifier extends SusuDetailV2Notifier {
  @override
  Future<SusuDetail> build(String susuId) async => _capSusu();
}

class _CapSusuMembersNotifier extends SusuMembersNotifier {
  @override
  Future<List<SusuMemberView>> build(String susuId) async => _capSusu().members;
}

class _CapSusuCyclesNotifier extends SusuCyclesNotifier {
  @override
  Future<List<SusuCycleView>> build(String susuId) async => _capSusu().cycles;
}

VaultDeposit _capDeposit(String id, double amount, int daysAgo) => VaultDeposit(
  id: id,
  amountUsdc: amount,
  type: 'MANUAL',
  status: 'COMPLETED',
  azmAwarded: 1,
  createdAt: _kGoldenNow.subtract(Duration(days: daysAgo)),
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
          // Pinned clock: the maturity countdown is measured against the
          // SAME fixed instant the fixture anchors to (_kGoldenNow), so the
          // 'Matures in' label can never decrement between CI runs.
          nowFn: () => _kGoldenNow,
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
        section('Escrow vault rail (large amount — narrow-screen honesty)'),
        EscrowVaultRail(
          escrow: _escrow(amount: 1234.56),
          currentUserId: 10,
          isLoading: false,
        ),
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
  List<Override> extraOverrides = const [],
  void Function(ProviderContainer)? onContainer,
}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
        if (call.method == 'read') return 'mock-token';
        return null;
      });
  // Cached network images reach flutter_cache_manager, which asks
  // path_provider for a cache directory; stub it so merchant captures
  // with imagery render deterministically without a platform plugin.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        switch (call.method) {
          case 'getTemporaryDirectory':
          case 'getApplicationSupportDirectory':
          case 'getApplicationDocumentsDirectory':
            return '/tmp/azm_golden_cache';
        }
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
  final container = ProviderContainer(
    overrides: [
      fxRateProvider.overrideWith((ref) async => _pinnedRate()),
      ...extraOverrides,
    ],
  );
  onContainer?.call(container);
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
        home: Builder(
          builder: (context) => MediaQuery(
            // copyWith, NOT a bare MediaQueryData: a fresh instance zeroes
            // size, so any surface reading MediaQuery.size (the dashboard's
            // quick-action chips divide screen width) computed against a
            // 0-width screen and crashed layout. Disabling animations must
            // still override the INNER data the widgets actually read.
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: RepaintBoundary(child: child),
          ),
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
  expect(
    find.text('I Agree — Continue'),
    findsNothing,
    reason: 'rules sheet must close before the capture',
  );
}

Future<void> _capture(
  WidgetTester tester, {
  required String name,
  required Widget child,
  required Size size,
  required bool dark,
  List<Override> extraOverrides = const [],
  void Function(ProviderContainer)? onContainer,
  Future<void> Function(WidgetTester)? afterPump,
}) async {
  await _pumpSubject(
    tester,
    child: child,
    size: size,
    dark: dark,
    extraOverrides: extraOverrides,
    onContainer: onContainer,
  );
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
    // Typed-field goldens (susu config, vault create) must not depend on
    // the caret's blink phase: which 16ms frame focus lands on shifts with
    // machine warm-up, and the caret drifts from mid-fade to solid
    // between environments. debugDeterministicCursor freezes the caret
    // full-opacity visible on EVERY frame — the field text stays the
    // only variable content. (Flutter's own flag for exactly this.)
    EditableText.debugDeterministicCursor = true;
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
        // Fixed clock: _startDate defaults to now+1d, and the goldens
        // must not silently roll over at midnight. The seam defaults to
        // the real clock in production.
        child: SusuConfigScreen(
          groupChatId: 'gc_1',
          now: () => DateTime(2026, 10, 22),
        ),
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
      '320short': sizes['320short']!,
    }.entries) {
      testWidgets('vault create ${e.key} $mode', (tester) async {
        await _capture(
          tester,
          name: 'vault_create_${e.key}_$mode',
          // Fixed clock: _maturity defaults to now+30d.
          child: VaultCreateScreen(now: () => DateTime(2026, 10, 22)),
          size: e.value,
          dark: dark,
          afterPump: (t) async {
            await _acceptRules(t);
            // Field order: name, TARGET, auto-deposit. Target by hint.
            final targetField = find.byWidgetPredicate(
              (w) =>
                  w is TextField && (w.decoration?.hintText ?? '') == '500.00',
            );
            await t.enterText(targetField, '500');
            await t.pump();
            await t.pump(const Duration(milliseconds: 200));
            // The capture's meaning: the form, the typed target, and the
            // labelled estimate at the pinned rate (500 × 15.38).
            expect(find.text('I Agree — Continue'), findsNothing);
            expect(find.byType(TextField).evaluate().isNotEmpty, isTrue);
            expect(
              find.textContaining('7,690'),
              findsOneWidget,
              reason: 'the GH\u2085 7,690.00 estimate must be on screen',
            );
          },
        );
      });
    }

    // ── FULL-SCREEN: Susu dashboard (stacked headline hero, wheel, cycle) ─
    final susuOverrides = [
      // Riverpod 2.6 family override: on the family, not a member.
      susuDetailV2Provider.overrideWith(() => _CapSusuDetailNotifier()),
      susuMembersProvider.overrideWith(() => _CapSusuMembersNotifier()),
      susuCyclesProvider.overrideWith(() => _CapSusuCyclesNotifier()),
      currentUserProvider.overrideWith((ref) => const Stream.empty()),
    ];
    for (final e in {'390': sizes['390']!, '320': sizes['320']!}.entries) {
      testWidgets('susu dashboard ${e.key} $mode', (tester) async {
        await _capture(
          tester,
          name: 'susu_dashboard_${e.key}_$mode',
          child: SusuDashboardScreen(susuId: 's_cap', nowFn: () => _kGoldenNow),
          size: e.value,
          dark: dark,
          extraOverrides: susuOverrides,
          afterPump: (t) async {
            await t.pump(const Duration(milliseconds: 100));
            // Meaning assertions: the REAL screen shows the native USDC
            // POOL (2.00 × 8 cycles = 16.00) AND the labelled GHS estimate
            // of that pool at the pinned rate (16 × 15.38 = 246.08).
            expect(find.textContaining('16.00 USDC'), findsWidgets);
            expect(
              find.textContaining('246.08'),
              findsWidgets,
              reason: 'GH\u2085 246.08 estimate must be on screen',
            );
            expect(t.takeException(), isNull);
          },
        );
      });
    }

    // ── D2 FULL-SCREEN: merchant settlement surfaces ────────────────────
    void seedCart(ProviderContainer c) {
      final cart = c.read(cartProvider.notifier);
      cart.startNewCart(
        businessProfileId: 'biz_cap',
        businessName: 'Makola Trading Co.',
      );
      cart.addItem(
        businessProfileId: 'biz_cap',
        businessName: 'Makola Trading Co.',
        productId: 'p1',
        name: 'Adinkra wall panel',
        unitPrice: 1234.56,
      );
    }

    for (final e in {'320': sizes['320']!, '390': sizes['390']!}.entries) {
      testWidgets('cart ${e.key} $mode', (tester) async {
        await _capture(
          tester,
          name: 'merchant_cart_${e.key}_$mode',
          child: const CartScreen(),
          size: e.value,
          dark: dark,
          onContainer: seedCart,
          afterPump: (t) async {
            // Meaning: grouped 1,234.56 USDC payable figure AND the
            // labelled estimate at the pinned rate (1,234.56 x 15.38).
            expect(find.textContaining('1,234.56 USDC'), findsWidgets);
            expect(find.textContaining('current estimate'), findsOneWidget);
            expect(t.takeException(), isNull);
          },
        );
      });
    }

    for (final e in {'320': sizes['320']!, '390': sizes['390']!}.entries) {
      testWidgets('receipt ${e.key} $mode', (tester) async {
        await _capture(
          tester,
          name: 'merchant_receipt_${e.key}_$mode',
          child: ReceiptScreen(
            invoice: _capInvoice(),
            businessName: 'Makola Trading Co.',
          ),
          size: e.value,
          dark: dark,
          afterPump: (t) async {
            // The receipt runs a 500ms elastic entrance; settle it.
            await t.pumpAndSettle();
            // Meaning: grouped line and bill totals, labelled estimate.
            expect(find.textContaining('1,234.56 USDC'), findsWidgets);
            expect(find.textContaining('current estimate'), findsOneWidget);
            expect(t.takeException(), isNull);
          },
        );
      });
    }

    // ── D2 FULL-SCREEN: invoice detail (UNPAID — payment preparation) ──
    for (final e in {'320': sizes['320']!, '390': sizes['390']!}.entries) {
      testWidgets('invoice ${e.key} $mode', (tester) async {
        await _capture(
          tester,
          name: 'merchant_invoice_${e.key}_$mode',
          child: InvoiceDetailScreen(
            invoiceId: 'inv_cap2',
            service: _CapInvoiceService(),
          ),
          size: e.value,
          dark: dark,
          afterPump: (t) async {
            // Meaning: the unpaid bill renders grouped totals and says
            // PAYABLE — settlement wording must never appear pre-payment.
            expect(find.textContaining('1,234.56 USDC'), findsWidgets);
            expect(find.textContaining('payable in USDC'), findsWidgets);
            expect(find.textContaining('settled in USDC'), findsNothing);
            expect(find.textContaining('current estimate'), findsWidgets);
            expect(t.takeException(), isNull);
          },
        );
      });
    }

    // ── D2 FULL-SCREEN: business dashboard (financial summaries + rows) ──
    for (final e in {'320': sizes['320']!, '390': sizes['390']!}.entries) {
      testWidgets('dashboard ${e.key} $mode', (tester) async {
        await _capture(
          tester,
          name: 'merchant_dashboard_${e.key}_$mode',
          child: BusinessDashboardScreen(service: _CapDashboardService()),
          size: e.value,
          dark: dark,
          extraOverrides: [
            myBusinessProvider.overrideWith(
              (ref) => _CapBusinessNotifier(
                _CapDashboardService(),
                const MyBusinessState(
                  profile: BusinessProfile(
                    id: 'biz_cap',
                    bizId: 'BIZ-TEST0001',
                    businessName: 'Makola Trading Co.',
                    category: 'RETAIL',
                    isVerified: true,
                    isSuspended: false,
                    kybStatus: 'APPROVED',
                    totalEscrows: 3,
                    completedEscrows: 3,
                    userId: 10,
                    totalVolume: 0,
                    averageRating: 4.6,
                    username: 'makola',
                  ),
                  hasLoaded: true,
                ),
              ),
            ),
          ],
          afterPump: (t) async {
            // Meaning: verified-USDC aggregates render grouped with an
            // explicit denomination, never bare digits.
            expect(find.text('12,345.67 USDC'), findsOneWidget);
            expect(find.text('617.28 USDC'), findsOneWidget);
            // Scroll the product rows into the built window, then pin the
            // truthful mixed state: one authoritative GHS price, one
            // product with NO GHS price (no invented conversion).
            await t.dragUntilVisible(
              find.text('MY PRODUCTS'),
              find.byType(Scrollable).first,
              const Offset(0, -300),
            );
            await t.pump();
            expect(find.text('GH₵18983.93'), findsOneWidget);
            expect(find.text('1,234.56 USDC payable'), findsOneWidget);
            expect(find.text('42.50 USDC payable'), findsOneWidget);
            expect(t.takeException(), isNull);
          },
        );
      });
    }

    // ── FULL-SCREEN: Vault detail (same-unit progress + history rows) ────
    final vaultOverrides = [
      vaultDetailProvider('v_cap').overrideWith((ref) async => _vault()),
      vaultDepositsProvider('v_cap').overrideWith(
        (ref) async => [_capDeposit('d1', 100, 2), _capDeposit('d2', 250, 6)],
      ),
    ];
    for (final e in {
      '390': sizes['390']!,
      '320short': sizes['320short']!,
    }.entries) {
      testWidgets('vault detail ${e.key} $mode', (tester) async {
        await _capture(
          tester,
          name: 'vault_detail_${e.key}_$mode',
          child: VaultDetailScreen(vaultId: 'v_cap', nowFn: () => _kGoldenNow),
          size: e.value,
          dark: dark,
          extraOverrides: vaultOverrides,
          afterPump: (t) async {
            await t.pump(const Duration(milliseconds: 100));
            // Meaning assertions: the detail screen shows the vault's own
            // USDC figures verbatim. The headline is Text.rich
            // (NativeAmountText), so read its RichText; the target slot
            // renders '/ 1000.00 USDC' — ungrouped, exactly as the screen
            // formats it.
            final balance = tester
                .widgetList<RichText>(
                  find.descendant(
                    of: find.byKey(const ValueKey('vault-detail-balance')),
                    matching: find.byType(RichText),
                  ),
                )
                .map((r) => r.text.toPlainText())
                .join(' ');
            expect(balance, contains('500.00'));
            expect(balance, contains('USDC'));
            expect(
              find.textContaining('/ 1000.00 USDC'),
              findsOneWidget,
              reason: 'the target slot must read / 1000.00 USDC',
            );
            expect(t.takeException(), isNull);
          },
        );
      });
    }
  }
}
