// lib/services/e2ee/e2ee_service.dart
// =============================================================================
// AZAMAN E2EE Protocol v1 — Dart/Flutter reference client implementation.
//
// Mirrors the BINDING contract in AZM-backend docs/e2ee-protocol.md and its
// canonical implementation services/e2ee/protocol.js, byte-for-byte:
//   • Signal X3DH (X25519, HKDF-SHA256, salt = 32 zero bytes)
//   • Signal Double Ratchet (HKDF-SHA256 KDF_RK, HMAC-SHA256 KDF_CK)
//   • ChaCha20-Poly1305-IETF AEAD (RFC 8439), nonce derived per message key
//   • Canonical authenticated-header binding (P0-B): every header byte is
//     authenticated via 'azaman-dr-v1|<dhB64>|<pn>|<n>'
//   • Transactional decrypt (P1-G): state advances only on success
//   • Bounded skipped-key cache with FIFO eviction (P1-H)
//
// Cross-platform byte-compatibility is proven by the vector suite
// (test/e2ee_protocol_vectors_test.dart) against the shared fixture
// generated from the Node reference implementation.
//
// PURE CRYPTOGRAPHY: no database, no HTTP, no key storage. Session state
// belongs to the client (secure storage), never the server.
// =============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

const int PROTOCOL_VERSION = 1;
const String X3DH_INFO = 'AZAMAN-X3DH-v1';
const String DR_RK_INFO = 'AZAMAN-DR-v1-rk';
const String DR_NONCE_INFO = 'AZAMAN-DR-v1-nonce';
const String AD_PREFIX = 'azaman-e2ee-v1';
const String BIND_PREFIX = 'azaman-e2ee-v1-device-bind';
const String SPK_PREFIX = 'azaman-e2ee-v1-spk';
const String HEADER_PREFIX = 'azaman-dr-v1';
const int MAX_SKIP = 1000;
const int MAX_SKIPPED_CACHE = 2000;

class E2eeException implements Exception {
  final String code;
  final String message;
  E2eeException(this.code, [this.message = '']);
  @override
  String toString() => 'E2eeException($code${message.isEmpty ? '' : ': $message'})';
}

Uint8List _u8(List<int> b) => b is Uint8List ? b : Uint8List.fromList(b);
Uint8List unb64(String text) => _u8(base64.decode(text));
String b64(List<int> data) => base64.encode(_u8(data));
Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));
Uint8List _zeros(int n) => Uint8List(n);

// ── Primitives ──────────────────────────────────────────────────────────────

Future<Uint8List> hmacSha256(List<int> key, List<int> data) async {
  final mac = await Hmac.sha256().calculateMac(data, secretKey: SecretKey(_u8(key)));
  return _u8(mac.bytes);
}

/// HKDF-SHA256 (RFC 5869) — identical construction to the Node reference.
Future<Uint8List> hkdfSha256(List<int> ikm, List<int> salt, String info, int length) async {
  final okm = await Hkdf(hmac: Hmac.sha256(), outputLength: length).deriveKey(
    secretKey: SecretKey(_u8(ikm)),
    nonce: _u8(salt),
    info: utf8Bytes(info),
  );
  return _u8(okm.bytes);
}

/// Raw X25519 scalarmult; all-zero output (small-subgroup) is rejected.
Future<Uint8List> dh(List<int> privateKey32, List<int> publicKey32) async {
  final shared = await X25519().sharedSecretKey(
    keyPair: SimpleKeyPairData(_u8(privateKey32),
        publicKey: SimplePublicKey(_u8(publicKey32), type: KeyPairType.x25519),
        type: KeyPairType.x25519),
    remotePublicKey: SimplePublicKey(_u8(publicKey32), type: KeyPairType.x25519),
  );
  final out = _u8(await shared.extractBytes());
  if (out.every((b) => b == 0)) throw E2eeException('E2EE_DH_ALL_ZERO');
  return out;
}

Future<X25519KeyMaterial> newX25519Pair() async {
  final kp = await X25519().newKeyPair();
  return X25519KeyMaterial(
    privateKey: _u8(await kp.extractPrivateKeyBytes()),
    publicKey: _u8((await kp.extractPublicKey()).bytes),
  );
}

class X25519KeyMaterial {
  final Uint8List publicKey;
  final Uint8List privateKey;
  X25519KeyMaterial({required this.publicKey, required this.privateKey});
  String get publicKeyB64 => b64(publicKey);
  String get privateKeyB64 => b64(privateKey);
}

