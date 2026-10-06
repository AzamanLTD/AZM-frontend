import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

/// §9 startup audit — duplicate Oracle-rate fetching.
///
/// Four call sites each issued their own `GET /oracle/rates` (the home
/// summary refresh, the 60-second oracle poller in `hologram_provider`,
/// the FX conversion provider in `currency_provider`, and the Susu
/// supplied-rate provider). At a cold start at least two of those are in
/// flight within milliseconds of each other, so the backend serves the
/// same public payload several times per launch.
///
/// [SingleFlight] coalesces CONCURRENT calls onto ONE request: the first
/// caller starts it and everyone who arrives while it is still running
/// shares the response. It never caches and never polls — a caller that
/// arrives after the in-flight request completes starts a fresh one,
/// exactly as before. Every caller keeps parsing the payload its own way,
/// so no consumer semantics change. Routing through [apiClient] also gives
/// every caller the demo-mode interceptor and standard headers/timeout
/// that some call sites were previously missing (the oracle poller used a
/// raw `http.get` that bypassed demo mode).
class SingleFlight {
  final Map<Object, Future> _inFlight = {};

  /// Concurrent [run] calls with the same [key] share the FIRST
  /// in-flight result (including its error). Once it settles, the next
  /// caller starts a fresh run — no caching.
  Future<T> run<T>(Object key, Future<T> Function() run) {
    final existing = _inFlight[key];
    if (existing is Future<T>) return existing;
    final request = run();
    _inFlight[key] = request;
    return request.whenComplete(() {
      if (identical(_inFlight[key], request)) _inFlight.remove(key);
    }) as Future<T>;
  }

  @visibleForTesting
  bool get hasInFlight => _inFlight.isNotEmpty;
}

final SingleFlight _flight = SingleFlight();

Future<http.Response> getOracleRates() => _flight.run(
      '/oracle/rates',
      () => apiClient.get('/oracle/rates', requireAuth: false),
    );
