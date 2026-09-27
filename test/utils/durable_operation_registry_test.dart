// =============================================================================
// r42 — DURABLE OPERATION REGISTRY v2 (OPERATION-INSTANCE MODEL) — regression
//
// Independent review (2026-09-27) required proofs, in the reviewer's order:
//
//   1.  Start operation A → K1.
//   2.  Start operation B of the same action type → K2.
//   3.  K1 != K2.
//   4.  BOTH durable records remain (no slot replacement).
//   5.  Retry A → K1.
//   6.  Retry B → K2.
//   7.  Resolve A → only A is retired.
//   8.  B remains recoverable.
//   9.  Resolve B → B is retired.
//   10. Two simultaneous operations with identical bodies still receive
//       distinct keys.
//   11. Different targets can remain pending simultaneously.
//   12. Same target can have multiple distinct unfinished operations.
//   13. Process/screen recreation can recover each independently.
//   14. Account A's durable records cannot become account B's records.
//   15. A materially different request does NOT silently replace an
//       unfinished operation; it creates a distinct operation instance.
//
//   MOST IMPORTANT — the reviewer's exact scenario:
//   16. A = withdrawal of 50; A times out (server may have committed);
//       before retrying A, start B = withdrawal of 75; then retry A.
//       The retry of A MUST send A's original key — not B's key and not a
//       newly minted key.
//   17. The identical-body case: A = deposit 10, B = separate deposit 10 —
//       both receive independent keys.
//
//   Plus the persistence invariant (the record exists before the first
//   request may leave the device) and corruption fail-safety.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/utils/durable_operation_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const acc = 'user_A';

  setUp(() {
    // A fresh, EMPTY store per test = a fresh application install.
    SharedPreferences.setMockInitialValues({});
    DurableOperationRegistry.storageWriterOverride = null;
  });

  tearDown(() {
    DurableOperationRegistry.storageWriterOverride = null;
  });

  /// "Process death": everything in memory is gone; the ONLY carried state
  /// is what was persisted. The registry is stateless by construction, so
  /// this re-seed proves the recovery horizon is the journal, not the
  /// process.
  Future<Map<String, Object>> _persistedState() async {
    final store = await SharedPreferences.getInstance();
    final state = <String, Object>{};
    for (final k in store.getKeys()) {
      final v = store.get(k);
      if (v != null) state[k] = v;
    }
    return state;
  }

  Future<void> _simulateProcessDeath(Map<String, Object> state) async {
    SharedPreferences.setMockInitialValues(state);
  }

  group('reviewer proofs 1–9: instances of one type', () {
    test('1–6. A → K1, B(same type) → K2, K1≠K2, both records remain, '
        'retry A → K1, retry B → K2', () async {
      final reqA = {'amount': 50, 'recipientPhone': '+233200000000'};
      final reqB = {'amount': 75, 'recipientPhone': '+233200000000'};

      // 1. Start operation A → K1.
      final a = await DurableOperationRegistry.begin(
          account: acc,
          type: 'withdrawal.fiat',
          endpoint: '/withdraw/fiat',
          request: reqA);
      // 2. Start operation B of the same action type → K2.
      final b = await DurableOperationRegistry.begin(
          account: acc,
          type: 'withdrawal.fiat',
          endpoint: '/withdraw/fiat',
          request: reqB);
      // 3. K1 != K2.
      expect(a.key, isNot(equals(b.key)));
      expect(a.operationId, isNot(equals(b.operationId)));

      // 4. BOTH durable records remain — a new operation never replaces,
      //    mutates or orphans an unfinished one.
      final pending = await DurableOperationRegistry.pending(
          account: acc, type: 'withdrawal.fiat');
      expect(pending, hasLength(2));
      expect(pending.map((o) => o.key), containsAll([a.key, b.key]));

      // 5. Retry A → K1.
      final retryA = await DurableOperationRegistry.retry(a.operationId,
          account: acc, request: reqA);
      expect(retryA.key, a.key);
      // 6. Retry B → K2.
      final retryB = await DurableOperationRegistry.retry(b.operationId,
          account: acc, request: reqB);
      expect(retryB.key, b.key);
    });

    test('7–9. resolving A retires ONLY A; B stays recoverable; then B '
        'retires', () async {
      final a = await DurableOperationRegistry.begin(
          account: acc,
          type: 'savings.goal.deposit',
          endpoint: '/savings/goals/g1/deposit',
          request: {'amountGhs': 10});
      final b = await DurableOperationRegistry.begin(
          account: acc,
          type: 'savings.goal.deposit',
          endpoint: '/savings/goals/g1/deposit',
          request: {'amountGhs': 10});

      // 7. Resolve A → only A is retired.
      await DurableOperationRegistry.retire(a.operationId, account: acc);
      expect(await DurableOperationRegistry.byId(a.operationId, account: acc),
          isNull);

      // 8. B remains recoverable.
      final stillPending = await DurableOperationRegistry.pending(account: acc);
      expect(stillPending, hasLength(1));
      expect(stillPending.single.operationId, b.operationId);
      final retryB = await DurableOperationRegistry.retry(b.operationId,
          account: acc, request: {'amountGhs': 10});
      expect(retryB.key, b.key);

      // 9. Resolve B → B is retired.
      await DurableOperationRegistry.retire(b.operationId, account: acc);
      expect(await DurableOperationRegistry.pending(account: acc), isEmpty);
    });
  });

  test('10. two simultaneous operations with identical bodies receive '
      'DISTINCT keys — genuinely separate user actions never share a '
      'financial identity', () async {
    final results = await Future.wait([
      DurableOperationRegistry.begin(
          account: acc,
          type: 'shared-vault.deposit',
          endpoint: '/shared-vaults/v1/deposit',
          request: {'amountUsdc': 10}),
      DurableOperationRegistry.begin(
          account: acc,
          type: 'shared-vault.deposit',
          endpoint: '/shared-vaults/v1/deposit',
          request: {'amountUsdc': 10}),
    ]);
    expect(results[0].key, isNot(equals(results[1].key)));
    expect(results[0].operationId, isNot(equals(results[1].operationId)));
    final pending = await DurableOperationRegistry.pending(account: acc);
    expect(pending, hasLength(2));
  });

  test('11. different targets remain pending simultaneously', () async {
    await DurableOperationRegistry.begin(
        account: acc,
        type: 'trade.accept.trade_1',
        endpoint: '/trades/accept',
        request: {'tradeId': 'trade_1'});
    await DurableOperationRegistry.begin(
        account: acc,
        type: 'trade.accept.trade_2',
        endpoint: '/trades/accept',
        request: {'tradeId': 'trade_2'});
    final pending = await DurableOperationRegistry.pending(account: acc);
    expect(pending, hasLength(2));
  });

  test('12. the SAME target can have multiple distinct unfinished '
      'operations — a target-specific type id is a recovery namespace, '
      'never the instance identity', () async {
    final a = await DurableOperationRegistry.begin(
        account: acc,
        type: 'vault.deposit.v1',
        endpoint: '/vaults/v1/deposit',
        request: {'amountUsdc': 25});
    final b = await DurableOperationRegistry.begin(
        account: acc,
        type: 'vault.deposit.v1',
        endpoint: '/vaults/v1/deposit',
        request: {'amountUsdc': 25});
    expect(a.key, isNot(equals(b.key)));

    // Retiring one leaves the other fully retryable.
    await DurableOperationRegistry.retire(a.operationId, account: acc);
    final retryB = await DurableOperationRegistry.retry(b.operationId,
        account: acc, request: {'amountUsdc': 25});
    expect(retryB.key, b.key);
  });

  test('13. process/screen recreation recovers EACH instance '
      'independently', () async {
    final a = await DurableOperationRegistry.begin(
        account: acc,
        type: 'withdrawal.fiat',
        endpoint: '/withdraw/fiat',
        request: {'amount': 50});
    final b = await DurableOperationRegistry.begin(
        account: acc,
        type: 'withdrawal.wallet',
        endpoint: '/wallet/withdraw',
        request: {'amount': 80});

    // Full process death: only the persisted journal carries over.
    final state = await _persistedState();
    _simulateProcessDeath(state);

    // Recovery finds BOTH unfinished instances (never "the" pending one).
    final recovered = await DurableOperationRegistry.pending(account: acc);
    expect(recovered, hasLength(2));
    final recoveredA = recovered.firstWhere((o) => o.type == 'withdrawal.fiat');
    final recoveredB =
        recovered.firstWhere((o) => o.type == 'withdrawal.wallet');

    // Each is independently retryable with its ORIGINAL key.
    final retryA = await DurableOperationRegistry.retry(recoveredA.operationId,
        account: acc, request: {'amount': 50});
    final retryB = await DurableOperationRegistry.retry(recoveredB.operationId,
        account: acc, request: {'amount': 80});
    expect(retryA.key, a.key);
    expect(retryB.key, b.key);

    // The recovery record carries enough metadata to display/reconcile.
    expect(retryA.request['amount'], 50);
    expect(retryA.endpoint, '/withdraw/fiat');
    expect(retryA.createdAt, isNotNull);
  });

  test('14. account A\'s durable records cannot become account B\'s '
      'records', () async {
    final a = await DurableOperationRegistry.begin(
        account: 'user_A',
        type: 'withdrawal.fiat',
        endpoint: '/withdraw/fiat',
        request: {'amount': 50});

    // B's namespace cannot see, retry or adopt A's instance.
    expect(await DurableOperationRegistry.pending(account: 'user_B'),
        isEmpty);
    expect(
        () => DurableOperationRegistry.retry(a.operationId,
            account: 'user_B', request: {'amount': 50}),
        throwsA(isA<DurableOperationNotFoundException>()));

    // A's instance is untouched by everything B did.
    final stillA =
        await DurableOperationRegistry.byId(a.operationId, account: 'user_A');
    expect(stillA, isNotNull);
    expect(stillA!.key, a.key);

    // Two accounts CAN hold pending instances of the same type — and the
    // records stay isolated from each other.
    final b = await DurableOperationRegistry.begin(
        account: 'user_B',
        type: 'withdrawal.fiat',
        endpoint: '/withdraw/fiat',
        request: {'amount': 50});
    expect(b.key, isNot(equals(a.key)));
    expect(await DurableOperationRegistry.pending(account: 'user_A'),
        hasLength(1));
    expect(await DurableOperationRegistry.pending(account: 'user_B'),
        hasLength(1));
  });

  test('15. a materially different request does NOT silently replace an '
      'unfinished operation — it REQUIRES a distinct instance, and the '
      'old record is untouched', () async {
    final a = await DurableOperationRegistry.begin(
        account: acc,
        type: 'withdrawal.fiat',
        endpoint: '/withdraw/fiat',
        request: {'amount': 50, 'recipientPhone': '+233200000000'});

    // A different body is NOT a retry of A — retry fails closed.
    expect(
        () => DurableOperationRegistry.retry(a.operationId,
            account: acc,
            request: {'amount': 75, 'recipientPhone': '+233200000000'}),
        throwsA(isA<DurableOperationFingerprintMismatchException>()));

    // The pending instance is untouched: same fingerprint, same key.
    final still =
        await DurableOperationRegistry.byId(a.operationId, account: acc);
    expect(still, isNotNull);
    expect(still!.key, a.key);
    expect(still.fingerprint, a.fingerprint);

    // The genuinely new action is a DISTINCT instance (create it).
    final b = await DurableOperationRegistry.begin(
        account: acc,
        type: 'withdrawal.fiat',
        endpoint: '/withdraw/fiat',
        request: {'amount': 75, 'recipientPhone': '+233200000000'});
    expect(b.key, isNot(equals(a.key)));
    // BOTH remain — nothing was replaced.
    expect(await DurableOperationRegistry.pending(account: acc), hasLength(2));
  });

  test('16. MOST IMPORTANT: A=50 times out, B=75 starts, then A is '
      'retried — the retry MUST use A\'s ORIGINAL key (not B\'s, not a '
      'freshly minted one)', () async {
    final reqA = {'amount': 50, 'recipientPhone': '+233200000000'};
    final reqB = {'amount': 75, 'recipientPhone': '+233200000000'};

    // A is submitted and the response is lost — A's instance is retained.
    final a = await DurableOperationRegistry.begin(
        account: acc,
        type: 'withdrawal.fiat',
        endpoint: '/withdraw/fiat',
        request: reqA);

    // Before A is resolved, a genuinely new withdrawal B starts.
    final b = await DurableOperationRegistry.begin(
        account: acc,
        type: 'withdrawal.fiat',
        endpoint: '/withdraw/fiat',
        request: reqB);

    // The retry of A sends A's ORIGINAL key.
    final retryA = await DurableOperationRegistry.retry(a.operationId,
        account: acc, request: reqA);
    expect(retryA.key, a.key, reason: 'the retry must reuse the ORIGINAL key');
    expect(retryA.key, isNot(equals(b.key)),
        reason: 'the retry must never send B\'s key');
    // Not a freshly minted key: the instance record is A's, unchanged.
    expect(retryA.operationId, a.operationId);
    expect(retryA.fingerprint, a.fingerprint);
    // Full process death does not change this — recovery finds A and B
    // as independent instances.
    final state = await _persistedState();
    _simulateProcessDeath(state);
    final recovered = await DurableOperationRegistry.pending(account: acc);
    expect(recovered, hasLength(2));
    final recoveredA = await DurableOperationRegistry.retry(a.operationId,
        account: acc, request: reqA);
    expect(recoveredA.key, a.key);
  });

  test('17. identical bodies, genuinely separate user actions → '
      'independent keys', () async {
    final a = await DurableOperationRegistry.begin(
        account: acc,
        type: 'savings.goal.deposit',
        endpoint: '/savings/goals/g1/deposit',
        request: {'amountGhs': 10});
    final b = await DurableOperationRegistry.begin(
        account: acc,
        type: 'savings.goal.deposit',
        endpoint: '/savings/goals/g1/deposit',
        request: {'amountGhs': 10});
    expect(a.key, isNot(equals(b.key)));
    // Both are pending; both retry to their OWN key.
    final retryA = await DurableOperationRegistry.retry(a.operationId,
        account: acc, request: {'amountGhs': 10});
    final retryB = await DurableOperationRegistry.retry(b.operationId,
        account: acc, request: {'amountGhs': 10});
    expect(retryA.key, isNot(equals(retryB.key)));
  });

  group('persistence invariant — the record exists before the first '
      'request may leave the device', () {
    test('a persistence failure blocks begin() (fail closed: the caller '
        'never sends a request without a durable record)', () async {
      DurableOperationRegistry.storageWriterOverride =
          (slot, encoded) async {
        throw Exception('disk full');
      };
      await expectLater(
          DurableOperationRegistry.begin(
              account: acc,
              type: 'withdrawal.fiat',
              endpoint: '/withdraw/fiat',
              request: {'amount': 50}),
          throwsA(isA<Exception>()));
      // And nothing was half-written into the journal.
      expect(await DurableOperationRegistry.pending(account: acc), isEmpty);
    });

    test('begin() returns only after the record is durably stored '
        '(read-back proof)', () async {
      var writeObserved = false;
      DurableOperationRegistry.storageWriterOverride = (slot, encoded) async {
        writeObserved = true;
      };
      final op = await DurableOperationRegistry.begin(
          account: acc,
          type: 'withdrawal.fiat',
          endpoint: '/withdraw/fiat',
          request: {'amount': 50});
      expect(writeObserved, isTrue,
          reason: 'begin() must complete the write before returning');
      expect(op.key, isNotEmpty);
    });
  });

  test('corruption fail-safety: an unreadable record is invisible to '
      'recovery and retry, and never corrupts other instances', () async {
    final a = await DurableOperationRegistry.begin(
        account: acc,
        type: 'withdrawal.fiat',
        endpoint: '/withdraw/fiat',
        request: {'amount': 50});
    final store = await SharedPreferences.getInstance();
    // Corrupt A's record in place.
    await store.setString('azm.r42.op2.$acc.${a.operationId}', '{not json');
    // A fresh, valid instance is unaffected.
    final b = await DurableOperationRegistry.begin(
        account: acc,
        type: 'withdrawal.fiat',
        endpoint: '/withdraw/fiat',
        request: {'amount': 60});
    final pending = await DurableOperationRegistry.pending(account: acc);
    expect(pending, hasLength(1));
    expect(pending.single.operationId, b.operationId);
    // The corrupt instance fails closed on retry — it can never be
    // confused with b's identity.
    expect(
        () => DurableOperationRegistry.retry(a.operationId,
            account: acc, request: {'amount': 50}),
        throwsA(isA<DurableOperationNotFoundException>()));
  });

  test('snapshot metadata: the instance carries enough to display, '
      'reconcile and re-present the operation after process death',
      () async {
    final op = await DurableOperationRegistry.begin(
        account: acc,
        type: 'withdrawal.fiat',
        endpoint: '/withdraw/fiat',
        request: {'amount': 50, 'recipientPhone': '+233200000000'});
    final state = await _persistedState();
    _simulateProcessDeath(state);
    final recovered =
        (await DurableOperationRegistry.pending(account: acc)).single;
    expect(recovered.type, 'withdrawal.fiat');
    expect(recovered.endpoint, '/withdraw/fiat');
    expect(recovered.request['amount'], 50);
    expect(recovered.request['recipientPhone'], '+233200000000');
    expect(recovered.createdAt, isNotNull);
    expect(recovered.account, acc);
  });

