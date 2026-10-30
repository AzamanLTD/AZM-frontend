// AZAMAN — BILLS GATEWAY CONTRACT
//
// The seam between the Bills UI and whatever the backend can actually do. It
// exists so the screens can be written and completed BEFORE the provider
// contract is agreed, without inventing endpoints or response fields here.
//
// Three implementations, deliberately separated:
//   • [UnavailableBillsGateway] — production default while no route exists.
//     Every capability reports "not configured"; nothing is synthesised.
//   • [DemoBillsGateway] — demo builds only (AppConfig.demoMode &&
//     !isProduction), the same rule the app-unlock demo uses. It is visibly
//     labelled as demo data everywhere it can be mistaken for real money.
//   • the HTTP implementation, written once the backend agent confirms the
//     routes and payloads. It is the ONLY thing that changes then: the screens,
//     the states and the tests below are already shaped around this contract.
//
// Rules this contract encodes:
//   • availability is the SERVER's answer, never a hardcoded list;
//   • a holder/meter name comes from a lookup, never from the client;
//   • amounts, fees and totals come from a QUOTE, never from arithmetic the UI
//     invented;
//   • "pending", "created" and "processing" are not success — only an
//     authoritative completed state is;
//   • saved accounts are server-owned, and only ever shown masked.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/config.dart';

import 'demo_bills_gateway.dart';

/// One biller category the backend reports it can serve.
class BillsCategory {
  const BillsCategory({
    required this.id,
    required this.label,
    this.billerCount = 0,
  });

  final String id;
  final String label;
  final int billerCount;
}

/// The server's answer to "what can this member actually pay right now?".
class BillsAvailability {
  const BillsAvailability({
    required this.isAvailable,
    this.categories = const <BillsCategory>[],
  });

  /// False when the facility is not configured, or the member/region has no
  /// reachable billers. The UI must render an honest empty state for this.
  final bool isAvailable;

  final List<BillsCategory> categories;

  static const BillsAvailability unavailable = BillsAvailability(
    isAvailable: false,
  );
}

/// A biller the server says it can reach.
class Biller {
  const Biller({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.identifierLabel,
    this.identifierHint,
  });

  final String id;
  final String categoryId;
  final String name;

  /// What the member must type to be found — "Meter number", "Smartcard
  /// number", "Account number". Supplied by the server so the form never
  /// guesses the identifier's meaning.
  final String identifierLabel;
  final String? identifierHint;
}

/// The result of a GENUINE lookup. The holder name is the server's; the mask is
/// what the member is allowed to see afterwards.
class BillLookup {
  const BillLookup({
    required this.billerId,
    required this.billerName,
    required this.identifierMasked,
    required this.holderName,
  });

  final String billerId;
  final String billerName;
  final String identifierMasked;

  /// Returned by the provider. NEVER invented by the client.
  final String holderName;
}

/// A saved bill account. Server-owned: the identifier is stored encrypted and
/// only ever surfaced masked.
class SavedBillAccount {
  const SavedBillAccount({
    required this.id,
    required this.billerId,
    required this.billerName,
    required this.categoryId,
    required this.identifierMasked,
    required this.holderName,
    this.alias,
  });

  final String id;
  final String billerId;
  final String billerName;
  final String categoryId;
  final String identifierMasked;
  final String holderName;

  /// The member's own name for it — "My Apartment".
  final String? alias;

  String get displayName =>
      (alias != null && alias!.trim().isNotEmpty) ? alias!.trim() : billerName;
}

/// A price for one payment, as quoted by the server. The UI shows these numbers
/// verbatim: it never computes a fee or a total itself.
class BillQuote {
  const BillQuote({
    required this.quoteId,
    required this.accountId,
    required this.billerName,
    required this.identifierMasked,
    required this.holderName,
    required this.amount,
    required this.feeAmount,
    required this.totalAmount,
    required this.currency,
    required this.expiresAt,
    this.amountDueIsAuthoritative = false,
  });

