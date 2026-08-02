// =============================================================================
// VAULT PROVIDER  (Master Sprint, 2026-05-27)
//
// Riverpod state for the Solo Vault feature. Two notifiers:
//   • vaultsProvider          → AsyncNotifier<List<Vault>>
//   • vaultDetailProvider     → family<AsyncNotifier<Vault?>, String>
//
// All requests funnel through the canonical apiClient. Mutations bump the
// list provider so the dashboard re-renders when the user returns.
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';

// ── Models ─────────────────────────────────────────────────────────────────

class Vault {
  final String id;
  final String name;
  final double targetAmountUsdc;
  final double currentAmountUsdc;
  final String status; // ACTIVE | COMPLETED | BROKEN_EARLY | CANCELLED
  final DateTime startDate;
  final DateTime maturityDate;
  final DateTime? completedAt;
  final DateTime? brokenAt;
  final bool isLocked;
  final double earlyBreakPenaltyPct;

  // Auto-rule
  final bool autoRuleEnabled;
  final double? autoRuleAmountUsdc;
  final String? autoRuleFrequency; // DAILY|WEEKLY|BIWEEKLY|MONTHLY
  final DateTime? autoRuleNextRun;

  // Gamification
  final int streakCount;
  final int longestStreak;
  final int missedCount;
  final double consistencyScore;
  final double totalAzmEarned;
  final Map<String, dynamic>? receiptSnapshot;

  // ── Phase 3: DeFi Yield ──
  final bool yieldEnabled;
  final String? yieldStrategy;
  final double yieldApr;
  final double yieldEarnedUsdc;
  final DateTime? yieldLastCompoundAt;
  final bool yieldAutoCompound;

  Vault({
    required this.id,
    required this.name,
    required this.targetAmountUsdc,
    required this.currentAmountUsdc,
    required this.status,
    required this.startDate,
    required this.maturityDate,
    this.completedAt,
    this.brokenAt,
    required this.isLocked,
    required this.earlyBreakPenaltyPct,
    required this.autoRuleEnabled,
    this.autoRuleAmountUsdc,
    this.autoRuleFrequency,
    this.autoRuleNextRun,
    required this.streakCount,
    required this.longestStreak,
    required this.missedCount,
    required this.consistencyScore,
    required this.totalAzmEarned,
    this.receiptSnapshot,
    this.yieldEnabled = false,
    this.yieldStrategy,
    this.yieldApr = 0,
    this.yieldEarnedUsdc = 0,
    this.yieldLastCompoundAt,
    this.yieldAutoCompound = true,
  });

  factory Vault.fromJson(Map<String, dynamic> j) => Vault(
        id: j['id'] as String,
        name: j['name'] as String,
        targetAmountUsdc: _num(j['targetAmountUsdc']),
        currentAmountUsdc: _num(j['currentAmountUsdc']),
        status: j['status'] as String,
        startDate: DateTime.parse(j['startDate']),
        maturityDate: DateTime.parse(j['maturityDate']),
        completedAt: j['completedAt'] != null ? DateTime.tryParse(j['completedAt']) : null,
        brokenAt: j['brokenAt'] != null ? DateTime.tryParse(j['brokenAt']) : null,
        isLocked: j['isLocked'] as bool? ?? true,
        earlyBreakPenaltyPct: _num(j['earlyBreakPenaltyPct']),
        autoRuleEnabled: j['autoRuleEnabled'] as bool? ?? false,
        autoRuleAmountUsdc:
            j['autoRuleAmountUsdc'] != null ? _num(j['autoRuleAmountUsdc']) : null,
        autoRuleFrequency: j['autoRuleFrequency'] as String?,
        autoRuleNextRun: j['autoRuleNextRun'] != null
            ? DateTime.tryParse(j['autoRuleNextRun'])
            : null,
        streakCount: (j['streakCount'] as num?)?.toInt() ?? 0,
        longestStreak: (j['longestStreak'] as num?)?.toInt() ?? 0,
        missedCount: (j['missedCount'] as num?)?.toInt() ?? 0,
        consistencyScore: _num(j['consistencyScore']),
        totalAzmEarned: _num(j['totalAzmEarned']),
        receiptSnapshot: j['receiptSnapshot'] as Map<String, dynamic>?,
        yieldEnabled: j['yieldEnabled'] as bool? ?? false,
        yieldStrategy: j['yieldStrategy'] as String?,
        yieldApr: _num(j['yieldApr']),
        yieldEarnedUsdc: _num(j['yieldEarnedUsdc']),
        yieldLastCompoundAt: j['yieldLastCompoundAt'] != null
            ? DateTime.tryParse(j['yieldLastCompoundAt'])
            : null,
        yieldAutoCompound: j['yieldAutoCompound'] as bool? ?? true,
      );