// ── Registration signature verification (client-side trust gate) ───────────

/// Verifies a device binding signature: the Ed25519 signing key attests the
/// X25519 identity key. Message = 'azaman-e2ee-v1-device-bind|<identity>|<signing>'.
Future<bool> verifyDeviceBinding({
  required String signingPublicKeyB64,
  required String identityPublicKeyB64,
  required String bindingSignatureB64,
}) async {
  final message = utf8Bytes('$BIND_PREFIX|$identityPublicKeyB64|$signingPublicKeyB64');
  return Ed25519().verify(message,
      signature: Signature(unb64(bindingSignatureB64),
          publicKey: SimplePublicKey(unb64(signingPublicKeyB64), type: KeyPairType.ed25519)));
}

/// Verifies the signed-prekey signature over '<prefix>|<keyId>|<spkPubB64>'.
Future<bool> verifySignedPreKeySignature({
  required String signingPublicKeyB64,
  required int signedPreKeyId,
  required String signedPreKeyPublicKeyB64,
  required String signatureB64,
}) async {
  final message = utf8Bytes('$SPK_PREFIX|$signedPreKeyId|$signedPreKeyPublicKeyB64');
  return Ed25519().verify(message,
      signature: Signature(unb64(signatureB64),
          publicKey: SimplePublicKey(unb64(signingPublicKeyB64), type: KeyPairType.ed25519)));
}

// ── X3DH (Signal specification) ─────────────────────────────────────────────

class X3dhResult {
  final Uint8List sharedKey;
  final X25519KeyMaterial ephemeral;
  X3dhResult({required this.sharedKey, required this.ephemeral});
}

/// Initiator side. [ephemeral] is injectable for deterministic test vectors;
/// production callers omit it and a fresh pair is generated.
Future<X3dhResult> initiateX3DH({
  required String ourIdentityPrivateKeyB64,
  required String theirIdentityPublicKeyB64,
  required String theirSignedPreKeyPublicKeyB64,
  String? theirOneTimePreKeyPublicKeyB64,
  X25519KeyMaterial? ephemeral,
}) async {
  final ikPriv = unb64(ourIdentityPrivateKeyB64);
  final ikbPub = unb64(theirIdentityPublicKeyB64);
  final spkbPub = unb64(theirSignedPreKeyPublicKeyB64);
  final eph = ephemeral ?? await newX25519Pair();

  final terms = <Uint8List>[
    Uint8List.fromList(List.filled(32, 0xff)),
    await dh(ikPriv, spkbPub),          // DH(IKa, SPKb)
    await dh(eph.privateKey, ikbPub),  // DH(EKa, IKb)
    await dh(eph.privateKey, spkbPub), // DH(EKa, SPKb)
  ];
  if (theirOneTimePreKeyPublicKeyB64 != null) {
    terms.add(await dh(eph.privateKey, unb64(theirOneTimePreKeyPublicKeyB64))); // DH(EKa, OPKb)
  }
  final input = Uint8List.fromList(terms.expand((t) => t).toList());
  final sharedKey = await hkdfSha256(input, _zeros(32), X3DH_INFO, 32);
  return X3dhResult(sharedKey: sharedKey, ephemeral: eph);
}

/// Responder side — mirrors each initiator DH term.
Future<Uint8List> acceptX3DH({
  required String ourIdentityPrivateKeyB64,
  required String ourSignedPreKeyPrivateKeyB64,
  String? ourOneTimePreKeyPrivateKeyB64,
  required String theirIdentityPublicKeyB64,
  required String theirEphemeralPublicKeyB64,
}) async {
  final ikPriv = unb64(ourIdentityPrivateKeyB64);
  final spkPriv = unb64(ourSignedPreKeyPrivateKeyB64);
  final ekaPub = unb64(theirEphemeralPublicKeyB64);
  final ikaPub = unb64(theirIdentityPublicKeyB64);

  final terms = <Uint8List>[
    Uint8List.fromList(List.filled(32, 0xff)),
    await dh(spkPriv, ikaPub), // = DH(IKa, SPKb)
    await dh(ikPriv, ekaPub),  // = DH(EKa, IKb)
    await dh(spkPriv, ekaPub), // = DH(EKa, SPKb)
  ];
  if (ourOneTimePreKeyPrivateKeyB64 != null) {
    terms.add(await dh(unb64(ourOneTimePreKeyPrivateKeyB64), ekaPub)); // = DH(EKa, OPKb)
  }
  final input = Uint8List.fromList(terms.expand((t) => t).toList());
  return hkdfSha256(input, _zeros(32), X3DH_INFO, 32);
}

