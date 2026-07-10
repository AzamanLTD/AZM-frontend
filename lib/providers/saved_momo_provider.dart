// =============================================================================
// SAVED MOMO ACCOUNTS PROVIDER  (Master Sprint v2, 2026-05-27)
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';

class SavedMomoAccount {
  final String id;
  final String nickname;
  final String provider;       // MTN | TELECEL | AIRTELTIGO (VODAFONE legacy still accepted)
  final String phoneNumber;    // E.164
  final String? accountName;   // resolved registered name
  final bool isVerified;
  final bool isPrimary;
  final DateTime? lastUsedAt;
  final DateTime createdAt;

  SavedMomoAccount({
    required this.id,
    required this.nickname,
    required this.provider,
    required this.phoneNumber,
    this.accountName,
    required this.isVerified,
    required this.isPrimary,
    this.lastUsedAt,
    required this.createdAt,
  });

  factory SavedMomoAccount.fromJson(Map<String, dynamic> j) => SavedMomoAccount(
        id: j['id'],
        nickname: j['nickname'],
        provider: j['provider'],
        phoneNumber: j['phoneNumber'],
        accountName: j['accountName'],
        isVerified: j['isVerified'] as bool? ?? false,
        isPrimary: j['isPrimary'] as bool? ?? false,
        lastUsedAt:
            j['lastUsedAt'] != null ? DateTime.tryParse(j['lastUsedAt']) : null,
        createdAt: DateTime.parse(j['createdAt']),
      );
}

class SavedMomoNotifier extends AsyncNotifier<List<SavedMomoAccount>> {
  @override
  Future<List<SavedMomoAccount>> build() => _fetch();

  Future<List<SavedMomoAccount>> _fetch() async {
    // Master Sprint v2 (2026-05-27): merge two backing tables so the
    // deposit-side picker sees BOTH new SavedMomoAccount rows AND legacy
    // SavedWallet rows of MoMo type. Saving via either route lands a row
    // in one of these tables — we display the union so users see every
    // saved MoMo number regardless of which entry point they used.
    final results = await Future.wait([
      _fetchSavedMomo(),
      _fetchLegacyWallets(),
    ]);
    final merged = <String, SavedMomoAccount>{};
    for (final list in results) {
      for (final acc in list) {
        // De-dup by normalised phone number — same number stored in both
        // tables only shows once. SavedMomoAccount entries (preferred,
        // since they have verified names) win over legacy.
        merged.putIfAbsent(acc.phoneNumber, () => acc);
      }
    }
    final sorted = merged.values.toList()
      ..sort((a, b) {
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    return sorted;
  }

  Future<List<SavedMomoAccount>> _fetchSavedMomo() async {
    final res = await apiClient.get('/saved-momo');
    if (res.statusCode != 200) {
      throw Exception('Failed to load accounts (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['accounts'] as List<dynamic>? ?? const [];
    return list.map((e) => SavedMomoAccount.fromJson(e)).toList();
  }

  /// Fetch the legacy `/wallet/saved` table and project any MoMo rows into
  /// the SavedMomoAccount shape. Crypto wallets are filtered out — they
  /// belong to the `SavedWalletsScreen`.
  Future<List<SavedMomoAccount>> _fetchLegacyWallets() async {
    try {
      final res = await apiClient.get('/wallet/saved');
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = body['wallets'] as List<dynamic>? ?? const [];
      const momoNetworks = {
        'MTN_MOMO',
        'TELECEL_CASH', 'VODAFONE_CASH', // legacy
        'AIRTELTIGO',
        'TELECEL_CASH',
      };
      return list
          .map((raw) => raw as Map<String, dynamic>)
          .where((w) => momoNetworks.contains((w['network'] ?? '').toString()))
          .map((w) {
        // Legacy schema → SavedMomoAccount projection
        final network = (w['network'] ?? '').toString();
        final providerCanon = switch (network) {
          'MTN_MOMO' => 'MTN',
          'VODAFONE_CASH' => 'TELECEL', // legacy
          'TELECEL_CASH' => 'TELECEL',
          'AIRTELTIGO' || 'TELECEL_CASH' => 'TELECEL',
          _ => network,
        };
        return SavedMomoAccount(
          id: 'legacy:${w['id']}',
          nickname: (w['label'] ?? '').toString(),
          provider: providerCanon,
          phoneNumber: (w['address'] ?? '').toString(),
          accountName: (w['accountName'] ?? '').toString().isEmpty
              ? null
              : w['accountName'].toString(),
          isVerified: (w['accountName'] ?? '').toString().isNotEmpty,
          isPrimary: false,
          createdAt: DateTime.tryParse(w['createdAt']?.toString() ?? '') ??
              DateTime.now(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Resolve a registered name without saving. Used by the "Add Account"
  /// flow to show the user the name on the number BEFORE they commit.
  Future<({String name, String msisdn})> lookupName({
    required String provider,
    required String phoneNumber,
  }) async {
    final res = await apiClient.post('/saved-momo/lookup', {
      'provider': provider,
      'phoneNumber': phoneNumber,
    });
    if (res.statusCode != 200) throw Exception(_msg(res.body));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (name: body['name'] as String, msisdn: body['msisdn'] as String);
  }

  Future<SavedMomoAccount> create({
    required String nickname,
    required String provider,
    required String phoneNumber,
    String? password,
    String? totpToken,
    bool isPrimary = false,
  }) async {
    final res = await apiClient.post('/saved-momo', {
      'nickname': nickname,
      'provider': provider,
      'phoneNumber': phoneNumber,
      if (password != null) 'password': password,
      if (totpToken != null) 'totpToken': totpToken,
      'isPrimary': isPrimary,
    });
    if (res.statusCode != 201) throw Exception(_msg(res.body));
    await refresh();
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return SavedMomoAccount.fromJson(body['account']);
  }

  Future<void> delete(String id) async {
    final res = await apiClient.delete('/saved-momo/$id');
    if (res.statusCode != 200) throw Exception(_msg(res.body));
    await refresh();
  }

  Future<void> setPrimary(String id) async {
    final res = await apiClient.patch('/saved-momo/$id', body: {'isPrimary': true});
    if (res.statusCode != 200) throw Exception(_msg(res.body));
    await refresh();
  }

  String _msg(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return m['message']?.toString() ?? 'MoMo account request failed';
    } catch (_) {
      return 'MoMo account request failed';
    }
  }
}

final savedMomoProvider =
    AsyncNotifierProvider<SavedMomoNotifier, List<SavedMomoAccount>>(SavedMomoNotifier.new);
