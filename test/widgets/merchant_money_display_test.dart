// =============================================================================
// WORKSTREAM D2 — MERCHANT MONEY DISPLAYS.
//
// The merchant USDC-settlement surfaces (cart summary, invoice, receipt)
// used to render raw `toStringAsFixed(2)` strings: ungrouped digits, and no
// cedi context for a Ghanaian payer looking at a USDC-native bill. The
// storefront LISTING contract (authoritative priceGhs, backend #359) is
// deliberately untouched — these tests cover the SETTLEMENT side only.
//
// Pins:
//   * every merchant-settlement amount renders grouped via AzMoney
//     (1,234.56 USDC — never raw '1234.56 USDC');
//   * the cart and receipt totals carry a live, LABELLED GHS estimate
//     ('≈ GH₵ … · current estimate'), never an unlabelled mix;
//   * with a stale external observation the estimate is replaced by an
//     honest 'GHS equivalent unavailable' — a guess is never rendered.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/currency_catalog.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/screens/marketplace/business_dashboard_screen.dart';
import 'package:azaman/screens/marketplace/invoice_detail_screen.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/providers/currency_provider.dart';
import 'package:azaman/screens/marketplace/cart_screen.dart';
import 'package:azaman/screens/marketplace/receipt_screen.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/storefront/services/storefront_service.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/utils/currency_math.dart';

DateTime get _nowUtc => DateTime.now().toUtc();

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

/// Server-fresh verdict with a long-past external observation: must yield
/// NO estimate (the observation, not the response, carries freshness).
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

/// The exact GHS figure the estimate line must show for [amountUsdc] at the
/// snapshot rate — computed with the production converter, so the assertion
/// pins behaviour, not hand-math.
String _expectedEstimateGhs(double amountUsdc, {double ghsPerUsdc = 15.38}) {
  final ghs = CurrencyMath.convert(
    amount: amountUsdc,
    from: CurrencyCatalog.usdc,
    to: CurrencyCatalog.ghs,
    ghsPerUsdc: ghsPerUsdc,
  );
  return '≈ ${AzMoney.ghs(ghs!)} · current estimate';
}

// ── Cart ─────────────────────────────────────────────────────────────────────

/// A real production-shaped container whose cart holds one 1,234.56 USDC
/// item — the grouped-amount threshold (>999) is the adversarial case:
/// raw toStringAsFixed would render '1234.56 USDC'.
ProviderContainer _cartContainer(FxRateSnapshot snapshot) {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      storefrontServiceProvider.overrideWithValue(StorefrontService()),
      fxRateProvider.overrideWith((ref) async => snapshot),
    ],
  );
  addTearDown(container.dispose);
  final cart = container.read(cartProvider.notifier);
  cart.startNewCart(businessProfileId: 'biz-001', businessName: 'Test Store');
  cart.addItem(
    businessProfileId: 'biz-001',
    businessName: 'Test Store',
    productId: 'p1',
    name: 'Adinkra wall panel',
    unitPrice: 1234.56,
  );
  return container;
}

