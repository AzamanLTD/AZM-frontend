import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/services/deposit_continuations.dart';

class _MemStorage implements FlutterSecureStorage {
  final Map<String, String> store = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final named = invocation.namedArguments;
    switch (invocation.memberName) {
      case #read:
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

class _GatedStorage extends _MemStorage {
  Completer<void>? readGate;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #read &&
        invocation.namedArguments[#key] ==
            'azm.deposit.continuations.ownerIndex') {
      final gate = readGate;
      if (gate != null) {
        readGate = null;
        return gate.future.then((_) async =>
            (await super.noSuchMethod(invocation)) as String?);
      }
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  const ownerIndexKey = 'azm.deposit.continuations.ownerIndex';

  Map<String, dynamic> persistedIndex(_MemStorage storage) =>
      jsonDecode(storage.store[ownerIndexKey] ?? '{}')
          as Map<String, dynamic>;

  test('resolve() removes the owner binding from the PERSISTED index '
      'and a reconstructed service finds no binding for the resolved '
      'reference', () async {
    final storage = _MemStorage();
    final svc = DepositContinuationsService(storage: storage);
    final ctrl = DepositContinuationsController(svc);
    await ctrl.save('user-a', 'DEP-R1');
    await ctrl.save('user-a', 'DEP-R2');
    expect(persistedIndex(storage)['DEP-R1'], 'user-a');

    await ctrl.resolve('user-a', 'DEP-R1');

    final idx = persistedIndex(storage);
    expect(idx.containsKey('DEP-R1'), isFalse,
        reason: 'the resolved reference must leave the persisted index');
    expect(idx['DEP-R2'], 'user-a',
        reason: 'the sibling binding must survive the cleanup');

    final fresh = DepositContinuationsService(storage: storage);
    expect(await fresh.lookupReferenceOwner('DEP-R1'), isNull);
    expect(await fresh.lookupReferenceOwner('DEP-R2'), 'user-a');
  });

  test('resolveIfPresent() (the settlement path) removes the owner '
      'binding from the PERSISTED index too; a no-op resolution for an '
      'absent record never wipes the index', () async {
    final storage = _MemStorage();
    final svc = DepositContinuationsService(storage: storage);
    final ctrl = DepositContinuationsController(svc);
    await ctrl.save('user-a', 'DEP-P1');

    // A foreign reference with no record: resolves nothing and must
    // not touch the persisted index.
    await svc.resolveIfPresent('user-b', 'DEP-NONE');
    expect(persistedIndex(storage)['DEP-P1'], 'user-a');

    await svc.resolveIfPresent('user-a', 'DEP-P1');

    expect(persistedIndex(storage).containsKey('DEP-P1'), isFalse);
    final fresh = DepositContinuationsService(storage: storage);
    expect(await fresh.lookupReferenceOwner('DEP-P1'), isNull);
    expect(await fresh.lookupReferenceOwner('DEP-NONE'), isNull);
  });

  test('a resolution racing ANOTHER reference\'s save keeps the '
      'resolved entry removed from the persisted index while the other '
      'binding survives — both through the same serialized persistence '
      'queue', () async {
    final storage = _MemStorage();
    final svc = DepositContinuationsService(storage: storage);
    final ctrl = DepositContinuationsController(svc);
    await ctrl.save('user-a', 'DEP-X1'); // bound + persisted
    await svc.save('user-b', 'DEP-Y1'); // record only (raw save)

    await Future.wait([
      ctrl.resolve('user-a', 'DEP-X1'),
      ctrl.save('user-b', 'DEP-Y1'), // binds + persists concurrently
    ]);

    final idx = persistedIndex(storage);
    expect(idx.containsKey('DEP-X1'), isFalse,
        reason: 'the resolved binding must STAY removed even when a '
            'concurrent save persists the index');
    expect(idx['DEP-Y1'], 'user-b');

    final fresh = DepositContinuationsService(storage: storage);
    expect(await fresh.lookupReferenceOwner('DEP-X1'), isNull);
    expect(await fresh.lookupReferenceOwner('DEP-Y1'), 'user-b');
  });

  test('shared init: lookups wait for the held read', () async {
    final storage = _GatedStorage();
    final svc = DepositContinuationsService(storage: storage);
    await svc.save('user-a', 'DEP-A9');
    storage.store['azm.deposit.continuations.ownerIndex'] =
        jsonEncode({'DEP-A9': 'user-a'});

    final gate = Completer<void>();
    storage.readGate = gate;

    final lookup = svc.lookupReferenceOwner('DEP-A9');
    // Give the async machinery a beat — the lookup must be pending.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    gate.complete();

    expect(await lookup, 'user-a');
  });
}
