// =============================================================================
// r42 — DURABLE FINANCIAL OPERATION REGISTRY v2 (OPERATION-INSTANCE MODEL)
// =============================================================================
// Independent review (2026-09-27) of the v1 DurableActionRegistry found a
// remaining correctness flaw: v1 stored ONE pending slot per logicalActionId,
// so for broad/static action ids ("withdrawal.fiat", "savings.goal.deposit",
// ...) there could only be ONE outstanding operation per TYPE. Two failure
// modes followed:
//
//   LOST OUTSTANDING OPERATION — operation A is armed with key K1, the
//   response is lost (A may have committed server-side); before A resolves,
//   a new operation B of the same type starts with a different body; v1
//   saw the fingerprint difference and REPLACED A's entry with B's key K2.
//   The device lost K1 — A's durable identity (and safe retry) is gone.
//
//   COLLAPSING DISTINCT OPERATIONS — two genuinely separate operations of
//   the same type with the SAME body both converged on the one slot and
//   received the SAME key: two distinct user intentions, one identity.
//
// The fix is one level of structure the v1 model lacked:
//
//       operation TYPE  ≠  operation INSTANCE.
//
// This registry gives every GENUINELY NEW financial action a unique durable
// OPERATION-INSTANCE record, persisted BEFORE the first request leaves the
// device, and supports MULTIPLE outstanding instances of the same type at
// the same time:
//
//   begin(account, type, endpoint, request)
//     — a genuinely new operation instance: mints a unique operationId and
//       a fresh Idempotency-Key, persists the record, returns it. NEVER
//       deduplicates by body: two begins are two instances, distinct keys,
//       both records retained, no matter how similar the bodies are.
//
//   retry(operationId, account, request)
//     — a retry/reconstruction of ONE existing instance: returns the SAME
//       instance (SAME key) if it is still pending and the request matches
//       its recorded fingerprint. Fails closed otherwise:
//       DurableOperationNotFoundException (no such pending instance — e.g.
//       already retired, corrupt, or another account's) or
//       DurableOperationFingerprintMismatchException (a materially
//       different request — that is a genuinely NEW action and must be
//       begun explicitly; retry() never silently replaces anything).
//
//   retire(operationId, account)
//     — terminal completion / definitive pre-economic release: removes THAT
//       instance only. Other outstanding instances are untouched.
//
//   pending({account, type})
//     — recovery: every unfinished instance, optionally filtered by account
//       and/or operation type. Recovery must never assume there is only one
//       pending action of a given type.
//
// ACCOUNT NAMESPACE: records are namespaced by the authenticated account.
// A pending operation belonging to one signed-in user can never be seen,
// retried, or adopted as another user's operation on the same device.
//
// STORAGE: SharedPreferences. The critical invariant — the durable record
// exists BEFORE the first financial request is allowed to leave the device —
// is preserved by making begin() await the write and by an injectable
// storage writer (used by tests to prove a persistence failure blocks the
// request instead of sending it keyless). Records are small and exist only
// while an operation is unresolved; retirement removes them. Instances are
// intentionally NEVER auto-pruned: an unresolved financial operation may
// still commit server-side, and silently deleting its identity is the exact
// lost-operation bug this registry exists to prevent.
//
// INVARIANT (the audit's one-liner):
//   ONE GENUINELY NEW FINANCIAL OPERATION INSTANCE
//     → ONE DURABLE KEY
//     → ALL RETRIES OF THAT INSTANCE REUSE THAT KEY
//     → OTHER OPERATION INSTANCES NEVER STEAL OR SHARE IT.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'idempotency_key.dart';

/// Base class of the registry's fail-closed retry outcomes.
abstract class DurableOperationException implements Exception {
  final String operationId;
  const DurableOperationException(this.operationId);
}

/// A pending durable operation instance could not be found: it was retired,
/// it belongs to another account namespace, or its record is unreadable.
class DurableOperationNotFoundException extends DurableOperationException {
  const DurableOperationNotFoundException(String operationId) : super(operationId);
  @override
  String toString() =>
      'DurableOperationNotFoundException: no pending operation '
      '"$operationId" in this account namespace';
}

