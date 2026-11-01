// =============================================================================
// SUBMITTED-DEPOSIT CONTINUATIONS (PR #202 review gap 3) — the separate
// persisted lifecycle for a deposit the user already instructed.
//
// Contract pinned by this suite:
//   * a submitted reference persists with NO five-minute clock — it
//     outlives the form-draft TTL many times over;
//   * save is an idempotent upsert per (user, reference);
//   * the record leaves storage ONLY on authoritative resolution
//     (settled/failed) — never on an expiry sweep;
//   * records are user-scoped and cleared on logout/account switch;
//   * the controller's generation guard discards stale storage reads
//     across logout and account switches.
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/services/deposit_continuations.dart';

/// Held reads work as: holdNextRead() parks a completer; the NEXT
/// storage read consumes it (synchronously, via noSuchMethod) and parks
/// it in [_active]; release([value]) completes the oldest one. This is
/// what makes "the old user's request resolves AFTER the new user's
/// load" an observable interleaving.
class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> store = {};
  final List<Completer<String?>> _held = [];
  final List<Completer<String?>> _active = [];

  /// FINAL REVIEW — deterministic WRITE interleaving: when set, the
  /// next write reports [writeStarted] and its effect lands only when
  /// the test completes the gate. This is how the race tests freeze a
  /// mutation mid-flight and let a settlement arrive behind it.
  Completer<void>? writeGate;
  final Completer<void> writeStarted = Completer<void>();

  void holdNextRead() => _held.add(Completer<String?>());

  void release([String? value]) {
    final c = _active.isNotEmpty
        ? _active.removeAt(0)
        : (_held.isNotEmpty ? _held.removeAt(0) : null);
    c?.complete(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final named = invocation.namedArguments;
    switch (invocation.memberName) {
      case #read:
        if (_held.isNotEmpty) {
          final c = _held.removeAt(0);
          _active.add(c);
          return c.future;
        }
        return Future.value(store[named[#key] as String]);
      case #write:
        final key = named[#key] as String;
        final value = named[#value] as String?;
        void land() {
          if (value == null) {
            store.remove(key);
          } else {
            store[key] = value;
          }
        }

        final gate = writeGate;
        if (gate != null) {
          writeGate = null;
          if (!writeStarted.isCompleted) writeStarted.complete();
          return gate.future.then((_) => land());
        }
        land();
        return Future.value();
      case #delete:
        store.remove(named[#key] as String);
        return Future.value();
      case #deleteAll:
        store.clear();
        return Future.value();
      default:
        throw UnimplementedError('${invocation.memberName}');
    }
  }
}

void main() {
  late _FakeSecureStorage storage;
  late DepositContinuationsService service;
  const uid = 'user-1';
  const otherUid = 'user-2';
  const ref = 'MOOLRE_DEP_12_1712345678_a1b2c3d4';

  setUp(() {
    storage = _FakeSecureStorage();
    service = DepositContinuationsService(storage: storage);
  });

  group('DepositContinuationsService', () {
    test('a submitted reference survives far beyond the five-minute '
        'form-draft TTL — there is NO expiry sweep', () async {
      final savedAt = DateTime.now()
          .subtract(const Duration(hours: 6))
          .millisecondsSinceEpoch;
      storage.store['azm.deposit.continuations.$uid'] = jsonEncode([
        {'id': '$uid.$ref', 'reference': ref, 'savedAtMs': savedAt},
      ]);

      final loaded = await service.loadForUser(uid);
      expect(
        loaded,
        hasLength(1),
        reason:
            'six hours later the submitted operation still has a '
            'way back — money may be moving under it',
      );
      expect(loaded.single.reference, ref);
    });

    test('save is an idempotent upsert: repeated saves of the same '
        'reference produce ONE continuation', () async {
      await service.save(uid, ref);
      await service.save(uid, ref);
      await service.save(uid, ref);

      final loaded = await service.loadForUser(uid);
      expect(loaded, hasLength(1));
      expect(loaded.single.reference, ref);
    });

    test('resolve removes exactly the referenced operation', () async {
      await service.save(uid, 'MOOLRE_DEP_A');
      await service.save(uid, 'MOOLRE_DEP_B');
      await service.resolve(uid, 'MOOLRE_DEP_A');

      final loaded = await service.loadForUser(uid);
      expect(loaded.map((c) => c.reference), ['MOOLRE_DEP_B']);
    });

    test('continuations are user-scoped: no cross-user bleed', () async {
      await service.save(uid, ref);
      expect(await service.loadForUser(otherUid), isEmpty);
    });

    test(
      'REVIEW FOLLOW-UP — resolution is OWNER-SCOPED: resolving under a '
      'different user never removes the initiating owner\'s record',
      () async {
        await service.save(uid, ref);
        // A resolution executed with the WRONG identity (an account
        // switched before the ledger answered) must not touch the
        // initiating owner's storage.
        await service.resolve(otherUid, ref);
        expect(
          await service.loadForUser(uid),
          hasLength(1),
          reason:
              "B's resolution must never remove A's stored "
              'continuation',
        );

        // Only the initiating owner's own resolution removes their record.
        await service.resolve(uid, ref);
        expect(await service.loadForUser(uid), isEmpty);
      },
    );

    test('resolve is the ONLY deletion path: an unresolved submitted '
        'operation never leaves storage otherwise', () async {
      await service.save(uid, ref);
      // Six hours, many re-saves — the record stays.
      await service.save(uid, ref);
      expect(await service.loadForUser(uid), hasLength(1));

      // Authoritative settlement is the one way out.
      await service.resolve(uid, ref);
      expect(await service.loadForUser(uid), isEmpty);
      expect(
        storage.store.containsKey('azm.deposit.continuations.$uid'),
        isFalse,
      );
    });

    test('a corrupt blob reads as empty, never throws', () async {
      storage.store['azm.deposit.continuations.$uid'] = 'not json';
      expect(await service.loadForUser(uid), isEmpty);
    });

    test('a blank reference is never persisted', () async {
      await service.save(uid, '   ');
      expect(storage.store, isEmpty);
    });
  });

  group('DepositContinuationsController', () {
    test('save -> load -> resolve lifecycle for the active user', () async {
      final controller = DepositContinuationsController(service);
      addTearDown(controller.dispose);

      await controller.loadForUser(uid);
      await controller.save(uid, ref);
      expect(controller.state.continuations, hasLength(1));
      expect(controller.state.continuations.single.reference, ref);

      await controller.resolve(uid, ref);
      expect(controller.state.continuations, isEmpty);
    });

    test("generation guard: an old user's read resolving after the new "
        "user's load publishes nothing", () async {
      final controller = DepositContinuationsController(service);
      addTearDown(controller.dispose);

      storage.holdNextRead();
      final stale = controller.loadForUser(uid);

      await controller.loadForUser(otherUid);
      expect(controller.state.userId, otherUid);
      expect(controller.state.continuations, isEmpty);

      storage.release();
      await stale;

      expect(
        controller.state.userId,
        otherUid,
        reason: 'the late old-user completion must not steal state',
      );
      expect(controller.state.continuations, isEmpty);
    });

    test('clearForLogout (REVIEW FOLLOW-UP P1) clears in-memory state '
        'but PRESERVES the stored record — logging out neither cancels '
        'nor resolves a submitted instruction', () async {
      final controller = DepositContinuationsController(service);
      addTearDown(controller.dispose);

      await controller.loadForUser(uid);
      await controller.save(uid, ref);
      expect(controller.state.continuations, hasLength(1));

      await controller.clearForLogout();
      expect(controller.state.userId, isNull);
      expect(controller.state.continuations, isEmpty);
      // The storage record SURVIVES the logout.
      expect(
        storage.store.containsKey('azm.deposit.continuations.$uid'),
        isTrue,
      );

      // The same user signs back in: their outstanding continuation is
      // right there again.
      await controller.loadForUser(uid);
      expect(controller.state.userId, uid);
      expect(controller.state.continuations, hasLength(1));
      expect(controller.state.continuations.single.reference, ref);

      // A different account never sees it.
      await controller.loadForUser(otherUid);
      expect(
        controller.state.continuations,
        isEmpty,
        reason: 'strict per-user isolation',
      );
    });

    test('clearForLogout bumps the generation: a stale in-flight read '
        "cannot repopulate the outgoing user's state", () async {
      final controller = DepositContinuationsController(service);
      addTearDown(controller.dispose);

      await controller.save(uid, ref);
      storage.holdNextRead();
      final stale = controller.loadForUser(uid);

      await controller.clearForLogout();
      expect(controller.state.userId, isNull);

      storage.release();
      await stale;
      expect(controller.state.userId, isNull);
      expect(controller.state.continuations, isEmpty);
    });

    test('switchToUser (REVIEW FOLLOW-UP P1) drops the outgoing user '
        'immediately, loads the incoming user, and preserves the '
        "outgoing user's stored records", () async {
      final controller = DepositContinuationsController(service);
      addTearDown(controller.dispose);

      // user A has an outstanding submitted deposit.
      await service.save(uid, ref);
      await controller.loadForUser(uid);
      expect(controller.state.continuations, hasLength(1));

      // A DIRECT switch to B (no logout): B's state lands, A's records
      // are gone from memory the moment the boundary is crossed.
      await controller.switchToUser(otherUid);
      expect(controller.state.userId, otherUid);
      expect(controller.state.continuations, isEmpty);

      // A delayed read that A started before the switch resolves into
      // the void — it can never repopulate A's records.
      // (Covered structurally by the generation bump; the stale-read
      // interleaving is pinned in the generation-guard test above.)

      // A's STORED record is preserved across the switch.
      expect(
        storage.store.containsKey('azm.deposit.continuations.$uid'),
        isTrue,
      );

      // Switching back to A reloads exactly A's outstanding record.
      await controller.switchToUser(uid);
      expect(controller.state.userId, uid);
      expect(controller.state.continuations.single.reference, ref);
    });
  });

  // ── FINAL REVIEW: serialized mutations + terminal resolution ────────────

  group('FINAL REVIEW — serialized per-user mutations and terminal '
      'resolution', () {
    DepositContinuationsService svc({required _FakeSecureStorage store}) =>
        DepositContinuationsService(storage: store);

    Future<List<String>> refs(DepositContinuationsService s, String u) async =>
        [for (final c in await s.loadForUser(u)) c.reference];

    test('a socket settlement arriving while the INITIAL continuation '
        'save is still in flight cannot be overwritten by the save\'s '
        'late write, and sibling records are preserved', () async {
      final storage = _FakeSecureStorage();
      final service = svc(store: storage);

      // An earlier, still-unresolved operation for the same user.
      await service.save('user-a', 'DEP-EARLIER');

      // Freeze the initial save MID-WRITE (the exact window in which a
      // socket settlement can arrive behind it).
      final gate = Completer<void>();
      storage.writeGate = gate;
      final inFlightSave = service.save('user-a', 'DEP-SETTLE-1');
      await storage.writeStarted.future; // the save is now at its write

      // The ledger settles the operation while the save is in flight.
      final settlement = service.resolve('user-a', 'DEP-SETTLE-1');

      // The held write finally lands — LAST, exactly the ordering that
      // used to resurrect the settled reference.
      gate.complete();
      await inFlightSave;
      await settlement;

      expect(
        await refs(service, 'user-a'),
        ['DEP-EARLIER'],
        reason:
            'the settled reference must NOT be resurrected by its '
            'own late write, and the unrelated sibling must survive',
      );
    });

    test('a resolution racing an OTP-confirm re-save is terminal in BOTH '
        'enqueue orders — the stale re-save can never resurrect it', () async {
      final storage = _FakeSecureStorage();
      final service = svc(store: storage);
      await service.save('user-a', 'DEP-OTP-CONFIRM');

      // Order 1: the settlement enqueues first, the stale confirm
      // re-save lands behind it.
      final settle = service.resolve('user-a', 'DEP-OTP-CONFIRM');
      final resave = service.save('user-a', 'DEP-OTP-CONFIRM');
      await settle;
      await resave;
      expect(
        await refs(service, 'user-a'),
        isEmpty,
        reason: 'a re-save enqueued AFTER resolution is a no-op',
      );

      // Order 2: the stale re-save enqueues first, the settlement
      // lands behind it — the reference still ends resolved.
      await service.save('user-a', 'DEP-OTP-CONFIRM-2');
      final resave2 = service.save('user-a', 'DEP-OTP-CONFIRM-2');
      final settle2 = service.resolve('user-a', 'DEP-OTP-CONFIRM-2');
      await resave2;
      await settle2;
      expect(
        await refs(service, 'user-a'),
        isEmpty,
        reason: 'resolution behind a racing save still wins',
      );
    });

    test(
      'a RETRY attempting to save a reference after its authoritative '
      'resolution is a no-op, and terminality is PER-REFERENCE only',
      () async {
        final storage = _FakeSecureStorage();
        final service = svc(store: storage);

        await service.save('user-a', 'DEP-RESOLVED');
        await service.resolve('user-a', 'DEP-RESOLVED');
        expect(await refs(service, 'user-a'), isEmpty);

        // The retry (user taps "Save receipt" again) — must not resurrect.
        await service.save('user-a', 'DEP-RESOLVED');
        expect(
          await refs(service, 'user-a'),
          isEmpty,
          reason:
              'resolution is terminal: a later retry never '
              'resurrects the reference',
        );

        // Terminality never bleeds into other, valid operations.
        await service.save('user-a', 'DEP-NEW-OP');
        expect(
          await refs(service, 'user-a'),
          ['DEP-NEW-OP'],
          reason:
              'an unrelated reference saves normally after another '
              'one resolved',
        );
      },
    );

    test('CONCURRENT mutations to separate references of the same user '
        'lose NEITHER record', () async {
      final storage = _FakeSecureStorage();
      final service = svc(store: storage);

      final f1 = service.save('user-a', 'DEP-A');
      final f2 = service.save('user-a', 'DEP-B');
      final f3 = service.save('user-a', 'DEP-C');
      await Future.wait([f1, f2, f3]);

      expect(
        await refs(service, 'user-a'),
        containsAll(['DEP-A', 'DEP-B', 'DEP-C']),
      );
      expect(
        (await service.loadForUser('user-a')),
        hasLength(3),
        reason:
            'unserialized load-modify-write used to let the last '
            'write drop the siblings',
      );
    });

    test('a settlement resolving one reference while another is being '
        'saved preserves the OTHER record', () async {
      final storage = _FakeSecureStorage();
      final service = svc(store: storage);
      await service.save('user-a', 'DEP-OLD');

      final settle = service.resolve('user-a', 'DEP-OLD');
      final fresh = service.save('user-a', 'DEP-FRESH');
      await Future.wait([settle, fresh]);

      expect(
        await refs(service, 'user-a'),
        ['DEP-FRESH'],
        reason:
            'the resolved record is gone, the concurrently-saved '
            'one survives',
      );
    });

    test('different users never queue behind each other and never bleed '
        'records', () async {
      final storage = _FakeSecureStorage();
      final service = svc(store: storage);

      final fa = service.save('user-a', 'DEP-X');
      final fb = service.save('user-b', 'DEP-X');
      await Future.wait([fa, fb]);

      expect(await refs(service, 'user-a'), ['DEP-X']);
      expect(await refs(service, 'user-b'), ['DEP-X']);
      // Resolving under one user never touches the other user's record.
      await service.resolve('user-a', 'DEP-X');
      expect(await refs(service, 'user-a'), isEmpty);
      expect(await refs(service, 'user-b'), ['DEP-X']);
    });
  });
}
