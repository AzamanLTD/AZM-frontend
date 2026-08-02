// test/services/business_service_test.dart
//
// Unit tests for the business model JSON parsing. Written against the ACTUAL
// lib/models/business_models.dart shapes:
//   • BusinessProduct exposes imageUrls (List<String>) + a primaryImage getter
//     — there is no scalar `imageUrl` field.
//   • BusinessProfile derives userId/username from a nested `user` object.
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/models/business_models.dart';

void main() {
  group('BusinessProduct.fromJson', () {
    test('parses a complete product record', () {
      final json = {
        'id': 'prod-123',
        'businessProfileId': 'biz-1',
        'name': 'Test Product',
        'priceUsdc': 49.99,
        'imageUrls': ['https://res.cloudinary.com/azaman/image/upload/v1/img.jpg'],
        'isActive': true,
        'slug': 'test-product',
        'description': 'A test product',
      };
      final product = BusinessProduct.fromJson(json);
      expect(product.id, 'prod-123');
      expect(product.priceUsdc, 49.99);
      expect(product.isActive, true);
      expect(
        product.primaryImage,
        'https://res.cloudinary.com/azaman/image/upload/v1/img.jpg',
      );
    });

    test('handles missing images gracefully (primaryImage is null)', () {
      final json = {
        'id': 'prod-456',
        'name': 'No Image',
        'priceUsdc': 10.0,
        'isActive': true,
        'slug': 'no-image',
      };
      final product = BusinessProduct.fromJson(json);
      expect(product.imageUrls, isEmpty);
      expect(product.primaryImage, isNull);
    });
  });

  group('BusinessProfile.fromJson', () {
    test('parses a complete profile', () {
      final json = {
        'id': 1,
        'bizId': 'BIZ-TEST-001',
        'businessName': 'Test Biz',
        'category': 'TECH_SERVICES',
        'kybStatus': 'VERIFIED',
        'isVerified': true,
        'logoUrl': null,
        'user': {'id': 1, 'username': 'testbiz'},
      };
      final profile = BusinessProfile.fromJson(json);
      expect(profile.bizId, 'BIZ-TEST-001');
      expect(profile.isVerified, true);
      expect(profile.isKybVerified, true);
      expect(profile.username, 'testbiz');
    });
  });
}