// ── Double Ratchet (Signal specification) ──────────────────────────────────

class RatchetHeader {
  final String dh;
  final int pn;
  final int n;
  RatchetHeader({required this.dh, required this.pn, required this.n});
  Map<String, Object?> toJson() => {'dh': dh, 'pn': pn, 'n': n};
  factory RatchetHeader.fromJson(Map<String, Object?> j) =>
      RatchetHeader(dh: j['dh'] as String, pn: j['pn'] as int, n: j['n'] as int);
}

class MessageContext {
  final String conversationId;
  final String senderDeviceId;
  final String senderIdentityKey;
  final String recipientIdentityKey;
  MessageContext({required this.conversationId, required this.senderDeviceId,
      required this.senderIdentityKey, required this.recipientIdentityKey});
}

class RatchetEnvelope {
  final RatchetHeader header;
  final Uint8List nonce;
  final Uint8List ciphertext;
  RatchetEnvelope({required this.header, required this.nonce, required this.ciphertext});
}

class _KdfRkResult { final Uint8List rootKey; final Uint8List chainKey;
  _KdfRkResult(this.rootKey, this.chainKey); }

Future<_KdfRkResult> _kdfRk(Uint8List rk, Uint8List dhOut) async {
  final out = await hkdfSha256(dhOut, rk, DR_RK_INFO, 64);
  return _KdfRkResult(
    Uint8List.sublistView(out, 0, 32),
    Uint8List.sublistView(out, 32, 64),
  );
}

Future<(Uint8List, Uint8List)> _kdfCk(Uint8List ck) async => (
  await hmacSha256(ck, const [0x01]),
  await hmacSha256(ck, const [0x02]),
);

Future<Uint8List> _messageNonce(Uint8List mk) async {
  final h = await hmacSha256(mk, utf8Bytes(DR_NONCE_INFO));
  return Uint8List.sublistView(h, 0, 12);
}

/// libsodium's AEAD output layout is ciphertext || tag (16 bytes).
Future<Uint8List> _aeadEncrypt(Uint8List mk, Uint8List nonce, List<int> plaintext, List<int> ad) async {
  final box = await Chacha20.poly1305Aead().encrypt(
    _u8(plaintext), secretKey: SecretKey(mk), nonce: nonce, aad: _u8(ad));
  return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
}

