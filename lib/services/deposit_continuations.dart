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
//   • USER-SCOPED — one storage key per authenticated user, never
//     persisted anonymously, never rendered to another account. The
//     in-memory state is cleared on logout/account switch; the STORED
//     record is NOT — logging out neither cancels nor resolves a
//     submitted instruction, and the same user must find their way
//     back when they sign in again. The record leaves storage only
//     via resolve() (authoritative settlement/failure).
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

  // FINAL REVIEW — SERIALIZED PER-USER MUTATIONS. save() and resolve()
  // each load, modify, and write the SAME user-scoped list; unserialized,
  // a socket settlement resolving mid-save lets whichever stale write
  // finishes last resurrect a resolved reference or drop a sibling
  // record. Every mutation for a user now queues behind that user's
  // previous one, so the load-modify-write cycle can never interleave
  // with itself. Different users share nothing and never queue
  // behind each other.
  final Map<String, Future<void>> _mutationQueues = {};

  // FINAL REVIEW — TERMINAL RESOLUTION. The ledger's authoritative
  // settlement/failure is FINAL for that (user, reference): a save or
  // retry landing after a resolve is a no-op and can never resurrect
  // the reference into the continuation lifecycle.
  final Set<String> _resolvedReferences = {};

  static String _terminalKey(String userId, String reference) =>
      '$userId\u0000$reference';

  // LAST REVIEW — THE SETTLEMENT OWNER INDEX. A settlement event carries
  // a reference and NO identity. Attributing it to whichever account is
  // ACTIVE is wrong (user A's deposit must resolve while user B holds
  // the session), and attributing it to whichever user's storage happens
  // to contain the matching string is worse. The session therefore binds
  // reference -> initiating owner at the CONTROLLER save (the real
  // durable-reference moment) — in MEMORY first (a settlement racing
  // the very save that creates the record still finds the owner) and
  // in a persisted map afterwards (the binding survives a restart).
  // The index is an ATTRIBUTION hint only: resolution still requires
  // the bound owner's OWN stored list to contain the EXACT reference,
  // so a foreign or tampered entry can never clear anyone's way back.
  static const _ownerIndexKey = 'azm.deposit.continuations.ownerIndex';
  final Map<String, String> _refOwners = {};

  /// LAST REVIEW (concurrent owner-index initialization) — the
  /// initialization is a SHARED, AWAITABLE future, never a boolean-only
  /// guard: a flag set before the storage read lands lets a second
  /// caller (another settlement's owner lookup, or an index persist)
  /// proceed against an UNLOADED map — the lookup would fall back to
  /// the active account and silently mis-attribute, and the persist
  /// would write an incomplete map over the persisted index. Every
  /// caller now waits for the SAME in-flight read.
  Future<void>? _refOwnersInit;
  Future<void> _refOwnersPersistQueue = Future<void>.value();

  /// Bind an exact reference to the identity whose controller-save is
  /// creating its continuation record. Memory-first and synchronous, so
  /// a settlement arriving during the save's storage write is already
  /// attributable. Deliberately NOT called by raw service saves: an
  /// out-of-band record carries no session ownership evidence.
  void bindReferenceOwner(String userId, String reference) {
    final uid = userId.trim();
    final ref = reference.trim();
    if (uid.isEmpty || ref.isEmpty) return;
    if (_resolvedReferences.contains(_terminalKey(uid, ref))) return;
    _refOwners[ref] = uid;
  }

  /// The bound owner for an exact reference, or null when this device
  /// never bound it (the caller falls back to the active session, and
  /// even then only the ACTIVE user's own stored record can resolve).
  Future<String?> lookupReferenceOwner(String reference) async {
    await _loadRefOwners();
    return _refOwners[reference.trim()];
  }

  /// Durable copy of the index. Serialized behind any previous persist
  /// and best-effort: a failed index write must never fail the record
  /// save that already succeeded.
  Future<void> persistReferenceOwners() async {
    _refOwnersPersistQueue = _refOwnersPersistQueue.then((_) async {
      await _loadRefOwners();
      try {
        await _storage.write(
            key: _ownerIndexKey, value: jsonEncode(_refOwners));
      } catch (_) {
        // Best-effort durability only — the in-memory binding owns the
        // session; a stale persisted entry is inert (exact-reference
        // matching still governs every resolution).
      }
    });
    await _refOwnersPersistQueue;
  }

  /// EVERY caller shares the SAME in-flight initialization: the first
  /// caller creates the future AND assigns it before its first await,
  /// so concurrent lookups/persists wait for the read to land instead
  /// of observing a pre-set "loaded" flag against an empty map.
  Future<void> _loadRefOwners() {
    final existing = _refOwnersInit;
    if (existing != null) return existing;
    final init = _doLoadRefOwners();
    _refOwnersInit = init;
    return init;
  }

  Future<void> _doLoadRefOwners() async {
    try {
      final raw = await _storage.read(key: _ownerIndexKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          final key = k?.toString().trim() ?? '';
          final owner = v?.toString().trim() ?? '';
          if (key.isNotEmpty && owner.isNotEmpty) {
            // putIfAbsent: a binding made in MEMORY during this read
            // (bindReferenceOwner is memory-first and synchronous) is
            // NEWER than the persisted copy and must win the merge.
            _refOwners.putIfAbsent(key, () => owner);
          }
        });
      }
    } catch (_) {
      // Corrupt index: absence is safe (the active-user fallback plus
      // exact-reference matching govern resolution).
    }
  }

  /// Queue [action] behind the user's previous mutation. The queue
  /// itself never breaks on a failed action (the chain swallows and
  /// continues); the original caller still observes the real error.
  Future<void> _enqueue(String userId, Future<void> Function() action) {
    final previous = _mutationQueues[userId] ?? Future<void>.value();
    final operation = previous.then((_) => action());
    _mutationQueues[userId] = operation.then((_) {}, onError: (_) {});
    return operation;
  }

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
  /// SERIALIZED per user, and a NO-OP for a reference the ledger has
  /// already resolved — a late save or retry can never resurrect it.
  Future<void> save(String userId, String reference) async {
    final ref = reference.trim();
    if (ref.isEmpty) return;
    await _enqueue(userId, () async {
      if (_resolvedReferences.contains(_terminalKey(userId, ref))) {
        return; // resolution is terminal for this reference
      }
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
    });
  }

  /// AUTHORITATIVE resolution only: the ledger (or socket confirm) said
  /// the deposit settled or failed. This is the one way a submitted
  /// operation leaves the continuation lifecycle — and it is TERMINAL
  /// for the reference: a save or retry landing afterwards can never
  /// resurrect it. A discarded FORM draft must never reach here.
  Future<void> resolve(String userId, String reference) async {
    final ref = reference.trim();
    if (ref.isEmpty) return;
    await _enqueue(userId, () async {
      _resolvedReferences.add(_terminalKey(userId, ref));
      // LAST REVIEW: the binding purge must wait for owner-index
      // initialization, so the PERSISTED copy is purged too and no
      // in-flight index read can merge it back afterwards.
      await _loadRefOwners();
      if (_refOwners[ref] == userId) {
        _refOwners.remove(ref);
        // FINAL REVIEW (persisted cleanup): removing the binding in
        // MEMORY alone leaves the resolved reference in the persisted
        // index forever — stale attribution that survives every
        // restart and grows without bound. The cleanup goes through
        // the SAME serialized persistence queue as the saves, so it
        // is ordered against concurrent index writes and best-effort:
        // a failed cleanup write can never fail the authoritative
        // resolution that already succeeded.
        await persistReferenceOwners();
      }
      final list = [...await loadForUser(userId)];
      list.removeWhere((c) => c.reference == ref);
      await _write(userId, list);
    });
  }

  /// LAST REVIEW — RACE-SAFE SETTLEMENT ENTRY. A settlement event may
  /// land while the continuation record's INITIAL save is still in
  /// flight: a storage pre-check outside the lock would miss it and
  /// lose the event forever. This queues on the owner's OWN mutation
  /// chain — the same serialization as save()/resolve() — so a
  /// settlement racing the initial save WAITS for the record to land
  /// and then resolves it; a save landing after a resolution remains a
  /// no-op (terminal resolution). Exact-reference matching, sibling
  /// preservation and per-owner isolation are unchanged: only the
  /// owner's list is read, and only the exact reference leaves it.
  Future<void> resolveIfPresent(String userId, String reference) async {
    final uid = userId.trim();
    final ref = reference.trim();
    if (uid.isEmpty || ref.isEmpty) return;
    await _enqueue(uid, () async {
      final list = [...await loadForUser(uid)];
      if (!list.any((c) => c.reference == ref)) return;
      _resolvedReferences.add(_terminalKey(uid, ref));
      // LAST REVIEW: purge after initialization, and through the same
      // serialized persistence queue as the saves — see resolve().
      await _loadRefOwners();
      if (_refOwners[ref] == uid) {
        _refOwners.remove(ref);
        await persistReferenceOwners();
      }
      list.removeWhere((c) => c.reference == ref);
      await _write(uid, list);
    });
  }

  // NOTE (review follow-up P1): there is deliberately NO clearAll.
  // Logout and account switches must NOT delete an unresolved
  /// submitted-operation record — that deletion is reserved for
  // resolve() (authoritative settlement/failure). Strict per-user
  // isolation comes from the user-scoped storage key: another account
  // can never read this block.
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
  /// LAST REVIEW — the save ALSO binds reference -> initiating owner
  /// (in memory BEFORE the storage write, durably after it) so the
  /// session-wide settlement monitor can attribute a settlement to
  /// the INITIATING identity even when another account holds the
  /// session or this surface is long disposed.
  Future<void> save(String userId, String reference) async {
    final uid = userId.trim();
    final ref = reference.trim();
    if (uid.isEmpty || ref.isEmpty) return;
    _service.bindReferenceOwner(uid, ref);
    await _service.save(uid, ref);
    await _service.persistReferenceOwners();
    if (state.userId == uid) await loadForUser(uid);
  }

  /// Authoritative resolution — the deposit settled or failed.
  Future<void> resolve(String userId, String reference) async {
    await _service.resolve(userId, reference);
    if (state.userId == userId) await loadForUser(userId);
  }

  /// LAST REVIEW (settlement attribution + the save race) — a socket
  /// settlement event is attributed to the reference's BOUND OWNER:
  /// the identity recorded at the durable-save moment, so user A's
  /// deposit resolves while user B holds the session and long after
  /// the deposit surface is disposed. The ACTIVE user is only a
  /// conservative fallback for a reference this device never bound —
  /// and even then resolution requires the ACTIVE user's OWN stored
  /// list to contain the EXACT reference (a foreign reference matches
  /// nothing, so another account's way back is never touched).
  ///
  /// RACE-SAFE: resolution runs inside the owner's serialized mutation
  /// chain (resolveIfPresent), so a settlement arriving while the
  /// record's INITIAL save is still in flight WAITS for the write to
  /// land instead of being lost; a save landing after a resolution is
  /// a no-op (terminal resolution). Duplicate events are no-ops.
  Future<void> handleSettlement(String? activeUserId, String reference) async {
    final ref = reference.trim();
    if (ref.isEmpty) return;
    final boundOwner = await _service.lookupReferenceOwner(ref);
    final owner = boundOwner ?? activeUserId?.trim();
    if (owner == null || owner.isEmpty) return;
    await _service.resolveIfPresent(owner, ref);
    if (state.userId == owner) await loadForUser(owner);
  }

  /// Logout / session invalidation. Bumps the generation FIRST so an
  /// in-flight read cannot undo the cleanup, then clears the IN-MEMORY
  /// state only. REVIEW FOLLOW-UP P1: the stored record is deliberately
  /// PRESERVED — logging out neither cancels nor resolves a submitted
  /// Moolre instruction, so deleting the user's only local way back
  /// would contradict the continuation contract. Per-user isolation is
  /// preserved by the user-scoped storage key: another account never
  /// sees this block, and the same user's outstanding continuations
  /// reload on their next loadForUser (sign-in / centre open).
  Future<void> clearForLogout() async {
    ++_generation;
    state = const DepositContinuationsState();
  }

  /// Direct account switch (no logout). The outgoing user's in-memory
  /// state is dropped IMMEDIATELY — synchronously — so their records
  /// can never render after the boundary, and the new user's records
  /// load under a fresh generation. REVIEW FOLLOW-UP P1: the outgoing
  /// user's STORED continuations are preserved (user-scoped, they
  /// reload when that user signs back in); an in-flight read for the
  /// old user completes into the void via the generation bump.
  Future<void> switchToUser(String? userId) async {
    ++_generation;
    state = const DepositContinuationsState();
    await loadForUser(userId);
  }
}

/// The single submitted-deposit continuation authority. The
/// notification centre and the deposit surface share it.
final depositContinuationsProvider =
    StateNotifierProvider<DepositContinuationsController,
        DepositContinuationsState>(
  (ref) => DepositContinuationsController(DepositContinuationsService()),
);
