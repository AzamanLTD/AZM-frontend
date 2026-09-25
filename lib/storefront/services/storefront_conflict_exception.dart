class StorefrontConflictException implements Exception {
  final String message;
  final String code;

  const StorefrontConflictException({
    required this.message,
    this.code = 'STOREFRONT_DRAFT_CONFLICT',
  });

  @override
  String toString() => message;
}
