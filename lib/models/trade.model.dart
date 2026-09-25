class Trade {
  final String id;
  final String status;
  final double amountFiat;
  final double amountCrypto;
  final bool isDisputed;
  final String? vendorUsername;

  Trade({
    required this.id,
    required this.status,
    required this.amountFiat,
    required this.amountCrypto,
    this.isDisputed = false,
    this.vendorUsername,
  });

  factory Trade.fromJson(Map<String, dynamic> json) {
    return Trade(
      id: json['id']?.toString() ?? '',
      status: json['status'],
      amountFiat: (json['amountFiat'] ?? 0).toDouble(),
      amountCrypto: (json['amountCrypto'] ?? 0).toDouble(),
      isDisputed: json['status'] == 'DISPUTED',
      vendorUsername: json['vendorName'] as String?,
    );
  }
}
