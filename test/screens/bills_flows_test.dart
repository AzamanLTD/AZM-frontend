// THE BILLS FLOWS ARE FINISHED WITHOUT THE BACKEND — AND STILL HONEST.
//
// The owner's instruction: build the whole experience now, wire it to real
// routes once the contract is agreed. So these contracts are about the STATES,
// not the transport:
//
//   • a holder name shown to the member is the one the lookup returned;
//   • a fee or a total shown to the member is the quote's number, never one
//     this app computed;
//   • an expired quote is refreshed instead of paid;
//   • only a provider-completed payment is called paid — pending, processing
//     and "no answer" each say what they are;
//   • asking a contact shows exactly which details are shared, and produces a
//     request, never a payment.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/screens/bills/bills_add_account_screen.dart';
import 'package:azaman/screens/bills/bills_pay_screen.dart';
import 'package:azaman/screens/bills/bills_request_screen.dart';
import 'package:azaman/services/bills/bills_gateway.dart';
import 'package:azaman/services/bills/demo_bills_gateway.dart';

/// A scripted gateway: each test states only the answers it is exercising.
class _Scripted extends UnavailableBillsGateway {
  _Scripted({
    this.lookupResult,
    this.lookupError,
    required this.quoted,
    this.receiptState = BillPaymentState.paid,
    this.payThrows = false,
    this.accounts = const [],
  });

  final BillLookup? lookupResult;
  final Object? lookupError;
  final BillQuote quoted;
  final BillPaymentState receiptState;
  final bool payThrows;
  final List<SavedBillAccount> accounts;

  int lookups = 0;
  int quotes = 0;
  int pays = 0;
  final List<BillPaymentRequest> sentRequests = [];
  final List<String> savedAliases = [];

  @override
  bool get isDemo => false;

  @override
  Future<List<SavedBillAccount>> savedAccounts() async => accounts;

  @override
  Future<List<Biller>> billers({String? categoryId}) async => const [
    Biller(
      id: 'b1',
      categoryId: 'electricity',
      name: 'Test Power',
      identifierLabel: 'Meter number',
      identifierHint: 'Try 1234',
    ),
  ];

  @override
  Future<BillLookup> lookup({
    required String billerId,
    required String identifier,
  }) async {
    lookups++;
    if (lookupError != null) throw lookupError!;
    return lookupResult!;
  }

  @override
  Future<SavedBillAccount> saveAccount({
    required BillLookup lookup,
    String? alias,
  }) async {
    savedAliases.add(alias ?? '');
    return SavedBillAccount(
      id: 'a1',
      billerId: lookup.billerId,
      billerName: lookup.billerName,
      categoryId: 'electricity',
      identifierMasked: lookup.identifierMasked,
      holderName: lookup.holderName,
      alias: alias,
    );
  }

  @override
  Future<BillQuote> quote({required String accountId, double? amount}) async {
    quotes++;
    return quoted;
  }

  @override
  Future<BillPaymentReceipt> pay({required String quoteId}) async {
    pays++;
    if (payThrows) throw const BillsUnavailableException('timeout');
    return BillPaymentReceipt(
      paymentId: 'p1',
      state: receiptState,
      billerName: quoted.billerName,
      identifierMasked: quoted.identifierMasked,
      totalAmount: quoted.totalAmount,
      currency: quoted.currency,
      reference: receiptState == BillPaymentState.paid ? 'AZM-1' : null,
      token: null,
    );
  }

  @override
  Future<BillPaymentRequest> sendRequest({
    required String accountId,
    required String recipientName,
    double? amount,
    String? note,
    DateTime? expiresAt,
  }) async {
    final request = BillPaymentRequest(
      id: 'r1',
      direction: 'outgoing',
      billerName: 'Test Power',
      alias: 'My Apartment',
      identifierMasked: '•••• 5678',
      state: BillRequestState.pending,
      counterpartyName: recipientName,
      amount: amount,
      note: note,
      createdAt: DateTime(2026, 10, 30),
    );
    sentRequests.add(request);
    return request;
  }
}

const _account = SavedBillAccount(
  id: 'a1',
  billerId: 'b1',
  billerName: 'Test Power',
  categoryId: 'electricity',
  identifierMasked: '•••• 5678',
  holderName: 'AMA MENSAH',
  alias: 'My Apartment',
);