Future<Uint8List> _aeadDecrypt(Uint8List mk, Uint8List nonce, Uint8List ciphertext, List<int> ad) async {
  if (ciphertext.length < 16) throw E2eeException('E2EE_MESSAGE_AUTH_FAILED');
  final ct = Uint8List.sublistView(ciphertext, 0, ciphertext.length - 16);
  final mac = Uint8List.sublistView(ciphertext, ciphertext.length - 16);
  try {
    final pt = await Chacha20.poly1305Aead().decrypt(
      SecretBox(ct, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(mk), aad: _u8(ad));
    return _u8(pt);
  } catch (_) {
    throw E2eeException('E2EE_MESSAGE_AUTH_FAILED');
  }
}

/// Canonical authenticated-header encoding (P0-B) — byte-identical across
/// every client implementation: 'azaman-dr-v1|<dhB64>|<pn>|<n>'.
String canonicalHeader(RatchetHeader header) {
  return '$HEADER_PREFIX|${header.dh}|${header.pn}|${header.n}';
}

/// AEAD associated data: context binding || canonical header. A ciphertext is
/// bound to protocol version, conversation, sender device, sender identity,
/// recipient identity AND every header byte.
Uint8List messageAssociatedData(MessageContext context, RatchetHeader header) {
  final ad = '$AD_PREFIX|${context.conversationId}|${context.senderDeviceId}'
      '|${context.senderIdentityKey}|${context.recipientIdentityKey}';
  return Uint8List.fromList([...utf8Bytes(ad), ...utf8Bytes(canonicalHeader(header))]);
}

/// Client-owned Double Ratchet session — transactional, JSON-serializable.
class DoubleRatchetSession {
  Uint8List rootKey;
  Uint8List? sendingChainKey;
  Uint8List? receivingChainKey;
  X25519KeyMaterial dhSelf;
  Uint8List? dhRemote;
  int sendCount, recvCount, prevSendCount;
  // P1-H: insertion-ordered FIFO cache, bounded at MAX_SKIPPED_CACHE.
  final Map<String, Uint8List> skipped;

  DoubleRatchetSession._({
    required this.rootKey, required this.sendingChainKey, required this.receivingChainKey,
    required this.dhSelf, required this.dhRemote,
    required this.sendCount, required this.recvCount, required this.prevSendCount,
    Map<String, Uint8List>? skipped,
  }) : skipped = skipped ?? {};

  static Future<DoubleRatchetSession> initiator(Uint8List sharedKey, String theirSignedPreKeyPublicKeyB64,
      {X25519KeyMaterial? ratchetKeyPair}) async {
    // [ratchetKeyPair] is a determinism hook for the cross-platform vector
    // suite only; production callers omit it and a fresh pair is generated.
    final ratchet = ratchetKeyPair ?? await newX25519Pair();
    final rk = await _kdfRk(sharedKey, await dh(ratchet.privateKey, unb64(theirSignedPreKeyPublicKeyB64)));
    return DoubleRatchetSession._(
      rootKey: rk.rootKey, sendingChainKey: rk.chainKey, receivingChainKey: null,
      dhSelf: ratchet, dhRemote: unb64(theirSignedPreKeyPublicKeyB64),
      sendCount: 0, recvCount: 0, prevSendCount: 0,
    );
  }

  static DoubleRatchetSession responder(Uint8List sharedKey, X25519KeyMaterial ourSignedPreKeyKeyPair) =>
      DoubleRatchetSession._(
        rootKey: Uint8List.fromList(sharedKey), sendingChainKey: null, receivingChainKey: null,
        dhSelf: ourSignedPreKeyKeyPair, dhRemote: null,
        sendCount: 0, recvCount: 0, prevSendCount: 0,
      );

  Uint8List? _trySkipped(String headerKey, int counter) {
    final key = '$headerKey:$counter';
    final mk = skipped[key];
    if (mk != null) skipped.remove(key);
    return mk;
  }

  Future<void> _skipMessageKeys(Uint8List dhRemoteB, int until) async {
    final rck = receivingChainKey;
    if (rck == null) return;
    if (until + 1 - recvCount > MAX_SKIP) throw E2eeException('E2EE_TOO_MANY_SKIPPED');
    var ck = rck;
    while (recvCount < until) {
      final (mk, next) = await _kdfCk(ck);
      final cacheKey = '${b64(dhRemoteB)}:$recvCount';
      if (skipped.length >= MAX_SKIPPED_CACHE) {
        skipped.remove(skipped.keys.first); // FIFO eviction
      }
      skipped[cacheKey] = mk;
      ck = next;
      recvCount += 1;
    }
    receivingChainKey = ck;
  }

  Future<RatchetEnvelope> encrypt(String plaintext, MessageContext context,
      {X25519KeyMaterial? freshPair}) async {
    // Transactional (P1-G): all mutation happens on a trial clone.
    final trial = DoubleRatchetSession.parse(serialize());

    if (trial.sendingChainKey == null) {
      final remote = trial.dhRemote;
      if (remote == null) throw E2eeException('E2EE_CANNOT_SEND_BEFORE_RECEIVE');
      // [freshPair] is a determinism hook for the vector suite only.
      final fresh = freshPair ?? await newX25519Pair();
      final rk = await _kdfRk(trial.rootKey, await dh(fresh.privateKey, remote));
      trial.rootKey = rk.rootKey;
      trial.sendingChainKey = rk.chainKey;
      trial.prevSendCount = trial.sendCount;
      trial.sendCount = 0;
      trial.dhSelf = fresh;
    }
    final header = RatchetHeader(dh: trial.dhSelf.publicKeyB64, pn: trial.prevSendCount, n: trial.sendCount);
    final (mk, ck) = await _kdfCk(trial.sendingChainKey!);
    trial.sendingChainKey = ck;
    final nonce = await _messageNonce(mk);
    final ct = await _aeadEncrypt(mk, nonce, utf8Bytes(plaintext), messageAssociatedData(context, header));
    trial.sendCount += 1;

    _commit(trial);
    return RatchetEnvelope(header: header, nonce: nonce, ciphertext: ct);
  }

  Future<String> decrypt(RatchetEnvelope envelope, MessageContext context) async {
    final trial = DoubleRatchetSession.parse(serialize());
    final pt = await trial._decryptInPlace(envelope, context);
    _commit(trial);
    return utf8.decode(pt);
  }

  Future<Uint8List> _decryptInPlace(RatchetEnvelope envelope, MessageContext context) async {
    final ad = messageAssociatedData(context, envelope.header);
    final dhRemoteB = unb64(envelope.header.dh);

    final skipped = _trySkipped(b64(dhRemoteB), envelope.header.n);
    if (skipped != null) {
      return _aeadDecrypt(skipped, envelope.nonce, envelope.ciphertext, ad);
    }

    final currentRemote = dhRemote;
    if (currentRemote == null || !_bytesEqual(currentRemote, dhRemoteB)) {
      // Finish the old chain (retaining its keys) before the DH step.
      if (currentRemote != null) await _skipMessageKeys(currentRemote, envelope.header.pn);
      final rk = await _kdfRk(rootKey, await dh(dhSelf.privateKey, dhRemoteB));
      rootKey = rk.rootKey;
      receivingChainKey = rk.chainKey;
      dhRemote = dhRemoteB;
      recvCount = 0;
      prevSendCount = 0;
    }
    await _skipMessageKeys(dhRemoteB, envelope.header.n);
    final (mk, ck) = await _kdfCk(receivingChainKey!);
    receivingChainKey = ck;
    recvCount = envelope.header.n + 1;
    return _aeadDecrypt(mk, envelope.nonce, envelope.ciphertext, ad);
  }

  void _commit(DoubleRatchetSession trial) {
    rootKey = trial.rootKey;
    sendingChainKey = trial.sendingChainKey;
    receivingChainKey = trial.receivingChainKey;
    dhSelf = trial.dhSelf;
    dhRemote = trial.dhRemote;
    sendCount = trial.sendCount;
    recvCount = trial.recvCount;
    prevSendCount = trial.prevSendCount;
    skipped
      ..clear()
      ..addAll(trial.skipped);
  }

  Map<String, Object?> serialize() => {
    'rootKey': b64(rootKey),
    'sendingChainKey': sendingChainKey == null ? null : b64(sendingChainKey!),
    'receivingChainKey': receivingChainKey == null ? null : b64(receivingChainKey!),
    'dhSelf': {'publicKey': dhSelf.publicKeyB64, 'privateKey': dhSelf.privateKeyB64},
    'dhRemote': dhRemote == null ? null : b64(dhRemote!),
    'sendCount': sendCount, 'recvCount': recvCount, 'prevSendCount': prevSendCount,
    'skipped': skipped.entries.map((e) => [e.key, b64(e.value)]).toList(),
  };

  static DoubleRatchetSession parse(Map<String, Object?> data) => DoubleRatchetSession._(
    rootKey: unb64(data['rootKey'] as String),
    sendingChainKey: data['sendingChainKey'] == null ? null : unb64(data['sendingChainKey'] as String),
    receivingChainKey: data['receivingChainKey'] == null ? null : unb64(data['receivingChainKey'] as String),
    dhSelf: X25519KeyMaterial(
      publicKey: unb64((data['dhSelf'] as Map)['publicKey'] as String),
      privateKey: unb64((data['dhSelf'] as Map)['privateKey'] as String)),
    dhRemote: data['dhRemote'] == null ? null : unb64(data['dhRemote'] as String),
    sendCount: data['sendCount'] as int,
    recvCount: data['recvCount'] as int,
    prevSendCount: data['prevSendCount'] as int,
    skipped: {
      for (final e in (data['skipped'] as List? ?? []) as List<dynamic>)
        e[0] as String: unb64(e[1] as String),
    },
  );
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Identity fingerprint: BLAKE2b-256 over the X25519 identity public key,
/// uppercase hex, grouped in 5-char chunks. Mirrors the backend's
/// GET /fingerprint/:userId response format.
Future<String> identityFingerprint(String identityPublicKeyB64) async {
  final hash = await Blake2b(hashLengthInBytes: 32).hash(unb64(identityPublicKeyB64));
  final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
  final groups = <String>[];
  for (var i = 0; i < hex.length; i += 5) {
    groups.add(hex.substring(i, i + 5 > hex.length ? hex.length : i + 5));
  }
  return groups.join(' ');
}
