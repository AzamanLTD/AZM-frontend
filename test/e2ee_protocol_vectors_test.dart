// r40 E2EE v2 — cross-platform byte-vector suite (pure Dart: `dart test` and
// `flutter test` both run this without platform channels).
//
// The fixture (test/fixtures/r40-e2ee-vectors.json) is the SAME file the
// backend proof suite consumes (AZM-backend/__tests__/helpers/…): if this
// suite is green, the Dart client and the Node reference produce identical
// bytes for the same inputs — no drift in the KDF schedule, header format,
// nonce construction, AEAD layout, or associated-data binding is possible.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/e2ee/e2ee_service.dart';

Map<String, dynamic> _fixture() =>
    json.decode(File('test/fixtures/r40-e2ee-vectors.json').readAsStringSync());

void main() {
  final v = _fixture();
  final inputs = v['inputs'] as Map<String, dynamic>;
  final expected = v['expected'] as Map<String, dynamic>;

  test('P12: reproduces the cross-platform fixture EXACTLY (Node/Dart byte-compatibility)', () async {
    final init = await x3dhInitiate(
      peerBundle: {
        'identityPublicKey': inputs['identityPublicKeyB'],
        'identityDhPublicKey': inputs['identityDhPublicKeyB'],
        'signedPreKeyPublicKey': inputs['signedPreKeyPublicKeyB'],
        'oneTimePreKey': {
          'keyId': inputs['oneTimePreKeyId'],
          'publicKey': inputs['oneTimePreKeyPublicKeyB'],
        },
      },
      identityDhPrivateKeyB64: inputs['identityDhPrivateKeyA'],
      identityPublicKeyB64: inputs['identityPublicKeyA'],
      peerIdentityPublicKeyB64: inputs['identityPublicKeyB'],
      ephemeralKeyPair: X25519KeyMaterial(
        publicKey: unb64(inputs['ephemeralPublicKeyA']),
        privateKey: unb64(inputs['ephemeralPrivateKeyA']),
      ),
    );
    expect(b64(init.rootKey), expected['rootKeyB64']);
    expect(init.associatedData, expected['associatedData']);

    final alice = await initiatorRatchet(
      init.rootKey,
      init.ephemeralKeyPair,
      inputs['signedPreKeyPublicKeyB'] as String,
    );
    final m1 = await ratchetEncrypt(alice, expected['message1']['plaintext'] as String, init.associatedData);
    final m1h = expected['message1']['header'] as Map<String, dynamic>;
    expect(m1.header.v, m1h['v']);
    expect(m1.header.dh, m1h['dh']);
    expect(m1.header.pn, m1h['pn']);
    expect(m1.header.n, m1h['n']);
    expect(m1.cipherTextB64, expected['message1']['cipherText']);

    // Bob's deterministic responder state decrypts the fixture ciphertext:
    final bob = responderRatchet(
      unb64(expected['rootKeyB64'] as String),
      X25519KeyMaterial(
        publicKey: unb64(inputs['signedPreKeyPublicKeyB']),
        privateKey: unb64(inputs['signedPreKeyPrivateKeyB']),
      ),
    );
    final d1 = await ratchetDecrypt(
      bob,
      RatchetHeader.fromWire(expected['message1']['header']),
      expected['message1']['cipherText'] as String,
      expected['associatedData'] as String,
    );
    expect(d1.plaintext, expected['message1']['plaintext']);
  });

  test('P2: full-duplex ratchet round trip with live keys', () async {
    final A = await generateIdentityKeys();
    final B = await generateIdentityKeys();
    final spkB = await generateSignedPreKey(B.identityPrivateKey, B.identityPublicKey);
    final otkB = (await generateOneTimePreKeys(1)).first;

    final init = await x3dhInitiate(
      peerBundle: {
        'identityPublicKey': b64(B.identityPublicKey),
        'identityDhPublicKey': b64(B.identityDhPublicKey),
        'signedPreKeyPublicKey': b64(spkB.publicKey),
        'oneTimePreKey': {'keyId': spkB.keyId, 'publicKey': b64(otkB.publicKey)},
      },
      identityDhPrivateKeyB64: b64(A.identityDhPrivateKey),
      identityPublicKeyB64: b64(A.identityPublicKey),
      peerIdentityPublicKeyB64: b64(B.identityPublicKey),
    );
    final ad = init.associatedData;
    final alice = await initiatorRatchet(init.rootKey, init.ephemeralKeyPair, b64(spkB.publicKey));

    final resp = await x3dhRespond(
      ephemeralPublicKeyB64: init.ephemeralPublicKey!,
      initiatorIdentityDhPublicKeyB64: b64(A.identityDhPublicKey),
      identityDhPrivateKeyB64: b64(B.identityDhPrivateKey),
      signedPreKeyPrivateKeyB64: b64(spkB.privateKey),
      oneTimePreKeyPrivateKeyB64: b64(otkB.privateKey),
      identityPublicKeyB64: b64(B.identityPublicKey),
      initiatorIdentityPublicKeyB64: b64(A.identityPublicKey),
    );
    expect(b64(resp.rootKey), b64(init.rootKey)); // X3DH symmetry
    expect(resp.associatedData, ad);

    var bob = responderRatchet(resp.rootKey, X25519KeyMaterial(publicKey: spkB.publicKey, privateKey: spkB.privateKey));

    final a1 = await ratchetEncrypt(alice, 'hello bob', ad);
    bob = (await ratchetDecrypt(bob, a1.header, a1.cipherTextB64, ad)).state;

    final b1 = await ratchetEncrypt(bob, 'hello alice', ad); // bob now has a sending chain
    final d = await ratchetDecrypt(a1.state, b1.header, b1.cipherTextB64, ad);
    expect(d.plaintext, 'hello alice');

    // A few more rounds both directions:
    var aliceState = d.state;
    final a2 = await ratchetEncrypt(aliceState, 'again', ad);
    final d2 = await ratchetDecrypt(b1.state, a2.header, a2.cipherTextB64, ad);
    expect(d2.plaintext, 'again');
    final b2 = await ratchetEncrypt(d2.state, 'roger', ad);
    final d3 = await ratchetDecrypt(a2.state, b2.header, b2.cipherTextB64, ad);
    expect(d3.plaintext, 'roger');
  });

  test('P6: out-of-order delivery decrypts via retained message keys', () async {
    final A = await generateIdentityKeys();
    final B = await generateIdentityKeys();
    final spkB = await generateSignedPreKey(B.identityPrivateKey, B.identityPublicKey);

    final init = await x3dhInitiate(
      peerBundle: {
        'identityPublicKey': b64(B.identityPublicKey),
        'identityDhPublicKey': b64(B.identityDhPublicKey),
        'signedPreKeyPublicKey': b64(spkB.publicKey),
      },
      identityDhPrivateKeyB64: b64(A.identityDhPrivateKey),
      identityPublicKeyB64: b64(A.identityPublicKey),
      peerIdentityPublicKeyB64: b64(B.identityPublicKey),
    );
    final ad = init.associatedData;
    final m0 = await ratchetEncrypt(await initiatorRatchet(init.rootKey, init.ephemeralKeyPair, b64(spkB.publicKey)), 'first', ad);
    final m1 = await ratchetEncrypt(m0.state, 'second', ad);
    final m2 = await ratchetEncrypt(m1.state, 'third', ad);

    var bob = responderRatchet(
      (await x3dhRespond(
        ephemeralPublicKeyB64: init.ephemeralPublicKey!,
        initiatorIdentityDhPublicKeyB64: b64(A.identityDhPublicKey),
        identityDhPrivateKeyB64: b64(B.identityDhPrivateKey),
        signedPreKeyPrivateKeyB64: b64(spkB.privateKey),
        identityPublicKeyB64: b64(B.identityPublicKey),
        initiatorIdentityPublicKeyB64: b64(A.identityPublicKey),
      )).rootKey,
      X25519KeyMaterial(publicKey: spkB.publicKey, privateKey: spkB.privateKey),
    );

    // Deliver m2 FIRST, then m0, then m1:
    final r2 = await ratchetDecrypt(bob, m2.header, m2.cipherTextB64, ad);
    expect(r2.plaintext, 'third');
    final r0 = await ratchetDecrypt(r2.state, m0.header, m0.cipherTextB64, ad);
    expect(r0.plaintext, 'first');
    final r1 = await ratchetDecrypt(r0.state, m1.header, m1.cipherTextB64, ad);
    expect(r1.plaintext, 'second');
  });

  test('P7: tampered ciphertext fails closed', () async {
    final A = await generateIdentityKeys();
    final B = await generateIdentityKeys();
    final spkB = await generateSignedPreKey(B.identityPrivateKey, B.identityPublicKey);
    final init = await x3dhInitiate(
      peerBundle: {
        'identityPublicKey': b64(B.identityPublicKey),
        'identityDhPublicKey': b64(B.identityDhPublicKey),
        'signedPreKeyPublicKey': b64(spkB.publicKey),
      },
      identityDhPrivateKeyB64: b64(A.identityDhPrivateKey),
      identityPublicKeyB64: b64(A.identityPublicKey),
      peerIdentityPublicKeyB64: b64(B.identityPublicKey),
    );
    final ad = init.associatedData;
    final m = await ratchetEncrypt(await initiatorRatchet(init.rootKey, init.ephemeralKeyPair, b64(spkB.publicKey)), 'secret', ad);
    final raw = unb64(m.cipherTextB64);
    raw[0] ^= 0x01; // flip one bit
    final bob = responderRatchet(
      (await x3dhRespond(
        ephemeralPublicKeyB64: init.ephemeralPublicKey!,
        initiatorIdentityDhPublicKeyB64: b64(A.identityDhPublicKey),
        identityDhPrivateKeyB64: b64(B.identityDhPrivateKey),
        signedPreKeyPrivateKeyB64: b64(spkB.privateKey),
        identityPublicKeyB64: b64(B.identityPublicKey),
        initiatorIdentityPublicKeyB64: b64(A.identityPublicKey),
      )).rootKey,
      X25519KeyMaterial(publicKey: spkB.publicKey, privateKey: spkB.privateKey),
    );
    expect(
      () => ratchetDecrypt(bob, m.header, b64(raw), ad),
      throwsA(isA<E2eeException>().having((e) => e.code, 'code', 'E2EE_DECRYPT_FAILED')),
    );
  });

  test('state serialization round trips byte-stable', () async {
    final A = await generateIdentityKeys();
    final B = await generateIdentityKeys();
    final spkB = await generateSignedPreKey(B.identityPrivateKey, B.identityPublicKey);
    final init = await x3dhInitiate(
      peerBundle: {
        'identityPublicKey': b64(B.identityPublicKey),
        'identityDhPublicKey': b64(B.identityDhPublicKey),
        'signedPreKeyPublicKey': b64(spkB.publicKey),
      },
      identityDhPrivateKeyB64: b64(A.identityDhPrivateKey),
      identityPublicKeyB64: b64(A.identityPublicKey),
      peerIdentityPublicKeyB64: b64(B.identityPublicKey),
    );
    final ad = init.associatedData;
    final alice = await initiatorRatchet(init.rootKey, init.ephemeralKeyPair, b64(spkB.publicKey));
    final m = await ratchetEncrypt(alice, 'persist me', ad);

    final wire = serializeState(m.state);
    final restored = deserializeState(Map<String, dynamic>.from(json.decode(json.encode(wire))));
    expect(serializeState(restored), wire);

    final m2 = await ratchetEncrypt(restored, 'after reload', ad);
    expect(m2.header.n, 1);
  });

  test('bundle signature verification accepts genuine, rejects forged', () async {
    final A = await generateIdentityKeys();
    final spk = await generateSignedPreKey(A.identityPrivateKey, A.identityPublicKey);
    final ok = await verifyBundleSignatures(
      identityPublicKey: b64(A.identityPublicKey),
      identityDhPublicKey: b64(A.identityDhPublicKey),
      identityKeySignature: b64(A.identityKeySignature),
      signedPreKeyPublicKey: b64(spk.publicKey),
      signedPreKeySignature: b64(spk.signature),
    );
    expect(ok, isTrue);

    final evil = await generateIdentityKeys(); // different identity
    final forged = await verifyBundleSignatures(
      identityPublicKey: b64(A.identityPublicKey),
      identityDhPublicKey: b64(evil.identityDhPublicKey),
      identityKeySignature: b64(evil.identityKeySignature),
      signedPreKeyPublicKey: b64(spk.publicKey),
      signedPreKeySignature: b64(spk.signature),
    );
    expect(forged, isFalse);
  });

  test('fingerprint: BLAKE2b-256 hex grouped in 5-char chunks', () async {
    final A = await generateIdentityKeys();
    final fp = await fingerprint(b64(A.identityPublicKey));
    expect(RegExp(r'^([0-9A-F]{1,5} )*[0-9A-F]{1,5}$').hasMatch(fp), isTrue);
    expect(fp.replaceAll(' ', '').length, 64);
    final B = await generateIdentityKeys();
    expect(await fingerprint(b64(B.identityPublicKey)), isNot(fp));
  });
}