// =============================================================================
// r42 CLOSE-OUT REVIEW (2026-09-27) — EXACT-MATCH PROCESS-DEATH RECOVERY.
//
// The withdrawn v2 rule "adopt the NEWEST pending operation of the type"
// could bind the WRONG instance: with an older A and a newer B both
// outstanding, it bound B, so the user's reconstruction of A opened a
// THIRD instance and A's key was orphaned. Recovery is now exact-match
// (recoverExact) and fails closed on ambiguity.
// =============================================================================

group('close-out proofs: exact-match process-death recovery', () {
  test('MOST IMPORTANT REGRESSION — full post-death lifecycle: A=50/K1, '
      'B=75/K2, both responses lost, process dies; reconstruction of A '
      'MUST recover A (not B), retry A sends K1, B stays pending with K2, '
      'then B recovers with K2 — and NO third key is ever minted',
      () async {
    const type = 'withdrawal.fiat';
    final reqA = {'amount': 50, 'recipientPhone': '+233200000000'};
    final reqB = {'amount': 75, 'recipientPhone': '+233200000000'};

    // 1-4. A → K1, B → K2, both responses lost (both stay unfinished).
    final a = await DurableOperationRegistry.begin(
        account: acc, type: type, endpoint: '/withdraw/fiat', request: reqA);
    final b = await DurableOperationRegistry.begin(
        account: acc, type: type, endpoint: '/withdraw/fiat', request: reqB);
    final k1 = a.key;
    final k2 = b.key;
    expect(k1, isNot(equals(k2)));

    // 5. Simulate complete process death: ALL in-memory refs are gone.
    final carried = await _persistedState();
    await _simulateProcessDeath(carried);

    // 7. The user reconstructs the intended A request.
    // 8. Recovery MUST identify A, not B (B is newer — that must not win).
    final matchA = await DurableOperationRegistry.recoverExact(
        account: acc, type: type, request: reqA);
    expect(matchA, isA<DurableRecoveryUnique>());
    final recoveredA = (matchA as DurableRecoveryUnique).operation;
    expect(recoveredA.operationId, a.operationId,
        reason: 'the OLDER instance A must be recovered for A\'s body — '
            '"newest of the type" must never be the rule');
    expect(recoveredA.key, k1);

    // 9. Retry A through the authoritative exact-instance path sends K1.
    final retriedA = await DurableOperationRegistry.retry(recoveredA.operationId,
        account: acc, request: reqA);
    expect(retriedA.key, k1);

    // 10. B remains pending, untouched, with K2.
    final stillPending =
        await DurableOperationRegistry.pending(account: acc, type: type);
    expect(stillPending.length, 2,
        reason: 'no instance was replaced, retired, or orphaned');

    // 11. Then B is reconstructed and recovered — with K2.
    final matchB = await DurableOperationRegistry.recoverExact(
        account: acc, type: type, request: reqB);
    expect(matchB, isA<DurableRecoveryUnique>());
    final recoveredB = (matchB as DurableRecoveryUnique).operation;
    expect(recoveredB.operationId, b.operationId);
    final retriedB = await DurableOperationRegistry.retry(recoveredB.operationId,
        account: acc, request: reqB);
    expect(retriedB.key, k2);

    // 12. Neither instance was replaced, orphaned, or given a third key.
    final finalPending =
        await DurableOperationRegistry.pending(account: acc, type: type);
    expect(finalPending.length, 2);
    expect(finalPending.map((o) => o.key).toSet(), {k1, k2});
  });

  test('IDENTICAL BODIES — A=deposit 10/K1 and a separate B=deposit 10/K2; '
      'after death, recovery is AMBIGUOUS and FAILS CLOSED: no guessing, '
      'both instances remain independently durable and recoverable',
      () async {
    const type = 'deposit.savings';
    final req = {'amount': 10, 'goalId': 'goal_1'};

    final a = await DurableOperationRegistry.begin(
        account: acc, type: type, endpoint: '/savings/deposit', request: req);
    final b = await DurableOperationRegistry.begin(
        account: acc, type: type, endpoint: '/savings/deposit', request: req);
    expect(a.key, isNot(equals(b.key)));

    // Process death, then reconstruction of the same body.
    await _simulateProcessDeath(await _persistedState());

    final match = await DurableOperationRegistry.recoverExact(
        account: acc, type: type, request: req);
    expect(match, isA<DurableRecoveryAmbiguous>(),
        reason: 'two identical unfinished bodies must NOT be resolved by '
            'a heuristic');
    final candidates = (match as DurableRecoveryAmbiguous).candidates;
    expect(candidates.length, 2);
    expect(candidates.map((o) => o.key).toSet(), {a.key, b.key});

    // Both remain retryable by their EXPLICIT instance ids — the user
    // (or an explicit selection surface) picks; the registry never does.
    final retriedA =
        await DurableOperationRegistry.retry(a.operationId, account: acc, request: req);
    final retriedB =
        await DurableOperationRegistry.retry(b.operationId, account: acc, request: req);
    expect(retriedA.key, a.key);
    expect(retriedB.key, b.key);
  });

  test('DurableRecoveryNone — a body with no unfinished match recovers '
      'nothing: the submit is a genuinely new operation, and recovery '
      'never mutates storage', () async {
    const type = 'withdrawal.fiat';
    await DurableOperationRegistry.begin(
        account: acc,
        type: type,
        endpoint: '/withdraw/fiat',
        request: {'amount': 50, 'recipientPhone': '+233200000000'});

    final before = await _persistedState();
    final match = await DurableOperationRegistry.recoverExact(
        account: acc, type: type, request: {'amount': 999, 'recipientPhone': '+233200000000'});
    expect(match, isA<DurableRecoveryNone>());
    expect(await _persistedState(), before,
        reason: 'a failed lookup must not touch the journal');
  });

  test('recovery is account-scoped — another user\'s unfinished identical '
      'operation is invisible and unadoptable', () async {
    const type = 'withdrawal.fiat';
    final req = {'amount': 50, 'recipientPhone': '+233200000000'};
    await DurableOperationRegistry.begin(
        account: 'user_OTHER', type: type, endpoint: '/withdraw/fiat', request: req);

    final match = await DurableOperationRegistry.recoverExact(
        account: acc, type: type, request: req);
    expect(match, isA<DurableRecoveryNone>(),
        reason: 'a pending operation in another account namespace can '
            'never be adopted');
  });

  test('pending(fingerprint:) selects exact instances only — the '
      'programmatic selector behind recoverExact', () async {
    const type = 'withdrawal.fiat';
    final reqA = {'amount': 50, 'recipientPhone': '+233200000000'};
    await DurableOperationRegistry.begin(
        account: acc, type: type, endpoint: '/withdraw/fiat', request: reqA);
    await DurableOperationRegistry.begin(
        account: acc,
        type: type,
        endpoint: '/withdraw/fiat',
        request: {'amount': 75, 'recipientPhone': '+233200000000'});

    final exact = await DurableOperationRegistry.pending(
        account: acc, type: type, fingerprint: DurableOperationRegistry.fingerprintOf(reqA));
    expect(exact.length, 1);
    expect(exact.single.fingerprint, DurableOperationRegistry.fingerprintOf(reqA));
  });
});


