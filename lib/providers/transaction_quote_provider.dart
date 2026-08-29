import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/models/transaction_quote.dart';
import 'package:azaman/providers/hologram_provider.dart';

/// Temporary quote source backed by the admin-controlled/mock oracle rate.
/// Replace the implementation behind this seam when KotaniPay quote APIs
/// become available; transaction screens should not read the oracle directly.
class TransactionQuoteService {
  final Ref _ref;

  const TransactionQuoteService(this._ref);

  TransactionQuote createQuote({
    Duration validity = const Duration(seconds: 60),
    double? feeGhs,
  }) {
    final rate = _ref.read(oracleRateProvider);
    final now = DateTime.now();
    return TransactionQuote(
      id: 'mock-${now.microsecondsSinceEpoch}',
      rateGhsPerUsdc: rate,
      feeGhs: feeGhs,
      createdAt: now,
      expiresAt: now.add(validity),
    );
  }
}

final transactionQuoteServiceProvider = Provider<TransactionQuoteService>(
  (ref) => TransactionQuoteService(ref),
);

/// Creates a short-lived quote from the current admin/mock rate.
/// This is intentionally separate from the display-rate provider.
final transactionQuoteProvider = Provider.family<TransactionQuote, String>((ref, purpose) {
  // `purpose` is part of the provider key so purchase/deposit flows can hold
  // independent quote instances without sharing lifecycle state.
  return ref.read(transactionQuoteServiceProvider).createQuote();
});
