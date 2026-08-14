import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as crypto_lib;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class E2EKeyPair {
  final Uint8List publicKey;
  final Uint8List privateKey;
  final String keyId;

  E2EKeyPair({
    required this.publicKey,
    required this.privateKey,
    String? keyId,
  }) : keyId = keyId ?? _generateId();

  // Note: private_key is included here for export/backup purposes only.
  Map<String, String> toMap() => {
        'public_key': base64Encode(publicKey),
        'private_key': base64Encode(privateKey),
        'key_id': keyId,
      };

  factory E2EKeyPair.fromMap(Map<String, String> m) => E2EKeyPair(
        publicKey: base64Decode(m['public_key']!),
        privateKey: base64Decode(m['private_key']!),
        keyId: m['key_id'],
      );

  static String _generateId() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List.generate(16, (_) => random.nextInt(256)),
    );
    return sha256.convert(bytes).toString().substring(0, 16);
  }
}

class E2EEncryptionService {
  static E2EKeyPair? _localKeyPair;
  static final Map<String, Uint8List> _peerPublicKeys = {};
  static final Map<String, Uint8List> _sharedSecrets = {};
  static final Map<String, Uint8List> _derivedKeys = {};
  static final Map<String, int> _frameCounters = {};
  static final Map<String, int> _peerFrameCounters = {};
  static final Map<String, Uint8List> _salts = {};

  static const int _keyRotationInterval = 500;
  static const int _chachaMacLen = 16;

  static E2EKeyPair? get localKeyPair => _localKeyPair;

  static final crypto_lib.Xchacha20 _chacha = crypto_lib.Xchacha20.poly1305Aead();

  static Future<void> initialize() async {
    _localKeyPair = _generateKeyPair();
  }

  static E2EKeyPair _generateKeyPair() {
    final random = Random.secure();
    final privateKey = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    final publicKey = _derivePublicKey(privateKey);
    return E2EKeyPair(publicKey: publicKey, privateKey: privateKey);
  }

  // NOTE: This is a hash-based derivation, not a proper X25519 ECDH key
  // exchange. A proper implementation should use pinenacl's X25519 for
  // forward secrecy. Kept for backward compatibility with existing peers.
  static Uint8List _derivePublicKey(Uint8List privateKey) {
    return Uint8List.fromList(sha256.convert([...privateKey, ...utf8.encode('najime-pubkey')]).bytes);
  }

  // WARNING: This is a hash-based shared secret, not a proper Diffie-Hellman
  // key exchange. It does not provide forward secrecy. Kept for backward
  // compatibility; new connections should use X25519 via pinenacl.
  static Uint8List computeSharedSecret(Uint8List privateKey, Uint8List peerPublicKey) {
    final combined = Uint8List.fromList([
      ...privateKey,
      0xFF,
      ...peerPublicKey,
      ...utf8.encode('najime-e2ee-v1'),
    ]);
    return Uint8List.fromList(sha256.convert(combined).bytes);
  }

  static Uint8List _deriveEncryptionKey(Uint8List sharedSecret, String peerId) {
    final salt = _salts[peerId] ?? _generateSalt();
    _salts[peerId] = salt;

    final info = utf8.encode('frame-encryption-$peerId');
    return _hkdfSha256(sharedSecret, salt, info, 32);
  }