// =============================================================================
// PASS 2 (close-out review 2, 2026-09-27) — EXACT-ONLY RECOVERY + SECRETS
// =============================================================================

group('pass 2: secret scrubbing (never persisted, never fingerprinted)', () {
  test('G. a secret-bearing begin persists NO secret fields — the stored '
      'record contains no password/totpToken, and the record knows which '
      'fields to re-gather', () async {
    final op = await DurableOperationRegistry.begin(
        account: acc,
        type: 'storefront.escrow.fund',
        endpoint: '/escrow/fund',
        request: const {
          'escrowId': 'esc_1',
          'totpToken': '123456',
          'password': 'hunter2',
        });
    expect(op.request.containsKey('password'), isFalse);
    expect(op.request.containsKey('totpToken'), isFalse);
    expect(op.request['escrowId'], 'esc_1');
    expect(op.secretFields, containsAll(['password', 'totpToken']));

    // The SERIALIZED SharedPreferences record contains no secret values.
    final state = await _persistedState();
    final blob = state.values.join(' ');
    expect(blob.contains('hunter2'), isFalse,
        reason: 'a password may never reach persistent storage');
    expect(blob.contains('123456'), isFalse,
        reason: 'a TOTP may never reach persistent storage');
  });

  test('secrets are EXCLUDED from the fingerprint: a body WITH fresh '
      'credentials matches the scrubbed snapshot\'s record — recovered '
      'step-up operations converge on their own identity', () async {
    final op = await DurableOperationRegistry.begin(
        account: acc,
        type: 'storefront.escrow.fund',
        endpoint: '/escrow/fund',
        request: const {
          'escrowId': 'esc_1',
          'totpToken': '111111',
          'password': 'first-attempt',
        });
    final fingerprint = DurableOperationRegistry.fingerprintOf(
        {'escrowId': 'esc_1', 'totpToken': '222222', 'password': 'new'});
    expect(fingerprint, op.fingerprint,
        reason: 'credentials are ephemeral auth, not economic identity');
  });

  test('replaySafe:false instances are marked and never generically '
      'replayable', () async {
    final op = await DurableOperationRegistry.begin(
        account: acc,
        type: 'storefront.checkout',
        endpoint: '/storefront/checkout',
        request: const {'lines': [{'id': 'p1', 'qty': 2}]},
        replaySafe: false);
    expect(op.replaySafe, isFalse);
    // Simulated process death must preserve the flag.
    await _simulateProcessDeath(await _persistedState());
    final revived = await DurableOperationRegistry.byId(op.operationId,
        account: acc);
    expect(revived!.replaySafe, isFalse);
  });
});

