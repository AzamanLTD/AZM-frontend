// =============================================================================
// AZAMAN — DEPOSIT CONTINUATIONS (submitted-operation lifecycle)
//
// PR #202 review gap 3: a SUBMITTED deposit instruction is not a form
// draft. The five-minute `LauncherDraft` is the editable form's
// convenience; its TTL expiry must NEVER take away the user's way back
// onto a transaction they already instructed — money may be moving
// under that reference right now, and no cancellation endpoint exists.
//
// This service is a SEPARATE persisted lifecycle for exactly one kind
// of record: the payment reference of a Moolre fiat deposit that has
// been initiated (OTP pending, or prompt sent, or recovery unresolved)
// but not yet authoritatively resolved. It is:
//
//   • USER-SCOPED — one storage key per authenticated user, cleared on
//     logout/account switch, never persisted anonymously.
//   • TTL-FREE — a submitted operation outlives every form-draft clock.
//     The record leaves storage only when the deposit is AUTHORITATIVELY
//     resolved (settled or failed by the ledger, confirmed on the
//     socket) — never by an expiry sweep, and never by the exit
//     prompt's "Discard draft" choice (that discards the LOCAL editable
//     draft only; it cannot cancel a submitted operation).
//   • READ-ONLY OBSERVATION — it stores what the server already knows
//     (the durable txHash the backend persisted at initiation) and
//     nothing that could re-instruct anything.
//
// The notification centre renders these as a "submitted deposits"
// section, visually and semantically distinct from the five-minute
// "Continue where you left off" draft cards, with no destructive
// swipe: hiding a submitted operation is not offered, because no
// cancellation endpoint is established.
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DepositContinuation {
  /// Stable identity: one continuation per (user, reference) —
  /// `'<userId>.<reference>'`. A re-save of the same reference UPSERTS;
  /// duplicates are impossible by construction.
  final String id;

  /// The backend's durable txHash (`MOOLRE_DEP_...`). This is the exact
  /// value the recovery service reconciles against the ledger.
  final String reference;

  /// Wall-clock epoch millis of the last save — for honest display only
  /// ("started 2h ago"); it NEVER drives expiry.
  final int savedAtMs;

  const DepositContinuation({
    required this.id,
    required this.reference,
    required this.savedAtMs,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'reference': reference, 'savedAtMs': savedAtMs};

  static DepositContinuation? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final reference = json['reference']?.toString();
    final savedAtMs = json['savedAtMs'];
    if (id == null || id.isEmpty || reference == null || reference.isEmpty) {
      return null;
    }
    if (savedAtMs is! int) return null;
    return DepositContinuation(
        id: id, reference: reference, savedAtMs: savedAtMs);
  }
}

class DepositContinuationsService {
  DepositContinuationsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyPrefix = 'azm.deposit.continuations.';

  String _key(String userId) => '$_keyPrefix$userId';

  /// Generational identity: `<userId>.<reference>`.
  static String continuationId(String userId, String reference) =>
      '$userId.$reference';

  /// Load the user's unresolved submitted deposits. NO expiry sweep —
  /// a submitted operation never dies of old age here.
  Future<List<DepositContinuation>> loadForUser(String userId) async {
    final raw = await _storage.read(key: _key(userId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final alive = <DepositContinuation>[];
      for (final e in decoded) {
        final c =
            e is Map<String, dynamic> ? DepositContinuation.fromJson(e) : null;
        if (c != null) alive.add(c);
      }
      return alive;
    } catch (_) {
      // Corrupt blob: honest absence, never a crash at the centre's open.
      return const [];
    }
  }

  Future<void> _write(String userId, List<DepositContinuation> list) async {
    if (list.isEmpty) {
      await _storage.delete(key: _key(userId));
      return;
    }
    await _storage.write(
      key: _key(userId),
      value: jsonEncode([for (final c in list) c.toJson()]),
    );
  }

  /// Record a submitted deposit reference (idempotent upsert by stable id).
  Future<void> save(String userId, String reference) async {
    final ref = reference.trim();
    if (ref.isEmpty) return;
    final list = [...await loadForUser(userId)];
    final id = continuationId(userId, ref);
    final fresh = DepositContinuation(
        id: id,
        reference: ref,
        savedAtMs: DateTime.now().millisecondsSinceEpoch);
    final i = list.indexWhere((c) => c.id == id);
    if (i >= 0) {
      list[i] = fresh;
    } else {
      list.add(fresh);
    }
    await _write(userId, list);
  }

  /// AUTHORITATIVE resolution only: the ledger (or socket confirm) said
  /// the deposit settled or failed. This is the one way a submitted
  /// operation leaves the continuation lifecycle. A discarded FORM
  /// draft must never reach here.
  Future<void> resolve(String userId, String reference) async {
    final ref = reference.trim();
    if (ref.isEmpty) return;
    final list = [...await loadForUser(userId)];
    list.removeWhere((c) => c.reference == ref);
    await _write(userId, list);
  }

  /// Logout / account switch: the next user must never inherit a
  /// submitted-operation record.
  Future<void> clearAll(String userId) async {
    await _storage.delete(key: _key(userId));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider — generation-protected like the drafts authority, so a
// storage read started under one user can never complete into the next
// user's state.
// ─────────────────────────────────────────────────────────────────────────────

class DepositContinuationsState {
  /// The authenticated user the current continuation list belongs to.
  /// Null until the first load — nothing renders before that.
  final String? userId;
  final List<DepositContinuation> continuations;

  const DepositContinuationsState({
    this.userId,
    this.continuations = const [],
  });
}

class DepositContinuationsController
    extends StateNotifier<DepositContinuationsState> {
  DepositContinuationsController(this._service)
      : super(const DepositContinuationsState());

  final DepositContinuationsService _service;

  /// GENERATION GUARD (review gap 4): every load and every invalidation
  /// bumps the generation; a storage read started under an older
  /// generation completes into the void instead of overwriting the
  /// active user's state.
  int _generation = 0;

  /// Load (or reload) the user's submitted-operation continuations.
  /// A late completion from an earlier generation (user switched, or
  /// logout happened mid-read) is discarded — it must never resurrect
  /// the previous user's continuations.
  Future<void> loadForUser(String? userId) async {
    final gen = ++_generation;
    if (userId == null || userId.isEmpty) {
      state = const DepositContinuationsState();
      return;
    }
    final list = await _service.loadForUser(userId);
    if (gen != _generation) return; // a newer load/invalidation owns state
    state = DepositContinuationsState(userId: userId, continuations: list);
  }

  /// Record a submitted reference for the active user.
  Future<void> save(String userId, String reference) async {
    await _service.save(userId, reference);
    if (state.userId == userId) await loadForUser(userId);
  }

  /// Authoritative resolution — the deposit settled or failed.
  Future<void> resolve(String userId, String reference) async {
    await _service.resolve(userId, reference);
    if (state.userId == userId) await loadForUser(userId);
  }

  /// Logout / account switch / session invalidation. Bumps the
  /// generation FIRST so an in-flight read cannot undo the cleanup.
  Future<void> clearForLogout() async {
    ++_generation;
    final uid = state.userId;
    state = const DepositContinuationsState();
    if (uid != null) await _service.clearAll(uid);
  }
}

/// The single submitted-deposit continuation authority. The
/// notification centre and the deposit surface share it.
final depositContinuationsProvider =
    StateNotifierProvider<DepositContinuationsController,
        DepositContinuationsState>(
  (ref) => DepositContinuationsController(DepositContinuationsService()),
);
