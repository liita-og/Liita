import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// EncryptedPayload
// ---------------------------------------------------------------------------

/// Container for AES-GCM encrypted data.
class EncryptedPayload {
  /// Base64-encoded ciphertext (includes GCM auth tag appended by pointycastle).
  final String ciphertext;

  /// Base64-encoded 12-byte nonce / IV.
  final String nonce;

  const EncryptedPayload({
    required this.ciphertext,
    required this.nonce,
  });

  Map<String, dynamic> toJson() => {
        'ciphertext': ciphertext,
        'nonce': nonce,
      };

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) {
    return EncryptedPayload(
      ciphertext: json['ciphertext'] as String,
      nonce: json['nonce'] as String,
    );
  }
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Abstract cryptographic service for ECDH key exchange, AES-GCM encryption,
/// and secure key storage.
abstract class CryptoService {
  /// Perform any one-time setup (e.g. load keys from secure storage).
  Future<void> initialize();

  /// Generate a new ECDH key pair on the P-256 (prime256v1) curve.
  Future<AsymmetricKeyPair<PublicKey, PrivateKey>> generateKeyPair();

  /// Export an [ECPublicKey] to a Base64-encoded uncompressed point.
  Future<String> exportPublicKey(ECPublicKey key);

  /// Import a Base64-encoded uncompressed point as an [ECPublicKey].
  Future<ECPublicKey> importPublicKey(String base64Der);

  /// Derive a 32-byte shared secret using ECDH + HKDF-SHA256.
  Future<Uint8List> deriveSharedSecret(ECPrivateKey myKey, ECPublicKey theirKey);

  /// Encrypt [plaintext] with AES-256-GCM using the provided 32-byte [key].
  Future<EncryptedPayload> encrypt(String plaintext, Uint8List key);

  /// Decrypt an [EncryptedPayload] with AES-256-GCM using the provided [key].
  Future<String> decrypt(EncryptedPayload payload, Uint8List key);

  /// Persist a shared key for a match so it survives app restarts.
  Future<void> storeSharedKey(String matchId, Uint8List key);

  /// Retrieve a previously stored shared key, or `null`.
  Future<Uint8List?> getSharedKey(String matchId);

  /// Return the stable device ID, creating and storing one if needed.
  Future<String> getOrCreateDeviceId();

  /// Return the persistent ECDH private key, creating one if needed.
  Future<ECPrivateKey> getOrCreatePrivateKey();

  /// Return the public key corresponding to the stored private key.
  Future<ECPublicKey> getPublicKey();
}

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

/// Production [CryptoService] backed by `pointycastle` for crypto primitives
/// and `flutter_secure_storage` for key persistence.
class CryptoServiceImpl implements CryptoService {
  static const String _keyDeviceId = 'liita_device_id';
  static const String _keyPrivateKey = 'liita_ec_private_key';
  static const String _sharedKeyPrefix = 'liita_shared_key_';
  static const String _curveName = 'prime256v1';

  final FlutterSecureStorage _storage;
  final Uuid _uuid;

  late final ECDomainParameters _domainParams;
  late final SecureRandom _secureRandom;

