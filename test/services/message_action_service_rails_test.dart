// =============================================================================
// MessageActionService rail contracts (URL construction + envelope shape)
// =============================================================================
// Five client message actions previously hardcoded an '/api/' prefix on top
// of ApiClient's '/api' baseUrl (resolving to /api/api/messages/... and
// 404ing): search, pin, star, starred list, and forward.
//
// This suite drives the real service through a recording test seam and pins
// the EXACT path each action constructs, plus the request body keys and the
// `{success, data}` envelope keys the parses depend on (verified against
// backend main messageActionController.js).
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/message_action_service.dart';

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _RecordingClient extends ApiClient {
  final List<(String method, String path)> calls = [];
  final List<Map<String, dynamic>> postBodies = [];

  @override
  Future<http.Response> post(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    bool requireAuth = true,
    String? idempotencyKey,
  }) async {
    calls.add(('POST', endpoint));
    postBodies.add(Map<String, dynamic>.from(body));
    if (endpoint == '/messages/search') {
      return _json(200, {
        'success': true,
        'data': [
          {'id': 'm1', 'content': 'hit'},
        ],
      });
    }
    return _json(200, {
      'success': true,
      'data': {'id': 'fwd-1'},
    });
  }

  @override
  Future<http.Response> patch(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    calls.add(('PATCH', endpoint));
    return _json(200, {
      'success': true,
      'data': {'id': 'm1', 'isPinned': true, 'isStarred': true},
    });
  }

  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    calls.add(('GET', endpoint));
    return _json(200, {
      'success': true,
      'data': [
        {'id': 'm2', 'content': 'starred hit'},
      ],
    });
  }
}

void main() {
  late _RecordingClient client;

  setUp(() {
    client = _RecordingClient();
    MessageActionService.testClientOverride = client;
    addTearDown(() => MessageActionService.testClientOverride = null);
  });

  test(
    'searchMessages posts the exact /messages/search rail with body keys',
    () async {
      final results = await MessageActionService.searchMessages(
        query: 'receipt',
        context: 'friend',
        conversationId: 'c9',
      );
      expect(client.calls, [('POST', '/messages/search')]);
      expect(client.postBodies.single['query'], 'receipt');
      expect(client.postBodies.single['context'], 'friend');
      expect(client.postBodies.single['conversationId'], 'c9');
      expect(results, hasLength(1)); // parses body['data']
      expect(results.first['content'], 'hit');
    },
  );

  test('togglePin patches the exact context-scoped pin rail', () async {
    final result = await MessageActionService.togglePin(
      context: 'friend',
      messageId: 'abc123',
    );
    expect(client.calls, [('PATCH', '/messages/friend/abc123/pin')]);
    expect(result['id'], 'm1'); // parses body['data']
  });

  test('toggleStar patches the exact context-scoped star rail', () async {
    final result = await MessageActionService.toggleStar(
      context: 'group',
      messageId: 'xyz9',
    );
    expect(client.calls, [('PATCH', '/messages/group/xyz9/star')]);
    expect(result['isStarred'], true);
  });

  test('getStarredMessages reads the exact /messages/starred rail', () async {
    final results = await MessageActionService.getStarredMessages();
    expect(client.calls, [('GET', '/messages/starred')]);
    expect(results, hasLength(1)); // parses body['data']
  });

  test(
    'forwardMessage posts the exact /messages/forward rail with body keys',
    () async {
      final result = await MessageActionService.forwardMessage(
        messageId: 'm1',
        fromContext: 'friend',
        toContext: 'group',
        toConversationId: 'g7',
      );
      expect(client.calls, [('POST', '/messages/forward')]);
      expect(client.postBodies.single['messageId'], 'm1');
      expect(client.postBodies.single['fromContext'], 'friend');
      expect(client.postBodies.single['toContext'], 'group');
      expect(client.postBodies.single['toConversationId'], 'g7');
      expect(result['id'], 'fwd-1');
    },
  );

  test('no message-action rail ever constructs a double /api prefix', () async {
    await MessageActionService.searchMessages(query: 'q');
    await MessageActionService.togglePin(context: 'friend', messageId: 'a');
    await MessageActionService.toggleStar(context: 'friend', messageId: 'a');
    await MessageActionService.getStarredMessages();
    await MessageActionService.forwardMessage(
      messageId: 'm',
      fromContext: 'friend',
      toContext: 'group',
      toConversationId: 'g',
    );
    expect(client.calls, hasLength(5));
    for (final (_, path) in client.calls) {
      expect(
        path.startsWith('/api/'),
        isFalse,
        reason: 'ApiClient baseUrl already ends in /api — saw $path',
      );
    }
  });
}
