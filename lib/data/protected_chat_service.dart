import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as crypto_lib;
import 'package:flutter/foundation.dart';
import 'websocket_service.dart';

class _ProtectedSession {
  final String peerId;
  final Uint8List encryptionKey;
  int sendCounter;
  int recvCounter;
  bool keysExchanged;

  _ProtectedSession({
    required this.peerId,
    required this.encryptionKey,
    this.sendCounter = 0,
    this.recvCounter = 0,
    this.keysExchanged = false,
  });
}

class ProtectedChatService {
  ProtectedChatService._();
  static final instance = ProtectedChatService._();

  static final crypto_lib.Xchacha20 _chacha = crypto_lib.Xchacha20.poly1305Aead();
  static final crypto_lib.X25519 _x25519 = crypto_lib.X25519();

  final Map<String, _ProtectedSession> _sessions = {};
  crypto_lib.SimpleKeyPair? _localKeyPair;

  bool isProtectedChat(String chatId) => _sessions.containsKey(chatId);

  Future<void> _ensureKeys() async {
    if (_localKeyPair != null) return;
    _localKeyPair = await _x25519.newKeyPair();
  }

  Future<String?> get localPublicKeyBase64 async {
    await _ensureKeys();
    final pk = await _localKeyPair!.extractPublicKey();
    return base64Encode(pk.bytes);
  }

  Future<void> initiateKeyExchange(String chatId, String peerId) async {
    await _ensureKeys();
    if (_sessions.containsKey(chatId)) return;

    final pk = await _localKeyPair!.extractPublicKey();
    WebSocketService.sendSignal('e2e_key_exchange', {
      'contact_id': peerId,
      'chat_id': chatId,
      'public_key': base64Encode(pk.bytes),
    });
    debugPrint('[E2EE-X25519] Key exchange initiated for chat $chatId');
  }

  Future<void> handleKeyExchange(Map<String, dynamic> data) async {
    final chatId = data['chat_id'] as String?;
    final peerPubKeyB64 = data['public_key'] as String?;
    final fromId = data['_from'] as String?;
    if (chatId == null || peerPubKeyB64 == null || fromId == null) return;

    await _ensureKeys();
    final peerPubKey = crypto_lib.SimplePublicKey(
      base64Decode(peerPubKeyB64),
      type: crypto_lib.KeyPairType.x25519,
    );

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _localKeyPair!,
      remotePublicKey: peerPubKey,
    );
    final sharedBytes = await sharedSecret.extractBytes();

    final encKey = _hkdfSha256(
      Uint8List.fromList(sharedBytes),
      Uint8List.fromList(utf8.encode('protected-chat-$chatId')),
      32,
    );

    _sessions[chatId] = _ProtectedSession(
      peerId: fromId,
      encryptionKey: encKey,
      keysExchanged: true,
    );

    final pk = await _localKeyPair!.extractPublicKey();
    WebSocketService.sendSignal('e2e_key_exchange', {
      'contact_id': fromId,
      'chat_id': chatId,
      'public_key': base64Encode(pk.bytes),
    });

    debugPrint('[E2EE-X25519] Keys exchanged for chat $chatId');
  }

  Future<void> handleKeyExchangeReply(Map<String, dynamic> data) async {
    final chatId = data['chat_id'] as String?;
    final peerPubKeyB64 = data['public_key'] as String?;
    final fromId = data['_from'] as String?;
    if (chatId == null || peerPubKeyB64 == null || fromId == null) return;

    final existing = _sessions[chatId];
    if (existing != null && existing.keysExchanged) return;

    await _ensureKeys();
    final peerPubKey = crypto_lib.SimplePublicKey(
      base64Decode(peerPubKeyB64),
      type: crypto_lib.KeyPairType.x25519,
    );

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _localKeyPair!,
      remotePublicKey: peerPubKey,
    );
    final sharedBytes = await sharedSecret.extractBytes();

    final encKey = _hkdfSha256(
      Uint8List.fromList(sharedBytes),
      Uint8List.fromList(utf8.encode('protected-chat-$chatId')),
      32,
    );

    _sessions[chatId] = _ProtectedSession(
      peerId: fromId,
      encryptionKey: encKey,
      keysExchanged: true,
    );

    debugPrint('[E2EE-X25519] Key exchange completed for chat $chatId');
  }

  Future<Map<String, dynamic>> encryptMessage(String chatId, String plaintext) async {
    final session = _sessions[chatId];
    if (session == null || !session.keysExchanged) {
      return {'ciphertext': plaintext};
    }

    session.sendCounter++;

    final nonce = _buildNonce(chatId, session.sendCounter);
    final data = Uint8List.fromList(utf8.encode(plaintext));

    final secretBox = await _chacha.encrypt(
      data,
      secretKey: crypto_lib.SecretKey(session.encryptionKey),
      nonce: nonce,
    );

    return {
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
      'counter': session.sendCounter,
    };
  }

  Future<String?> decryptMessage(String chatId, Map<String, dynamic> encrypted) async {
    final session = _sessions[chatId];
    if (session == null || !session.keysExchanged) return null;

    final ciphertext = base64Decode(encrypted['ciphertext'] as String);
    final mac = base64Decode(encrypted['mac'] as String);
    final counter = encrypted['counter'] as int;

    session.recvCounter = counter;

    final nonce = _buildNonce(chatId, counter);

    try {
      final secretBox = crypto_lib.SecretBox(
        ciphertext,
        nonce: nonce,
        mac: crypto_lib.Mac(mac),
      );
      final decrypted = await _chacha.decrypt(
        secretBox,
        secretKey: crypto_lib.SecretKey(session.encryptionKey),
      );
      return utf8.decode(decrypted);
    } catch (e) {
      debugPrint('[E2EE] Decrypt failed for chat $chatId: $e');
      return null;
    }
  }

  Future<String> encryptContent(String chatId, String plaintext) async {
    final map = await encryptMessage(chatId, plaintext);
    return jsonEncode(map);
  }

  Future<String?> decryptContent(String chatId, String jsonContent) async {
    try {
      final map = jsonDecode(jsonContent) as Map<String, dynamic>;
      return decryptMessage(chatId, map);
    } catch (_) {
      return null;
    }
  }

  Uint8List _buildNonce(String chatId, int counter) {
    final nonce = Uint8List(24);
    final chatHash = sha256.convert(utf8.encode(chatId)).bytes;
    nonce.setRange(0, 8, chatHash.sublist(0, 8));
    nonce.buffer.asByteData().setUint64(8, counter, Endian.big);
    nonce.setRange(16, 24, chatHash.sublist(8, 16));
    return nonce;
  }

  Uint8List _hkdfSha256(Uint8List ikm, Uint8List info, int length) {
    final salt = Uint8List(32);
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

  void endSession(String chatId) {
    _sessions.remove(chatId);
    debugPrint('[E2EE] Session ended for chat $chatId');
  }

  Future<void> reset() async {
    _sessions.clear();
    _localKeyPair = null;
  }
}
