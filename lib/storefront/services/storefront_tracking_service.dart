// =============================================================================
// Storefront Tracking Service
//
// Sends analytics events to the backend when customers interact with
// storefront widgets. Events are sent as fire-and-forget to avoid blocking UI.
// =============================================================================

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:azaman/services/api_client.dart';

class StorefrontTrackingService {
  static final StorefrontTrackingService instance = StorefrontTrackingService._internal();

  final ApiClient _apiClient = ApiClient();
  static const String _visitorIdKey = 'storefront_visitor_id';
  static const Duration _widgetViewDebounce = Duration(seconds: 5);
  static const int _maxWidgetViewDebounceEntries = 1000;
  String? _visitorId;

  // Cache of the last sent time of widget_view events for debouncing.
  // The key uses the stable tile id so layout reordering does not change the
  // analytics identity of a storefront component.
  final Map<String, DateTime> _lastWidgetViewTimes = {};

  StorefrontTrackingService._internal();

  void trackEvent(String businessProfileId, String eventType, Map<String, dynamic> metadata) {
    _trackEventAsync(businessProfileId, eventType, metadata).catchError((error) {
      debugPrint('[StorefrontTrackingService] Error tracking event $eventType: $error');
    });
  }

  Future<void> _trackEventAsync(
    String businessProfileId,
    String eventType,
    Map<String, dynamic> metadata,
  ) async {
    const allowedEventTypes = {
      'storefront_view',
      'widget_view',
      'cta_click',
      'product_tap',
      'follow_click',
      'review_click',
      'message_click',
      'share_click',
    };

    // Do not send events the backend contract does not recognize. A warning
    // alone is unsafe for analytics because it still produces an HTTP request.
    if (!allowedEventTypes.contains(eventType)) {
      debugPrint('[StorefrontTrackingService] Ignoring unknown event type: $eventType');
      return;
    }

    if (eventType == 'widget_view') {
      final tileId = metadata['tileId'];
      final widgetIdentity = tileId is String && tileId.isNotEmpty
          ? tileId
          : '${metadata['widgetType'] ?? ''}:${metadata['widgetIndex'] ?? ''}';
      final debounceKey = '$businessProfileId:$widgetIdentity';
      final now = DateTime.now();
      final lastSent = _lastWidgetViewTimes[debounceKey];
      if (lastSent != null && now.difference(lastSent) < _widgetViewDebounce) {
        return;
      }
      _lastWidgetViewTimes[debounceKey] = now;
      _trimWidgetViewCache();
    }

    final visitorId = await _getOrCreateVisitorId();
    final enrichedMetadata = Map<String, dynamic>.from(metadata);
    enrichedMetadata['timestamp'] = DateTime.now().toUtc().toIso8601String();
    enrichedMetadata['source'] = 'flutter_app';
    enrichedMetadata['visitorId'] = visitorId;

    final endpoint = '/storefront/$businessProfileId/events';
    await _apiClient.post(endpoint, {
      'eventType': eventType,
      'metadata': enrichedMetadata,
    });
  }

  void _trimWidgetViewCache() {
    if (_lastWidgetViewTimes.length <= _maxWidgetViewDebounceEntries) return;

    final entries = _lastWidgetViewTimes.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final removeCount = entries.length - _maxWidgetViewDebounceEntries;
    for (var i = 0; i < removeCount; i++) {
      _lastWidgetViewTimes.remove(entries[i].key);
    }
  }

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
      _visitorId ??= _generateUniqueId();
      return _visitorId!;
    }
  }

  String _generateUniqueId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;

    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) buffer.write('-');
      buffer.write(values[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
