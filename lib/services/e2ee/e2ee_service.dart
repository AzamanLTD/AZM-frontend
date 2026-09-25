// r40 E2EE v2 — client protocol library (pure Dart, no Flutter imports).
//
// Byte-compatible with the backend reference implementation
// (AZM-backend/services/e2eeService.js) and the cross-platform fixture
// (test/fixtures/r40-e2ee-vectors.json), verified by
// test/e2ee_protocol_vectors_test.dart.
//
// Trust model (docs/e2ee/PROTOCOL.md, backend repo):
//   • The server is a public-key directory and a blind relay. It stores only
//     signature-bound public bundles; private keys never leave this device.
//   • X3DH (Ed25519 identity binding + X25519 DH) establishes the session
//     root key; the Double Ratchet advances it per message.
//   • The AEAD is ChaCha20-Poly1305 (IETF, 12-byte nonce). AAD binds the
//     session identities and the exact ratchet header bytes.
//   • Message keys are single-use: the sending chain advances on every
//     encrypt, so (key, nonce) pairs can never repeat.
//
// This file is deliberately pure Dart so the vector suite runs under both
// `dart test` and `flutter test` without platform channels.

import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

// ── Protocol constants (must match e2eeService.js) ────────────────────────────

const int protocolVersion = 2;
const int maxSkip = 1000;
const int maxPreKeyId = 0x7FFFFFFF; // crypto_randombytes_uniform bound

const String _x3dhInfo = 'AzamanE2EE-v2-X3DH';
const String _kdfRkInfo = 'AzamanE2EE-v2-KDF_RK';

final Uint8List _zeroSalt = Uint8List(32);

// ── Errors ───────────────────────────────────────────────────────────────────

class E2eeException implements Exception {
  final String code;
  final String message;
  final int status;
  const E2eeException(this.code, this.message, {this.status = 400});
  @override
  String toString() => 'E2eeException($code): $message';
}

// ── Byte helpers ─────────────────────────────────────────────────────────────

Uint8List concat(List<List<int>> arrays) {
  int len = 0;
  for (final a in arrays) {
    len += a.length;
  }
  final out = Uint8List(len);
  int off = 0;
  for (final a in arrays) {
    out.setAll(off, a);
    off += a.length;
  }
  return out;
}

Uint8List u64be(int n) {
  final b = Uint8List(8);
  for (int i = 7; i >= 0; i--) {
    b[i] = n & 0xFF;
    n >>= 8;
  }
  return b;
}

Uint8List unb64(String s) => base64.decode(s);
String b64(List<int> bytes) => base64.encode(Uint8List.fromList(bytes));
Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

// ── KDFs (PROTOCOL.md §5) ────────────────────────────────────────────────────

/// HKDF-SHA-512 with an explicit 32-zero-byte salt — the exact bytes the
/// Node reference passes to hkdfSync. (Do NOT let the Dart library choose a
/// default salt: HKDF's spec default is HashLen zeros = 64 bytes here, which
/// would silently fork the key schedule.)
Future<Uint8List> _hkdfSha512(List<int> ikm, String info, int length) async {
  final hk = Hkdf(hmac: Hmac.sha512(), outputLength: length);
  final okm = await hk.deriveKey(
    secretKey: SecretKey(Uint8List.fromList(ikm)),
    nonce: _zeroSalt,
    info: utf8Bytes(info),
  );
  return Uint8List.fromList(okm.bytes);
}

/// KDF_RK(rk, dh_out) -> (rk', ck) — HKDF-SHA-512, split at 32 bytes.
Future<(Uint8List, Uint8List)> _kdfRk(Uint8List rootKey, Uint8List dhOut) async {
  final out = await _hkdfSha512(concat([rootKey, dhOut]), _kdfRkInfo, 64);
  return (out.sublist(0, 32), out.sublist(32, 64));
}

/// KDF_CK(ck) -> (mk, ck') — HMAC-SHA-256 over 0x01 / 0x02.
Future<(Uint8List, Uint8List)> _kdfCk(Uint8List chainKey) async {
  final h = Hmac.sha256();
  final key = SecretKey(chainKey);
  final mk = Uint8List.fromList((await h.calculateMac([0x01], secretKey: key)).bytes);
  final next = Uint8List.fromList((await h.calculateMac([0x02], secretKey: key)).bytes);
  return (mk, next);
}