  double get progressFraction =>
      targetAmountUsdc <= 0 ? 0 : (currentAmountUsdc / targetAmountUsdc).clamp(0, 1);
}

class VaultDeposit {
  final String id;
  final double amountUsdc;
  final String type; // MANUAL | AUTO_RULE | BONUS
  final String status; // COMPLETED | FAILED_INSUFFICIENT | FAILED_OTHER | PENDING
  final double azmAwarded;
  final Map<String, dynamic>? azmBreakdown;
  final String? failureReason;
  final DateTime createdAt;

  VaultDeposit({
    required this.id,
    required this.amountUsdc,
    required this.type,
    required this.status,
    required this.azmAwarded,
    this.azmBreakdown,
    this.failureReason,
    required this.createdAt,
  });

  factory VaultDeposit.fromJson(Map<String, dynamic> j) => VaultDeposit(
        id: j['id'],
        amountUsdc: _num(j['amountUsdc']),
        type: j['type'],
        status: j['status'],
        azmAwarded: _num(j['azmAwarded']),
        azmBreakdown: j['azmBreakdown'] as Map<String, dynamic>?,
        failureReason: j['failureReason'],
        createdAt: DateTime.parse(j['createdAt']),
      );
}

double _num(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

// ── Providers ──────────────────────────────────────────────────────────────

class VaultsNotifier extends AsyncNotifier<List<Vault>> {
  @override
  Future<List<Vault>> build() => _fetch();

  Future<List<Vault>> _fetch() async {
    final res = await apiClient.get('/vaults');
    if (res.statusCode != 200) {
      throw Exception('Failed to load vaults (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['vaults'] as List<dynamic>? ?? const [];
    return list.map((e) => Vault.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<Vault> create({
    required String name,
    required double targetAmountUsdc,
    required DateTime maturityDate,
    Map<String, dynamic>? autoRule,
  }) async {
    final res = await apiClient.post('/vaults', {
      'name': name,
      'targetAmountUsdc': targetAmountUsdc,
      'maturityDate': maturityDate.toIso8601String(),
      'rulesAccepted': true,
      if (autoRule != null) 'autoRule': autoRule,
    });
    if (res.statusCode != 201) {
      final msg = _msg(res.body);
      throw Exception(msg);
    }
    await refresh();
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return Vault.fromJson(body['vault']);
  }

  Future<void> deposit(String vaultId, double amountUsdc) async {
    final res = await apiClient.post('/vaults/$vaultId/deposit', {
      'amountUsdc': amountUsdc,
    });
    if (res.statusCode != 200) throw Exception(_msg(res.body));
    await refresh();
  }

  Future<void> setAutoRule(
    String vaultId, {
    required bool enabled,
    double? amountUsdc,
    String? frequency,
  }) async {
    final res = await apiClient.post('/vaults/$vaultId/auto-rule', {
      'enabled': enabled,
      if (amountUsdc != null) 'amountUsdc': amountUsdc,
      if (frequency != null) 'frequency': frequency,
    });
    if (res.statusCode != 200) throw Exception(_msg(res.body));
    await refresh();
  }

  Future<void> breakEarly(String vaultId) async {
    final res = await apiClient.post('/vaults/$vaultId/break', {
      'confirmedBreak': true,
    });
    if (res.statusCode != 200) throw Exception(_msg(res.body));
    await refresh();
  }

  String _msg(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return m['message']?.toString() ?? 'Vault request failed';
    } catch (_) {
      return 'Vault request failed';
    }
  }
}

final vaultsProvider =
    AsyncNotifierProvider<VaultsNotifier, List<Vault>>(VaultsNotifier.new);

// Detail provider — keyed by vault id
final vaultDetailProvider =
    FutureProvider.family<Vault?, String>((ref, vaultId) async {
  final res = await apiClient.get('/vaults/$vaultId');
  if (res.statusCode != 200) return null;
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return Vault.fromJson(body['vault']);
});

final vaultDepositsProvider =
    FutureProvider.family<List<VaultDeposit>, String>((ref, vaultId) async {
  final res = await apiClient.get('/vaults/$vaultId/deposits?limit=50');
  if (res.statusCode != 200) return const [];
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final list = body['deposits'] as List<dynamic>? ?? const [];
  return list.map((e) => VaultDeposit.fromJson(e)).toList();
});
