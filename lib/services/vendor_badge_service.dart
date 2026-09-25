import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:azaman/services/api_client.dart';

// =============================================================================
// AZAMAN — VENDOR BADGE SERVICE (Phase Q13-FE)
//
// Fetches vendor verification badges from GET /api/vendor/badges/:vendorId.
// Public endpoint — no auth required (marketplace visitors can see badges).
// =============================================================================

class VendorBadge {
  final String id;
  final String name;
  final String icon; // Material icon name
  final String description;
  final String color; // Hex color string

  const VendorBadge({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    required this.color,
  });

  factory VendorBadge.fromJson(Map<String, dynamic> json) {
    return VendorBadge(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? 'verified',
      description: json['description'] as String? ?? '',
      color: json['color'] as String? ?? '#02C076',
    );
  }
}

class VendorBadgeService {
  // In-memory cache to avoid repeated calls for the same vendor
  final Map<int, List<VendorBadge>> _cache = {};

  /// Fetch badges for a vendor. Returns cached result if available.
  Future<List<VendorBadge>> fetchBadges(int vendorId) async {
    if (_cache.containsKey(vendorId)) {
      return _cache[vendorId]!;
    }

    try {
      final response = await apiClient.get(
        '/vendor/badges/$vendorId',
        requireAuth: false, // Public endpoint
      );

      final body = jsonDecode(response.body);
      if (body['success'] == true && body['data'] != null) {
        final data = body['data'] as Map<String, dynamic>;
        final badges = (data['badges'] as List<dynamic>?)
                ?.map((e) => VendorBadge.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        _cache[vendorId] = badges;
        return badges;
      }
      return [];
    } catch (e) {
      debugPrint('[VendorBadgeService] fetchBadges($vendorId) error: $e');
      return [];
    }
  }

  /// Clear cache (e.g. on pull-to-refresh)
  void clearCache() => _cache.clear();
}

/// Singleton instance
final VendorBadgeService vendorBadgeService = VendorBadgeService();
