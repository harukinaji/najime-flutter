import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/token_info.dart';

/// Stores wallet data securely on the device.
class SecureStorageService {
  SecureStorageService() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _seedKey = 'naji_wallet_seed';
  static const _privateKeyKey = 'naji_wallet_private_key';
  static const _customTokensKey = 'naji_wallet_custom_tokens';

  Future<void> saveWallet({String mnemonic = '', String? privateKey}) async {
    if (mnemonic.isNotEmpty) {
      await _storage.write(key: _seedKey, value: mnemonic);
      await _storage.delete(key: _privateKeyKey);
    } else if (privateKey != null) {
      await _storage.write(key: _privateKeyKey, value: privateKey);
      await _storage.delete(key: _seedKey);
    }
  }

  Future<String?> getSeedPhrase() => _storage.read(key: _seedKey);

  Future<String?> getPrivateKey() => _storage.read(key: _privateKeyKey);

  Future<bool> hasWallet() async {
    final seed = await _storage.read(key: _seedKey);
    final pk = await _storage.read(key: _privateKeyKey);
    return (seed != null && seed.isNotEmpty) || (pk != null && pk.isNotEmpty);
  }

  Future<void> clear() async {
    await _storage.delete(key: _seedKey);
    await _storage.delete(key: _privateKeyKey);
    await _storage.delete(key: _customTokensKey);
  }

  Future<List<TokenInfo>> getCustomTokens() async {
    final raw = await _storage.read(key: _customTokensKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => TokenInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCustomTokens(List<TokenInfo> tokens) async {
    await _storage.write(
      key: _customTokensKey,
      value: jsonEncode([for (final t in tokens) t.toJson()]),
    );
  }
}