// ── X25519 ────────────────────────────────────────────────────────────────────

Future<Uint8List> _dh(List<int> privateKey, List<int> publicKey) async {
  final shared = await X25519().sharedSecretKey(
    keyPair: SimpleKeyPairData(
      Uint8List.fromList(privateKey),
      publicKey: SimplePublicKey(Uint8List.fromList(publicKey), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    ),
    remotePublicKey: SimplePublicKey(Uint8List.fromList(publicKey), type: KeyPairType.x25519),
  );
  final bytes = Uint8List.fromList(await shared.extractBytes());
  // Low-order/all-zero shared secrets are rejected, mirroring
  // crypto_scalarmult's behavior contract.
  bool allZero = true;
  for (final b in bytes) {
    if (b != 0) {
      allZero = false;
      break;
    }
  }
  if (allZero) {
    throw const E2eeException('E2EE_INVALID_KEY', 'X25519: low-order public key rejected.');
  }
  return bytes;
}

Future<X25519KeyMaterial> _newDhPair() async {
  final kp = await X25519().newKeyPair();
  return X25519KeyMaterial(
    privateKey: Uint8List.fromList(await kp.extractPrivateKeyBytes()),
    publicKey: Uint8List.fromList((await kp.extractPublicKey()).bytes),
  );
}

class X25519KeyMaterial {
  final Uint8List publicKey;
  final Uint8List privateKey;
  X25519KeyMaterial({required this.publicKey, required this.privateKey});
}

// ── Identity / prekey generation (client-side only) ───────────────────────────

class IdentityKeys {
  final Uint8List identityPublicKey; // Ed25519
  final Uint8List identityPrivateKey;
  final Uint8List identityDhPublicKey; // X25519
  final Uint8List identityDhPrivateKey;
  final Uint8List identityKeySignature; // Ed25519 detached over the DH half

  IdentityKeys({
    required this.identityPublicKey,
    required this.identityPrivateKey,
    required this.identityDhPublicKey,
    required this.identityDhPrivateKey,
    required this.identityKeySignature,
  });

  Map<String, String> toWire() => {
        'identityPublicKey': b64(identityPublicKey),
        'identityDhPublicKey': b64(identityDhPublicKey),
        'identityKeySignature': b64(identityKeySignature),
      };

  Map<String, String> toPersist() => {
        'identityPrivateKey': b64(identityPrivateKey),
        'identityDhPrivateKey': b64(identityDhPrivateKey),
        ...toWire(),
      };
}

Future<IdentityKeys> generateIdentityKeys() async {
  final signing = await Ed25519().newKeyPair();
  final dhIdentity = await _newDhPair();
  final signature = await Ed25519().sign(
    dhIdentity.publicKey,
    keyPair: signing,
  );
  return IdentityKeys(
    identityPublicKey: Uint8List.fromList((await signing.extractPublicKey()).bytes),
    identityPrivateKey: Uint8List.fromList(await signing.extractPrivateKeyBytes()),
    identityDhPublicKey: dhIdentity.publicKey,
    identityDhPrivateKey: dhIdentity.privateKey,
    identityKeySignature: Uint8List.fromList(signature.bytes),
  );
}

class SignedPreKey {
  final int keyId;
  final Uint8List publicKey;
  final Uint8List privateKey;
  final Uint8List signature; // Ed25519 detached by the identity key
  SignedPreKey({
    required this.keyId,
    required this.publicKey,
    required this.privateKey,
    required this.signature,
  });
}

Future<SignedPreKey> generateSignedPreKey(
  Uint8List identityPrivateKey,
  Uint8List identityPublicKey, {
  int? keyId,
}) async {
  final kp = await _newDhPair();
  final signature = await Ed25519().sign(
    kp.publicKey,
    keyPair: SimpleKeyPairData(
      identityPrivateKey,
      publicKey: SimplePublicKey(identityPublicKey, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    ),
  );
  return SignedPreKey(
    keyId: keyId ?? _randomPreKeyId(),
    publicKey: kp.publicKey,
    privateKey: kp.privateKey,
    signature: Uint8List.fromList(signature.bytes),
  );
}

class OneTimePreKey {
  final int keyId;
  final Uint8List publicKey;
  final Uint8List privateKey;
  OneTimePreKey({required this.keyId, required this.publicKey, required this.privateKey});
}

Future<List<OneTimePreKey>> generateOneTimePreKeys(int count) async {
  final keys = <OneTimePreKey>[];
  for (int i = 0; i < count; i++) {
    final kp = await _newDhPair();
    keys.add(OneTimePreKey(keyId: _randomPreKeyId(), publicKey: kp.publicKey, privateKey: kp.privateKey));
  }
  return keys;
}

int _randomPreKeyId() {
  // package:cryptography has no randombytes_uniform; Random.secure is the
  // platform CSPRNG (getrandom/SecRandomCopyBytes), masked into [0, maxPreKeyId].
  final rng = Random.secure();
  return rng.nextInt(maxPreKeyId + 1);
}

// ── Client-side bundle verification (trust the server's directory no further
//    than its signatures) ───────────────────────────────────────────────────────

Future<bool> verifyBundleSignatures({
  required String identityPublicKey,
  required String identityDhPublicKey,
  required String identityKeySignature,
  required String signedPreKeyPublicKey,
  required String signedPreKeySignature,
}) async {
  final ed = Ed25519();
  final pub = SimplePublicKey(unb64(identityPublicKey), type: KeyPairType.ed25519);
  final bindingOk = await ed.verify(
    unb64(identityDhPublicKey),
    signature: Signature(unb64(identityKeySignature), publicKey: pub),
  );
  final prekeyOk = await ed.verify(
    unb64(signedPreKeyPublicKey),
    signature: Signature(unb64(signedPreKeySignature), publicKey: pub),
  );
  return bindingOk && prekeyOk;
}

/// Validate a fetched peer bundle BEFORE trusting it (the server also checks,
/// but the client must not depend on that: a hostile or MITM'd directory is
/// within the threat model).
Future<void> validatePeerBundle(Map<String, dynamic> bundle) async {
  void need(bool ok, String msg) {
    if (!ok) throw E2eeException('E2EE_INVALID_BUNDLE', msg);
  }

  need(bundle['identityPublicKey'] is String && unb64(bundle['identityPublicKey']).length == 32,
      'identityPublicKey must be a base64 Ed25519 public key.');
  need(bundle['identityDhPublicKey'] is String && unb64(bundle['identityDhPublicKey']).length == 32,
      'identityDhPublicKey must be a base64 X25519 public key.');
  need(bundle['identityKeySignature'] is String && unb64(bundle['identityKeySignature']).length == 64,
      'identityKeySignature must be a base64 64-byte signature.');
  need(bundle['signedPreKeyId'] is int && bundle['signedPreKeyId'] >= 0 && bundle['signedPreKeyId'] <= maxPreKeyId,
      'signedPreKeyId out of range.');
  need(bundle['signedPreKeyPublicKey'] is String && unb64(bundle['signedPreKeyPublicKey']).length == 32,
      'signedPreKeyPublicKey must be a base64 X25519 public key.');
  need(bundle['signedPreKeySignature'] is String && unb64(bundle['signedPreKeySignature']).length == 64,
      'signedPreKeySignature must be a base64 64-byte signature.');
  need(
    await verifyBundleSignatures(
      identityPublicKey: bundle['identityPublicKey'],
      identityDhPublicKey: bundle['identityDhPublicKey'],
      identityKeySignature: bundle['identityKeySignature'],
      signedPreKeyPublicKey: bundle['signedPreKeyPublicKey'],
      signedPreKeySignature: bundle['signedPreKeySignature'],
    ),
    'Bundle signature verification failed.',
  );
}

/// Safety number (PROTOCOL.md §3): BLAKE2b-256 of the Ed25519 identity pub,
/// uppercase hex, grouped in 5-char chunks.
Future<String> fingerprint(String identityPublicKeyB64) async {
  final hash = await Blake2b(hashLengthInBytes: 32).hash(unb64(identityPublicKeyB64));
  final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  final groups = <String>[];
  for (int i = 0; i < hex.length; i += 5) {
    groups.add(hex.substring(i, i + 5 > hex.length ? hex.length : i + 5));
  }
  return groups.join(' ');
}

// ── X3DH (PROTOCOL.md §4) ─────────────────────────────────────────────────────

String sessionAD(String initiatorIdentityPubB64, String responderIdentityPubB64) =>
    '$initiatorIdentityPubB64|$responderIdentityPubB64';

Future<Uint8List> _x3dhSecret(Uint8List dh1, Uint8List dh2, Uint8List dh3, Uint8List? dh4) async {
  final ikm = dh4 == null
      ? concat([_zeroSalt, dh1, dh2, dh3])
      : concat([_zeroSalt, dh1, dh2, dh3, dh4]);
  final out = await _hkdfSha512(ikm, _x3dhInfo, 64);
  return out.sublist(0, 32);
}

class X3dhInitiateResult {
  final Uint8List rootKey;
  final X25519KeyMaterial ephemeralKeyPair;
  final String associatedData;
  final int? usedOneTimePreKeyId;
  X3dhInitiateResult({
    required this.rootKey,
    required this.ephemeralKeyPair,
    required this.associatedData,
    required this.usedOneTimePreKeyId,
  });

  /// Base64 of the ephemeral public half — what the initiator sends to the
  /// responder alongside the first ciphertext (message header 3DH material).
  String get ephemeralPublicKey => b64(ephemeralKeyPair.publicKey);
}

/// Initiator side (A). Bundle fields are base64 strings exactly as fetched
/// from the server directory (atomically claimed one-time prekey included).
Future<X3dhInitiateResult> x3dhInitiate({
  required Map<String, dynamic> peerBundle,
  required String identityDhPrivateKeyB64,
  required String identityPublicKeyB64,
  required String peerIdentityPublicKeyB64,
  X25519KeyMaterial? ephemeralKeyPair,
}) async {
  final ek = ephemeralKeyPair ?? await _newDhPair();
  final spk = unb64(peerBundle['signedPreKeyPublicKey'] as String);
  final dh1 = await _dh(unb64(identityDhPrivateKeyB64), spk);
  final dh2 = await _dh(ek.privateKey, unb64(peerBundle['identityDhPublicKey'] as String));
  final dh3 = await _dh(ek.privateKey, spk);
  Uint8List? dh4;
  int? usedOtkId;
  final otk = peerBundle['oneTimePreKey'];
  if (otk is Map && otk['publicKey'] is String) {
    dh4 = await _dh(ek.privateKey, unb64(otk['publicKey'] as String));
    usedOtkId = otk['keyId'] as int?;
  }
  final rootKey = await _x3dhSecret(dh1, dh2, dh3, dh4);
  return X3dhInitiateResult(
    rootKey: rootKey,
    ephemeralKeyPair: ek,
    associatedData: sessionAD(identityPublicKeyB64, peerIdentityPublicKeyB64),
    usedOneTimePreKeyId: usedOtkId,
  );
}

class X3dhRespondResult {
  final Uint8List rootKey;
  final String associatedData;
  X3dhRespondResult({required this.rootKey, required this.associatedData});
}

/// Responder side (B) — mirrors the initiator's DH terms with B's private
/// halves, in the same concatenation order.
Future<X3dhRespondResult> x3dhRespond({
  required String ephemeralPublicKeyB64,
  required String initiatorIdentityDhPublicKeyB64,
  required String identityDhPrivateKeyB64,
  required String signedPreKeyPrivateKeyB64,
  String? oneTimePreKeyPrivateKeyB64,
  required String identityPublicKeyB64,
  required String initiatorIdentityPublicKeyB64,
}) async {
  final ek = unb64(ephemeralPublicKeyB64);
  final ikA = unb64(initiatorIdentityDhPublicKeyB64);
  final dh1 = await _dh(unb64(signedPreKeyPrivateKeyB64), ikA);
  final dh2 = await _dh(unb64(identityDhPrivateKeyB64), ek);
  final dh3 = await _dh(unb64(signedPreKeyPrivateKeyB64), ek);
  Uint8List? dh4;
  if (oneTimePreKeyPrivateKeyB64 != null) {
    dh4 = await _dh(unb64(oneTimePreKeyPrivateKeyB64), ek);
  }
  final rootKey = await _x3dhSecret(dh1, dh2, dh3, dh4);
  return X3dhRespondResult(
    rootKey: rootKey,
    associatedData: sessionAD(initiatorIdentityPublicKeyB64, identityPublicKeyB64),
  );
}

// ── Double Ratchet (PROTOCOL.md §5) ───────────────────────────────────────────

class RatchetState {
  final int protocolVersion;
  final Uint8List rootKey;
  final X25519KeyMaterial dhs; // own ratchet keypair
  final Uint8List? dhr; // peer's current ratchet public key
  final Uint8List? cks; // sending chain key
  final Uint8List? ckr; // receiving chain key
  final int ns, nr, pn;
  final Map<String, String> mkSkipped; // 'b64(dhr)|n' -> b64 message key

  const RatchetState({
    required this.protocolVersion,
    required this.rootKey,
    required this.dhs,
    this.dhr,
    this.cks,
    this.ckr,
    required this.ns,
    required this.nr,
    required this.pn,
    required this.mkSkipped,
  });

  RatchetState copyWith({
    Uint8List? rootKey,
    X25519KeyMaterial? dhs,
    Uint8List? dhr,
    bool clearDhr = false,
    Uint8List? cks,
    bool clearCks = false,
    Uint8List? ckr,
    bool clearCkr = false,
    int? ns,
    int? nr,
    int? pn,
    Map<String, String>? mkSkipped,
  }) =>
      RatchetState(
        protocolVersion: protocolVersion,
        rootKey: rootKey ?? this.rootKey,
        dhs: dhs ?? this.dhs,
        dhr: clearDhr ? null : (dhr ?? this.dhr),
        cks: clearCks ? null : (cks ?? this.cks),
        ckr: clearCkr ? null : (ckr ?? this.ckr),
        ns: ns ?? this.ns,
        nr: nr ?? this.nr,
        pn: pn ?? this.pn,
        mkSkipped: mkSkipped ?? this.mkSkipped,
      );
}

/// Alice (initiator): DHs = X3DH ephemeral, DHr = B's signed prekey pub.
Future<RatchetState> initiatorRatchet(
  Uint8List rootKey,
  X25519KeyMaterial ephemeralKeyPair,
  String peerSignedPreKeyPublicKeyB64,
) async {
  final (rk, chainKey) = await _kdfRk(
    rootKey,
    await _dh(ephemeralKeyPair.privateKey, unb64(peerSignedPreKeyPublicKeyB64)),
  );
  return RatchetState(
    protocolVersion: protocolVersion,
    rootKey: rk,
    dhs: ephemeralKeyPair,
    dhr: unb64(peerSignedPreKeyPublicKeyB64),
    cks: chainKey,
    ckr: null,
    ns: 0,
    nr: 0,
    pn: 0,
    mkSkipped: {},
  );
}

/// Bob (responder): DHs = signed prekey pair, DHr = null. His first RECEIVED
/// message performs the DH ratchet step that creates his sending chain.
RatchetState responderRatchet(Uint8List rootKey, X25519KeyMaterial signedPreKeyPair) =>
    RatchetState(
      protocolVersion: protocolVersion,
      rootKey: rootKey,
      dhs: signedPreKeyPair,
      dhr: null,
      cks: null,
      ckr: null,
      ns: 0,
      nr: 0,
      pn: 0,
      mkSkipped: {},
    );

// Deterministic AEAD nonce: u32be(0) || u64be(n).
Uint8List _messageNonce(int n) => concat([Uint8List(4), u64be(n)]);

String _messageAD(String sessionAd, RatchetHeader header) =>
    '$sessionAd|${header.v}|${header.dh}|${header.pn}|${header.n}';

class RatchetHeader {
  final int v;
  final String dh; // base64
  final int pn;
  final int n;
  const RatchetHeader({required this.v, required this.dh, required this.pn, required this.n});

  Map<String, dynamic> toWire() => {'v': v, 'dh': dh, 'pn': pn, 'n': n};

  factory RatchetHeader.fromWire(dynamic raw) {
    if (raw is! Map) throw const E2eeException('E2EE_BAD_HEADER', 'Unsupported or missing ratchet header.');
    final v = raw['v'];
    final dh = raw['dh'];
    final pn = raw['pn'];
    final n = raw['n'];
    if (v != protocolVersion ||
        dh is! String ||
        pn is! int || n is! int ||
        pn < 0 || n < 0) {
      throw const E2eeException('E2EE_BAD_HEADER', 'Malformed ratchet header.');
    }
    return RatchetHeader(v: v, dh: dh, pn: pn, n: n);
  }
}

final Chacha20 _aead = Chacha20.poly1305Aead();

Future<String> _aeadEncrypt(Uint8List messageKey, Uint8List nonce, Uint8List plaintext, String aad) async {
  final box = await _aead.encrypt(
    plaintext,
    secretKey: SecretKey(messageKey),
    nonce: nonce,
    aad: utf8Bytes(aad),
  );
  // libsodium wire layout: ciphertext || 16-byte tag (this is what the relay
  // stores and what the Node reference produces).
  return b64(concat([box.cipherText, box.mac.bytes]));
}

Future<Uint8List> _aeadDecrypt(Uint8List messageKey, Uint8List nonce, String cipherTextB64, String aad) async {
  final raw = unb64(cipherTextB64);
  if (raw.length < 16) {
    throw const E2eeException('E2EE_DECRYPT_FAILED', 'AEAD authentication failed.');
  }
  final ct = raw.sublist(0, raw.length - 16);
  final mac = raw.sublist(raw.length - 16);
  try {
    final clear = await _aead.decrypt(
      SecretBox(ct, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(messageKey),
      aad: utf8Bytes(aad),
    );
    return Uint8List.fromList(clear);
  } catch (_) {
    throw const E2eeException('E2EE_DECRYPT_FAILED', 'AEAD authentication failed — ciphertext tampered or wrong key.');
  }
}

Future<(RatchetState, Uint8List?, int, Map<String, String>)> _skipMessageKeys(RatchetState state, int until) async {
  if (until - state.nr > maxSkip) {
    throw E2eeException(
      'E2EE_TOO_FAR_BEHIND',
      'Out-of-order window exceeded (${until - state.nr} > $maxSkip) — refusing to derive unbounded message keys.',
    );
  }
  var ckr = state.ckr;
  var nr = state.nr;
  final mkSkipped = Map<String, String>.from(state.mkSkipped);
  if (ckr != null) {
    var cur = ckr;
    while (nr < until) {
      final (mk, ck) = await _kdfCk(cur);
      mkSkipped['${b64(state.dhr!)}|$nr'] = b64(mk);
      cur = ck;
      nr += 1;
    }
    ckr = cur;
  }
  return (state, ckr, nr, mkSkipped);
}

Future<RatchetState> _dhRatchetStep(RatchetState state, RatchetHeader header) async {
  // Receiver-side DH ratchet step (lockstep with the peer, verified by the
  // proof suite): derive the NEW RECEIVING chain first with the CURRENT own
  // ratchet key, then rotate own keypair and derive the new SENDING chain.
  // The other order breaks the lockstep — the exact bug class this rewrite
  // exists to prevent.
  final pn = state.ns;
  final recvStep = await _kdfRk(state.rootKey, await _dh(state.dhs.privateKey, unb64(header.dh)));
  final newPair = await _newDhPair();
  final sendStep = await _kdfRk(recvStep.$1, await _dh(newPair.privateKey, unb64(header.dh)));
  return state.copyWith(
    rootKey: sendStep.$1,
    dhs: newPair,
    dhr: unb64(header.dh),
    cks: sendStep.$2,
    ckr: recvStep.$2,
    ns: 0,
    nr: 0,
    pn: pn,
  );
}

class RatchetEncryptResult {
  final RatchetHeader header;
  final String cipherTextB64;
  final RatchetState state;
  RatchetEncryptResult({required this.header, required this.cipherTextB64, required this.state});
}

/// Encrypt one message. Returns header, base64 ciphertext, and the NEW state.
/// The old state is NOT mutated — callers must persist the returned state.
Future<RatchetEncryptResult> ratchetEncrypt(RatchetState state, String plaintext, String sessionAd) async {
  if (state.cks == null) {
    throw const E2eeException(
      'E2EE_NO_SENDING_CHAIN',
      'No sending chain — this party must receive a message first (Double Ratchet initialization).',
    );
  }
  final (mk, nextCk) = await _kdfCk(state.cks!);
  final header = RatchetHeader(v: protocolVersion, dh: b64(state.dhs.publicKey), pn: state.pn, n: state.ns);
  final cipherText = await _aeadEncrypt(mk, _messageNonce(state.ns), utf8Bytes(plaintext), _messageAD(sessionAd, header));
  return RatchetEncryptResult(
    header: header,
    cipherTextB64: cipherText,
    state: state.copyWith(cks: nextCk, ns: state.ns + 1),
  );
}

class RatchetDecryptResult {
  final String plaintext;
  final RatchetState state;
  RatchetDecryptResult({required this.plaintext, required this.state});
}

/// Decrypt one message (out-of-order delivery via retained message keys;
/// DH ratchet step on new remote ratchet keys). Returns plaintext and the
/// NEW state — the old state is NOT mutated.
Future<RatchetDecryptResult> ratchetDecrypt(
  RatchetState state,
  RatchetHeader header,
  String cipherTextB64,
  String sessionAd,
) async {
  var s = state;

  // Out-of-order within a known chain: the message key was retained.
  final skippedKey = '${header.dh}|${header.n}';
  final retained = s.mkSkipped[skippedKey];
  if (retained != null) {
    final mk = unb64(retained);
    final mkSkipped = Map<String, String>.from(s.mkSkipped)..remove(skippedKey);
    final plain = await _aeadDecrypt(mk, _messageNonce(header.n), cipherTextB64, _messageAD(sessionAd, header));
    return RatchetDecryptResult(plaintext: utf8.decode(plain), state: s.copyWith(mkSkipped: mkSkipped));
  }

  // New remote ratchet key → close the old receiving chain, ratchet.
  if (s.dhr == null || b64(s.dhr!) != header.dh) {
    final (_, ckr1, nr1, mk1) = await _skipMessageKeys(s, header.pn);
    s = s.copyWith(ckr: ckr1, nr: nr1, mkSkipped: mk1);
    s = await _dhRatchetStep(s, header);
  }

  // Skip to the message's position in the current receiving chain.
  final (_, ckr2, nr2, mk2) = await _skipMessageKeys(s, header.n);
  s = s.copyWith(ckr: ckr2, nr: nr2, mkSkipped: mk2);
  final (mk, nextCk) = await _kdfCk(s.ckr!);
  final plain = await _aeadDecrypt(mk, _messageNonce(header.n), cipherTextB64, _messageAD(sessionAd, header));
  return RatchetDecryptResult(
    plaintext: utf8.decode(plain),
    state: s.copyWith(ckr: nextCk, nr: header.n + 1),
  );
}

// ── State serialization (byte-stable, mirrors e2eeService.js) ────────────────

Map<String, dynamic> serializeState(RatchetState s) => {
      'protocolVersion': s.protocolVersion,
      'rootKey': b64(s.rootKey),
      'dhs': {'publicKey': b64(s.dhs.publicKey), 'privateKey': b64(s.dhs.privateKey)},
      'dhr': s.dhr == null ? null : b64(s.dhr!),
      'cks': s.cks == null ? null : b64(s.cks!),
      'ckr': s.ckr == null ? null : b64(s.ckr!),
      'ns': s.ns,
      'nr': s.nr,
      'pn': s.pn,
      'mkSkipped': s.mkSkipped,
    };

RatchetState deserializeState(Map<String, dynamic> raw) {
  final dhs = raw['dhs'] as Map<String, dynamic>;
  Uint8List? opt(String? v) => v == null ? null : unb64(v);
  return RatchetState(
    protocolVersion: raw['protocolVersion'] as int,
    rootKey: unb64(raw['rootKey'] as String),
    dhs: X25519KeyMaterial(
      publicKey: unb64(dhs['publicKey'] as String),
      privateKey: unb64(dhs['privateKey'] as String),
    ),
    dhr: opt(raw['dhr'] as String?),
    cks: opt(raw['cks'] as String?),
    ckr: opt(raw['ckr'] as String?),
    ns: raw['ns'] as int,
    nr: raw['nr'] as int,
    pn: raw['pn'] as int,
    mkSkipped: Map<String, String>.from(raw['mkSkipped'] as Map),
  );
}