/// The instance's stored snapshot is NOT the exact wire request (it is a
/// synthetic fingerprint body): generic replay is invalid. Resume from the
/// operation's own flow, which reconstructs the exact request. The
/// instance is untouched.
class DurableOperationNotReplayableException extends DurableOperationException {
  const DurableOperationNotReplayableException(String operationId)
      : super(operationId);
  @override
  String toString() =>
      'DurableOperationNotReplayableException: the stored snapshot of '
      '"$operationId" is not an exact wire request — resume from the '
      "operation's own flow; generic replay fails closed";
}

/// The request is materially different from the instance's recorded
/// fingerprint: this is a genuinely NEW action, not a retry. The pending
/// instance is untouched.
class DurableOperationFingerprintMismatchException
    extends DurableOperationException {
  const DurableOperationFingerprintMismatchException(String operationId)
      : super(operationId);
  @override
  String toString() =>
      'DurableOperationFingerprintMismatchException: request differs from '
      'the recorded fingerprint of pending operation "$operationId" — '
      'begin a new operation instance instead';
}

/// ONE durable financial operation instance.
@immutable
class DurableOperation {
  /// Unique instance identity, minted at [DurableOperationRegistry.begin]
  /// BEFORE the first request. Retries address the instance by this id.
  final String operationId;

  /// Operation TYPE / recovery namespace, e.g. 'withdrawal.fiat' or
  /// 'trade.accept.<tradeId>'. The type NEVER identifies an instance on its
  /// own: repeated operations against the same target are distinct
  /// instances and must remain separately addressable.
  final String type;

  /// The HTTP Idempotency-Key. ONE instance, ONE key, forever.
  final String key;

  /// Endpoint the operation was first sent to.
  final String endpoint;

  /// Canonical fingerprint of the request body (identity-carrying fields
  /// excluded — they are derived FROM the key and must not feed it).
  final String fingerprint;

  /// When the instance was created (before its first request).
  final DateTime createdAt;

  /// The account namespace this instance belongs to.
  final String account;

  /// Snapshot of the request body — enough metadata to display, reconcile
  /// and re-present the operation to its owner after process death.
  /// SECRETS ARE NEVER IN THE SNAPSHOT (see DurableOperationRegistry's
  /// scrubber): ephemeral step-up credentials (password, TOTP, PIN ...) are
  /// stripped before the record is persisted and must be re-supplied
  /// freshly on any recovered retry.
  final Map<String, dynamic> request;

  /// The secret request fields that were scrubbed from [request] before
  /// persistence (empty when the request carried none). A recovered retry
  /// of such an operation MUST gather fresh values for exactly these
  /// fields — the durable record deliberately cannot replay them.
  final List<String> secretFields;

  /// True when the stored snapshot IS the exact non-secret wire request
  /// (generic exact replay is valid). False when the snapshot is a
  /// synthetic/reduced fingerprint body (e.g. a storefront cart
  /// fingerprint): generic replay would send a materially different
  /// request, so [ApiClient.postFinancialRecovered] FAILS CLOSED for
  /// such instances; recovery happens in the operation's own flow, which
  /// reconstructs its exact request and matches it via [recoverExact].
  final bool replaySafe;

  const DurableOperation({
    required this.operationId,
    required this.type,
    required this.key,
    required this.endpoint,
    required this.fingerprint,
    required this.createdAt,
    required this.account,
    required this.request,
    this.secretFields = const [],
    this.replaySafe = true,
  });
}

// ============================================================================
// EXACT-MATCH PROCESS-DEATH RECOVERY (r42 close-out review, 2026-09-27)
//
// Recovery lookups NEVER guess. They report one of three outcomes:
// ============================================================================

/// The outcome of an exact-fingerprint recovery lookup. The lookup itself
/// never picks: [DurableRecoveryAmbiguous] is a FAIL-CLOSED result — with
/// more than one pending instance of the exact same body, no code path may
/// silently select one.
@immutable
abstract class DurableRecoveryMatch {
  const DurableRecoveryMatch();
}

/// No pending instance of the type matches the reconstructed request: a
/// submit of this request is a GENUINELY NEW operation instance.
class DurableRecoveryNone extends DurableRecoveryMatch {
  const DurableRecoveryNone();
}

