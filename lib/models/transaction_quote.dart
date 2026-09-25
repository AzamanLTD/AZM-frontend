class TransactionQuote {
  final String id;
  final double amountGhs;
  final double feeGhs;
  final double netGhs;
  final double rateGhsPerUsdc;
  final double usdcAmount;
  final String? rateSource;
  final DateTime? rateAsOf;
  final DateTime expiresAt;
  final DateTime createdAt;

  const TransactionQuote({
    required this.id,
    required this.amountGhs,
    required this.feeGhs,
    required this.netGhs,
    required this.rateGhsPerUsdc,
    required this.usdcAmount,
    required this.expiresAt,
    required this.createdAt,
    this.rateSource,
    this.rateAsOf,
  });

  bool get isExpired => !expiresAt.isAfter(DateTime.now());

  Duration get timeRemaining {
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  double get progress {
    final total = expiresAt.difference(createdAt).inMilliseconds;
    if (total <= 0) return 0;
    return (timeRemaining.inMilliseconds / total).clamp(0.0, 1.0);
  }

  factory TransactionQuote.fromJson(Map<String, dynamic> json) {
    return TransactionQuote(
      id: json['id'] as String,
      amountGhs: (json['amountGhs'] as num?)?.toDouble() ?? 0,
      feeGhs: (json['feeGhs'] as num?)?.toDouble() ?? 0,
      netGhs: (json['netGhs'] as num?)?.toDouble() ?? 0,
      rateGhsPerUsdc: (json['rateGhsPerUsdc'] as num).toDouble(),
      usdcAmount: (json['usdcAmount'] as num).toDouble(),
      rateSource: json['rateSource'] as String?,
      rateAsOf: json['rateAsOf'] == null
          ? null
          : DateTime.parse(json['rateAsOf'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