  CryptoServiceImpl({
    FlutterSecureStorage? storage,
    Uuid? uuid,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _uuid = uuid ?? const Uuid();

  // -----------------------------------------------------------------------
  // Initialisation
  // -----------------------------------------------------------------------

  @override
  Future<void> initialize() async {
    _domainParams = ECDomainParameters(_curveName);
    _secureRandom = _createSecureRandom();
  }

  SecureRandom _createSecureRandom() {
    final rng = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    rng.seed(KeyParameter(Uint8List.fromList(seeds)));
    return rng;
  }

  // -----------------------------------------------------------------------
  // Key pair generation
  // -----------------------------------------------------------------------

  @override
  Future<AsymmetricKeyPair<PublicKey, PrivateKey>> generateKeyPair() async {
    final keyGen = ECKeyGenerator()
      ..init(
        ParametersWithRandom(
          ECKeyGeneratorParameters(_domainParams),
          _secureRandom,
        ),
      );
    return keyGen.generateKeyPair();
  }

  // -----------------------------------------------------------------------
  // Public key export / import (uncompressed point format)
  // -----------------------------------------------------------------------

  @override
  Future<String> exportPublicKey(ECPublicKey key) async {
    final point = key.Q!;
    final encoded = point.getEncoded(false); // uncompressed: 0x04 || x || y
    return base64Encode(encoded);
  }

  @override
  Future<ECPublicKey> importPublicKey(String base64Der) async {
    final bytes = base64Decode(base64Der);
    final point = _domainParams.curve.decodePoint(bytes);
    return ECPublicKey(point, _domainParams);
  }

  // -----------------------------------------------------------------------
  // ECDH shared secret derivation
  // -----------------------------------------------------------------------

  @override
  Future<Uint8List> deriveSharedSecret(
    ECPrivateKey myKey,
    ECPublicKey theirKey,
  ) async {
    // Raw ECDH: multiply their public point by our private scalar.
    final agreement = ECDHBasicAgreement()
      ..init(myKey);
    final sharedSecretBigInt = agreement.calculateAgreement(theirKey);

    // Convert BigInt to fixed-length 32-byte array (P-256 field size).
    final rawShared = _bigIntToBytes(sharedSecretBigInt, 32);

    // HKDF-SHA256 to derive a 32-byte symmetric key.
    return _hkdfSha256(
      ikm: rawShared,
      salt: utf8.encode('liita-v1'),
      info: Uint8List(0),
      length: 32,
    );
  }

  /// HKDF (RFC 5869) extract-then-expand using SHA-256.
  Uint8List _hkdfSha256({
    required List<int> ikm,
    required List<int> salt,
    required List<int> info,
    required int length,
  }) {
    final hmac = HMac(SHA256Digest(), 64);

    // Extract
    hmac.init(KeyParameter(Uint8List.fromList(salt)));
    final prk = Uint8List(hmac.macSize);
    hmac.update(Uint8List.fromList(ikm), 0, ikm.length);
    hmac.doFinal(prk, 0);

    // Expand
    final hashLen = hmac.macSize;
    final n = (length + hashLen - 1) ~/ hashLen;
    final okm = Uint8List(n * hashLen);
    var prev = Uint8List(0);

    for (var i = 1; i <= n; i++) {
      hmac.init(KeyParameter(prk));
      hmac.update(prev, 0, prev.length);
      hmac.update(Uint8List.fromList(info), 0, info.length);
      hmac.update(Uint8List.fromList([i]), 0, 1);
      final block = Uint8List(hashLen);
      hmac.doFinal(block, 0);
      okm.setRange((i - 1) * hashLen, i * hashLen, block);
      prev = block;
    }

    return Uint8List.fromList(okm.sublist(0, length));
  }

  /// Convert a non-negative [BigInt] to a fixed-length big-endian byte array.
  Uint8List _bigIntToBytes(BigInt number, int length) {
    final hexStr = number.toRadixString(16).padLeft(length * 2, '0');
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = int.parse(hexStr.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  // -----------------------------------------------------------------------
  // AES-256-GCM encryption / decryption
  // -----------------------------------------------------------------------

  @override
  Future<EncryptedPayload> encrypt(String plaintext, Uint8List key) async {
    final nonce = _secureRandom.nextBytes(12);
    final plaintextBytes = utf8.encode(plaintext);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true, // encrypt
        AEADParameters(
          KeyParameter(key),
          128, // tag length in bits
          nonce,
          Uint8List(0), // no additional authenticated data
        ),
      );

    final ciphertextBytes = Uint8List(
      cipher.getOutputSize(plaintextBytes.length),
    );
    final len = cipher.processBytes(
      Uint8List.fromList(plaintextBytes),
      0,
      plaintextBytes.length,
      ciphertextBytes,
      0,
    );
    cipher.doFinal(ciphertextBytes, len);

    return EncryptedPayload(
      ciphertext: base64Encode(ciphertextBytes),
      nonce: base64Encode(nonce),
    );
  }

  @override
  Future<String> decrypt(EncryptedPayload payload, Uint8List key) async {
    final nonce = base64Decode(payload.nonce);
    final ciphertextBytes = base64Decode(payload.ciphertext);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false, // decrypt
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List(0),
        ),
      );

    final plaintextBytes = Uint8List(
      cipher.getOutputSize(ciphertextBytes.length),
    );
    final len = cipher.processBytes(
      Uint8List.fromList(ciphertextBytes),
      0,
      ciphertextBytes.length,
      plaintextBytes,
      0,
    );
    cipher.doFinal(plaintextBytes, len);

    return utf8.decode(plaintextBytes);
  }

  // -----------------------------------------------------------------------
  // Secure key storage
  // -----------------------------------------------------------------------

  @override
  Future<void> storeSharedKey(String matchId, Uint8List key) async {
    await _storage.write(
      key: '$_sharedKeyPrefix$matchId',
      value: base64Encode(key),
    );
  }

  @override
  Future<Uint8List?> getSharedKey(String matchId) async {
    final encoded = await _storage.read(key: '$_sharedKeyPrefix$matchId');
    if (encoded == null) return null;
    return base64Decode(encoded);
  }

  // -----------------------------------------------------------------------
  // Device identity
  // -----------------------------------------------------------------------

  @override
  Future<String> getOrCreateDeviceId() async {
    final existing = await _storage.read(key: _keyDeviceId);
    if (existing != null) return existing;

    final id = _uuid.v4();
    await _storage.write(key: _keyDeviceId, value: id);
    return id;
  }

  // -----------------------------------------------------------------------
  // Persistent ECDH key pair
  // -----------------------------------------------------------------------

  @override
  Future<ECPrivateKey> getOrCreatePrivateKey() async {
    final stored = await _storage.read(key: _keyPrivateKey);
    if (stored != null) {
      return _decodePrivateKey(stored);
    }

    final keyPair = await generateKeyPair();
    final privateKey = keyPair.privateKey as ECPrivateKey;
    final encoded = _encodePrivateKey(privateKey);
    await _storage.write(key: _keyPrivateKey, value: encoded);
    return privateKey;
  }

  @override
  Future<ECPublicKey> getPublicKey() async {
    final privateKey = await getOrCreatePrivateKey();
    // Derive public key: Q = d * G
    final q = _domainParams.G * privateKey.d;
    return ECPublicKey(q, _domainParams);
  }

  /// Encode the private key scalar `d` as a Base64 string.
  String _encodePrivateKey(ECPrivateKey key) {
    final dBytes = _bigIntToBytes(key.d!, 32);
    return base64Encode(dBytes);
  }

  /// Decode a Base64 string back into an [ECPrivateKey].
  ECPrivateKey _decodePrivateKey(String encoded) {
    final bytes = base64Decode(encoded);
    final d = _bytesToBigInt(bytes);
    return ECPrivateKey(d, _domainParams);
  }

  /// Convert a big-endian byte array to a non-negative [BigInt].
  BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}
