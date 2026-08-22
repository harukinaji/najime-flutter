import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as crypto_lib;

class PasswordCrypto {
  static const int _saltLen = 16;
  static const int _iterations = 600000;

  static final crypto_lib.Xchacha20 _chacha =
      crypto_lib.Xchacha20.poly1305Aead();

  static Uint8List _pbkdf2Sha256(
    Uint8List password,
    Uint8List salt,
    int iterations,
    int keyLength,
  ) {
    final hmacInst = Hmac(sha256, password);
    final blockCount = (keyLength / 32).ceil();
    final result = Uint8List(keyLength);

    for (var i = 1; i <= blockCount; i++) {
      final counterBytes = Uint8List(4);
      counterBytes[0] = (i >> 24) & 0xFF;
      counterBytes[1] = (i >> 16) & 0xFF;
      counterBytes[2] = (i >> 8) & 0xFF;
      counterBytes[3] = i & 0xFF;

      var u = Uint8List.fromList(
        hmacInst.convert([...salt, ...counterBytes]).bytes,
      );
      var t = Uint8List.fromList(u);

      for (var j = 1; j < iterations; j++) {
        u = Uint8List.fromList(hmacInst.convert(u).bytes);
        for (var k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }

      final offset = (i - 1) * 32;
      final len = min(32, keyLength - offset);
      result.setRange(offset, offset + len, t.sublist(0, len));
    }

    return result;
  }

  static Uint8List _deriveKey(String password, Uint8List salt) {
    final passwordBytes = utf8.encode(password);
    return _pbkdf2Sha256(passwordBytes, salt, _iterations, 32);
  }

  static String hashPassword(String password) {
    final salt = _randomBytes(_saltLen);
    final key = _deriveKey(password, salt);
    final combined = Uint8List.fromList([...salt, ...key]);
    return base64Encode(combined);
  }

  static bool verifyPassword(String password, String storedHash) {
    final data = base64Decode(storedHash);
    final salt = data.sublist(0, _saltLen);
    final storedKey = data.sublist(_saltLen);
    final key = _deriveKey(password, salt);
    return _constantTimeCompare(key, storedKey);
  }

  static bool _constantTimeCompare(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static Future<Map<String, String>> encryptPhone(
    String phoneNumber,
    String password,
  ) async {
    final salt = _randomBytes(_saltLen);
    final key = _deriveKey(password, salt);
    final nonce = _randomBytes(24);

    final secretBox = await _chacha.encrypt(
      Uint8List.fromList(utf8.encode(phoneNumber)),
      secretKey: crypto_lib.SecretKey(key),
      nonce: nonce,
    );

    return {
      'encrypted_phone': base64Encode(secretBox.cipherText),
      'phone_mac': base64Encode(secretBox.mac.bytes),
      'phone_nonce': base64Encode(nonce),
      'salt': base64Encode(salt),
    };
  }

  static Future<String> decryptPhone(
    String encryptedPhone,
    String macBase64,
    String nonceBase64,
    String password,
    String saltBase64,
  ) async {
    final salt = base64Decode(saltBase64);
    final key = _deriveKey(password, salt);
    final nonce = base64Decode(nonceBase64);
    final ciphertext = base64Decode(encryptedPhone);
    final mac = base64Decode(macBase64);

    final secretBox = crypto_lib.SecretBox(
      ciphertext,
      nonce: nonce,
      mac: crypto_lib.Mac(mac),
    );

    final decrypted = await _chacha.decrypt(
      secretBox,
      secretKey: crypto_lib.SecretKey(key),
    );

    return String.fromCharCodes(decrypted);
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }
}
