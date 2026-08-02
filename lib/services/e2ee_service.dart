// =============================================================================
// AZAMAN — E2EE Service (Client-Side)
//
// Client-side end-to-end encryption using NaCl Box (X25519 + XSalsa20-Poly1305).
// The backend `services/e2eeService.js` handles key agreement and preKey
// management. This service handles:
//   1. On-device keypair generation (private key NEVER leaves the device)
//   2. Public key registration with backend
//   3. Peer public key lookup
//   4. Message encryption/decryption using Box (shared secret via ECDH)
//   5. Key-change detection (WhatsApp "Security code changed" banner)
//
// Security model:
//   - Private key stored in OS keychain/keystore via flutter_secure_storage
//   - Public key registered with backend so peers can encrypt to us
//   - Each message uses a unique nonce (random 24 bytes)
//   - The nonce is prepended to ciphertext for transmission
//
// Reference: Signal Protocol, WhatsApp (Signal), Wire (E2EE enterprise)
// =============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/x25519.dart';

import 'package:azaman/services/api_client.dart';

// ── Secure Storage ──────────────────────────────────────────────────────────

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

const _privKeyKey = 'e2ee_private_key_v1';
const _pubKeyKey = 'e2ee_public_key_v1';
const _peerKeyPrefix = 'e2ee_peer_';

// ── E2EE Service ─────────────────────────────────────────────────────────────

class E2eeService {
  // ── Key Management ────────────────────────────────────────────────────────

  /// Generate a new X25519 keypair and persist to secure storage.
  /// Call once on first login, or after a key rotation.
  static Future<({String publicKeyB64, String privateKeyB64})> generateKeypair() async {
    final privKey = PrivateKey.generate();
    final pubKey = privKey.publicKey;

    // Encode to base64 for storage and transmission
    final privB64 = base64Encode(privKey);
    final pubB64 = base64Encode(pubKey);

    // Persist private key to secure storage (NEVER leaves device)
    await _storage.write(key: _privKeyKey, value: privB64);
    await _storage.write(key: _pubKeyKey, value: pubB64);

    return (publicKeyB64: pubB64, privateKeyB64: privB64);
  }

  /// Load our own keypair from secure storage.
  /// Returns null if not initialized.
  static Future<({String? publicKeyB64, String? privateKeyB64})> loadKeypair() async {
    final pub = await _storage.read(key: _pubKeyKey);
    final priv = await _storage.read(key: _privKeyKey);
    return (publicKeyB64: pub, privateKeyB64: priv);
  }

  /// Check if E2EE is initialized for this device.
  static Future<bool> isInitialized() async {
    final priv = await _storage.read(key: _privKeyKey);
    return priv != null;
  }

  /// Register our public key with the backend so peers can encrypt to us.
  static Future<void> registerPublicKey(String publicKeyB64, ApiClient api) async {
    await api.post('/api/e2ee/keys/init', {
      'clientPublicKey': publicKeyB64,
    });
  }

  /// Fetch the peer's public key from the backend.
  static Future<String?> fetchPeerPublicKey(String peerUserId, ApiClient api) async {
    try {
      final resp = await api.get('/api/e2ee/keys/$peerUserId');
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['data']?['identityPublicKey'] as String?;
    } catch (e) {
      debugPrint('[E2EE] Failed to fetch peer public key: $e');
      return null;
    }
  }

