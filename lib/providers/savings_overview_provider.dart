// =============================================================================
// AZAMAN — SAVINGS OVERVIEW PROVIDER
//
// NEW-HOME §9 (audit: "align Save with Savings"): the Home "Save" module
// opens /savings, so its notice must represent the SAVINGS product — real
// goal data from GET /savings/overview — not Vault semantics.
//
// The provider exists so the SAME cached overview backs both the Savings
// screen and the Home notice board, and so Home can honour the
// no-decorative-fetch rule: it reads the provider ONLY when it already
// exists (`ref.exists`), so visiting Home never triggers a savings fetch.
// The Savings screen itself performs the fetch (it always did, via its
// own apiClient call; it now just reads/writes through this provider).
// =============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';

/// The `/savings/overview` payload, as the Savings screen consumes it:
/// `data` = { balance, currency, goals: [ { name, currentAmountGhs,
/// targetAmountGhs, ... } ], ... }.
class SavingsOverview {
  final Map<String, dynamic> data;
  const SavingsOverview(this.data);

  List<Map<String, dynamic>> get goals {
    final raw = data['goals'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((g) => Map<String, dynamic>.from(g))
        .toList(growable: false);
  }

  /// The most relevant goal for a compact notice: the one with the least
  /// remaining to target (ties broken by name for determinism).
  Map<String, dynamic>? mostRelevantGoal() {
    Map<String, dynamic>? best;
    double bestRemaining = double.infinity;
    for (final g in goals) {
      final current = (g['currentAmountGhs'] as num?)?.toDouble() ?? 0.0;
      final target = (g['targetAmountGhs'] as num?)?.toDouble() ?? 0.0;
      if (target <= 0) continue;
      final remaining = target - current;
      if (remaining < bestRemaining) {
        bestRemaining = remaining;
        best = g;
      }
    }
    return best;
  }
}

class SavingsOverviewNotifier extends AsyncNotifier<SavingsOverview> {
  @override
  Future<SavingsOverview> build() => _fetch();

  Future<SavingsOverview> _fetch() async {
    final response = await apiClient.get('/savings/overview');
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'];
      return SavingsOverview(
          data is Map ? Map<String, dynamic>.from(data) : const {});
    }
    throw Exception('Failed to load savings overview');
  }

  /// Pull-to-refresh on the Savings screen (or an explicit reload).
  Future<void> reload() async {
    state = const AsyncValue<SavingsOverview>.loading();
    state = await AsyncValue.guard(() => _fetch());
  }

  /// Local, optimistic edits from the goal sheets keep the cache honest
  /// without a refetch round-trip.
  void patchGoals(List<Map<String, dynamic>> goals) {
    final current = state.valueOrNull;
    if (current == null) return;
    final data = Map<String, dynamic>.from(current.data);
    data['goals'] = goals;
    state = AsyncValue.data(SavingsOverview(data));
  }
}

final savingsOverviewProvider =
    AsyncNotifierProvider<SavingsOverviewNotifier, SavingsOverview>(
        SavingsOverviewNotifier.new);
