import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/models/transaction_quote.dart';
import 'package:azaman/services/api_client.dart';

/// Server-authoritative transaction quote client.
///
/// Display rates may be cached for presentation, but a transaction quote must
/// come from the backend so the server owns the rate, expiry and quote id.
class TransactionQuoteService {
  final ApiClient _api;

  const TransactionQuoteService(this._api);

  Future<TransactionQuote> createQuote({
    required String purpose,
    required double amountGhs,
    int? ttlSeconds,
  }) async {
    if (amountGhs <= 0) {
      throw ArgumentError.value(
        amountGhs,
        'amountGhs',
        'Must be greater than zero.',
      );
    }

    final response = await _api.post('/quotes', {
      'purpose': purpose,
      'amountGhs': amountGhs,
      if (ttlSeconds != null) 'ttlSeconds': ttlSeconds,
    });

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invalid transaction quote response.');
    }

    // The backend returns { quote: {...} } and includes the purpose in the
    // returned quote. Keep this tolerant of a direct quote response so the
    // mobile client remains compatible with future API versions.
    final rawQuote = decoded['quote'];
    final data = rawQuote is Map<String, dynamic> ? rawQuote : decoded;

    return TransactionQuote.fromJson(data);
  }
}

final transactionQuoteServiceProvider = Provider<TransactionQuoteService>(
  (ref) => TransactionQuoteService(apiClient),
);

/// Creates a server-issued, short-lived quote. `purpose` separates independent
/// purchase/deposit flows so a quote cannot accidentally be reused across them.
final transactionQuoteProvider = FutureProvider.family<
    TransactionQuote,
    ({String purpose, double amountGhs})>((ref, args) {
  return ref.read(transactionQuoteServiceProvider).createQuote(
        purpose: args.purpose,
        amountGhs: args.amountGhs,
      );
});