  /// Get our own identity fingerprint for verification.
  static Future<String?> getOwnFingerprint(ApiClient api) async {
    try {
      final resp = await api.get('/api/e2ee/fingerprint');
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['data']?['fingerprint'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Get a peer's fingerprint for safety number comparison.
  static Future<String?> getPeerFingerprint(String peerUserId, ApiClient api) async {
    try {
      final resp = await api.get('/api/e2ee/fingerprint/$peerUserId');
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['data']?['fingerprint'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Key-Change Detection ───────────────────────────────────────────────────

  /// Check if a peer's public key has changed since last seen.
  /// Returns true if the key changed (show "Security code changed" banner).
  static Future<bool> hasKeyChanged(String peerUserId, String newKey) async {
    final storedKey = '$_peerKeyPrefix$peerUserId';
    final stored = await _storage.read(key: storedKey);

    if (stored == null) {
      // First time seeing this peer — no change, just store it
      await _storage.write(key: storedKey, value: newKey);
      return false;
    }

    if (stored != newKey) {
      // Key changed! Update stored key and return true
      await _storage.write(key: storedKey, value: newKey);
      return true;
    }

    return false; // Same key, no change
  }

  // ── Encryption / Decryption ───────────────────────────────────────────────

  /// Encrypt a plaintext message for a peer.
  /// Returns base64-encoded "nonce + ciphertext" ready for transmission.
  static Future<String?> encryptMessage({
    required String peerPublicKeyB64,
    required String plaintext,
  }) async {
    try {
      // Load our private key
      final privB64 = await _storage.read(key: _privKeyKey);
      if (privB64 == null) {
        debugPrint('[E2EE] No private key — E2EE not initialized');
        return null;
      }

      // Decode keys
      final privKeyBytes = base64Decode(privB64);
      final peerPubKeyBytes = base64Decode(peerPublicKeyB64);

      // Create Box (computes shared secret via X25519 ECDH)
      final myPrivateKey = PrivateKey(Uint8List.fromList(privKeyBytes));
      final theirPublicKey = PublicKey(Uint8List.fromList(peerPubKeyBytes));
      final box = Box(myPrivateKey: myPrivateKey, theirPublicKey: theirPublicKey);

      // Encrypt with random nonce
      final plaintextBytes = utf8.encode(plaintext);
      final encrypted = box.encrypt(Uint8List.fromList(plaintextBytes));

      // Return nonce + ciphertext as base64
      final nonceAndCipher = encrypted.nonce + encrypted.cipherText;
      return base64Encode(nonceAndCipher);
    } catch (e) {
      debugPrint('[E2EE] Encryption failed: $e');
      return null;
    }
  }

  /// Decrypt a message from a peer.
  /// Input is base64-encoded "nonce + ciphertext".
  static Future<String?> decryptMessage({
    required String peerPublicKeyB64,
    required String encryptedB64,
  }) async {
    try {
      // Load our private key
      final privB64 = await _storage.read(key: _privKeyKey);
      if (privB64 == null) {
        debugPrint('[E2EE] No private key — E2EE not initialized');
        return null;
      }

      // Decode keys
      final privKeyBytes = base64Decode(privB64);
      final peerPubKeyBytes = base64Decode(peerPublicKeyB64);

      // Create Box
      final myPrivateKey = PrivateKey(Uint8List.fromList(privKeyBytes));
      final theirPublicKey = PublicKey(Uint8List.fromList(peerPubKeyBytes));
      final box = Box(myPrivateKey: myPrivateKey, theirPublicKey: theirPublicKey);

      // Decode the encrypted message (nonce + ciphertext)
      final nonceAndCipher = base64Decode(encryptedB64);
      if (nonceAndCipher.length < 24) {
        debugPrint('[E2EE] Encrypted message too short');
        return null;
      }

      // Split nonce (24 bytes) and ciphertext
      final nonce = Uint8List.fromList(nonceAndCipher.sublist(0, 24));
      final cipherText = Uint8List.fromList(nonceAndCipher.sublist(24));

      // Decrypt
      final plaintextBytes = box.decrypt(
        EncryptedMessage(nonce: nonce, cipherText: cipherText),
      );

      return utf8.decode(plaintextBytes);
    } catch (e) {
      debugPrint('[E2EE] Decryption failed: $e');
      return null;
    }
  }

  // ── Initialization Flow ─────────────────────────────────────────────────────

  /// Full initialization: check if keys exist, generate if not, register with backend.
  /// Call this after login.
  static Future<bool> initializeIfNeeded(ApiClient api) async {
    final initialized = await isInitialized();
    if (initialized) {
      debugPrint('[E2EE] Already initialized');
      return true;
    }

    debugPrint('[E2EE] First-time initialization — generating keypair...');
    final keypair = await generateKeypair();

    try {
      await registerPublicKey(keypair.publicKeyB64, api);
      debugPrint('[E2EE] Public key registered with backend');
      return true;
    } catch (e) {
      debugPrint('[E2EE] Failed to register public key: $e');
      // Keys are still stored locally — we can retry registration later
      return false;
    }
  }
}

// ── E2EE Provider ────────────────────────────────────────────────────────────

/// Tracks E2EE initialization state.
/// true = keys generated and registered, messages will be encrypted.
/// false = not initialized (first login or key rotation needed).
final e2eeInitializedProvider = StateProvider<bool>((ref) => false);

/// Tracks which peers have had key changes (for showing the "Security code
/// changed" banner).
final e2eeKeyChangedProvider = StateProvider<Set<String>>((ref) => {});
