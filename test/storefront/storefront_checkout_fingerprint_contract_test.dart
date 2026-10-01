// =============================================================================
// RETAIL CHECKOUT RECOVERY — deep-dive step 3: cross-repo fingerprint
// contract proof.
//
// The durable checkout's convergence guarantee rests on ONE contract:
//
//   a same-key retry is an EXACT REPLAY server-side.
//
// The client reuses a durable key only when ITS fingerprint matches
// (DurableOperationRegistry.fingerprintOf — sha256 over the canonical
// ECONOMIC view, identity fields stripped). The backend answers 200
// idempotent only when ITS fingerprint matches (AZM-backend
// utils/storefrontOrderIdentity.js checkoutFingerprint — sha256 over a
// fixed projection of the request). The contract holds iff:
//
//   client-fingerprint-equal  ⇒  backend-fingerprint-equal
//
// If that implication ever broke, a lost-response retry would collide as a
// 409 domainConflict instead of converging — the exact failure class the
// recovery architecture exists to prevent.
//
// This suite proves the contract EXECUTABLY, three ways:
//
//   1. KNOWN-ANSWER VECTORS — produced by the REAL backend module
//      (node utils/storefrontOrderIdentity.js @ AZM-backend commit
//      d7dd53c4319dc45c39a3d04cd682d40e2e49f616). The Dart mirror below
//      must reproduce them byte-for-byte, so the mirror is not a
//      re-interpretation — it is pinned to the backend implementation at
//      a recorded commit. If the backend algorithm drifts, this test
//      fails and forces a cross-repo contract review.
//   2. EQUIVALENCE-CLASS PARITY — for the production wire field set,
//      every body pair with equal client fingerprints has equal backend
//      mirror fingerprints (the critical implication).
//   3. DIVERGENCE CATALOG — the directions where the two fingerprints
//      disagree are enumerated and pinned to the SAFE side: the client
//      is strictly FINER. A client-finer divergence mints a NEW durable
//      key (a fresh logical operation — harmless); a backend-finer
//      divergence would break convergence and must never exist.
//
// The traced production wire (CartScreen → checkoutCart) carries exactly:
// items[{productId, quantity, notes?, variants?}], customerNotes?,
// deliveryNotes?, paymentMode, idempotencyKey — and the backend
// checkoutFingerprint projection covers every persisted, order-
// determining field of that set (businessProfileId and customerId are
// identity — carried by the scoped key and the composite unique, not the
// fingerprint). See the deep-dive doc, "Step 3 outcome".
// =============================================================================

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/utils/durable_operation_registry.dart';

// ── Dart mirror of the backend fingerprint implementation
// (utils/storefrontOrderIdentity.js @ d7dd53c). Pinned byte-for-byte by
// the known-answer vectors in the group below — do not "fix" this mirror
// without re-deriving the vectors from the real backend module. ──────────

/// Mirror of stableJson: map keys sorted, array order preserved, scalars
/// via JSON.stringify semantics (jsonEncode is byte-identical for the
/// JSON-representable values this contract handles).
String _stableJson(Object? value) {
  if (value == null || (value is! Map && value is! List)) {
    return jsonEncode(value);
  }
  if (value is List) return '[${value.map(_stableJson).join(',')}]';
  final keys = (value as Map).keys.map((k) => k.toString()).toList()..sort();
  return '{${keys.map((k) => '"$k":${_stableJson(value[k])}').join(',')}}';
}

String _sha256Hex(String value) =>
    crypto.sha256.convert(utf8.encode(value)).toString();

/// Mirror of checkoutFingerprint: the fixed projection of the checkout
/// request — items (productId, quantity, notes ?? null, variants ?? {}),
/// customerNotes ?? null, deliveryNotes ?? null, paymentMode normalized
/// to upper case with '' / absent → 'DIRECT'.
String _mirrorCheckoutFingerprint(Map<String, dynamic> body) {
  final items = (body['items'] as List? ?? [])
      .map((raw) {
        final item = raw as Map<String, dynamic>;
        return <String, dynamic>{
          'productId': item['productId'],
          'quantity': item['quantity'],
          'notes': item['notes'],
          'variants': item['variants'] ?? <String, dynamic>{},
        };
      })
      .toList();
  final rawMode = body['paymentMode'];
  final mode =
      (rawMode == null || rawMode == '' ? 'DIRECT' : rawMode.toString())
          .toUpperCase();
  return _sha256Hex(_stableJson(<String, dynamic>{
    'items': items,
    'customerNotes': body['customerNotes'],
    'deliveryNotes': body['deliveryNotes'],
    'paymentMode': mode,
  }));
}

