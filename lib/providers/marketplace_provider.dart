// =============================================================================
// MARKETPLACE PROVIDER — Phase F2 | Azaman V2
//
// Phase F2 correction: P2P is a global fiat wallet liquidity bridge, NOT a
// GHS↔USDC exchange. All amounts are in USD (1:1 parity with USDC). The GHS
// oracle is ONLY for the internal MoMo deposit/withdrawal rail.
//
// Provider graph:
//
//   aiFilterProvider          StateProvider<bool>
//         │
//         ▼
//   adsProvider               AsyncNotifierProvider
//         │  watches aiFilterProvider, re-fetches when toggled
//         ▼
//   filteredAdsProvider       Provider<List<AdListing>>
//         │  client-side secondary sort (AI score desc when filter ON)
//
// AdListing is the canonical model for a single vendor ad card.
// =============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. AI Smart Filter toggle
// ─────────────────────────────────────────────────────────────────────────────
final aiFilterProvider = StateProvider<bool>((ref) => false);

// ─────────────────────────────────────────────────────────────────────────────
// User-side market view (FE-perspective, NOT vendor-perspective)
//
// The marketplace shows vendor ads. From the buying user's perspective:
//
//   • UserSide.buy  →  user wants to BUY USDC (with fiat) → match against
//                      vendor `type=SELL` ads (vendor sells USDC, vendor
//                      escrows). Default tab — most users come here.
//
//   • UserSide.sell →  user wants to SELL USDC (for fiat) → match against
//                      vendor `type=BUY` ads (vendor buys USDC, USER
//                      escrows their USDC upfront).
//
// The mapping is intentionally inverted because "Buy/Sell" on the FE is
// ALWAYS expressed from the user's POV; the backend `Ad.type` is the
// vendor's POV. See AZAMAN_MASTER_SOUL.md §4.1 (P2P architecture).
// ─────────────────────────────────────────────────────────────────────────────
enum UserSide { buy, sell }

final userSideProvider =
    StateProvider<UserSide>((ref) => UserSide.buy);

// ─────────────────────────────────────────────────────────────────────────────
// 2. Ad Listing model
// ─────────────────────────────────────────────────────────────────────────────
enum RiskLevel { low, medium, high }

class AdListing {
  final String id;
  final String vendorUsername;
  final String vendorId;
  final String adType;         // "SELL" | "BUY"
  final double pricePerUSD;    // informational display rate (Phase F2: static, no oracle)
  final double minLimit;       // minimum trade amount in USD
  final double maxLimit;       // maximum trade amount in USD
  final double availableUsdc;  // vendor's available USDC balance
  final String paymentMethod;  // "ZELLE" | "CASHAPP" | "VENMO" | etc.
  final String? tradeAccountId; // FK to TradeAccount (Phase F2)
  final bool queueFull;        // true → "Wait in Queue" CTA
  final int queueDepth;        // number of pending orders ahead
  final int completedTrades;
  final double completionRate; // 0.0 – 1.0
  final double aiScore;        // 0.0 – 1.0, higher = AI prefers this vendor
  final bool isOnline;
  final DateTime? lastSeen;
  final String? terms;         // vendor's trade terms

  const AdListing({
    required this.id,
    required this.vendorUsername,
    required this.vendorId,
    this.adType = 'SELL',
    required this.pricePerUSD,
    required this.minLimit,
    required this.maxLimit,
    required this.availableUsdc,
    required this.paymentMethod,
    this.tradeAccountId,
    required this.queueFull,
    required this.queueDepth,
    required this.completedTrades,
    required this.completionRate,
    required this.aiScore,
    required this.isOnline,
    this.lastSeen,
    this.terms,
  });

  /// Whether this is a SELL ad (vendor sells crypto, buyer sends fiat)
  bool get isSellAd => adType.toUpperCase() == 'SELL';

  /// Whether this is a BUY ad (vendor buys crypto, user sells their USDC)
  bool get isBuyAd => adType.toUpperCase() == 'BUY';

  // ── Risk classification ──────────────────────────────────────────────────
  // Phase F2: updated for global payment methods
  //   Zelle / Wire Transfer → Low (established, reversible with limits)
  //   CashApp / Venmo / Google Pay / Apple Pay → Medium
  //   PayPal / Gift Cards / Unknown / < 80% completion → High
  RiskLevel get riskLevel {
    if (completionRate < 0.80) return RiskLevel.high;
    final method = paymentMethod.toUpperCase();
    if (method.contains('ZELLE') || method.contains('WIRE') ||
        method.contains('WISE') || method.contains('REVOLUT')) {
      return RiskLevel.low;
    }
    if (method.contains('CASHAPP') || method.contains('VENMO') ||
        method.contains('GOOGLE') || method.contains('APPLE')) {
      return RiskLevel.medium;
    }
    return RiskLevel.high;
  }

