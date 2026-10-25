// lib/services/follow_onboarding_dismissal_store.dart
// =============================================================================
// I1 — Marketplace Follow Onboarding: the "Maybe later" persistence.
//
// A dismissal is an explicit, permanent per-user decision: the user
// told the spotlight card "not now" and the card must never nag them
// again. Honesty rules:
//
//  * USER-SCOPED by construction — the storage key embeds the
//    authenticated user id ('azm.marketplace.followOnboarding.'
//    '<userId>'), so no other account can inherit (or even see) the
//    dismissal. Account switching is isolated without any logout hook.
//  * LOCAL-ONLY BY CONTRACT (documented limitation): the backend has
//    NO dismissal endpoint, and the I1 spec forbids inventing one just
//    to store this flag. The dismissal therefore does NOT sync across
//    devices — same user on another device sees the card once there.
//    The UI copy never claims otherwise.
//  * Only an explicit "Maybe later" writes here. Loading failures,
//    eligibility errors and app restarts never write: absence of a
//    stored dismissal simply means "not yet dismissed".
//  * Corrupt blob = not dismissed (honest absence, no crash).
// =============================================================================
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FollowOnboardingDismissalStore {
  FollowOnboardingDismissalStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyPrefix = 'azm.marketplace.followOnboarding.';

  String _key(String userId) => '$_keyPrefix$userId';

  /// True only when THIS user previously chose "Maybe later" and the
  /// record is readable. Any failure/corruption reads as not
  /// dismissed — the card's absence must never be guessed from a
  /// broken read.
  Future<bool> isDismissed(String userId) async {
    final raw = await _storage.read(key: _key(userId));
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> && decoded['dismissed'] == true;
    } catch (_) {
      return false;
    }
  }

  /// The one write path: an explicit "Maybe later".
  Future<void> dismiss(String userId, {int? atMs}) async {
    await _storage.write(
      key: _key(userId),
      value: jsonEncode({
        'dismissed': true,
        'dismissedAtMs': atMs ?? DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  /// Test/debug helper. Never called from production flow: there is no
  /// "un-dismiss" affordance — a dismissal is permanent by design.
  Future<void> clear(String userId) async {
    await _storage.delete(key: _key(userId));
  }
}
