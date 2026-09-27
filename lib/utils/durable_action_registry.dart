// =============================================================================
// r42 — DURABLE FINANCIAL OPERATION REGISTRY (audit close-out, 2026-09-27)
// =============================================================================
// The cross-repo audit finding this closes: an in-memory LogicalActionKey
// defines the retry horizon as "while the owning object survives". A lost
// HTTP response followed by app/process death or screen recreation let the
// user's next tap of the SAME logical action mint a FRESH key — the backend
// correctly treated it as a new financial operation and the money could
// move twice. The duplicate-money failure had merely moved one layer out.
//
// This registry gives every logical financial action a DURABLE identity:
//
//   arm(logicalActionId, endpoint, fingerprint)
//     — creates the entry and PERSISTS it BEFORE the first request is sent;
//     — returns the SAME key for every retry of the same unfinished action,
//       including across widget/screen recreation, provider/service
//       recreation, and full application restart/process death;
//     — a materially different request (fingerprint mismatch) is a
//       GENUINELY NEW action: it receives a fresh key and a fresh entry;
//     — a genuinely new action id receives a fresh key by construction.
//
//   retire(logicalActionId)
//     — terminal completion: the authoritative outcome is in the caller's
//       hands, so the pending entry is removed and the next arm mints fresh.
//       Called on 2xx (after the response is fully received) and on
//       definitive pre-economic 4xx refusals (the backend authority releases
//       the claim on those routes, so a corrected action starts clean).
//
//   Retained (NOT retired): network errors, timeouts, 401, 409, 429, 5xx —
//   the operation may have committed or may still be in flight; retrying
//   with the SAME key is exactly the protection the backend provides.
//
// Storage: SharedPreferences — survives process restart; the entry is
// written synchronously with the arm() future BEFORE any request is sent.
// Entries are tiny (id, key, endpoint, fingerprint, createdAt, state) and
// exist only while the action is pending, so the journal cannot grow
// unboundedly.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'idempotency_key.dart';

class DurableActionRegistry {
  DurableActionRegistry._();

  static const _prefix = 'azm.r42.op.';

  /// Canonical stable stringify: recursively sorted keys, mirroring the
  /// backend's fingerprint algorithm so both sides agree on what a
  /// "materially different body" means. Money values compare by their exact
  /// string form; no float arithmetic happens anywhere in the identity path.
  static String canonical(Object? value) {
    if (value == null) return 'null';
    if (value is List) return '[${value.map(canonical).join(',')}]';
    if (value is Map) {
      final keys = (value.keys.map((k) => k.toString()).toList()..sort());
      return '{${keys.map((k) => '"$k":${canonical(value[k])}').join(',')}}';
    }
    if (value is num && value is! int) return value.toString();
    return jsonEncode(value);
  }

  /// Request fingerprint: sha256 over the canonical body form. The legacy
  /// in-body identity field (clientRequestId) is excluded — it CARRIES the
  /// key, so including it would make the fingerprint self-referential.
  static String fingerprintOf(Map<String, dynamic> body) {
    final identityFree = Map<String, dynamic>.from(body)
      ..remove('clientRequestId');
    return sha256.convert(utf8.encode(canonical(identityFree))).toString();
  }

  static Future<SharedPreferences> _store() => SharedPreferences.getInstance();

  static String _slot(String logicalActionId) => '$_prefix$logicalActionId';

  /// Arms (or re-arms) the durable identity of ONE logical financial action.
  ///
  /// - Returns the PERSISTED key of any pending entry for this action whose
  ///   fingerprint matches: a retry of the same unfinished action, possibly
  ///   after full process death, reuses the SAME key.
  /// - A pending entry with a DIFFERENT fingerprint is a genuinely new
  ///   action: minted fresh, persisted, old entry replaced.
  /// - No entry: mint fresh, persist, return.
  static Future<String> arm({
    required String logicalActionId,
    required String endpoint,
    required Map<String, dynamic> request,
  }) async {
    final fingerprint = fingerprintOf(request);
    final store = await _store();
    final slot = _slot(logicalActionId);
    final raw = store.getString(slot);
    if (raw != null) {
      try {
        final entry = jsonDecode(raw) as Map<String, dynamic>;
        if (entry['f'] == fingerprint && entry['s'] == 'pending') {
          // Same unfinished logical action → SAME durable identity.
          return entry['k'] as String;
        }
      } catch (_) {
        // Corrupt entry: fail safe by minting fresh below.
      }
    }
    final key = IdempotencyKey.generate();
    await store.setString(slot, jsonEncode({
      'k': key,
      'e': endpoint,
      'f': fingerprint,
      't': DateTime.now().toIso8601String(),
      's': 'pending',
    }));
    return key;
  }

  /// Terminal completion: removes the durable pending entry. The next arm of
  /// this logical action id mints a fresh key.
  static Future<void> retire(String logicalActionId) async {
    final store = await _store();
    await store.remove(_slot(logicalActionId));
  }

  /// Introspection (surfaces/debugging): the pending entry, if any.
  static Future<Map<String, dynamic>?> pending(String logicalActionId) async {
    final store = await _store();
    final raw = store.getString(_slot(logicalActionId));
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
