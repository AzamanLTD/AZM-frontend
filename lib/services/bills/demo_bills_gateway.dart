// AZAMAN — DEMO BILLS GATEWAY (demo builds only)
//
// The owner's instruction was explicit: build the whole Bills experience now,
// and wire it to real routes once the backend contract is agreed. So the flow
// has to be walkable today — which means SOMETHING has to answer the gateway.
//
// This is that something, and it is quarantined by two rules:
//   1. billsGatewayProvider only returns it when AppConfig.demoMode is true AND
//      the build is not production, the same rule the unlock demo PIN uses.
//   2. `isDemo` is true, so every screen that can show money from here says
//      "Demo data" on its face. A demo receipt can never look like a real one.
//
// It is deterministic (no clock, no random, no network) so tests and captures
// are stable, and it holds no personal data.
import 'package:azaman/services/bills/bills_gateway.dart';

class DemoBillsGateway implements BillsGateway {
  DemoBillsGateway({DateTime? now}) : _now = now ?? DateTime(2026, 10, 30, 12);

  final DateTime _now;

  final List<SavedBillAccount> _accounts = [];
  final List<BillPaymentReceipt> _receipts = [];
  final List<BillPaymentRequest> _requests = [];
  final Map<String, BillQuote> _quotes = {};
  final Map<String, BillLookup> _lookups = {};
  int _seq = 0;

  /// Meter/account numbers the demo recognises. Anything else "is not found",
  /// so the not-found path is walkable too.
  static const Map<String, String> _known = {
    'ecg-001': 'AMA MENSAH',
    'gw-002': 'KOFI BOATENG',
    'dstv-003': 'ADWOA OWUSU',
  };

  static const List<BillsCategory> _categories = [
    BillsCategory(id: 'electricity', label: 'Electricity', billerCount: 1),
    BillsCategory(id: 'water', label: 'Water', billerCount: 1),
    BillsCategory(id: 'tv', label: 'Television', billerCount: 1),
    BillsCategory(id: 'internet', label: 'Internet', billerCount: 0),
  ];

  static const List<Biller> _billers = [
    Biller(
      id: 'ecg',
      categoryId: 'electricity',
      name: 'Electricity Company of Ghana',
      identifierLabel: 'Meter number',
      identifierHint: 'Try ecg-001',
    ),
    Biller(
      id: 'gwater',
      categoryId: 'water',
      name: 'Ghana Water Company',
      identifierLabel: 'Account number',
      identifierHint: 'Try gw-002',
    ),
    Biller(
      id: 'dstv',
      categoryId: 'tv',
      name: 'DStv',
      identifierLabel: 'Smartcard number',
      identifierHint: 'Try dstv-003',
    ),
  ];

  @override
  bool get isDemo => true;

  @override
  Future<BillsAvailability> availability() async =>
      const BillsAvailability(isAvailable: true, categories: _categories);

  @override
  Future<List<Biller>> billers({String? categoryId}) async => categoryId == null
      ? _billers
      : _billers.where((b) => b.categoryId == categoryId).toList();

  @override
  Future<BillLookup> lookup({
    required String billerId,
    required String identifier,
  }) async {
    final biller = _billers.firstWhere((b) => b.id == billerId);
    final normalized = identifier.trim().toLowerCase();
    final holder = _known[normalized];
    if (holder == null) {
      throw const BillsLookupNotFoundException();
    }
    final lookup = BillLookup(
      billerId: biller.id,
      billerName: biller.name,
      identifierMasked: _mask(identifier),
      holderName: holder,
    );
    _lookups['$billerId:$normalized'] = lookup;
    return lookup;
  }

  @override
  Future<List<SavedBillAccount>> savedAccounts() async =>
      List.unmodifiable(_accounts);

  @override
  Future<SavedBillAccount> saveAccount({
    required String billerId,
    required String identifier,
    String? alias,
  }) async {
    final biller = _billers.firstWhere((b) => b.id == billerId);
    final lookup = await this.lookup(
      billerId: billerId,
      identifier: identifier,
    );
    final account = SavedBillAccount(
      id: 'acct-${++_seq}',
      billerId: biller.id,
      billerName: biller.name,
      categoryId: biller.categoryId,
      identifierMasked: lookup.identifierMasked,
      holderName: lookup.holderName,
      alias: (alias != null && alias.trim().isNotEmpty) ? alias.trim() : null,
    );
    _accounts
      ..removeWhere((a) => a.identifierMasked == account.identifierMasked)
      ..add(account);
    return account;
  }

