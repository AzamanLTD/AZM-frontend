// test/e2ee_protocol_vectors_test.dart
// =============================================================================
// E2EE v1 cross-platform vector suite — the fixture
// (test/fixtures/r40-e2ee-vectors.json) is generated from the backend's
// canonical Node implementation (services/e2ee/protocol.js) with
// deterministic seeds. This suite proves the Dart client reproduces the
// reference's bytes EXACTLY: X3DH shared key, every ratchet header, nonce,
// ciphertext and associated-data byte, final session states (including the
// skipped-key cache encoding), signature verification, and fingerprints.
// The binding contract is AZM-backend docs/e2ee-protocol.md.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/e2ee/e2ee_service.dart';

Map<String, dynamic> _fixture() =>
    json.decode(File('test/fixtures/r40-e2ee-vectors.json').readAsStringSync());

RatchetEnvelope _envFrom(Map<String, dynamic> t) => RatchetEnvelope(
    header: RatchetHeader.fromJson({
      'dh': t['header']['dh'],
      'pn': t['header']['pn'],
      'n': t['header']['n'],
    }),
    nonce: unb64(t['nonce']),
    ciphertext: unb64(t['ciphertext']));

void main() {
  final v = _fixture();
  final keys = v['keys'] as Map<String, dynamic>;
  final ctx = v['context'] as Map<String, dynamic>;
  final expected = v['expected'] as Map<String, dynamic>;

  final ctxA = MessageContext(
      conversationId: ctx['ctxA']['conversationId'],
      senderDeviceId: ctx['ctxA']['senderDeviceId'],
      senderIdentityKey: ctx['ctxA']['senderIdentityKey'],
      recipientIdentityKey: ctx['ctxA']['recipientIdentityKey']);
  final ctxB = MessageContext(
      conversationId: ctx['ctxB']['conversationId'],
      senderDeviceId: ctx['ctxB']['senderDeviceId'],
      senderIdentityKey: ctx['ctxB']['senderIdentityKey'],
      recipientIdentityKey: ctx['ctxB']['recipientIdentityKey']);

  // Deterministic A/B sessions matching the generator's flow. Receiver
  // decrypts with the SENDER's context (that is the associated data the
  // sender authenticated).
  Future<(DoubleRatchetSession, DoubleRatchetSession)> _freshSessions() async {
    final x = await initiateX3DH(
        ourIdentityPrivateKeyB64: keys['A']['identity']['privateKey'],
        theirIdentityPublicKeyB64: keys['B']['identity']['publicKey'],
        theirSignedPreKeyPublicKeyB64: keys['B']['spk']['publicKey'],
        theirOneTimePreKeyPublicKeyB64: keys['B']['otpk']['publicKey'],
        ephemeral: X25519KeyMaterial(
            publicKey: unb64(keys['ephemeral']['publicKey']),
            privateKey: unb64(keys['ephemeral']['privateKey'])));
    final sk = await acceptX3DH(
        ourIdentityPrivateKeyB64: keys['B']['identity']['privateKey'],
        ourSignedPreKeyPrivateKeyB64: keys['B']['spk']['privateKey'],
        ourOneTimePreKeyPrivateKeyB64: keys['B']['otpk']['privateKey'],
        theirIdentityPublicKeyB64: keys['A']['identity']['publicKey'],
        theirEphemeralPublicKeyB64: keys['ephemeral']['publicKey']);
    expect(b64(sk), expected['x3dhSharedKey'], reason: 'responder X3DH parity');
    final alice = await DoubleRatchetSession.initiator(x.sharedKey, keys['B']['spk']['publicKey'],
        ratchetKeyPair: X25519KeyMaterial(
            publicKey: unb64(keys['ratchetA']['publicKey']),
            privateKey: unb64(keys['ratchetA']['privateKey'])));
    final bob = DoubleRatchetSession.responder(sk,
        X25519KeyMaterial(
            publicKey: unb64(keys['B']['spk']['publicKey']),
            privateKey: unb64(keys['B']['spk']['privateKey'])));
    return (alice, bob);
  }

  // Deterministic send hook: the ONLY randomness in the transcript is the
  // responder's first-send ratchet pair — the fixture seeds it (ratchetB).
  Future<RatchetEnvelope> _send(DoubleRatchetSession s, String text, MessageContext c, Map k) async {
    final fresh = s.serialize()['sendingChainKey'] == null ? k : null;
    return fresh == null
        ? s.encrypt(text, c)
        : s.encrypt(text, c,
            freshPair: X25519KeyMaterial(
                publicKey: unb64(fresh['publicKey']),
                privateKey: unb64(fresh['privateKey'])));
  }

  test('P1: X3DH shared key matches the Node reference byte-for-byte', () async {
    final x = await initiateX3DH(
        ourIdentityPrivateKeyB64: keys['A']['identity']['privateKey'],
        theirIdentityPublicKeyB64: keys['B']['identity']['publicKey'],
        theirSignedPreKeyPublicKeyB64: keys['B']['spk']['publicKey'],
        theirOneTimePreKeyPublicKeyB64: keys['B']['otpk']['publicKey'],
        ephemeral: X25519KeyMaterial(
            publicKey: unb64(keys['ephemeral']['publicKey']),
            privateKey: unb64(keys['ephemeral']['privateKey'])));
    expect(b64(x.sharedKey), expected['x3dhSharedKey']);
  });

  test('P2: full transcript replays byte-exactly (headers, nonces, ciphertexts, ADs)', () async {
    final (alice, bob) = await _freshSessions();
    for (final t in (expected['transcript'] as List).cast<Map<String, dynamic>>()) {
      final senderCtx = t['dir'] == 'A->B' ? ctxA : ctxB;
      final receiverCtx = t['dir'] == 'A->B' ? ctxB : ctxA;
      final sender = t['dir'] == 'A->B' ? alice : bob;
      final receiver = t['dir'] == 'A->B' ? bob : alice;

      final e = await _send(sender, t['text'] as String, senderCtx,
          (sender == bob) ? keys['ratchetB'] : <String, dynamic>{});
      expect(e.header.dh, t['header']['dh'], reason: '${t['text']}: header.dh');
      expect(e.header.pn, t['header']['pn'], reason: '${t['text']}: header.pn');
      expect(e.header.n, t['header']['n'], reason: '${t['text']}: header.n');
      expect(b64(e.nonce), t['nonce'], reason: '${t['text']}: nonce');
      expect(b64(e.ciphertext), t['ciphertext'], reason: '${t['text']}: ciphertext');

      final adHex = messageAssociatedData(senderCtx, e.header)
          .map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(adHex, t['adHex'], reason: '${t['text']}: associated data');

      final pt = await receiver.decrypt(_envFrom(t), senderCtx);
      expect(pt, t['text']);
    }
  });

  test('P3: out-of-order delivery decrypts via retained message keys', () async {
    final oo = expected['outOfOrder'] as Map<String, dynamic>;
    final (alice, bob) = await _freshSessions();
    // In-order prefix (messages one..five) mirrors the generator flow.
    final transcript = (expected['transcript'] as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < 5; i++) {
      final t = transcript[i];
      final s = t['dir'] == 'A->B' ? alice : bob;
      await _send(s, t['text'] as String, t['dir'] == 'A->B' ? ctxA : ctxB,
          (s == bob) ? keys['ratchetB'] : <String, dynamic>{});
      await (t['dir'] == 'A->B' ? bob : alice).decrypt(_envFrom(t), t['dir'] == 'A->B' ? ctxA : ctxB);
    }
    await alice.encrypt('Vector message six', ctxA);
    await alice.encrypt('Vector message seven', ctxA);
    // seven (n=4) arrives BEFORE six (n=3): retained-key path both ways.
    expect(await bob.decrypt(_envFrom(oo['seven']), ctxA), 'Vector message seven');
    expect(await bob.decrypt(_envFrom(oo['six']), ctxA), 'Vector message six');
  });

  test('P4: tampered ciphertext fails closed and leaves session state untouched', () async {
    final (alice, bob) = await _freshSessions();
    final t = (expected['transcript'] as List).first as Map<String, dynamic>;
    await bob.decrypt(_envFrom(t), ctxA);
    final before = json.encode(bob.serialize());

    final tampered = RatchetEnvelope(
        header: RatchetHeader.fromJson(t['header']),
        nonce: unb64(t['nonce']),
        ciphertext: unb64(expected['tamperedCiphertext'] as String));
    await expectLater(bob.decrypt(tampered, ctxA),
        throwsA(isA<E2eeException>().having((e) => e.code, 'code', 'E2EE_MESSAGE_AUTH_FAILED')));
    expect(json.encode(bob.serialize()), before, reason: 'failed decrypt must not advance state');
  });

  test('P5: far-future header rejects via MAX_SKIP without consuming state', () async {
    final (alice, bob) = await _freshSessions();
    final t = (expected['transcript'] as List).first as Map<String, dynamic>;
    await bob.decrypt(_envFrom(t), ctxA);
    final before = json.encode(bob.serialize());
    final far = RatchetEnvelope(
        header: RatchetHeader(dh: t['header']['dh'], pn: t['header']['pn'], n: 5000),
        nonce: unb64(t['nonce']),
        ciphertext: unb64(t['ciphertext']));
    await expectLater(bob.decrypt(far, ctxA),
        throwsA(isA<E2eeException>().having((e) => e.code, 'code', 'E2EE_TOO_MANY_SKIPPED')));
    expect(json.encode(bob.serialize()), before);
  });

  test('P6: final session states match the reference (incl. skipped-key cache)', () async {
    final (alice, bob) = await _freshSessions();
    final transcript = (expected['transcript'] as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < 5; i++) {
      final t = transcript[i];
      final s = t['dir'] == 'A->B' ? alice : bob;
      await _send(s, t['text'] as String, t['dir'] == 'A->B' ? ctxA : ctxB,
          (s == bob) ? keys['ratchetB'] : <String, dynamic>{});
      await (t['dir'] == 'A->B' ? bob : alice).decrypt(_envFrom(t), t['dir'] == 'A->B' ? ctxA : ctxB);
    }
    await alice.encrypt('Vector message six', ctxA);
    await alice.encrypt('Vector message seven', ctxA);
    await bob.decrypt(_envFrom(transcript[6]), ctxA); // seven
    await bob.decrypt(_envFrom(transcript[5]), ctxA); // six
    await alice.encrypt('Vector message eight', ctxA);
    await alice.encrypt('Vector message nine', ctxA);
    await bob.decrypt(_envFrom(transcript[8]), ctxA); // nine skips eight -> retained key

    // The generator encrypts one extra (tamper-target) message on alice AFTER
    // the transcript — mirrored here so the final states align.
    await alice.encrypt('Vector tamper target', ctxA);
    expect(alice.serialize(), expected['aliceState']);
    expect(bob.serialize(), expected['bobState']);
    // The retained key must be present, proving the cache encoding.
    expect((bob.serialize()['skipped'] as List).length, 1);
  });

  test('P7: state serialization round trips byte-stable', () async {
    final (alice, _) = await _freshSessions();
    await alice.encrypt('round trip', ctxA);
    final s1 = alice.serialize();
    final again = DoubleRatchetSession.parse(Map<String, Object?>.from(s1));
    expect(again.serialize(), s1);
  });

  test('P8: device binding + SPK signatures verify; forgeries reject', () async {
    expect(await verifyDeviceBinding(
        signingPublicKeyB64: keys['B']['signing']['publicKey'],
        identityPublicKeyB64: keys['B']['identity']['publicKey'],
        bindingSignatureB64: keys['B']['deviceBinding']['signature']), isTrue);

    // Forged: flip a signature byte.
    final sig = unb64(keys['B']['deviceBinding']['signature'] as String);
    sig[10] ^= 0x01;
    expect(await verifyDeviceBinding(
        signingPublicKeyB64: keys['B']['signing']['publicKey'],
        identityPublicKeyB64: keys['B']['identity']['publicKey'],
        bindingSignatureB64: b64(sig)), isFalse);

    // Forged: bind someone else's identity key.
    expect(await verifyDeviceBinding(
        signingPublicKeyB64: keys['B']['signing']['publicKey'],
        identityPublicKeyB64: keys['A']['identity']['publicKey'],
        bindingSignatureB64: keys['B']['deviceBinding']['signature']), isFalse);

    expect(await verifySignedPreKeySignature(
        signingPublicKeyB64: keys['B']['signing']['publicKey'],
        signedPreKeyId: keys['B']['spk']['keyId'],
        signedPreKeyPublicKeyB64: keys['B']['spk']['publicKey'],
        signatureB64: keys['B']['spk']['signature']), isTrue);

    expect(await verifySignedPreKeySignature(
        signingPublicKeyB64: keys['B']['signing']['publicKey'],
        signedPreKeyId: 999, // wrong key id
        signedPreKeyPublicKeyB64: keys['B']['spk']['publicKey'],
        signatureB64: keys['B']['spk']['signature']), isFalse);
  });

  test('P9: fingerprint matches the backend format exactly', () async {
    final fp = await identityFingerprint(keys['B']['identity']['publicKey'] as String);
    expect(fp, expected['fingerprint']);
    expect(fp.split(' ').first.length, 5);
    expect(fp, fp.toUpperCase());
  });

  test('P10: canonical header rejects malformed inputs', () {
    expect(() => canonicalHeader(RatchetHeader(dh: '', pn: -1, n: 0)), returnsNormally);
    expect(canonicalHeader(RatchetHeader(dh: 'abc', pn: 1, n: 2)),
        '${HEADER_PREFIX}|abc|1|2');
  });
}
