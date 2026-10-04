// =============================================================================
// MARKET STOREFRONT — invoice rebuild regression (PR #135 review, blocker 1)
//
// Invariant under test: sheet-extent changes must NEVER initiate network
// work. The storefront shell rebuilds its product subtree on every
// draggable-sheet extent tick, so the "Outstanding Bills" section must be a
// pure render projection of invoice details cached ONCE in stable parent
// state by BusinessProfileScreen._loadUnpaidInvoices().
//
// The test pumps the REAL screen (not the shell in isolation) with a
// counter-based fake BusinessService, drives the sheet through repeated
// extent changes, and proves the invoice request was fired exactly once
// for the whole session. Against the pre-fix implementation (a FutureBuilder
// creating a NEW future per rebuild) this test fails: every drag re-fires
// BusinessService.getMyInvoices and the counter grows.
//
// The screen's non-critical loads (menu / follow / showcase) go through the
// global apiClient; HttpOverrides blocks real sockets so they fail fast and
// are swallowed by their catch blocks, as in production offline use.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
import 'package:azaman/services/business_service.dart';

/// HttpClient is an interface: implement it, block every request at
/// openUrl, and let noSuchMethod fail loudly for anything unexpected.
class _BlockedHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    throw const SocketException('network is disabled in widget tests');
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BlockedOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedHttpClient();
}

BusinessProfile _business() {
  return const BusinessProfile(
    id: 'biz-1',
    bizId: 'BIZ-TEST01',
    businessName: 'Makola Fresh Market',
    category: 'RETAIL',
    isVerified: true,
    isSuspended: false,
    kybStatus: 'VERIFIED',
    totalEscrows: 42,
    completedEscrows: 40,
    userId: 1,
    totalVolume: 1200,
    averageRating: 4.8,
    reviewCount: 24,
    username: 'makola',
    description: 'Genuine Accra goods, straight from the source.',
    website: 'https://example.com',
    logoUrl: 'https://img.example/logo.png',
    coverImageUrl: 'https://img.example/cover.jpg',
    phoneNumber: '+233 20 000 0000',
    contactEmail: 'hello@example.com',
    address: '12 Kojo Thompson Rd, Accra',
  );
}

BusinessInvoice _invoice({
  required String businessProfileId,
  String id = 'inv-1',
}) {
  return BusinessInvoice(
    id: id,
    businessProfileId: businessProfileId,
    invoiceRef: 'AZ-INV-001',
    customerId: 7,
    status: InvoiceStatus.sent,
    subtotalUsdc: 20,
    taxTotalUsdc: 0,
    tipUsdc: 0,
    billTotalUsdc: 20,
    feeUsdc: 0,
    customerCoveredFee: false,
    createdAt: DateTime(2026, 10, 1),
    lineItems: const [],
    taxLines: const [],
  );
}

/// Counter-based fake: business + locations resolve instantly; every call to
/// getMyInvoices is counted and returns one invoice for THIS market plus one
/// for a different market (proving the per-business filter is a projection,
/// not an extra request).
class _CountingInvoiceService extends BusinessService {
  int invoiceCalls = 0;

  @override
  Future<BusinessProfile?> getBusinessByBizId(String bizId) async =>
      bizId == 'BIZ-TEST01' ? _business() : null;

  @override
  Future<List<BusinessLocation>> getPublicLocations(String bizId) async =>
      const [];

  @override
  Future<InvoicePage> getMyInvoices({
    String? status,
    int limit = 20,
    String? cursor,
  }) async {
    invoiceCalls++;
    return (
      invoices: [
        _invoice(businessProfileId: 'biz-1'),
        _invoice(businessProfileId: 'biz-other', id: 'inv-other'),
      ],
      hasMore: false,
      nextCursor: null,
    );
  }
}

Future<void> _pumpScreen(WidgetTester tester, _CountingInvoiceService service) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: BusinessProfileScreen(bizId: 'BIZ-TEST01', service: service),
      ),
    ),
  );
}

/// Advance explicitly through the discovery choreography timeline (same
/// discipline as the shell suite: pumpAndSettle alone can freeze mid-dip).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 240));
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump(const Duration(milliseconds: 420));
  // Explicit beats, never pumpAndSettle: the loading skeleton shimmers with
  // an infinitely repeating controller while _load is in flight, and a
  // pumpAndSettle here can race the load completing.
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump(const Duration(milliseconds: 150));
}

Finder _handle() => find.byKey(const Key('market-storefront-handle'));

void main() {
  setUpAll(() {
    HttpOverrides.global = _BlockedOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  testWidgets(
    'sheet-extent changes never re-fire the invoice request (details are '
    'cached once in stable parent state)',
    (tester) async {
      // Taller-than-default surface: the screen's loading skeleton lays out
      // fixed-height blocks that need ~740px (a pre-existing cosmetic quirk,
      // not part of this patch).
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _CountingInvoiceService();

      // Initial load: business resolves, the single invoice load fires once.
      await _pumpScreen(tester, service);
      await tester.pump();
      await _settle(tester);

      expect(find.text('Makola Fresh Market'), findsWidgets);
      expect(
        service.invoiceCalls,
        1,
        reason: 'exactly ONE invoice load for the whole screen session',
      );

      // Bring the "Outstanding Bills" section into the built viewport: lock
      // shopping, then scroll the product list down.
      await tester.drag(_handle(), const Offset(0, -320), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.drag(
        find.byType(ListView).last,
        const Offset(0, -900),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));
      for (var i = 0; i < 6; i++) {
        await tester.drag(
          find.byType(ListView).last,
          const Offset(0, -500),
          warnIfMissed: false,
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));

      // Invoice access preserved: the section renders from the cached state,
      // and the OTHER market's invoice was filtered out client-side.
      expect(find.text('Outstanding Bills'), findsOneWidget);
      expect(find.text('AZ-INV-001'), findsOneWidget);
      expect(
        service.invoiceCalls,
        1,
        reason: 'list scrolling must not initiate network work either',
      );

      // Drive the sheet through repeated EXTENT changes via the grab handle —
      // the deterministic snap control. Each drag ticks _onExtentChanged and
      // rebuilds the product subtree many times.
      for (var i = 0; i < 3; i++) {
        await tester.drag(_handle(), const Offset(0, 400), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          find.text('About this market'),
          findsOneWidget,
          reason: 'drag $i: sheet receded to the info snap',
        );
        await tester.drag(
          _handle(),
          const Offset(0, -400),
          warnIfMissed: false,
        );
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 120));
      }

      // THE INVARIANT: dragging the sheet around did not initiate any network
      // work — the counter never moved past the single initial load.
      expect(
        service.invoiceCalls,
        1,
        reason: 'sheet extent changes must never initiate network work',
      );
    },
  );

  testWidgets(
    'the redundant in-storefront "Storefront" action is gone; primary CTA '
    '+ catalog shortcut + More remain',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _CountingInvoiceService();
      await _pumpScreen(tester, service);
      await tester.pump();
      await _settle(tester);

      // The market surface no longer offers a second storefront entry.
      expect(find.text('Storefront'), findsNothing);
      // The action hierarchy is intact: primary CTA + More. (The catalog
      // shortcut is data-driven — it only appears once menu data loads, which
      // the blocked network prevents here.)
      expect(find.byKey(const Key('market-primary-cta')), findsOneWidget);
      expect(find.byTooltip('More'), findsOneWidget);
    },
  );
}
