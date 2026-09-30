import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/data/demo_seed_marketplace.dart';
import 'package:azaman/data/demo_interceptor.dart';

/// Marketplace demo-seed permanent guards (milestone 2026-09-30):
///   1. The seed carries EIGHT businesses (two per primary category) so the
///      marketplace portal feels populated.
///   2. Search is deterministic and filter-aware: category / verified / q /
///      cursor selections genuinely change the result set.
///   3. Media is drawn from verified, checked-in assets — no random
///      picsum generators anywhere.
///   4. Every endpoint in [DemoMarketplaceSeed.requiredGetEndpoints] is
///      explicitly covered by the demo interceptor — a Marketplace GET the
///      app's journey expects can never masquerade as a successful empty
///      dataset (the family guard throws DemoEndpointNotSeededException).
void main() {
  group('DemoMarketplaceSeed — catalog', () {
    test('carries 8 businesses, 2 per primary category', () {
      final all = DemoMarketplaceSeed.allBusinesses();
      expect(all.length, 8);
      for (final wire in [
        'FOOD_BEVERAGE',
        'HOSPITALITY',
        'LOGISTICS',
        'RETAIL',
      ]) {
        final inCat = all.where((b) => b['category'] == wire).length;
        expect(inCat, 2, reason: 'category $wire should have 2 businesses');
      }
    });

    test('each category has at least one verified and one unverified entry', () {
      for (final wire in [
        'FOOD_BEVERAGE',
        'HOSPITALITY',
        'LOGISTICS',
        'RETAIL',
      ]) {
        final inCat =
            DemoMarketplaceSeed.allBusinesses().where((b) => b['category'] == wire);
        final verified = inCat.where((b) => b['isVerified'] == true).length;
        final unverified = inCat.where((b) => b['isVerified'] != true).length;
        expect(verified, greaterThanOrEqualTo(1),
            reason: '$wire needs a verified business');
        expect(unverified, greaterThanOrEqualTo(1),
            reason: '$wire needs an unverified business so the verified filter is testable');
      }
    });

    test('all business media is a verified Base44 asset (no picsum)', () {
      void walk(Map<String, dynamic> m) {
        for (final e in m.entries) {
          final v = e.value;
          // `website` fields are business URLs, not media assets.
          if (e.key == 'website') continue;
          if (v is String) {
            if (v.startsWith('http')) {
              expect(v, startsWith('https://media.base44.com/'),
                  reason: 'media must be a checked-in asset: $v');
              expect(v.contains('picsum'), isFalse);
            }
          } else if (v is Map) {
            walk(Map<String, dynamic>.from(v));
          } else if (v is List) {
            for (final e in v) {
              if (e is Map) walk(Map<String, dynamic>.from(e));
              if (e is String && e.startsWith('http')) {
                expect(e, startsWith('https://media.base44.com/'),
                    reason: 'media must be a checked-in asset: $e');
              }
            }
          }
        }
      }

      for (final b in DemoMarketplaceSeed.allBusinesses()) {
        walk(b);
      }
    });
  });

  group('DemoMarketplaceSeed — deterministic search', () {
    test('unfiltered search returns all 8, hasMore=false', () {
      final r = DemoMarketplaceSeed.searchBusinesses();
      expect((r['businesses'] as List).length, 8);
      expect(r['hasMore'], isFalse);
      expect(r['nextCursor'], isNull);
    });

    test('category filter changes the result set', () {
      for (final wire in [
        'FOOD_BEVERAGE',
        'HOSPITALITY',
        'LOGISTICS',
        'RETAIL',
      ]) {
        final r = DemoMarketplaceSeed.searchBusinesses(category: wire);
        final rows = (r['businesses'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        expect(rows.length, 2);
        expect(rows.every((b) => b['category'] == wire), isTrue);
      }
    });

    test('REAL_ESTATE dial wire maps to HOSPITALITY businesses', () {
      final r = DemoMarketplaceSeed.searchBusinesses(category: 'REAL_ESTATE');
      final rows = (r['businesses'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      expect(rows.length, 2);
      expect(rows.every((b) => b['category'] == 'HOSPITALITY'), isTrue);
    });

    test('verified=true keeps only verified businesses', () {
      final r = DemoMarketplaceSeed.searchBusinesses(verified: true);
      final rows = (r['businesses'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      expect(rows, isNotEmpty);
      expect(rows.every((b) => b['isVerified'] == true), isTrue);
      expect(rows.length, lessThan(8));
    });

    test('query text matches name/description terms (AND semantics)', () {
      final jollof = DemoMarketplaceSeed.searchBusinesses(q: 'jollof');
      expect((jollof['businesses'] as List).length, 1);

      // AND semantics: both terms must appear ("jollof" and "accra" both
      // live in Chef Abby's copy, so this matches; a pair that no single
      // business satisfies matches nothing).
      final both = DemoMarketplaceSeed.searchBusinesses(q: 'jollof accra');
      expect((both['businesses'] as List).length, 1);

      final noSingleBusiness = DemoMarketplaceSeed.searchBusinesses(q: 'jollof kumasi');
      expect((noSingleBusiness['businesses'] as List).length, 0);

      final none = DemoMarketplaceSeed.searchBusinesses(q: 'zzzz-not-a-word');
      expect((none['businesses'] as List).length, 0);
    });

    test('cursor pagination slices deterministically', () {
      final page1 = DemoMarketplaceSeed.searchBusinesses(limit: 3);
      expect((page1['businesses'] as List).length, 3);
      expect(page1['hasMore'], isTrue);
      expect(page1['nextCursor'], '3');

      final page2 = DemoMarketplaceSeed.searchBusinesses(
          limit: 3, cursor: page1['nextCursor'] as String);
      expect((page2['businesses'] as List).length, 3);
      expect(page2['hasMore'], isTrue);

      final page3 = DemoMarketplaceSeed.searchBusinesses(
          limit: 3, cursor: page2['nextCursor'] as String);
      expect((page3['businesses'] as List).length, 2);
      expect(page3['hasMore'], isFalse);
      expect(page3['nextCursor'], isNull);
    });

    test('nearby search returns one location per business and honours filters',
        () {
      final all = DemoMarketplaceSeed.searchNearby();
      expect((all['locations'] as List).length, 8);

      final retail =
          DemoMarketplaceSeed.searchNearby(category: 'RETAIL');
      expect((retail['locations'] as List).length, 2);
    });
  });

  group('DemoMarketplaceSeed — truthful coverage', () {
    test('unknown bizId throws the typed not-seeded signal', () {
      expect(
        () => DemoMarketplaceSeed.getBusinessByBizId('BIZ-NOPE-999'),
        throwsA(isA<DemoEndpointNotSeededException>()),
      );
    });

    test('each seeded business has two coherent reviews (not fake-empty)', () {
      for (final b in DemoMarketplaceSeed.allBusinesses()) {
        final reviews = DemoMarketplaceSeed.getReviews(b['bizId'] as String);
        expect((reviews['reviews'] as List).length, 2,
            reason: 'reviews must exist for ${b['bizId']}');
      }
    });

    test('owner-surface seeds are the deliberate truthful values', () {
      final stats = DemoMarketplaceSeed.getOwnerStats();
      expect(stats['stats']['totalOrders'], 0);

      final kyb = DemoMarketplaceSeed.getKybStatus();
      expect(kyb['kybStatus'], 'UNVERIFIED');

      final notifications = DemoMarketplaceSeed.getOwnerNotifications();
      expect((notifications['notifications'] as List), isEmpty);
    });
  });

  group('DemoInterceptor — required GET coverage', () {
    test(
        'every requiredGetEndpoint is explicitly seeded (non-null, 200, JSON)',
        () {
      for (final endpoint in DemoMarketplaceSeed.requiredGetEndpoints) {
        final res = DemoInterceptor.tryGet(endpoint);
        expect(res, isNotNull,
            reason: 'required demo GET $endpoint must be covered');
        expect(res!.statusCode, 200);
        expect(
          () => jsonDecode(res.body),
          returnsNormally,
          reason: 'body of $endpoint must be valid JSON',
        );
      }
    });

    test(
        'query params genuinely flow through the interceptor search cases',
        () {
      final res = DemoInterceptor.tryGet(
          '/business/search?category=RETAIL&verified=true&limit=20');
      expect(res, isNotNull);
      final body = jsonDecode(res!.body) as Map<String, dynamic>;
      final rows = (body['businesses'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      expect(rows.length, 1, reason: 'RETAIL + verified=true = Mr. Price only');
      expect(rows.first['businessName'], 'Mr. Price');
      expect(rows.first['isVerified'], true);
    });

    test('unseeded marketplace-family GET throws the typed signal', () {
      expect(
        () => DemoInterceptor.tryGet('/business/totally-unseeded/xyz'),
        throwsA(isA<DemoEndpointNotSeededException>()),
      );
      expect(
        () => DemoInterceptor.tryGet('/marketplace/unheard/of'),
        throwsA(isA<DemoEndpointNotSeededException>()),
      );
      expect(
        () => DemoInterceptor.tryGet('/follows/unseeded'),
        throwsA(isA<DemoEndpointNotSeededException>()),
      );
    });
  });
}
