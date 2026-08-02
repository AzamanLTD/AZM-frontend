// =============================================================================
// AZAMAN — Message Action Service (Phase 3.3.4)
//
// API client for: message search, pin/unpin, star/unstar, forward, get starred
// Uses ApiClient (http-based) instead of dio.
// =============================================================================

import 'dart:convert';
import 'package:azaman/services/api_client.dart';

class MessageActionService {
  static final ApiClient _client = ApiClient();

  /// Search messages across conversations
  static Future<List<Map<String, dynamic>>> searchMessages({
    required String query,
    String context = 'all',
    String? conversationId,
  }) async {
    final response = await _client.post('/api/messages/search', {
      'query': query,
      'context': context,
      if (conversationId != null) 'conversationId': conversationId,
    });
    final body = jsonDecode(response.body);
    return List<Map<String, dynamic>>.from(body['data'] as List);
  }

  /// Toggle pin status on a message
  static Future<Map<String, dynamic>> togglePin({
    required String context,
    required String messageId,
  }) async {
    final response = await _client.patch('/api/messages/$context/$messageId/pin');
    final body = jsonDecode(response.body);
    return body['data'] as Map<String, dynamic>;
  }

  /// Toggle star status on a message
  static Future<Map<String, dynamic>> toggleStar({
    required String context,
    required String messageId,
  }) async {
    final response = await _client.patch('/api/messages/$context/$messageId/star');
    final body = jsonDecode(response.body);
    return body['data'] as Map<String, dynamic>;
  }

  /// Get all starred messages
  static Future<List<Map<String, dynamic>>> getStarredMessages() async {
    final response = await _client.get('/api/messages/starred');
    final body = jsonDecode(response.body);
    return List<Map<String, dynamic>>.from(body['data'] as List);
  }

  /// Forward a message to another conversation
  static Future<Map<String, dynamic>> forwardMessage({
    required String messageId,
    required String fromContext,
    required String toContext,
    required String toConversationId,
  }) async {
    final response = await _client.post('/api/messages/forward', {
      'messageId': messageId,
      'fromContext': fromContext,
      'toContext': toContext,
      'toConversationId': toConversationId,
    });
    final body = jsonDecode(response.body);
    return body['data'] as Map<String, dynamic>;
  }
}
