import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/storefront/services/storefront_conflict_exception.dart';

describe('StorefrontConflictException', () {
  test('preserves the backend conflict code and message', () {
    const error = StorefrontConflictException(
      message: 'This storefront draft changed elsewhere.',
      code: 'STOREFRONT_DRAFT_CONFLICT',
    );

    expect(error.code, 'STOREFRONT_DRAFT_CONFLICT');
    expect(error.message, 'This storefront draft changed elsewhere.');
    expect(error.toString(), error.message);
  });

  test('uses the stable default domain code', () {
    const error = StorefrontConflictException(
      message: 'Refresh required.',
    );

    expect(error.code, 'STOREFRONT_DRAFT_CONFLICT');
  });
});