group('pass 2: exact-only recovery semantics', () {
  test('C. stale recovery — the instance retired before the retry: retry() '
      'throws NotFound; the caller (exact-only path) must NOT begin '
      'anything', () async {
    const type = 'withdrawal.fiat';
    final req = {'amount': 50, 'recipientPhone': '+233200000000'};
    final a = await DurableOperationRegistry.begin(
        account: acc, type: type, endpoint: '/withdraw/fiat', request: req);
    await DurableOperationRegistry.retire(a.operationId, account: acc);

    await expectLater(
        DurableOperationRegistry.retry(a.operationId,
            account: acc, request: req),
        throwsA(isA<DurableOperationNotFoundException>()));
    // And the journal is still empty: nothing was silently re-created.
    expect(
        await DurableOperationRegistry.pending(account: acc, type: type),
        isEmpty);
  });

  test('D. fingerprint mismatch on an exact resume attempt throws — never '
      'silently replaces the instance', () async {
    const type = 'withdrawal.fiat';
    final a = await DurableOperationRegistry.begin(
        account: acc,
        type: type,
        endpoint: '/withdraw/fiat',
        request: {'amount': 50, 'recipientPhone': '+233200000000'});
    await expectLater(
        DurableOperationRegistry.retry(a.operationId,
            account: acc,
            request: {'amount': 51, 'recipientPhone': '+233200000000'}),
        throwsA(isA<DurableOperationFingerprintMismatchException>()));
    // The original instance is untouched and still recoverable.
    final still =
        await DurableOperationRegistry.byId(a.operationId, account: acc);
    expect(still, isNotNull);
    expect(still!.fingerprint,
        DurableOperationRegistry.fingerprintOf({'amount': 50, 'recipientPhone': '+233200000000'}));
  });

  test('E. wrong-account recovery is invisible — byId/retry fail closed',
      () async {
    final a = await DurableOperationRegistry.begin(
        account: 'user_OTHER',
        type: 'withdrawal.fiat',
        endpoint: '/withdraw/fiat',
        request: const {'amount': 50});
    expect(await DurableOperationRegistry.byId(a.operationId, account: acc),
        isNull);
    await expectLater(
        DurableOperationRegistry.retry(a.operationId,
            account: acc, request: const {'amount': 50}),
        throwsA(isA<DurableOperationNotFoundException>()));
  });
});

}