BillQuote _quote({
  bool expired = false,
  bool authoritative = true,
}) => BillQuote(
  quoteId: 'q1',
  accountId: 'a1',
  billerName: 'Test Power',
  identifierMasked: '•••• 5678',
  holderName: 'AMA MENSAH',
  amount: 214.35,
  // Deliberately NOT 2 + 214.35: the screen must print the quote's own total.
  feeAmount: 2.5,
  totalAmount: 217.85,
  currency: 'GHS',
  expiresAt: expired
      ? DateTime(2026, 10, 30, 11)
      : DateTime(2026, 10, 30, 23, 59),
  amountDueIsAuthoritative: authoritative,
);

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  _Scripted gateway,
) async {
  await tester.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [billsGatewayProvider.overrideWithValue(gateway)],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('save a bill', () {
    testWidgets('the holder name shown is the one the provider returned', (
      tester,
    ) async {
      final gateway = _Scripted(
        quoted: _quote(),
        lookupResult: const BillLookup(
          billerId: 'b1',
          billerName: 'Test Power',
          identifierMasked: '•••• 5678',
          holderName: 'AMA MENSAH',
        ),
      );
      await _pump(tester, const BillsAddAccountScreen(), gateway);

      await tester.tap(find.text('Test Power'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '12345678');
      await tester.tap(find.text('Look it up'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(gateway.lookups, 1);
      expect(find.text('AMA MENSAH'), findsOneWidget);
      // The lookup answers with a MASK, so the confirm card shows the mask. The
      // raw digits appear exactly once — in the field the member typed them
      // into — and never as account detail.
      expect(find.text('•••• 5678'), findsOneWidget);
      expect(
        find.text('12345678'),
        findsOneWidget,
        reason: 'the typed value stays in its own field, and appears nowhere '
            'else on the confirm card',
      );
    });

    testWidgets('an unknown identifier is reported, not guessed at', (
      tester,
    ) async {
      final gateway = _Scripted(
        quoted: _quote(),
        lookupError: const BillsLookupNotFoundException(),
      );
      await _pump(tester, const BillsAddAccountScreen(), gateway);

      await tester.tap(find.text('Test Power'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'nope');
      await tester.tap(find.text('Look it up'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('has no account with that'), findsOneWidget);
      // Nothing to confirm, because nothing was found.
      expect(find.text('Save this bill'), findsNothing);
    });
  });

  group('pay a bill', () {
    testWidgets('review shows the quote\'s fee and total, not arithmetic', (
      tester,
    ) async {
      final gateway = _Scripted(quoted: _quote(), accounts: const [_account]);
      await _pump(tester, const BillsPayScreen(accountId: 'a1'), gateway);

      await tester.tap(find.text('Get the price'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(gateway.quotes, 1);
      expect(find.text('214.35 GHS'), findsOneWidget);
      expect(find.text('2.50 GHS'), findsOneWidget);
      expect(find.text('217.85 GHS'), findsOneWidget);
      // The pay button carries the same total the quote stated.
      expect(find.text('Pay 217.85 GHS'), findsOneWidget);
    });

    testWidgets('a paid payment says paid and carries the reference', (
      tester,
    ) async {
      final gateway = _Scripted(quoted: _quote(), accounts: const [_account]);
      await _pump(tester, const BillsPayScreen(accountId: 'a1'), gateway);

      await tester.tap(find.text('Get the price'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Pay 217.85 GHS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(gateway.pays, 1);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('AZM-1'), findsOneWidget);
    });

    for (final state in [
      BillPaymentState.pending,
      BillPaymentState.processing,
      BillPaymentState.unknown,
    ]) {
      testWidgets('$state is never dressed up as paid', (tester) async {
        final gateway = _Scripted(
          quoted: _quote(),
          accounts: const [_account],
          receiptState: state,
        );
        await _pump(tester, const BillsPayScreen(accountId: 'a1'), gateway);

        await tester.tap(find.text('Get the price'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Pay 217.85 GHS'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Paid'), findsNothing);
        expect(gateway.pays, 1);
      });
    }

    testWidgets('no answer from the biller is reported as unknown, and the '
        'member is warned about paying twice', (tester) async {
      final gateway = _Scripted(
        quoted: _quote(),
        accounts: const [_account],
        payThrows: true,
      );
      await _pump(tester, const BillsPayScreen(accountId: 'a1'), gateway);

      await tester.tap(find.text('Get the price'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Pay 217.85 GHS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('may still be processing'), findsOneWidget);
      expect(find.text('Paid'), findsNothing);
    });

    testWidgets('an expired quote is refreshed, and nothing is paid', (
      tester,
    ) async {
      final gateway = _Scripted(
        quoted: _quote(expired: true),
        accounts: const [_account],
      );
      await _pump(tester, const BillsPayScreen(accountId: 'a1'), gateway);

      await tester.tap(find.text('Get the price'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Pay 217.85 GHS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(gateway.pays, 0, reason: 'a stale price must never be paid');
      expect(gateway.quotes, 2, reason: 'the price is fetched again');
      expect(find.textContaining('expired'), findsOneWidget);
    });
  });

  group('ask a contact', () {
    testWidgets('the shared details are shown masked, and sending produces a '
        'request rather than a payment', (tester) async {
      final gateway = _Scripted(quoted: _quote(), accounts: const [_account]);
      await _pump(tester, const BillsRequestScreen(), gateway);

      await tester.tap(find.text('My Apartment'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'ama');
      await tester.pump();

      expect(find.text('•••• 5678'), findsWidgets);
      expect(find.text('AMA MENSAH'), findsWidgets);

      await tester.tap(find.text('Send the request'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(gateway.sentRequests, hasLength(1));
      expect(gateway.sentRequests.single.state, BillRequestState.pending);
      expect(gateway.pays, 0, reason: 'a request is not a payment');
      expect(find.text('Waiting for an answer'), findsOneWidget);
      expect(find.text('Paid'), findsNothing);
    });
  });
}
