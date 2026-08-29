class TransactionQuote {
  final String id;
  final double rateGhsPerUsdc;
  final double? feeGhs;
  final DateTime expiresAt;
  final DateTime createdAt;

  const TransactionQuote({
    required this.id,
    required this.rateGhsPerUsdc,
    required this.expiresAt,
    required this.createdAt,
    this.feeGhs,
  });

  bool get isExpired => !expiresAt.isAfter(DateTime.now());

  double usdcForGhs(double amountGhs) {
    if (rateGhsPerUsdc <= 0) return 0;
    return amountGhs / rateGhsPerUsdc;
  }

  factory TransactionQuote.fromJson(Map<String, dynamic> json) {
    return TransactionQuote(
      id: json['id'] as String,
      rateGhsPerUsdc: (json['rateGhsPerUsdc'] as num).toDouble(),
      feeGhs: (json['feeGhs'] as num?)?.toDouble(),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
