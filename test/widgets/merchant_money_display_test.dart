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

BusinessStats _dashboardStats() => const BusinessStats(
  totalOrders: 40,
  completedOrders: 20,
  pendingOrders: 5,
  disputedOrders: 0,
  cancelledOrders: 0,
  totalRevenue: 12345.67,
  avgOrderValue: 617.28,
  recentOrders: [],
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
  List<BusinessProduct> products = const [],
}) async {
  final service = _FakeDashboardService(_dashboardStats(), (
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
}
