// =============================================================================
// Storefront Tracking Service
//
// Sends analytics events to the backend when customers interact with
// storefront widgets. Events are sent as fire-and-forget to avoid blocking UI.
// =============================================================================

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:azaman/services/api_client.dart';

class StorefrontTrackingService {
  // Static singleton instance
  static final StorefrontTrackingService instance = StorefrontTrackingService._internal();

  final ApiClient _apiClient = ApiClient();
  static const String _visitorIdKey = 'storefront_visitor_id';
  String? _visitorId;

  // Cache of the last sent time of widget_view events for debouncing
  final Map<String, DateTime> _lastWidgetViewTimes = {};

  StorefrontTrackingService._internal();

  /// Tracks a storefront event asynchronously (fire-and-forget).
  void trackEvent(String businessProfileId, String eventType, Map<String, dynamic> metadata) {
    _trackEventAsync(businessProfileId, eventType, metadata).catchError((error) {
      debugPrint('[StorefrontTrackingService] Error tracking event $eventType: $error');
    });
  }

  /// Internal async method to enrich and send the analytics event.
  Future<void> _trackEventAsync(String businessProfileId, String eventType, Map<String, dynamic> metadata) async {
    // 1. Debounce widget_view events (don't send duplicate views for the same widget within 5 seconds)
    if (eventType == 'widget_view') {
      final widgetType = metadata['widgetType'] ?? '';
      final widgetIndex = metadata['widgetIndex'] ?? '';
      final debounceKey = '$businessProfileId:$widgetType:$widgetIndex';
      final now = DateTime.now();
      final lastSent = _lastWidgetViewTimes[debounceKey];
      if (lastSent != null && now.difference(lastSent) < const Duration(seconds: 5)) {
        // Debounced - duplicate view within 5 seconds
        return;
      }
      _lastWidgetViewTimes[debounceKey] = now;
    }

    // Allowed event types verification
    const allowedEventTypes = {
      'storefront_view',
      'widget_view',
      'cta_click',
      'product_tap',
      'follow_click',
      'review_click',
      'message_click',
      'share_click'
    };

    if (!allowedEventTypes.contains(eventType)) {
      debugPrint('[StorefrontTrackingService] Warning: $eventType is not a recognized event type.');
    }

    // 2. Retrieve or generate unique visitor ID cached in SharedPreferences
    final visitorId = await _getOrCreateVisitorId();

    // 3. Construct enriched metadata containing timestamp, source, and visitor ID
    final enrichedMetadata = Map<String, dynamic>.from(metadata);
    enrichedMetadata['timestamp'] = DateTime.now().toUtc().toIso8601String();
    enrichedMetadata['source'] = 'flutter_app';
    enrichedMetadata['visitorId'] = visitorId;

    // 4. Send request using ApiClient (appends AppConfig.apiUrl automatically)
    final endpoint = '/storefront/$businessProfileId/events';
    await _apiClient.post(endpoint, {
      'eventType': eventType,
      'metadata': enrichedMetadata,
    });
  }

  /// Retrieves the cached visitor ID or generates a new one.
  Future<String> _getOrCreateVisitorId() async {
    if (_visitorId != null) return _visitorId!;

    try {
      final prefs = await SharedPreferences.getInstance();
      String? cachedId = prefs.getString(_visitorIdKey);
      if (cachedId == null || cachedId.isEmpty) {
        cachedId = _generateUniqueId();
        await prefs.setString(_visitorIdKey, cachedId);
      }
      _visitorId = cachedId;
      return _visitorId!;
    } catch (e) {
      debugPrint('[StorefrontTrackingService] SharedPreferences read/write error: $e');
      // Fallback to memory-cached ID for this session if storage fails
      _visitorId ??= _generateUniqueId();
      return _visitorId!;
    }
  }

  /// Generates a unique UUID v4.
  String _generateUniqueId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));

    // Set version to 4 (random)
    values[6] = (values[6] & 0x0f) | 0x40;
    // Set variant to RFC 4122
    values[8] = (values[8] & 0x3f) | 0x80;

    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        buffer.write('-');
      }
      buffer.write(values[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
