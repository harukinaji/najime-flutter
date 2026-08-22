import 'package:flutter/services.dart';

/// Encrypts/decrypts the session token via the Android Keystore-backed native
/// channel so it is never persisted in plaintext SharedPreferences.
class TokenCipher {
  TokenCipher._();

  static const MethodChannel _channel = MethodChannel(
    'com.naji.najimessenger/token',
  );

  static Future<String?> encrypt(String plaintext) async {
    try {
      return await _channel.invokeMethod<String>('encrypt', plaintext);
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