  static Uint8List _generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(16, (_) => random.nextInt(256)),
    );
  }

  static Uint8List _hkdfSha256(
    Uint8List ikm,
    Uint8List salt,
    Uint8List info,
    int length,
  ) {
    final prk = Hmac(sha256, salt).convert(ikm).bytes;
    final hmac = Hmac(sha256, Uint8List.fromList(prk));

    var t = Uint8List(0);
    var okm = Uint8List(0);
    var counter = 1;

    while (okm.length < length) {
      final input = Uint8List.fromList([...t, ...info, counter]);
      t = Uint8List.fromList(hmac.convert(input).bytes);
      okm = Uint8List.fromList([...okm, ...t]);
      counter++;
    }

    return okm.sublist(0, length);
  }

  static void registerPeerKey(String peerId, Uint8List peerPublicKey) {
    if (_localKeyPair == null) return;
    _peerPublicKeys[peerId] = peerPublicKey;

    final sharedSecret = computeSharedSecret(
      _localKeyPair!.privateKey,
      peerPublicKey,
    );
    _sharedSecrets[peerId] = sharedSecret;

    final derivedKey = _deriveEncryptionKey(sharedSecret, peerId);
    _derivedKeys[peerId] = derivedKey;

    _frameCounters[peerId] = 0;
    _peerFrameCounters[peerId] = 0;
  }

  static Uint8List? getPeerPublicKey(String peerId) {
    return _peerPublicKeys[peerId];
  }

  static Uint8List? getSharedSecret(String peerId) {
    return _sharedSecrets[peerId];
  }

  static String? getPublicKeyBase64() {
    return _localKeyPair != null ? base64Encode(_localKeyPair!.publicKey) : null;
  }

  static Future<Uint8List> encryptFrame(
    String peerId,
    Uint8List frameData,
  ) async {
    final key = _derivedKeys[peerId];
    if (key == null) return frameData;

    final counter = (_frameCounters[peerId] ?? 0) + 1;
    _frameCounters[peerId] = counter;

    if (counter % _keyRotationInterval == 0) {
      _rotateKey(peerId);
    }

    final nonce = _buildNonce(peerId, counter);
    final secretBox = await _chacha.encrypt(
      frameData,
      secretKey: crypto_lib.SecretKey(key),
      nonce: nonce,
    );

    final header = Uint8List(16);
    header.buffer.asByteData().setUint32(0, counter, Endian.big);
    final pubKeyPart = _localKeyPair?.publicKey.sublist(0, 8) ?? Uint8List(8);
    header.setRange(4, 12, pubKeyPart);
    final dataLen = frameData.length;
    header.buffer.asByteData().setUint32(12, dataLen, Endian.big);

    return Uint8List.fromList([...header, ...secretBox.cipherText, ...secretBox.mac.bytes]);
  }

  static Future<Uint8List> decryptFrame(
    String peerId,
    Uint8List encryptedFrame,
  ) async {
    final key = _derivedKeys[peerId];
    if (key == null || encryptedFrame.length < 16 + _chachaMacLen) return encryptedFrame;

    final header = encryptedFrame.sublist(0, 16);
    final counter = header.buffer.asByteData().getUint32(0, Endian.big);
    final payload = encryptedFrame.sublist(16);
    final ciphertext = payload.sublist(0, payload.length - _chachaMacLen);
    final mac = payload.sublist(payload.length - _chachaMacLen);

    final peerCounter = _peerFrameCounters[peerId] ?? 0;
    if (counter > 0 && (counter - peerCounter).abs() > 200) {
      throw E2EException('Frame counter drift too large for $peerId');
    }
    _peerFrameCounters[peerId] = counter;

    final nonce = _buildNonce(peerId, counter);

    try {
      final secretBox = crypto_lib.SecretBox(
        ciphertext,
        nonce: nonce,
        mac: crypto_lib.Mac(mac),
      );
      final decrypted = await _chacha.decrypt(
        secretBox,
        secretKey: crypto_lib.SecretKey(key),
      );
      return Uint8List.fromList(decrypted);
    } catch (e) {
      throw E2EException('Decryption failed for $peerId: $e');
    }
  }

  static Uint8List _buildNonce(String peerId, int counter) {
    final nonce = Uint8List(24);
    final peerIdHash = sha256.convert(utf8.encode(peerId)).bytes;
    nonce.setRange(0, 8, peerIdHash.sublist(0, 8));
    nonce.buffer.asByteData().setUint64(8, counter, Endian.big);
    nonce.setRange(16, 24, peerIdHash.sublist(8, 16));
    return nonce;
  }

  static void _rotateKey(String peerId) {
    final oldKey = _derivedKeys[peerId];
    if (oldKey == null || _localKeyPair == null) return;

    final newKey = _deriveEncryptionKey(
      computeSharedSecret(
        _localKeyPair!.privateKey,
        _peerPublicKeys[peerId]!,
      ),
      '$peerId-rot-${_frameCounters[peerId]}',
    );

    _derivedKeys[peerId] = newKey;
  }

  static Future<String> encryptSignalingData(Map<String, dynamic> data) async {
    final jsonStr = jsonEncode(data);
    final key = await _deriveMasterKey();
    final random = Random.secure();
    final nonce = Uint8List.fromList(
      List.generate(24, (_) => random.nextInt(256)),
    );

    final secretBox = await _chacha.encrypt(
      Uint8List.fromList(utf8.encode(jsonStr)),
      secretKey: crypto_lib.SecretKey(key),
      nonce: nonce,
    );

    return jsonEncode({
      'ciphertext': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    });
  }

  static Future<Map<String, dynamic>?> decryptSignalingData(String encryptedJson) async {
    try {
      final data = jsonDecode(encryptedJson) as Map<String, dynamic>;
      final ciphertext = base64Decode(data['ciphertext'] as String);
      final nonce = base64Decode(data['nonce'] as String);
      final mac = base64Decode(data['mac'] as String);
      final key = await _deriveMasterKey();

      final secretBox = crypto_lib.SecretBox(
        ciphertext,
        nonce: nonce,
        mac: crypto_lib.Mac(mac),
      );
      final decrypted = await _chacha.decrypt(
        secretBox,
        secretKey: crypto_lib.SecretKey(key),
      );

      return jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  static const _secureStorage = FlutterSecureStorage();
  static const _keyMasterKey = 'e2e_master_key';

  static Future<Uint8List> _deriveMasterKey() async {
    // Try to load existing master key from secure storage
    final existing = await _secureStorage.read(key: _keyMasterKey);
    if (existing != null) {
      return base64Decode(existing);
    }
    // Generate a new random master key and persist it
    final random = Random.secure();
    final key = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
    await _secureStorage.write(key: _keyMasterKey, value: base64Encode(key));
    return key;
  }

  static Map<String, dynamic> getKeyExchangePayload() {
    if (_localKeyPair == null) return {};
    return {
      'public_key': base64Encode(_localKeyPair!.publicKey),
      'key_id': _localKeyPair!.keyId,
    };
  }

  static bool isPeerRegistered(String peerId) {
    return _peerPublicKeys.containsKey(peerId) &&
        _derivedKeys.containsKey(peerId);
  }

  static List<String> get registeredPeers =>
      List.unmodifiable(_peerPublicKeys.keys);

  static void removePeer(String peerId) {
    _peerPublicKeys.remove(peerId);
    _sharedSecrets.remove(peerId);
    _derivedKeys.remove(peerId);
    _frameCounters.remove(peerId);
    _peerFrameCounters.remove(peerId);
    _salts.remove(peerId);
  }

  static void reset() {
    _localKeyPair = null;
    _peerPublicKeys.clear();
    _sharedSecrets.clear();
    _derivedKeys.clear();
    _frameCounters.clear();
    _peerFrameCounters.clear();
    _salts.clear();
  }

  static Future<void> exportKeys(String path) async {
    final data = {
      'key_pair': _localKeyPair?.toMap(),
      'peers': _peerPublicKeys.map(
        (k, v) => MapEntry(k, base64Encode(v)),
      ),
    };
    final jsonStr = jsonEncode(data);
    final key = await _deriveMasterKey();
    final nonce = _generateSalt();

    await _chacha.encrypt(
      Uint8List.fromList(utf8.encode(jsonStr)),
      secretKey: crypto_lib.SecretKey(key),
      nonce: nonce,
    );
  }
}

class E2EException implements Exception {
  final String message;
  E2EException(this.message);

  @override
  String toString() => 'E2EException: $message';
}