  final String quoteId;
  final String accountId;
  final String billerName;
  final String identifierMasked;
  final String holderName;
  final double amount;
  final double feeAmount;
  final double totalAmount;
  final String currency;
  final DateTime expiresAt;

  /// True when the provider itself said "this is what is owed", so the member
  /// cannot underpay or overpay. False means the member chose the amount.
  final bool amountDueIsAuthoritative;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);
}

/// How a payment ended. Only [BillPaymentState.paid] may be shown as success.
enum BillPaymentState {
  pending,
  processing,
  paid,
  failed,

  /// The provider's answer never arrived. The money may or may not have moved,
  /// so the UI says exactly that and nothing more.
  unknown,
}

class BillPaymentReceipt {
  const BillPaymentReceipt({
    required this.paymentId,
    required this.state,
    required this.billerName,
    required this.identifierMasked,
    required this.totalAmount,
    required this.currency,
    this.reference,
    this.token,
    this.receiptUrl,
    this.failureReason,
    this.settledAt,
  });

  final String paymentId;
  final BillPaymentState state;
  final String billerName;
  final String identifierMasked;
  final double totalAmount;
  final String currency;

  /// The provider's own reference/token. Present only when it really exists.
  final String? reference;
  final String? token;
  final String? receiptUrl;
  final String? failureReason;
  final DateTime? settledAt;

  bool get isPaid => state == BillPaymentState.paid;
}

/// A bill shared with a contact so THEY can pay it from their own balance.
/// This is not /api/payment-requests: nothing here can debit anyone.
enum BillRequestState {
  pending,
  acceptedAwaitingPayment,
  paid,
  failed,
  declined,
  cancelled,
  expired,
}

class BillPaymentRequest {
  const BillPaymentRequest({
    required this.id,
    required this.direction,
    required this.billerName,
    required this.identifierMasked,
    required this.state,
    required this.counterpartyName,
    required this.createdAt,
    this.alias,
    this.amount,
    this.currency = 'GHS',
    this.note,
    this.expiresAt,
  });

  final String id;

  /// 'outgoing' = the member asked someone to pay; 'incoming' = someone asked
  /// the member to pay.
  final String direction;
  final String billerName;
  final String? alias;
  final String identifierMasked;
  final BillRequestState state;
  final String counterpartyName;
  final double? amount;
  final String currency;
  final String? note;
  final DateTime createdAt;
  final DateTime? expiresAt;

  bool get isIncoming => direction == 'incoming';

  String get displayName =>
      (alias != null && alias!.trim().isNotEmpty) ? alias!.trim() : billerName;
}

/// Everything the Hub renders, in one read.
class BillsHubSnapshot {
  const BillsHubSnapshot({
    this.savedAccounts = const [],
    this.recentPayments = const [],
    this.outstanding = const [],
    this.requests = const [],
  });

  final List<SavedBillAccount> savedAccounts;
  final List<BillPaymentReceipt> recentPayments;

  /// Bills the server reports as due. Never derived from "we have no receipt".
  final List<SavedBillAccount> outstanding;
  final List<BillPaymentRequest> requests;

  static const BillsHubSnapshot empty = BillsHubSnapshot();
}

/// Raised when a capability is not configured on the server yet. The UI turns
/// this into the same honest state as [BillsAvailability.unavailable].
class BillsUnavailableException implements Exception {
  const BillsUnavailableException([this.message]);

  final String? message;

  @override
  String toString() =>
      'BillsUnavailableException: ${message ?? 'not configured'}';
}

/// The bill-payment capability surface.
///
/// Everything the screens need, and nothing about transport: swap the
/// implementation and the whole flow works, which is the point of writing it
/// before the backend is settled.
abstract class BillsGateway {
  /// True only for the demo implementation, so the UI can say so out loud.
  bool get isDemo => false;

  Future<BillsAvailability> availability();

  /// Billers for a category (or all of them when [categoryId] is null).
  Future<List<Biller>> billers({String? categoryId});

