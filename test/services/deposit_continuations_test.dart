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

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        if (value == null) {
          store.remove(key);
        } else {
          store[key] = value;
        }
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
      expect(loaded, hasLength(1),
          reason: 'six hours later the submitted operation still has a '
              'way back — money may be moving under it');
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

    test('resolve is the ONLY deletion path: an unresolved submitted '
        'operation never leaves storage otherwise', () async {
      await service.save(uid, ref);
      // Six hours, many re-saves — the record stays.
      await service.save(uid, ref);
      expect(await service.loadForUser(uid), hasLength(1));

      // Authoritative settlement is the one way out.
      await service.resolve(uid, ref);
      expect(await service.loadForUser(uid), isEmpty);
      expect(storage.store.containsKey('azm.deposit.continuations.$uid'),
          isFalse);
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

      expect(controller.state.userId, otherUid,
          reason: 'the late old-user completion must not steal state');
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
      expect(storage.store.containsKey('azm.deposit.continuations.$uid'),
          isTrue);

      // The same user signs back in: their outstanding continuation is
      // right there again.
      await controller.loadForUser(uid);
      expect(controller.state.userId, uid);
      expect(controller.state.continuations, hasLength(1));
      expect(controller.state.continuations.single.reference, ref);

      // A different account never sees it.
      await controller.loadForUser(otherUid);
      expect(controller.state.continuations, isEmpty,
          reason: 'strict per-user isolation');
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
      expect(storage.store.containsKey('azm.deposit.continuations.$uid'),
          isTrue);

      // Switching back to A reloads exactly A's outstanding record.
      await controller.switchToUser(uid);
      expect(controller.state.userId, uid);
      expect(controller.state.continuations.single.reference, ref);
    });
  });
}