/// EXACTLY ONE pending instance matches: this is the recovered operation.
/// Binding its operationId into the flow's FinancialOperationRef resumes
/// THAT instance — same key — on the next submit.
class DurableRecoveryUnique extends DurableRecoveryMatch {
  final DurableOperation operation;
  const DurableRecoveryUnique(this.operation);
}

/// MORE THAN ONE pending instance matches the exact same body. FAIL CLOSED:
/// the caller must surface the candidates explicitly (the user picks the
/// instance) or refuse. Never pick one automatically — not the newest, not
/// the oldest, not by any heuristic.
class DurableRecoveryAmbiguous extends DurableRecoveryMatch {
  final List<DurableOperation> candidates;
  const DurableRecoveryAmbiguous(this.candidates);
}

extension DurableOperationSafeSummary on DurableOperation {
  /// SAFE, non-secret human identification for recovery surfaces
  /// (close-out review 2, finding 5): amount, masked recipient /
  /// destination, target/entity ids — derived ONLY from the scrubbed
  /// durable snapshot, so it can never display credentials.
  String safeSummary() {
    final parts = <String>[];
    final amount = request['amount'];
    if (amount is num) {
      parts.add('${amount % 1 == 0 ? amount.toInt() : amount}');
    }
    for (final k in const ['recipientPhone', 'destination', 'address']) {
      final v = request[k]?.toString();
      if (v == null || v.isEmpty) continue;
      final tail = v.length <= 4 ? v : v.substring(v.length - 4);
      parts.add('to ••••$tail');
      break;
    }
    for (final k in const [
      'escrowId', 'vaultId', 'susuId', 'goalId', 'friendshipId',
      'businessProfileId', 'tradeId', 'walletId', 'groupId',
    ]) {
      final v = request[k]?.toString();
      if (v != null && v.isNotEmpty) {
        parts.add('#${v.length > 10 ? v.substring(0, 10) : v}');
        break;
      }
    }
    if (parts.isEmpty) return type;
    return parts.join(' · ');
  }
}

class DurableOperationRegistry {
  DurableOperationRegistry._();

  /// Storage prefix: `azm.r42.op2.<account>.<operationId>`.
  static const _prefix = 'azm.r42.op2.';

  /// Injectable persistence writer — used by tests to prove the
  /// record-before-request invariant (a failing write must block the
  /// request). Production always writes through SharedPreferences.
  @visibleForTesting
  static Future<void> Function(String slot, String encoded)?
      storageWriterOverride;

  static Future<SharedPreferences> _store() =>
      SharedPreferences.getInstance();

  // -------------------------------------------------------------------------
  // Canonical fingerprinting (unchanged from v1 — the backend agreement on
  // what a "materially different body" means; money values compare by their
  // exact string form, no float arithmetic in the identity path).
  // -------------------------------------------------------------------------

  /// Canonical stable stringify: recursively sorted keys.
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

  static Set<String> _identityFields = {'clientRequestId', 'idempotencyKey'};

  /// EPHEMERAL AUTHENTICATION MATERIAL — never persisted, never
  /// fingerprinted, never displayed. Step-up credentials (password, TOTP,
  /// PIN, ...) authenticate a REQUEST, not the operation's economic
  /// identity: they are stripped from the durable snapshot at begin()
  /// and must be re-supplied freshly on any recovered retry. Fields that
  /// are economic identity (e.g. a susu INVITE token, which identifies
  /// the resource being redeemed and is required for exact replay) are
  /// deliberately NOT in this set.
  static const Set<String> secretFieldsDenylist = {
    'password',
    'currentPassword',
    'newPassword',
    'pin',
    'pinCode',
    'totpToken',
    'otp',
    'otpToken',
    'twoFactorCode',
    'authCode',
    'accessToken',
    'refreshToken',
  };

  /// The non-secret, non-identity view of a request body: the fields that
  /// constitute the operation's ECONOMIC identity.
  static Map<String, dynamic> economicView(Map<String, dynamic> body) {
    return Map<String, dynamic>.from(body)
      ..removeWhere((k, _) =>
          _identityFields.contains(k) || secretFieldsDenylist.contains(k));
  }

