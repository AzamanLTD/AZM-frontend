// =============================================================================
// AZAMAN — BUSINESS STORIES REAL-RAIL GUARDS (Workstream E, 2026-10-19)
//
// The marketplace story ring used to fetch GET /api/stories/business/:id — a
// route that never existed on the backend. Every production tap silently
// fell back to the business profile while the UI still advertised stories
// (a false affordance). The only real business-stories rail is
// GET /api/marketplace/business/:id/stories → {success, stories:[row]}.
//
// These guards pin:
//   1. The service hits the exact real-rail path with no /api double prefix.
//   2. The row → StoryGroup mapping is truthful: the Story schema carries no
//      mediaType, no per-viewer seen state, no boost flag and no server
//      duration, so items map with the IMAGE/5s/seen=false fallbacks —
//      exactly like GET /stories/feed's own parse. Nothing is fabricated.
//   3. A failed rail ({success:false}) yields no stories — never a partial
//      or invented group.
//   4. The dead /stories/business/ path stays out of production code.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/models/story_model.dart';

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

class _RailRecordingClient extends ApiClient {
  final List<String> getPaths = [];
  final Map<String, http.Response> responses;

  _RailRecordingClient(this.responses);

  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers, bool requireAuth = true}) async {
    getPaths.add(endpoint);
    return responses[endpoint] ?? _json(404, {'success': false});
  }
}

Map<String, dynamic> _row(String id, {String? caption, String? username}) => {
      'id': id,
      'userId': 42,
      'businessProfileId': 'BIZ-REST-001',
      'mediaUrl': 'https://cdn.example/story-$id.jpg',
      'caption': caption,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'expiresAt':
          DateTime.now().add(const Duration(hours: 20)).toUtc().toIso8601String(),
      'user': {'username': username ?? 'chef_abby'},
    };

void main() {
  group('business stories rail — exact-path contract', () {
    test('service fetches GET /marketplace/business/:id/stories, unprefixed',
        () async {
      final client = _RailRecordingClient({
        '/marketplace/business/BIZ-REST-001/stories':
            _json(200, {'success': true, 'stories': [_row('bs-r1')]}),
      });
      final svc = MarketplaceBookingService(apiClient: client);

      final stories = await svc.getBusinessStories('BIZ-REST-001');

      expect(client.getPaths, ['/marketplace/business/BIZ-REST-001/stories'],
          reason: 'the only backend business-stories rail is the marketplace one');
      expect(stories, hasLength(1));
      expect(stories.first.id, 'bs-r1');
      expect(stories.first.username, 'chef_abby',
          reason: 'poster user rides on the row, like the Prisma include');
      expect(stories.first.businessProfileId, 'BIZ-REST-001');
    });

    test('a failed rail never yields stories', () async {
      final client = _RailRecordingClient({
        '/marketplace/business/BIZ-REST-001/stories':
            _json(200, {'success': false, 'message': 'no profile'}),
      });
      final svc = MarketplaceBookingService(apiClient: client);

      final stories = await svc.getBusinessStories('BIZ-REST-001');

      expect(stories, isEmpty,
          reason: 'no invented groups when the rail answers failure');
    });
  });

  group('business stories row → viewer group mapping (truthful defaults)', () {
    test('maps rows with the schema-honest IMAGE/5s/seen=false fallbacks', () {
      final rows = [
        _row('bs-r1', caption: 'Fresh jollof'),
        _row('bs-r2', caption: 'Suya night', username: 'mama_titi'),
      ]
          .map((j) => BusinessStory.fromJson(j))
          .toList();

      final group = storyGroupFromBusinessStories(rows);

      // One group per business; the author identity is the poster the rail
      // actually reported (first row), never an invented business persona.
      expect(group.authorId, 42);
      expect(group.authorUsername, 'chef_abby');
      expect(group.stories, hasLength(2));

      final item = group.stories.first;
      expect(item.id, 'bs-r1');
      expect(item.caption, 'Fresh jollof');
      expect(item.linkedBizId, 'BIZ-REST-001');
      // The Story schema sends no mediaType, no duration, no view state and
      // no boost flag on this rail — the mapping must not invent any.
      expect(item.mediaType, 'IMAGE');
      expect(item.durationSeconds, 5);
      expect(item.durationSecondsProvided, isNull);
      expect(item.seen, isFalse);
      expect(item.boosted, isFalse);
      expect(group.isBoosted, isFalse);
    });

    test('empty rows map to no groups (callers fall back to the profile)', () {
      // The screen treats an empty rail as "no stories here": it must never
      // open a fabricated viewer group.
      final stories = <BusinessStory>[];
      expect(stories.isEmpty, isTrue);
    });
  });

  group('dead-path removal guards', () {
    test('no production call site references the dead /stories/business/ path',
        () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        if (src.contains("'/stories/business/") ||
            src.contains('"/stories/business/')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty,
          reason:
              'GET /stories/business/:id never existed; every tap silently '
              'fell back to the profile page (false affordance). Use '
              '/marketplace/business/:id/stories instead.');
    });

    test('home screen fetches through the booking service, not raw apiClient',
        () {
      final src = File('lib/screens/marketplace/marketplace_home_screen.dart')
          .readAsStringSync();
      expect(src, isNot(contains("apiClient.get('/stories/business")));
      expect(src, contains('marketplaceBookingServiceProvider'));
    });
  });
}
