import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression suite for the STRICT businessLogoUrl parse on the Mix
/// discovery DTO (backend PR #354 exposes the real BusinessProfile
/// .logoUrl). Wrong types, blank strings, malformed URLs and unsupported
/// schemes must all be treated as absent — never stringified, never
/// substituted with an item image.
void main() {
  // Minimal valid discovery row builder — only the fields under test vary.
  Map<String, dynamic> row({dynamic businessLogoUrl}) => <String, dynamic>{
    'id': 'item-1',
    'businessId': 'biz-1',
    'bizId': 'BIZ-1',
    'businessName': 'Accra Home Goods',
    'businessCategory': 'RETAIL',
    'businessLogoUrl': businessLogoUrl,
    'item': {
      'name': 'Ceramic bowl',
      'images': <String>['https://cdn.example.com/bowl.jpg'],
    },
    'pricing': {'currency': 'GHS', 'amount': '45.00'},
  };

  group('MixOffer.fromDiscoveryDto businessLogoUrl strict parse', () {
    test('accepts a valid https URL', () {
      final offer = MixOffer.fromDiscoveryDto(
        row(businessLogoUrl: 'https://cdn.example.com/logo.png'),
      );
      expect(offer.businessLogoUrl, 'https://cdn.example.com/logo.png');
    });

    test('accepts a valid http URL', () {
      final offer = MixOffer.fromDiscoveryDto(
        row(businessLogoUrl: 'http://cdn.example.com/logo.png'),
      );
      expect(offer.businessLogoUrl, 'http://cdn.example.com/logo.png');
    });

    test('rejects non-string types instead of stringifying them', () {
      expect(
        MixOffer.fromDiscoveryDto(row(businessLogoUrl: 123)).businessLogoUrl,
        isNull,
      );
      expect(
        MixOffer.fromDiscoveryDto(row(businessLogoUrl: true)).businessLogoUrl,
        isNull,
      );
      expect(
        MixOffer.fromDiscoveryDto(
          row(businessLogoUrl: <String, dynamic>{'url': 'x'}),
        ).businessLogoUrl,
        isNull,
      );
      expect(
        MixOffer.fromDiscoveryDto(
          row(businessLogoUrl: <dynamic>[1]),
        ).businessLogoUrl,
        isNull,
      );
    });

    test('rejects blank and whitespace-only strings', () {
      expect(
        MixOffer.fromDiscoveryDto(row(businessLogoUrl: '')).businessLogoUrl,
        isNull,
      );
      expect(
        MixOffer.fromDiscoveryDto(row(businessLogoUrl: '   ')).businessLogoUrl,
        isNull,
      );
    });

    test('rejects malformed URLs and scheme-less values', () {
      expect(
        MixOffer.fromDiscoveryDto(
          row(businessLogoUrl: 'not a url at all'),
        ).businessLogoUrl,
        isNull,
      );
      expect(
        MixOffer.fromDiscoveryDto(
          row(businessLogoUrl: 'www.example.com/logo.png'),
        ).businessLogoUrl,
        isNull,
      );
    });

    test('rejects unsupported schemes', () {
      for (final bad in [
        'ftp://example.com/logo.png',
        'file:///etc/passwd',
        'data:image/png;base64,AAAA',
        'javascript:alert(1)',
      ]) {
        expect(
          MixOffer.fromDiscoveryDto(row(businessLogoUrl: bad)).businessLogoUrl,
          isNull,
          reason: '$bad must be treated as absent',
        );
      }
    });

    test('absent/null key stays an honest null', () {
      expect(
        MixOffer.fromDiscoveryDto(row(businessLogoUrl: null)).businessLogoUrl,
        isNull,
      );
      final noKey = row();
      noKey.remove('businessLogoUrl');
      expect(MixOffer.fromDiscoveryDto(noKey).businessLogoUrl, isNull);
    });

    test('logo never leaks into the item image slot', () {
      final offer = MixOffer.fromDiscoveryDto(
        row(
          businessLogoUrl: 42, // rejected type
        ),
      );
      expect(offer.businessLogoUrl, isNull);
      expect(offer.imageUrls.single, 'https://cdn.example.com/bowl.jpg');
      expect(offer.primaryImage, 'https://cdn.example.com/bowl.jpg');
    });
  });
}