  /// Request fingerprint: sha256 over the canonical body form. Fields that
  /// CARRY the identity (clientRequestId / idempotencyKey) are excluded —
  /// they carry the key, so including them would make the fingerprint
  /// self-referential. SECRET fields are excluded too: they are ephemeral
  /// authentication, not economic identity, and are never persisted — so
  /// a fingerprint computed from a body WITH fresh credentials equals the
  /// fingerprint computed from the SCRUBBED snapshot. This is what lets a
  /// recovered step-up operation match its own record.
  static String fingerprintOf(Map<String, dynamic> body) {
    return sha256.convert(utf8.encode(canonical(economicView(body)))).toString();
  }

  // -------------------------------------------------------------------------
  // Storage primitives
  // -------------------------------------------------------------------------

  static String _slot(String account, String operationId) =>
      '$_prefix$account.$operationId';

  static DurableOperation? _decode(String raw, {String? expectAccount}) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final op = DurableOperation(
        operationId: m['op'] as String,
        type: m['type'] as String,
        key: m['key'] as String,
        endpoint: m['e'] as String,
        fingerprint: m['f'] as String,
        createdAt: DateTime.parse(m['t'] as String),
        account: m['acc'] as String,
        request: (m['req'] as Map<String, dynamic>?) ?? const {},
        secretFields:
            (m['sec'] as List<dynamic>?)?.cast<String>() ?? const [],
        replaySafe: (m['rs'] as bool?) ?? true,
      );
      if (expectAccount != null && op.account != expectAccount) return null;
      return op;
    } catch (_) {
      // Corrupt record: fail safe — it is invisible to recovery and retry.
      return null;
    }
  }

  static String _encode(DurableOperation op) => jsonEncode({
        'op': op.operationId,
        'type': op.type,
        'key': op.key,
        'e': op.endpoint,
        'f': op.fingerprint,
        't': op.createdAt.toIso8601String(),
        'acc': op.account,
        'req': op.request,
        'sec': op.secretFields,
        'rs': op.replaySafe,
      });

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// A GENUINELY NEW financial operation instance. Mints a unique
  /// operationId and a fresh key, PERSISTS the record, and returns it.
  /// Never deduplicates — the caller decides when an action is new; the
  /// registry never conflates two begins, however similar their bodies.
  static Future<DurableOperation> begin({
    required String account,
    required String type,
    required String endpoint,
    required Map<String, dynamic> request,
    bool replaySafe = true,
  }) async {
    if (account.trim().isEmpty) {
      throw ArgumentError('account namespace is required (non-empty)');
    }
    if (type.trim().isEmpty) {
      throw ArgumentError('operation type is required (non-empty)');
    }
    // SECRET SCRUBBING (close-out review 2, 2026-09-27): ephemeral
    // credentials never reach persistent storage. The wire request keeps
    // them; the durable record does not.
    final secretFields = <String>[];
    final snapshot = Map<String, dynamic>.from(request);
    for (final k in secretFieldsDenylist) {
      if (snapshot.remove(k) != null) secretFields.add(k);
    }
    final operationId = IdempotencyKey.generate();
    final op = DurableOperation(
      operationId: operationId,
      type: type,
      key: IdempotencyKey.generate(),
      endpoint: endpoint,
      fingerprint: fingerprintOf(request),
      createdAt: DateTime.now(),
      account: account,
      request: snapshot,
      secretFields: secretFields,
      replaySafe: replaySafe,
    );
    // THE invariant: the durable record exists BEFORE the first request
    // is allowed to leave the device. begin() only returns once the write
    // has completed — and if the write fails, the caller never sends.
    final writer = storageWriterOverride;
    if (writer != null) {
      await writer(_slot(account, operationId), _encode(op));
    } else {
      final store = await _store();
      await store.setString(_slot(account, operationId), _encode(op));
    }
    return op;
  }

  /// A retry/reconstruction of ONE existing instance. Returns the SAME
  /// instance (SAME key) when [operationId] is still pending in [account]'s
  /// namespace and [request] matches its recorded fingerprint. Fails closed
  /// otherwise — a materially different request is a genuinely new action
  /// and must be [begin]t explicitly. NEVER mutates, replaces or orphans
  /// the pending instance.
  static Future<DurableOperation> retry(
    String operationId, {
    required String account,
    required Map<String, dynamic> request,
  }) async {
    final store = await _store();
    final raw = store.getString(_slot(account, operationId));
    if (raw == null) {
      throw DurableOperationNotFoundException(operationId);
    }
    final op = _decode(raw, expectAccount: account);
    if (op == null) {
      throw DurableOperationNotFoundException(operationId);
    }
    if (op.fingerprint != fingerprintOf(request)) {
      throw DurableOperationFingerprintMismatchException(operationId);
    }
    return op;
  }

  /// Terminal completion / definitive pre-economic release: removes THAT
  /// instance only. Every other outstanding instance — including other
  /// pending instances of the SAME type — is untouched.
  static Future<void> retire(String operationId,
      {required String account}) async {
    final store = await _store();
    await store.remove(_slot(account, operationId));
  }

  /// Recovery: every unfinished instance, optionally filtered by [account]
  /// namespace, operation [type], and an EXACT [fingerprint] match. Never
  /// assumes a single pending action per type. Newest first.
  ///
  /// The [fingerprint] filter is the exact-instance selector of the
  /// process-death recovery contract (r42 close-out review, 2026-09-27):
  /// recovery must identify the operation INSTANCE whose recorded
  /// fingerprint EXACTLY matches the reconstructed request — never "the
  /// newest pending operation of the type". If the filter matches more
  /// than one instance, the CALLER must fail closed (see [recoverExact])
  /// and never guess.
  static Future<List<DurableOperation>> pending(
      {String? account, String? type, String? fingerprint}) async {
    final store = await _store();
    final results = <DurableOperation>[];
    for (final k in store.getKeys()) {
      if (!k.startsWith(_prefix)) continue;
      final raw = store.getString(k);
      if (raw == null) continue;
      final op = _decode(raw, expectAccount: account);
      if (op == null) continue;
      if (type != null && op.type != type) continue;
      if (fingerprint != null && op.fingerprint != fingerprint) continue;
      results.add(op);
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  // -------------------------------------------------------------------------
  // EXACT-MATCH PROCESS-DEATH RECOVERY (r42 close-out review, 2026-09-27)
  // -------------------------------------------------------------------------

  /// Exact-instance process-death recovery. Given the RECONSTRUCTED request
  /// (the user re-entered the operation's details), finds the pending
  /// instance of [type] in [account]'s namespace whose recorded fingerprint
  /// EXACTLY matches it:
  ///
  ///   DurableRecoveryNone      → nothing outstanding matches: this submit
  ///                              is a genuinely new instance.
  ///   DurableRecoveryUnique    → resume THAT instance (same key).
  ///   DurableRecoveryAmbiguous → several identical unfinished operations:
  ///                              FAIL CLOSED — present them, never guess.
  ///
  /// This replaces the withdrawn v2 `adoptPending` rule ("adopt the newest
  /// pending operation of the type"), which could bind the WRONG instance:
  /// with A (key K1, response lost) and B (key K2, response lost) both
  /// outstanding, newest-only adoption bound B, so the user's reconstruction
  /// of A began a THIRD instance and A's key was orphaned again — the exact
  /// lost-identity bug this registry exists to prevent.
  ///
  /// In-session retries do NOT go through this path: an armed
  /// FinancialOperationRef (postFinancial's retry path, retry(operationId))
  /// remains the AUTHORITATIVE exact-instance route. recoverExact is only
  /// for binding a ref AFTER process death, when no ref survives.
  static Future<DurableRecoveryMatch> recoverExact(
      {required String account,
      required String type,
      required Map<String, dynamic> request}) async {
    final matches = await pending(
        account: account, type: type, fingerprint: fingerprintOf(request));
    if (matches.isEmpty) return const DurableRecoveryNone();
    if (matches.length == 1) return DurableRecoveryUnique(matches.first);
    return DurableRecoveryAmbiguous(matches);
  }

  /// Introspection: ONE instance by id, or null. Account-scoped.
  static Future<DurableOperation?> byId(String operationId,
      {required String account}) async {
    final store = await _store();
    final raw = store.getString(_slot(account, operationId));
    if (raw == null) return null;
    return _decode(raw, expectAccount: account);
  }
}
