// =============================================================================
// AZAMAN — Message Action Service (Phase 3.3.4)
//
// API client for: message search, pin/unpin, star/unstar, forward, get starred
// =============================================================================

import 'package:azaman/services/api_client.dart';

class MessageActionService {
  /// Search messages across conversations
  /// [query]: search string
  /// [context]: 'all' | 'direct' | 'group'
  /// [conversationId]: optional, to search within a specific conversation
  static Future<List<Map<String, dynamic>>> searchMessages({
    required String query,
    String context = 'all',
    String? conversationId,
  }) async {
    final response = await ApiClient.dio.post('/api/messages/search', data: {
      'query': query,
      'context': context,
      if (conversationId != null) 'conversationId': conversationId,
    });
    return List<Map<String, dynamic>>.from(response.data['data'] as List);
  }

  /// Toggle pin status on a message
  static Future<Map<String, dynamic>> togglePin({
    required String context, // 'direct' | 'group' | 'trade'
    required String messageId,
  }) async {
    final response = await ApiClient.dio.patch(
      '/api/messages/$context/$messageId/pin',
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  /// Toggle star status on a message
  static Future<Map<String, dynamic>> toggleStar({
    required String context,
    required String messageId,
  }) async {
    final response = await ApiClient.dio.patch(
      '/api/messages/$context/$messageId/star',
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  /// Get all starred messages
  static Future<List<Map<String, dynamic>>> getStarredMessages() async {
    final response = await ApiClient.dio.get('/api/messages/starred');
    return List<Map<String, dynamic>>.from(response.data['data'] as List);
  }

  /// Forward a message to another conversation
  static Future<Map<String, dynamic>> forwardMessage({
    required String messageId,
    required String fromContext,
    required String toContext,
    required String toConversationId,
  }) async {
    final response = await ApiClient.dio.post('/api/messages/forward', data: {
      'messageId': messageId,
      'fromContext': fromContext,
      'toContext': toContext,
      'toConversationId': toConversationId,
    });
    return response.data['data'] as Map<String, dynamic>;
  }
}