  @override
  Future<void> removeAccount(String accountId) async {
    _accounts.removeWhere((a) => a.id == accountId);
  }

  @override
  Future<BillQuote> quote({required String accountId, double? amount}) async {
    final account = _accounts.firstWhere((a) => a.id == accountId);
    // An electricity meter has an authoritative amount due; the others let the
    // member choose. Both paths need to be walkable in the demo.
    final authoritative = account.categoryId == 'electricity';
    final due = amount ?? (authoritative ? 214.35 : 100);
    const fee = 2.5;
    final quote = BillQuote(
      quoteId: 'quote-${++_seq}',
      accountId: account.id,
      billerName: account.billerName,
      identifierMasked: account.identifierMasked,
      // Demo accounts carry a provider name; a real saved account from the
      // server may not, and the quote then says so instead of borrowing one.
      holderName: account.holderName ?? account.displayName,
      amount: due,
      feeAmount: fee,
      totalAmount: due + fee,
      currency: 'GHS',
      expiresAt: _now.add(const Duration(minutes: 10)),
      amountDueIsAuthoritative: authoritative && amount == null,
    );
    _quotes[quote.quoteId] = quote;
    return quote;
  }

  @override
  Future<BillPaymentReceipt> pay({required String quoteId}) async {
    final quote = _quotes[quoteId];
    if (quote == null) {
      throw const BillsUnavailableException('Quote expired');
    }
    final receipt = BillPaymentReceipt(
      paymentId: 'pay-${++_seq}',
      // The demo's terminal state is PAID because it is simulating the
      // provider's completed callback — the screens' honesty rules are what the
      // real gateway will exercise for pending/unknown.
      state: BillPaymentState.paid,
      billerName: quote.billerName,
      identifierMasked: quote.identifierMasked,
      totalAmount: quote.totalAmount,
      currency: quote.currency,
      reference: 'AZM-DEMO-${1000 + _seq}',
      token: quote.billerName == 'DStv' ? 'DEMO-TOKEN-${1000 + _seq}' : null,
      settledAt: _now,
    );
    _receipts.insert(0, receipt);
    return receipt;
  }

  @override
  Future<List<BillPaymentRequest>> requests() async =>
      List.unmodifiable(_requests);

  @override
  Future<BillPaymentRequest> sendRequest({
    required String accountId,
    required String recipientName,
    double? amount,
    String? note,
    DateTime? expiresAt,
  }) async {
    final account = _accounts.firstWhere((a) => a.id == accountId);
    final request = BillPaymentRequest(
      id: 'req-${++_seq}',
      direction: 'outgoing',
      billerName: account.billerName,
      alias: account.alias,
      identifierMasked: account.identifierMasked,
      state: BillRequestState.pending,
      counterpartyName: recipientName,
      amount: amount,
      note: note,
      createdAt: _now,
      expiresAt: expiresAt,
    );
    _requests.insert(0, request);
    return request;
  }

  @override
  Future<BillPaymentRequest> respondToRequest({
    required String requestId,
    required bool accept,
  }) async {
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index < 0) throw const BillsUnavailableException('Request not found');
    final old = _requests[index];
    final updated = BillPaymentRequest(
      id: old.id,
      direction: old.direction,
      billerName: old.billerName,
      alias: old.alias,
      identifierMasked: old.identifierMasked,
      state: accept
          ? BillRequestState.acceptedAwaitingPayment
          : BillRequestState.declined,
      counterpartyName: old.counterpartyName,
      amount: old.amount,
      note: old.note,
      createdAt: old.createdAt,
      expiresAt: old.expiresAt,
    );
    _requests[index] = updated;
    return updated;
  }

  @override
  Future<BillsHubSnapshot> hub() async => BillsHubSnapshot(
    savedAccounts: List.unmodifiable(_accounts),
    recentPayments: List.unmodifiable(_receipts.take(5)),
    // "Outstanding" is the SERVER's claim, so the demo does not invent one from
    // the accounts it happens to hold.
    outstanding: const [],
    requests: List.unmodifiable(_requests),
  );

  /// `1234 5678` style mask for the identifier's tail.
  static String _mask(String identifier) {
    final digits = identifier.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final tail = digits.length <= 4
        ? digits
        : digits.substring(digits.length - 4);
    return '•••• $tail';
  }
}

/// A genuine "this identifier does not exist" from the provider — distinct from
/// "the facility is not configured", because the two need different words.
class BillsLookupNotFoundException implements Exception {
  const BillsLookupNotFoundException();
}
