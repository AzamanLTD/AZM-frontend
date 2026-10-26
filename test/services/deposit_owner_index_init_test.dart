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
