// lib/models/ad.dart
// =============================================================================
// Phase F2: Updated to include adType, tradeAccountId, and USD-based pricing.
// =============================================================================

class Ad {
  final String id;
  final String adType;           // "SELL" | "BUY"
  final double pricePerUSD;      // informational display rate
  final double baseMargin;
  final double vendorMargin;
  final int maxConcurrentTrades;
  final String paymentMethod;
  final String? tradeAccountId;  // Phase F2: FK to TradeAccount
  final String? terms;

  Ad({
    required this.id,
    this.adType = 'SELL',
    required this.pricePerUSD,
    this.baseMargin = 0.0,
    this.vendorMargin = 0.0,
    this.maxConcurrentTrades = 1,
    this.paymentMethod = '',
    this.tradeAccountId,
    this.terms,
  });

  bool get isSellAd => adType.toUpperCase() == 'SELL';
  bool get isBuyAd => adType.toUpperCase() == 'BUY';

  factory Ad.fromJson(Map<String, dynamic> json) {
    return Ad(
      id: json['id']?.toString() ?? '',
      adType: json['type']?.toString() ?? 'SELL',
      pricePerUSD: (json['pricePerUSD'] ?? 0).toDouble(),
      baseMargin: (json['baseMargin'] ?? 0).toDouble(),
      vendorMargin: (json['vendorMargin'] ?? json['margin'] ?? 0).toDouble(),
      maxConcurrentTrades: json['maxConcurrentTrades'] ?? 1,
      paymentMethod: json['paymentMethod'] as String? ?? '',
      tradeAccountId: json['tradeAccountId']?.toString(),
      terms: json['terms'] as String?,
    );
  }
}
