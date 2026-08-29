import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/config.dart';
import 'package:azaman/models/transaction_quote.dart';
import 'package:azaman/services/api_client.dart';

/// Server-authoritative transaction quote client.
///
/// Display rates may come from the oracle cache, but a transaction quote must
/// come from the backend so the server can own the rate, expiry and quote id.
class TransactionQuoteService {
  final ApiClient _api;

  const TransactionQuoteService(this._api);

  Future<TransactionQuote> createQuote({
    required String purpose,
    required double amountGhs,
  }) async {
    if (amountGhs <= 0) {
      throw ArgumentError.value(amountGhs, 'amountGhs', 'Must be greater than zero.');
    }

    final response = await _api.post('/quotes', {
      'purpose': purpose,
      'amountGhs': amountGhs,
    });

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Unable to create transaction quote (${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, dynamic>
        ? (decoded['data'] is Map<String, dynamic> ? decoded['data'] : decoded)
        : null;
    if (data == null) throw StateError('Invalid transaction quote response.');

    return TransactionQuote.fromJson(data);
  }
}

final transactionQuoteServiceProvider = Provider<TransactionQuoteService>(
  (ref) => TransactionQuoteService(apiClient),
);

/// Creates a server-issued, short-lived quote. `purpose` separates independent
/// purchase/deposit flows so a quote cannot accidentally be reused across them.
final transactionQuoteProvider = FutureProvider.family<TransactionQuote, ({String purpose, double amountGhs})>(
  (ref, args) => ref.read(transactionQuoteServiceProvider).createQuote(
        purpose: args.purpose,
        amountGhs: args.amountGhs,
      ),
);