Future<void> _pumpCart(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CartScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

// ── Invoice detail (unpaid payment prep vs paid receipt evidence) ────────────

class _FakeInvoiceService extends BusinessService {
  _FakeInvoiceService(this.invoice);
  final BusinessInvoice invoice;

  @override
  Future<BusinessInvoice> getInvoice(String invoiceId) async => invoice;
}

BusinessInvoice _invoiceFor(InvoiceStatus status) => BusinessInvoice(
  id: 'inv_d2',
  businessProfileId: 'biz-001',
  customerId: 10,
  invoiceRef: 'AZ-INV-2001',
  status: status,
  subtotalUsdc: 1234.56,
  taxTotalUsdc: 0,
  tipUsdc: 0,
  billTotalUsdc: 1234.56,
  feeUsdc: 0,
  customerCoveredFee: false,
  customerPaidUsdc: status == InvoiceStatus.paid ? 1234.56 : null,
  paidAt: status == InvoiceStatus.paid ? DateTime.utc(2026, 10, 20) : null,
  createdAt: DateTime.utc(2026, 10, 20),
  lineItems: [
    const InvoiceLineItem(
      id: 'li_1',
      description: 'Bulk kente order',
      quantity: 1,
      unitPriceUsdc: 1234.56,
      lineTotalUsdc: 1234.56,
    ),
  ],
  taxLines: [],
  businessName: 'Test Store',
);

Future<void> _pumpInvoice(
  WidgetTester tester, {
  required InvoiceStatus status,
  required FxRateSnapshot snapshot,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [fxRateProvider.overrideWith((ref) async => snapshot)],
      child: MaterialApp(
        home: InvoiceDetailScreen(
          invoiceId: 'inv_d2',
          service: _FakeInvoiceService(_invoiceFor(status)),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

// ── Business dashboard (verified USDC aggregates, authoritative GHS) ─────────

class _FakeDashboardService extends BusinessService {
  _FakeDashboardService(this.stats, this.page);
  final BusinessStats stats;
  final ProductPage page;

  @override
  Future<BusinessStats> getBusinessStats() async => stats;

  @override
  Future<ProductPage> getMyProducts({int limit = 20, String? cursor}) async =>
      page;
}

class _PresetBusinessNotifier extends MyBusinessNotifier {
  _PresetBusinessNotifier(super.service, MyBusinessState preset) {
    state = preset;
  }
}

BusinessProfile _dashboardProfile() => const BusinessProfile(
  id: 'biz-001',
  bizId: 'BIZ-TEST0001',
  businessName: 'Test Store',
  category: 'RETAIL',
  isVerified: true,
  isSuspended: false,
  kybStatus: 'APPROVED',
  totalEscrows: 0,
  completedEscrows: 0,
  userId: 10,
  totalVolume: 0,
  averageRating: 4.5,
  username: 'teststore',
);

// The backend contract's dated series (revenueByDay): seven UTC buckets,
// zero-revenue days included, backend-rendered labels. Fixed dates keep the
// goldens and tests independent of the machine clock.
const List<DailyRevenue> _chartSeries = [
  DailyRevenue(date: '2026-10-15', label: 'Oct 15', revenue: 12.5),
  DailyRevenue(date: '2026-10-16', label: 'Oct 16', revenue: 0),
  DailyRevenue(date: '2026-10-17', label: 'Oct 17', revenue: 40.25),
  DailyRevenue(date: '2026-10-18', label: 'Oct 18', revenue: 88),
  DailyRevenue(date: '2026-10-19', label: 'Oct 19', revenue: 0),
  DailyRevenue(date: '2026-10-20', label: 'Oct 20', revenue: 6.75),
  DailyRevenue(date: '2026-10-21', label: 'Oct 21', revenue: 133.5),
];

BusinessStats _dashboardStats() => const BusinessStats(
  totalOrders: 40,
  completedOrders: 20,
  pendingOrders: 5,
  disputedOrders: 0,
  cancelledOrders: 0,
  totalRevenue: 12345.67,
  avgOrderValue: 617.28,
  recentOrders: [],
  revenueByDay: _chartSeries,
);

BusinessProduct _dashboardProduct({String? priceGhs}) => BusinessProduct(
  id: 'p1',
  businessProfileId: 'biz-001',
  name: 'Adinkra wall panel',
  slug: 'adinkra-wall-panel',
  priceUsdc: 4.2,
  priceGhs: priceGhs,
  totalRevenue: 0,
  imageUrls: const [],
  isActive: true,
  totalOrders: 0,
);

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required FxRateSnapshot snapshot,
  BusinessStats? stats,
  List<BusinessProduct> products = const [],
}) async {
  final service = _FakeDashboardService(stats ?? _dashboardStats(), (
    products: products,
    hasMore: false,
    nextCursor: null,
  ));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fxRateProvider.overrideWith((ref) async => snapshot),
        myBusinessProvider.overrideWith(
          (ref) => _PresetBusinessNotifier(
            service,
            MyBusinessState(profile: _dashboardProfile(), hasLoaded: true),
          ),
        ),
      ],
      child: MaterialApp(home: BusinessDashboardScreen(service: service)),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'cart summary: large subtotal renders GROUPED, never raw digits',
    (tester) async {
      final container = _cartContainer(_freshSnapshot());
      await _pumpCart(tester, container);

      // Subtotal and Total rows both show the grouped figure.
      expect(
        find.text('1,234.56 USDC'),
        findsWidgets,
        reason: 'merchant settlement amounts render grouped via AzMoney',
      );
      // The raw ungrouped form must not exist anywhere on the screen.
      expect(
        find.textContaining('1234.56'),
        findsNothing,
        reason: 'raw toStringAsFixed rendering is gone',
      );
    },
  );

  testWidgets('cart summary: CTA states the grouped payable total', (
    tester,
  ) async {
    final container = _cartContainer(_freshSnapshot());
    await _pumpCart(tester, container);

    expect(find.textContaining('1,234.56 USDC'), findsWidgets);
    expect(
      find.textContaining(RegExp('· 1,234\\.56 USDC\$')),
      findsOneWidget,
      reason: 'the checkout CTA states the grouped payable amount',
    );
  });

  testWidgets('cart summary: total carries a labelled live GHS estimate', (
    tester,
  ) async {
    final container = _cartContainer(_freshSnapshot(ghsPerUsdc: 15.38));
    await _pumpCart(tester, container);

    expect(
      find.textContaining(_expectedEstimateGhs(1234.56)),
      findsOneWidget,
      reason:
          'the estimate line shows the converter-exact GHS figure, '
          'labelled as a current estimate',
    );
    expect(find.textContaining('current estimate'), findsOneWidget);
  });

  testWidgets(
    'cart summary: stale rate yields an honest unavailable line, no guess',
    (tester) async {
      final container = _cartContainer(_staleSnapshot());
      await _pumpCart(tester, container);

      expect(find.textContaining('GHS equivalent unavailable'), findsOneWidget);
      expect(
        find.textContaining('current estimate'),
        findsNothing,
        reason: 'a stale observation must never be presented as an estimate',
      );
    },
  );

  // ── Receipt ──────────────────────────────────────────────────────────────

  BusinessInvoice invoiceFixture() => BusinessInvoice(
    id: 'inv_1',
    businessProfileId: 'biz-001',
    customerId: 10,
    invoiceRef: 'AZ-RC-1001',
    status: InvoiceStatus.paid,
    subtotalUsdc: 1234.56,
    taxTotalUsdc: 0,
    tipUsdc: 0,
    billTotalUsdc: 1234.56,
    feeUsdc: 0,
    customerCoveredFee: true,
    createdAt: DateTime.utc(2026, 10, 20),
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
    businessName: 'Test Store',
  );

  Future<void> pumpReceipt(WidgetTester tester, FxRateSnapshot snapshot) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fxRateProvider.overrideWith((ref) async => snapshot)],
        child: MaterialApp(
          home: ReceiptScreen(
            invoice: invoiceFixture(),
            businessName: 'Test Store',
          ),
        ),
      ),
    );
    await tester.pump();
    // The receipt runs a 500ms elastic-out entrance animation; settle it
    // so no timer is pending when the test ends.
    await tester.pumpAndSettle();
  }

  testWidgets('receipt: line and bill totals render GROUPED', (tester) async {
    await pumpReceipt(tester, _freshSnapshot());

    expect(
      find.text('1,234.56 USDC'),
      findsWidgets,
      reason: 'line total and bill total render grouped',
    );
    expect(
      find.textContaining('1234.56'),
      findsNothing,
      reason: 'no raw ungrouped rendering remains',
    );
  });

  testWidgets('receipt: total carries a labelled live GHS estimate', (
    tester,
  ) async {
    await pumpReceipt(tester, _freshSnapshot(ghsPerUsdc: 15.38));

    expect(
      find.textContaining(_expectedEstimateGhs(1234.56)),
      findsOneWidget,
      reason: 'the settled total shows cedi context, labelled as an estimate',
    );
  });

  testWidgets('receipt: stale rate yields the honest unavailable line', (
    tester,
  ) async {
    await pumpReceipt(tester, _staleSnapshot());

    expect(find.textContaining('GHS equivalent unavailable'), findsOneWidget);
    expect(find.textContaining('current estimate'), findsNothing);
  });

  // ── Invoice detail ─────────────────────────────────────────────────────────

  testWidgets('invoice: grouped line items and totals; an UNPAID bill is '
      'payable, never settled', (tester) async {
    await _pumpInvoice(
      tester,
      status: InvoiceStatus.sent,
      snapshot: _freshSnapshot(),
    );

    expect(
      find.text('1,234.56 USDC'),
      findsWidgets,
      reason: 'line item, subtotal, taxes and bill total render grouped',
    );
    expect(
      find.textContaining('payable in USDC'),
      findsWidgets,
      reason: 'the unpaid bill-total note and pay-sheet note say payable',
    );
    expect(
      find.textContaining('settled in USDC'),
      findsNothing,
      reason: 'a sent invoice must never claim settlement',
    );
  });

  testWidgets('invoice: paid state uses settlement wording with DTO '
      'evidence', (tester) async {
    await _pumpInvoice(
      tester,
      status: InvoiceStatus.paid,
      snapshot: _freshSnapshot(),
    );

    expect(
      find.textContaining('settled in USDC'),
      findsOneWidget,
      reason:
          'status=paid with a recorded customerPaidUsdc and paidAt is '
          'the DTO evidence that authorizes settlement wording',
    );
    expect(find.text('You paid 1,234.56 USDC'), findsOneWidget);
    expect(find.textContaining('payable in USDC'), findsNothing);
  });

  testWidgets('invoice: estimate is labelled and disappears with a stale '
      'observation', (tester) async {
    await _pumpInvoice(
      tester,
      status: InvoiceStatus.sent,
      snapshot: _staleSnapshot(),
    );

    expect(find.textContaining('GHS equivalent unavailable'), findsWidgets);
    expect(find.textContaining('current estimate'), findsNothing);
  });

  // ── Business dashboard ─────────────────────────────────────────────────────

  testWidgets('dashboard: revenue and avg order are grouped with an explicit '
      'USDC denomination (backend-verified)', (tester) async {
    await _pumpDashboard(
      tester,
      snapshot: _freshSnapshot(),
      products: [_dashboardProduct(priceGhs: '25.50')],
    );

    // The aggregation contract (businessOrderService.getBusinessStats) sums
    // BusinessOrder.amountUsdc — USDC-denominated, verified at source.
    expect(find.text('12,345.67 USDC'), findsOneWidget);
    expect(find.text('617.28 USDC'), findsOneWidget);
    expect(
      find.textContaining('12345.67'),
      findsNothing,
      reason: 'no raw ungrouped rendering of the aggregates',
    );
  });

  testWidgets('dashboard: product row shows the authoritative GH₵ price and '
      'the separately labelled USDC payable', (tester) async {
    await _pumpDashboard(
      tester,
      snapshot: _freshSnapshot(),
      products: [_dashboardProduct(priceGhs: '25.50')],
    );

    // The products section is lazy below the fold of the dashboard's
    // ListView: scroll it into the built window first.
    await tester.dragUntilVisible(
      find.text('MY PRODUCTS'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pump();
    // priceGhs is the server-confirmed exact 2dp string (BE PR #359) — shown
    // verbatim, never converted from priceUsdc.
    expect(find.text('GH₵25.50'), findsOneWidget);
    expect(
      find.text('4.20 USDC payable'),
      findsOneWidget,
      reason: 'the payable USDC figure stays a separate labelled fact',
    );
  });

  testWidgets('dashboard: an absent authoritative GHS price is never '
      'invented', (tester) async {
    await _pumpDashboard(
      tester,
      snapshot: _freshSnapshot(),
      products: [_dashboardProduct()],
    );

    await tester.dragUntilVisible(
      find.text('MY PRODUCTS'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pump();
    expect(
      find.textContaining('GH₵'),
      findsNothing,
      reason:
          'no eligible BusinessPrice row means no GHS claim — never a '
          'converted priceUsdc',
    );
    expect(find.text('4.20 USDC payable'), findsOneWidget);
  });

  testWidgets('dashboard: display preference changes presentation only, '
      'never the business figures', (tester) async {
    SharedPreferences.setMockInitialValues({'az_display_currency': 'ghs'});
    await _pumpDashboard(
      tester,
      snapshot: _freshSnapshot(),
      products: [_dashboardProduct(priceGhs: '25.50')],
    );

    // The GHS display preference is a PERSONAL-rail concept; business
    // aggregates and listing prices do not convert or estimate on it.
    expect(find.text('12,345.67 USDC'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('MY PRODUCTS'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pump();
    expect(find.text('GH₵25.50'), findsOneWidget);
    expect(find.textContaining('current estimate'), findsNothing);
  });

  // ── Revenue chart source of truth (revenueByDay, not recentOrders) ─────────

  test('revenueByDay: typed daily buckets parse with date, label and revenue; '
      'absent field degrades to empty', () {
    final stats = BusinessStats.fromJson({
      'totalOrders': 7,
      'recentOrders': [],
      'revenueByDay': [
        {'date': '2026-10-20', 'label': 'Oct 20', 'revenue': 41.5},
        {'date': '2026-10-21', 'label': 'Oct 21', 'revenue': '133.25'},
        {'date': '2026-10-22', 'label': 'Oct 22', 'revenue': 0},
      ],
    });
    expect(stats.revenueByDay, hasLength(3));
    expect(stats.revenueByDay[0].date, '2026-10-20');
    expect(stats.revenueByDay[0].label, 'Oct 20');
    expect(stats.revenueByDay[0].revenue, 41.5);
    // Numbers may arrive as strings (legacy decimal encoders) — the same
    // coercion as every other model field.
    expect(stats.revenueByDay[1].revenue, 133.25);
    expect(stats.revenueByDay[2].revenue, 0);

    final legacy = BusinessStats.fromJson({'totalOrders': 0});
    expect(legacy.revenueByDay, isEmpty);
  });

  test('sevenDayRevenueSeries: latest seven dated buckets, chronological, '
      'zero-revenue days preserved, shuffled input tolerated', () {
    final buckets = List.generate(10, (i) {
      final day = 6 + i; // 2026-10-06 .. 2026-10-15
      // The backend sends zero-padded ISO dates (toISOString().slice(0,10)).
      return DailyRevenue(
        date: '2026-10-${day.toString().padLeft(2, '0')}',
        label: 'Oct $day',
        revenue: i == 7 ? 0 : day.toDouble(), // one zero day in the window
      );
    });
    // Simulate an out-of-order transport: the selection must not trust it.
    final shuffled = [...buckets]..shuffle();
    final series = BusinessDashboardScreen.sevenDayRevenueSeries(
      BusinessStats(
        totalOrders: 0,
        completedOrders: 0,
        pendingOrders: 0,
        disputedOrders: 0,
        cancelledOrders: 0,
        totalRevenue: 0,
        avgOrderValue: 0,
        recentOrders: [],
        revenueByDay: shuffled,
      ),
    );
    expect(series, hasLength(7));
    expect(series.map((b) => b.date).toList(), [
      '2026-10-09',
      '2026-10-10',
      '2026-10-11',
      '2026-10-12',
      '2026-10-13',
      '2026-10-14',
      '2026-10-15',
    ], reason: 'the LATEST seven buckets, ascending by date');
    // 2026-10-13 (i == 7) is the zero-revenue day; it lands at index 4 of
    // the seven-day window and must NOT be dropped.
    expect(series[4].revenue, 0, reason: 'zero-revenue days stay in the truth');
    // Null stats degrade to an empty series (chart hides itself).
    expect(BusinessDashboardScreen.sevenDayRevenueSeries(null), isEmpty);
  });

  testWidgets('dashboard: the revenue chart follows the dated revenueByDay '
      'series and never sums recentOrders', (tester) async {
    // CONFLICTING FIXTURE: recentOrders carries pending, disputed, refunded
    // and cancelled money (recentOrders is the five most recent orders of ANY
    // status — never a revenue source). The dated series says otherwise.
    final stats = _dashboardStats().copyWith(
      recentOrders: [
        BusinessOrder(
          id: 'o1',
          businessProfileId: 'biz-001',
          orderRef: 'ORD-777',
          title: 'Pending kente order',
          customerId: 10,
          status: BusinessOrderStatus.awaitingPayment,
          amountUsdc: 777.77,
          createdAt: DateTime(2026, 10, 21),
        ),
        BusinessOrder(
          id: 'o2',
          businessProfileId: 'biz-001',
          orderRef: 'ORD-888',
          title: 'Disputed shipment',
          customerId: 11,
          status: BusinessOrderStatus.disputed,
          amountUsdc: 888.88,
          createdAt: DateTime(2026, 10, 21),
        ),
        BusinessOrder(
          id: 'o3',
          businessProfileId: 'biz-001',
          orderRef: 'ORD-999',
          title: 'Refunded panel',
          customerId: 12,
          status: BusinessOrderStatus.refunded,
          amountUsdc: 999.99,
          createdAt: DateTime(2026, 10, 21),
        ),
      ],
    );
    await _pumpDashboard(tester, snapshot: _freshSnapshot(), stats: stats);

    // Scope is truthful: this is ORDER revenue from completed orders.
    expect(find.text('7-Day Order Revenue'), findsOneWidget);
    expect(find.text('USDC  ·  completed orders, last 7 days'), findsOneWidget);

    // All seven dated buckets show the backend-rendered labels, zero-revenue
    // days included, with no weekday guessing and no clock dependency.
    for (final label in [
      'Oct 15',
      'Oct 16',
      'Oct 17',
      'Oct 18',
      'Oct 19',
      'Oct 20',
      'Oct 21',
    ]) {
      expect(find.text(label), findsOneWidget,
          reason: 'each dated bucket label renders once');
    }

    // The non-completed amounts live ONLY in the lazy RECENT ORDERS list
    // below the fold. Scroll it into view, then require exactly one copy
    // of each: if the chart summed recentOrders, 777.77/888.88/999.99 would
    // render a second time inside the chart card (axis scale or tooltip
    // text) — and the 999.99 disputed order would tower over the real
    // 133.50 completed-revenue peak.
    await tester.dragUntilVisible(
      find.text('Pending kente order'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pump();
    expect(find.text('777.77 USDC'), findsOneWidget);
    expect(find.text('888.88 USDC'), findsOneWidget);
    expect(find.text('999.99 USDC'), findsOneWidget);
  });
}
