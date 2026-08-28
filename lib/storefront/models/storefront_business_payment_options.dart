/// Customer-visible payment capabilities advertised by a storefront.
///
/// The backend remains authoritative; this model only describes what the
/// storefront is allowed to offer during checkout.
class StorefrontPaymentOptions {
  final bool escrowProtectionAvailable;

  const StorefrontPaymentOptions({
    this.escrowProtectionAvailable = false,
  });

  factory StorefrontPaymentOptions.fromBusinessJson(
    Map<String, dynamic> json,
  ) {
    return StorefrontPaymentOptions(
      escrowProtectionAvailable: json['escrowProtectionAvailable'] == true,
    );
  }
}