/// Mirror of orderFingerprint: the single-item /order projection —
/// productId, quantity, customerNotes ?? null, deliveryNotes ?? null.
String _mirrorOrderFingerprint(Map<String, dynamic> body) {
  return _sha256Hex(_stableJson(<String, dynamic>{
    'productId': body['productId'],
    'quantity': body['quantity'],
    'customerNotes': body['customerNotes'],
    'deliveryNotes': body['deliveryNotes'],
  }));
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

// The exact cart body shape CartScreen sends (cartProvider.toCheckoutItems
// + checkoutCart's body construction), with a durable key attached.
Map<String, dynamic> _checkoutBodyA() => {
      'items': [
        {'productId': 'p1', 'quantity': 2},
        {
          'productId': 'p2',
          'quantity': 1,
          'notes': 'extra hot',
          'variants': {'Size': 'Large'}
        },
      ],
      'customerNotes': 'call on arrival',
      'deliveryNotes': null,
      'paymentMode': 'DIRECT',
      'idempotencyKey': 'v1:biz-001:user-1:abc',
    };

// ── Known-answer vectors, produced by the REAL backend module ───────────
// node -e "require('./utils/storefrontOrderIdentity.js')" @ d7dd53c.
// If a vector changes after a backend edit, the backend fingerprint
// algorithm drifted: re-run the cross-repo contract review.
const _backendCommit = 'd7dd53c4319dc45c39a3d04cd682d40e2e49f616';

const _vecCheckoutA =
    '325965d819b3599193d9f985a97c0cba7cd1837e96245d450f58372aab73aa7e';
const _vecCheckoutB =
    'a2f650e754fc2e3cb3d56e587f8d3f9dfcd369a7a0dc4dd2fb6e230dd9794fe7';
const _vecCheckoutBReorder =
    '899058a4395cb84ce43d0766cf6925957d72776b7d02f0bb3b61a8a6309b0c77';
const _vecCheckoutBOrdered =
    '07f658c51e7cbdb2ebf5a4e7b5d8653a87e2d73d0556838a0e24ba54e7e2296f';
const _vecOrderA =
    '52358ce9cf961c8ed92efee9156181b24d5882b2ce05db038438d4510753efac';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('known-answer vectors — the Dart mirror IS the backend algorithm (@ $_backendCommit)', () {
    test('checkoutFingerprint reproduces the backend digests byte-for-byte', () {
      final a = _checkoutBodyA();
      expect(_mirrorCheckoutFingerprint(a), _vecCheckoutA);

      // The single-item cart with paymentMode, vs the same cart without
      // the field entirely (backend normalizes absent → 'DIRECT').
      final b = {
        'items': [
          {'productId': 'p1', 'quantity': 3}
        ],
        'paymentMode': 'DIRECT',
      };
      expect(_mirrorCheckoutFingerprint(b), _vecCheckoutB);
      expect(_mirrorCheckoutFingerprint({..._deepCopy(b)}..remove('paymentMode')),
          _vecCheckoutB,
          reason: 'absent paymentMode must hash identically to DIRECT');

      // Item order is MATERIAL on the backend (array order preserved).
      final reorder = {
        'items': [
          {'productId': 'p1', 'quantity': 3},
          {'productId': 'p0', 'quantity': 1},
        ],
        'paymentMode': 'DIRECT',
      };
      final ordered = {
        'items': [
          {'productId': 'p0', 'quantity': 1},
          {'productId': 'p1', 'quantity': 3},
        ],
        'paymentMode': 'DIRECT',
      };
      expect(_mirrorCheckoutFingerprint(reorder), _vecCheckoutBReorder);
      expect(_mirrorCheckoutFingerprint(ordered), _vecCheckoutBOrdered);
      expect(reorder['items'], isNot(equals(ordered['items'])),
          reason: 'sanity: the two bodies really differ');
    });

    test('orderFingerprint reproduces the backend digest', () {
      expect(
          _mirrorOrderFingerprint(
              {'productId': 'p1', 'quantity': 2, 'customerNotes': 'x'}),
          _vecOrderA);
    });
  });

  group('equivalence-class parity — client-fingerprint-equal ⇒ backend-fingerprint-equal', () {
    test('the identity carrier never participates in EITHER fingerprint', () {
      {
        // Same economic body, different durable key: both fingerprints must
        // ignore the key — this is the exclusion that makes a same-key
        // retry byte-clean on both sides of the contract.
        final base = _checkoutBodyA();
        final keyChanged = _deepCopy(base);
        keyChanged['idempotencyKey'] = 'COMPLETELY-DIFFERENT-KEY';

        expect(
          DurableOperationRegistry.fingerprintOf(base),
          DurableOperationRegistry.fingerprintOf(keyChanged),
          reason: 'the client fingerprint must ignore the durable key',
        );
        expect(
          _mirrorCheckoutFingerprint(base),
          _mirrorCheckoutFingerprint(keyChanged),
          reason: 'and so must the backend fingerprint',
        );
      }
    });

    test('every backend-covered field is client-covered too (no backend-finer divergence)', () {
      final mutations = <String, void Function(Map<String, dynamic>)>{
        'item productId': (b) => (b['items'] as List)[0]['productId'] = 'pX',
        'item quantity': (b) => (b['items'] as List)[0]['quantity'] = 99,
        'item notes': (b) => (b['items'] as List)[0]['notes'] = 'changed',
        'item variants': (b) => (b['items'] as List)[1]['variants'] = {'Size': 'Small'},
        'item added': (b) => (b['items'] as List).add({
              'productId': 'p9',
              'quantity': 1,
            }),
        'item order': (b) => (b['items'] as List).insert(
            0, (b['items'] as List).removeAt(1)),
        'customerNotes': (b) => b['customerNotes'] = 'changed',
        'deliveryNotes': (b) => b['deliveryNotes'] = 'changed',
        'paymentMode': (b) => b['paymentMode'] = 'ESCROW',
      };

      for (final entry in mutations.entries) {
        final base = _checkoutBodyA();
        final mutated = _deepCopy(base);
        entry.value(mutated);

        expect(
          DurableOperationRegistry.fingerprintOf(base),
          isNot(equals(DurableOperationRegistry.fingerprintOf(mutated))),
          reason: '${entry.key}: the CLIENT must see this as materially '
              'different (it determines key reuse)',
        );
        expect(
          _mirrorCheckoutFingerprint(base),
          isNot(equals(_mirrorCheckoutFingerprint(mutated))),
          reason: '${entry.key}: and the BACKEND projection covers it (it '
              'determines exact-replay vs 409)',
        );
      }
    });

    test('documented client-stricter divergences are safe-direction only', () {
      final base = _checkoutBodyA();

      // paymentMode cosmetic case: the backend normalizes it away; the
      // client treats the raw value as material. Client-stricter is SAFE:
      // the changed retry mints a NEW durable key, so it can never
      // collide with the old instance as a 409.
      final modeLower = _deepCopy(base);
      modeLower['paymentMode'] = 'direct';
      expect(
        DurableOperationRegistry.fingerprintOf(base),
        isNot(equals(DurableOperationRegistry.fingerprintOf(modeLower))),
        reason: 'client fingerprint is raw (finer)',
      );
      expect(
        _mirrorCheckoutFingerprint(base),
        _mirrorCheckoutFingerprint(modeLower),
        reason: 'backend fingerprint normalizes case (coarser) — the safe '
            'divergence direction',
      );
    });

    test('the single-item /order body shares the same parity', () {
      final base = {
        'productId': 'p1',
        'quantity': 2,
        'customerNotes': 'x',
        'deliveryNotes': null,
        'idempotencyKey': 'v1:biz-001:user-1:abc',
      };
      final keyChanged = _deepCopy(base);
      keyChanged['idempotencyKey'] = 'OTHER-KEY';
      expect(DurableOperationRegistry.fingerprintOf(base),
          DurableOperationRegistry.fingerprintOf(keyChanged));
      expect(_mirrorOrderFingerprint(base), _mirrorOrderFingerprint(keyChanged));

      for (final mutation in <void Function(Map<String, dynamic>)>[
        (b) => b['productId'] = 'pX',
        (b) => b['quantity'] = 5,
        (b) => b['customerNotes'] = 'changed',
        (b) => b['deliveryNotes'] = 'changed',
      ]) {
        final mutated = _deepCopy(base);
        mutation(mutated);
        expect(
            DurableOperationRegistry.fingerprintOf(base),
            isNot(equals(DurableOperationRegistry.fingerprintOf(mutated))),
            reason: 'client must see every orderFingerprint-covered field');
        expect(_mirrorOrderFingerprint(base),
            isNot(equals(_mirrorOrderFingerprint(mutated))));
      }
    });
  });
}