  /// A GENUINE lookup of an identifier against the provider.
  Future<BillLookup> lookup({
    required String billerId,
    required String identifier,
  });

  Future<List<SavedBillAccount>> savedAccounts();

  Future<SavedBillAccount> saveAccount({
    required BillLookup lookup,
    String? alias,
  });

  Future<void> removeAccount(String accountId);

  /// A fresh price for a payment. Called again at confirm time, so a stale
  /// quote can never be paid.
  Future<BillQuote> quote({required String accountId, double? amount});

  /// Execute a quoted payment. Returns the provider's own terminal state.
  Future<BillPaymentReceipt> pay({required String quoteId});

  Future<List<BillPaymentRequest>> requests();

  Future<BillPaymentRequest> sendRequest({
    required String accountId,
    required String recipientName,
    double? amount,
    String? note,
    DateTime? expiresAt,
  });

  Future<BillPaymentRequest> respondToRequest({
    required String requestId,
    required bool accept,
  });

  Future<BillsHubSnapshot> hub();
}

/// Production default: honest unavailability, with no invented data.
class UnavailableBillsGateway implements BillsGateway {
  const UnavailableBillsGateway();

  @override
  bool get isDemo => false;

  Future<T> _refuse<T>() async =>
      throw const BillsUnavailableException('Bill payments are not configured');

  @override
  Future<BillsAvailability> availability() async =>
      BillsAvailability.unavailable;

  @override
  Future<List<Biller>> billers({String? categoryId}) => _refuse();

  @override
  Future<BillLookup> lookup({
    required String billerId,
    required String identifier,
  }) => _refuse();

  @override
  Future<List<SavedBillAccount>> savedAccounts() async =>
      const <SavedBillAccount>[];

  @override
  Future<SavedBillAccount> saveAccount({
    required BillLookup lookup,
    String? alias,
  }) => _refuse();

  @override
  Future<void> removeAccount(String accountId) => _refuse();

  @override
  Future<BillQuote> quote({required String accountId, double? amount}) =>
      _refuse();

  @override
  Future<BillPaymentReceipt> pay({required String quoteId}) => _refuse();

  @override
  Future<List<BillPaymentRequest>> requests() async =>
      const <BillPaymentRequest>[];

  @override
  Future<BillPaymentRequest> sendRequest({
    required String accountId,
    required String recipientName,
    double? amount,
    String? note,
    DateTime? expiresAt,
  }) => _refuse();

  @override
  Future<BillPaymentRequest> respondToRequest({
    required String requestId,
    required bool accept,
  }) => _refuse();

  @override
  Future<BillsHubSnapshot> hub() async => BillsHubSnapshot.empty;
}

/// The gateway the app uses. Tests override this provider; demo builds get the
/// demo gateway, which can never appear in production.
final billsGatewayProvider = Provider<BillsGateway>((ref) {
  if (AppConfig.demoMode && !AppConfig.isProduction) {
    return DemoBillsGateway();
  }
  return const UnavailableBillsGateway();
});

/// Mutable demo state, created lazily so that a production build never
/// constructs it.
final _demoGatewayProvider = Provider<DemoBillsGateway>(
  (ref) => DemoBillsGateway(),
);

/// Exposed for the demo gateway file to reuse the same lazily-built instance
/// when it is the active gateway.
Provider<DemoBillsGateway> get demoBillsGatewayProvider => _demoGatewayProvider;

/// What the Hub reads. A failed read is NOT the same as "no bills": the Hub
/// distinguishes them so a network problem never looks like an empty account.
final billsHubProvider = FutureProvider<BillsHubSnapshot>((ref) async {
  return ref.watch(billsGatewayProvider).hub();
});

/// Saved accounts alone, for the pickers that do not need the whole Hub.
final savedBillAccountsProvider = FutureProvider<List<SavedBillAccount>>((
  ref,
) async {
  return ref.watch(billsGatewayProvider).savedAccounts();
});
