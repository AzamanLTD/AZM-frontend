import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:azaman/services/api_client.dart';

// =============================================================================
// AZAMAN — VERSION GATE SERVICE (Phase Q15-FE)
//
// Calls GET /health (no auth) and inspects the `versionGate` field.
// If the backend signals a minimum version newer than the running client,
// the splash screen blocks with a "Force Update" screen.
// =============================================================================

class VersionGateResult {
  final bool updateRequired;
  final String? minVersion;
  final String? updateUrl;
  final String? message;

  const VersionGateResult({
    required this.updateRequired,
    this.minVersion,
    this.updateUrl,
    this.message,
  });

  factory VersionGateResult.noUpdate() =>
      const VersionGateResult(updateRequired: false);
}

class VersionGateService {
  /// Check the /health endpoint and compare the backend's minVersion
  /// against the client's current version.
  ///
  /// Returns [VersionGateResult.noUpdate()] if:
  ///   - The endpoint doesn't respond (fail-open so users aren't locked out)
  ///   - There's no versionGate field in the response
  ///   - The client version is >= minVersion
  Future<VersionGateResult> check(String clientVersion) async {
    try {
      final response = await apiClient.get(
        '/health',
        requireAuth: false,
      );

      final data = jsonDecode(response.body);
      final versionGate = data['versionGate'];

      if (versionGate == null || versionGate is! Map<String, dynamic>) {
        return VersionGateResult.noUpdate();
      }

      final minVersion = versionGate['minVersion'] as String?;
      final updateUrl = versionGate['updateUrl'] as String?;
      final message = versionGate['message'] as String?;

      if (minVersion == null || minVersion.isEmpty) {
        return VersionGateResult.noUpdate();
      }

      final needsUpdate = _isVersionLessThan(clientVersion, minVersion);

      return VersionGateResult(
        updateRequired: needsUpdate,
        minVersion: minVersion,
        updateUrl: updateUrl,
        message: message,
      );
    } catch (e) {
      // Fail-open: if /health is unreachable, don't block the user.
      debugPrint('[VersionGate] Health check failed (fail-open): $e');
      return VersionGateResult.noUpdate();
    }
  }

  /// Simple semver comparison: returns true if [current] < [minimum].
  /// Splits on "." and compares major/minor/patch numerically.
  bool _isVersionLessThan(String current, String minimum) {
    final currentParts = _parseSemver(current);
    final minimumParts = _parseSemver(minimum);

    for (int i = 0; i < 3; i++) {
      if (currentParts[i] < minimumParts[i]) return true;
      if (currentParts[i] > minimumParts[i]) return false;
    }
    return false; // equal versions — no update needed
  }

  /// Parse a version string like "1.2.3" into [major, minor, patch].
  /// Handles missing parts gracefully (defaults to 0).
  List<int> _parseSemver(String version) {
    final parts = version.split('.');
    return [
      parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0,
      parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
      parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0,
    ];
  }
}

/// Singleton instance
final VersionGateService versionGateService = VersionGateService();