  // ── JSON deserialiser ────────────────────────────────────────────────────
  factory AdListing.fromJson(Map<String, dynamic> j) {
    return AdListing(
      id: j['id']?.toString() ?? '',
      vendorUsername: j['vendorUsername']?.toString() ??
          j['vendor']?['username']?.toString() ?? 'Unknown',
      vendorId: j['vendorId']?.toString() ??
          j['vendor']?['id']?.toString() ?? '',
      adType: j['type']?.toString() ?? 'SELL',
      pricePerUSD: (j['pricePerUSD'] as num?)?.toDouble() ??
          (j['rate'] as num?)?.toDouble() ?? 1.0,
      minLimit: (j['minLimit'] as num?)?.toDouble() ?? 0.0,
      maxLimit: (j['maxLimit'] as num?)?.toDouble() ?? 0.0,
      availableUsdc: (j['availableUsdc'] as num?)?.toDouble() ??
          (j['totalAmount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: j['paymentMethod']?.toString() ?? 'ZELLE',
      tradeAccountId: j['tradeAccountId']?.toString(),
      queueFull: j['queueFull'] as bool? ?? false,
      queueDepth: (j['queueDepth'] as num?)?.toInt() ?? 0,
      completedTrades: (j['completedTrades'] as num?)?.toInt() ??
          (j['vendor']?['completedTrades'] as num?)?.toInt() ?? 0,
      completionRate: (j['completionRate'] as num?)?.toDouble() ??
          (j['vendor']?['completionRate'] as num?)?.toDouble() ?? 1.0,
      aiScore: (j['aiScore'] as num?)?.toDouble() ?? 0.5,
      isOnline: j['isOnline'] as bool? ?? false,
      lastSeen: j['lastSeen'] != null
          ? DateTime.tryParse(j['lastSeen'].toString())
          : null,
      terms: j['terms'] as String?,
    );
  }

  // ── Mock data factory (used when backend is unreachable in dev) ──────────
  static List<AdListing> mockList() => [
    AdListing(
      id: 'mock-1', vendorUsername: 'KwameGold', vendorId: 'v1',
      adType: 'SELL', pricePerUSD: 1.0, minLimit: 50, maxLimit: 5000,
      availableUsdc: 2340.00, paymentMethod: 'ZELLE',
      queueFull: false, queueDepth: 0,
      completedTrades: 312, completionRate: 0.98, aiScore: 0.94, isOnline: true,
    ),
    AdListing(
      id: 'mock-2', vendorUsername: 'AkosuaSwap', vendorId: 'v2',
      adType: 'SELL', pricePerUSD: 1.0, minLimit: 100, maxLimit: 10000,
      availableUsdc: 800.00, paymentMethod: 'CASHAPP',
      queueFull: false, queueDepth: 1,
      completedTrades: 88, completionRate: 0.91, aiScore: 0.78, isOnline: true,
    ),
    AdListing(
      id: 'mock-3', vendorUsername: 'KofiBarter', vendorId: 'v3',
      adType: 'BUY', pricePerUSD: 1.0, minLimit: 200, maxLimit: 20000,
      availableUsdc: 5500.00, paymentMethod: 'VENMO',
      queueFull: true, queueDepth: 3,
      completedTrades: 45, completionRate: 0.82, aiScore: 0.61, isOnline: false,
    ),
    AdListing(
      id: 'mock-4', vendorUsername: 'NanaDeFi', vendorId: 'v4',
      adType: 'SELL', pricePerUSD: 1.0, minLimit: 50, maxLimit: 3000,
      availableUsdc: 1200.00, paymentMethod: 'PAYPAL',
      queueFull: false, queueDepth: 0,
      completedTrades: 11, completionRate: 0.72, aiScore: 0.42, isOnline: true,
    ),
    AdListing(
      id: 'mock-5', vendorUsername: 'AbenaExchange', vendorId: 'v5',
      adType: 'BUY', pricePerUSD: 1.0, minLimit: 100, maxLimit: 8000,
      availableUsdc: 3100.00, paymentMethod: 'WIRE_TRANSFER',
      queueFull: false, queueDepth: 0,
      completedTrades: 210, completionRate: 0.97, aiScore: 0.88, isOnline: true,
    ),
    AdListing(
      id: 'mock-6', vendorUsername: 'YaaFastPay', vendorId: 'v6',
      adType: 'SELL', pricePerUSD: 1.0, minLimit: 50, maxLimit: 2000,
      availableUsdc: 620.00, paymentMethod: 'WISE',
      queueFull: false, queueDepth: 2,
      completedTrades: 67, completionRate: 0.85, aiScore: 0.65, isOnline: false,
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Ads AsyncNotifier — fetches from /api/p2p/ads
// ─────────────────────────────────────────────────────────────────────────────
class AdsNotifier extends AsyncNotifier<List<AdListing>> {
  @override
  Future<List<AdListing>> build() async {
    // Re-run whenever the AI filter toggle changes
    final aiFilter = ref.watch(aiFilterProvider);
    return _fetchAds(aiFilter: aiFilter);
  }

  Future<List<AdListing>> _fetchAds({required bool aiFilter}) async {
    final endpoint = aiFilter ? '/p2p/ads?aiFilter=true' : '/p2p/ads';

    try {
      final response = await apiClient.get(endpoint);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> raw =
            body is List ? body : (body['ads'] ?? body['data'] ?? []);
        final ads = raw
            .map((e) => AdListing.fromJson(e as Map<String, dynamic>))
            .toList();
        debugPrint(
            '✅ [MarketplaceProvider] Fetched ${ads.length} ads (aiFilter=$aiFilter)');
        return ads;
      }
      // Non-200 → return empty list, show premium empty state
      debugPrint(
          '⚠️  [MarketplaceProvider] HTTP ${response.statusCode} — returning empty list');
      return [];
    } catch (e) {
      debugPrint('⚠️  [MarketplaceProvider] Fetch error: $e — returning empty list');
      // Network error → throw to show error UI, not empty state
      rethrow;
    }
  }

  /// Hard refresh — call from pull-to-refresh or manual reload button.
  Future<void> refresh() async {
    state = const AsyncLoading();
    final aiFilter = ref.read(aiFilterProvider);
    state = await AsyncValue.guard(() => _fetchAds(aiFilter: aiFilter));
  }

  /// Initiate a new trade with backend.
  /// Phase N: returns TradeInitiationResult to distinguish queued vs immediate trade.
  /// Phase F2: accepts optional buyerPaymentDetails (required for SELL ads).
  Future<TradeInitiationResult> initiateTrade({
    required String adId,
    required double amountFiat,
    required double amountCrypto,
    required String paymentMethod,
    Map<String, dynamic>? buyerPaymentDetails,
  }) async {
    final body = <String, dynamic>{
      'adId': adId,
      'amountCrypto': amountCrypto,
      'amountFiat': amountFiat,
      'paymentMethod': paymentMethod,
      if (buyerPaymentDetails != null) 'buyerPaymentDetails': buyerPaymentDetails,
    };

    final response = await apiClient.post('/trades/initiate', body);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final respBody = jsonDecode(response.body);
      final tradeId = respBody['trade']?['id']?.toString() ?? '';
      debugPrint('✅ [MarketplaceProvider] Trade initiated: $tradeId');
      return TradeInitiationResult(queued: false, tradeId: tradeId);
    }

    // Phase N: HTTP 202 = queued (vendor at max concurrent trades)
    if (response.statusCode == 202) {
      final respBody = jsonDecode(response.body);
      final data = respBody['data'] as Map<String, dynamic>? ?? {};
      final queueId = data['queueId']?.toString() ?? '';
      final queuePosition = (data['queuePosition'] as num?)?.toInt() ?? 1;
      final adIdReturned = data['adId']?.toString() ?? adId;
      debugPrint('⏳ [MarketplaceProvider] Trade queued: position #$queuePosition, queueId=$queueId');
      return TradeInitiationResult(
        queued: true,
        queueId: queueId,
        queuePosition: queuePosition,
        adId: adIdReturned,
      );
    }

    // Error handling
    final respBody = jsonDecode(response.body);
    final errorMsg = respBody['message'] ?? 'Failed to initiate trade';
    final errorCode = respBody['code']?.toString();
    debugPrint('❌ [MarketplaceProvider] Trade initiation failed: $errorMsg (code: $errorCode)');
    throw TradeInitiationException(message: errorMsg, code: errorCode);
  }

  /// Leave a queue position. Phase N: calls PUT /api/queue/:queueId/leave.
  Future<void> leaveQueue(String queueId) async {
    final response = await apiClient.put('/ai/queue/$queueId/leave', {});

    if (response.statusCode == 200) {
      debugPrint('✅ [MarketplaceProvider] Left queue: $queueId');
      return;
    }

    final respBody = jsonDecode(response.body);
    final errorMsg = respBody['message'] ?? 'Failed to leave queue';
    debugPrint('❌ [MarketplaceProvider] Leave queue failed: $errorMsg');
    throw Exception(errorMsg);
  }
}

/// Typed exception for trade initiation failures so the UI can respond
/// to specific error codes (e.g., BUYER_DETAILS_REQUIRED).
class TradeInitiationException implements Exception {
  final String message;
  final String? code;
  TradeInitiationException({required this.message, this.code});
  @override
  String toString() => message;
}

/// Phase N: Result from initiateTrade — distinguishes immediate trade from queue.
class TradeInitiationResult {
  final bool queued;
  final String? tradeId;      // populated when queued == false
  final String? queueId;      // populated when queued == true
  final int? queuePosition;   // populated when queued == true
  final String? adId;         // populated when queued == true

  const TradeInitiationResult({
    required this.queued,
    this.tradeId,
    this.queueId,
    this.queuePosition,
    this.adId,
  });
}

final adsProvider =
    AsyncNotifierProvider<AdsNotifier, List<AdListing>>(AdsNotifier.new);

// ─────────────────────────────────────────────────────────────────────────────
// 4. Filtered / sorted view — derived, zero async cost
//
// Filter chain:
//   1. `userSideProvider` filters ads by the FE-perspective tab. Buy tab
//      keeps `ad.adType == SELL` (vendor sells USDC), Sell tab keeps
//      `ad.adType == BUY` (vendor buys USDC).
//   2. `aiFilterProvider` re-sorts by aiScore descending when on. When
//      off, backend ordering (pricePerUSD ascending) is preserved.
// ─────────────────────────────────────────────────────────────────────────────
final filteredAdsProvider = Provider<AsyncValue<List<AdListing>>>((ref) {
  final raw = ref.watch(adsProvider);
  final aiFilter = ref.watch(aiFilterProvider);
  final side = ref.watch(userSideProvider);
  final filters = ref.watch(p2pFiltersProvider);

  return raw.whenData((ads) {
    // Step 1: user-side tab filter (Buy tab → SELL ads, Sell tab → BUY ads)
    var result = ads
        .where((a) => side == UserSide.buy ? a.isSellAd : a.isBuyAd)
        .toList();

    // Step 2: payment method filter
    if (filters.paymentMethods.isNotEmpty) {
      result = result
          .where((a) =>
              filters.paymentMethods.contains(a.paymentMethod.toUpperCase()))
          .toList();
    }

    // Step 3: amount range filter — keep ads whose limit range overlaps
    if (filters.minAmount != null) {
      result = result.where((a) => a.maxLimit >= filters.minAmount!).toList();
    }
    if (filters.maxAmount != null) {
      result = result.where((a) => a.minLimit <= filters.maxAmount!).toList();
    }

    // Step 4: completion rate floor
    if (filters.minCompletionRate > 0) {
      result = result
          .where((a) => a.completionRate >= filters.minCompletionRate)
          .toList();
    }

    // Step 5: online-only
    if (filters.onlineOnly) {
      result = result.where((a) => a.isOnline).toList();
    }

    // Step 6: AI sort (when AI filter is on, sort by aiScore desc)
    if (aiFilter) {
      result.sort((a, b) => b.aiScore.compareTo(a.aiScore));
    }

    return result;
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// P2P Advanced Filters (P2P Premium Sprint, 2026-06-21)
// ─────────────────────────────────────────────────────────────────────────────

/// Immutable value object for the P2P filter sheet state.
class P2PFilters {
  /// Selected payment methods (empty = all).
  final Set<String> paymentMethods;

  /// Min trade amount in USD (null = no floor).
  final double? minAmount;

  /// Max trade amount in USD (null = no ceiling).
  final double? maxAmount;

  /// Minimum completion rate 0–1 (0 = no filter).
  final double minCompletionRate;

  /// Only show vendors currently online.
  final bool onlineOnly;

  const P2PFilters({
    this.paymentMethods = const {},
    this.minAmount,
    this.maxAmount,
    this.minCompletionRate = 0,
    this.onlineOnly = false,
  });

  bool get isEmpty =>
      paymentMethods.isEmpty &&
      minAmount == null &&
      maxAmount == null &&
      minCompletionRate == 0 &&
      !onlineOnly;

  int get activeCount {
    int n = 0;
    if (paymentMethods.isNotEmpty) n++;
    if (minAmount != null) n++;
    if (maxAmount != null) n++;
    if (minCompletionRate > 0) n++;
    if (onlineOnly) n++;
    return n;
  }

  P2PFilters copyWith({
    Set<String>? paymentMethods,
    Object? minAmount = _sentinel,
    Object? maxAmount = _sentinel,
    double? minCompletionRate,
    bool? onlineOnly,
  }) {
    return P2PFilters(
      paymentMethods: paymentMethods ?? this.paymentMethods,
      minAmount: minAmount == _sentinel ? this.minAmount : minAmount as double?,
      maxAmount: maxAmount == _sentinel ? this.maxAmount : maxAmount as double?,
      minCompletionRate: minCompletionRate ?? this.minCompletionRate,
      onlineOnly: onlineOnly ?? this.onlineOnly,
    );
  }
}

const _sentinel = Object();

final p2pFiltersProvider = StateProvider<P2PFilters>((ref) => const P2PFilters());
