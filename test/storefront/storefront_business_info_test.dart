import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/storefront/models/storefront_models.dart';

void main() {
  group('StorefrontBusinessInfo.escrowProtectionAvailable', () {
    test('parses true when backend reports escrow protection enabled', () {
      final info = StorefrontBusinessInfo.fromJson({
        'name': 'Example Store',
        'escrowProtectionAvailable': true,
      });

      expect(info.escrowProtectionAvailable, isTrue);
    });

    test('parses false when backend reports escrow protection disabled', () {
      final info = StorefrontBusinessInfo.fromJson({
        'name': 'Example Store',
        'escrowProtectionAvailable': false,
      });

      expect(info.escrowProtectionAvailable, isFalse);
    });

    test('defaults to false when field is missing', () {
      final info = StorefrontBusinessInfo.fromJson({
        'name': 'Example Store',
      });

      expect(info.escrowProtectionAvailable, isFalse);
    });

    test('defaults to false when field is null', () {
      final info = StorefrontBusinessInfo.fromJson({
        'name': 'Example Store',
        'escrowProtectionAvailable': null,
      });

      expect(info.escrowProtectionAvailable, isFalse);
    });

    test('preserves other fields when escrow is parsed', () {
      final info = StorefrontBusinessInfo.fromJson({
        'name': 'Shop',
        'category': 'RETAIL',
        'logoUrl': 'https://example.com/logo.png',
        'escrowProtectionAvailable': true,
      });

      expect(info.name, 'Shop');
      expect(info.category, 'RETAIL');
      expect(info.logoUrl, 'https://example.com/logo.png');
      expect(info.escrowProtectionAvailable, isTrue);
    });

    test('constructor defaults escrowProtectionAvailable to false', () {
      final info = StorefrontBusinessInfo(name: 'Test');

      expect(info.escrowProtectionAvailable, isFalse);
    });

    test('constructor accepts explicit true', () {
      final info = StorefrontBusinessInfo(
        name: 'Test',
        escrowProtectionAvailable: true,
      );

      expect(info.escrowProtectionAvailable, isTrue);
    });
  });
}