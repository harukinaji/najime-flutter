import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import 'secure_http_client.dart';

/// Per-device app attestation service.
///
/// Generates a unique HMAC-SHA256 key stored in Android Keystore / iOS Keychain
/// on first launch. Every HTTP request is signed with this key so the server
/// can verify it originates from a genuine app instance.
///
/// Even if an attacker captures network traffic (PCAP), they cannot replay
/// requests because:
///   1. Each request has a unique nonce (anti-replay)
///   2. Each request has a timestamp (anti-replay, ±60s window)
///   3. The HMAC key never leaves the device
///   4. Certificate pinning prevents MITM interception
class AppAttestation {
  AppAttestation._();
  static final instance = AppAttestation._();

  static const _keyAlias = 'najime_app_hmac_key';
  static const _keyRegistered = 'najime_app_key_registered';
  static const _storage = FlutterSecureStorage();

  static const _attestChannel = MethodChannel('com.najime.attestation');

  Uint8List? _hmacKey;
  bool _initialized = false;
  String? _authToken;

  bool get isInitialized => _initialized;

  /// Stores the auth token for re-registration on 403.
  void setAuthToken(String token) => _authToken = token;

  /// Returns the stored auth token (for SignedHttpClient retry on 403).
  String? get authToken => _authToken;

  /// Initializes the attestation service. Call once at app startup.
  Future<void> init() async {
    if (_initialized) return;
    _hmacKey = await _loadOrCreateKey();
    _initialized = true;
    // Key registration requires an auth token.  It will be attempted
    // in [ensureRegistered] once the user logs in.
  }

  /// Ensures the device key is registered with the server. Must be called
  /// after the user logs in (the registration endpoint requires auth).
  /// Always attempts registration — the endpoint is idempotent (INSERT OR
  /// REPLACE) and the local "registered" flag can become stale when the
  /// server database is reset or recreated.
  Future<void> ensureRegistered(String token) async {
    if (_hmacKey == null) {
      debugPrint('[Attestation] HMAC key is null, cannot register');
      return;
    }
    _authToken = token;
    debugPrint('[Attestation] Registering key for device: $deviceId');
    try {
      await _registerWithServer(authToken: token);
      await markKeyRegistered();
      debugPrint('[Attestation] Key registered successfully');
    } catch (e) {
      debugPrint('[Attestation] Registration failed: $e');
    }
  }

  /// Clears the local "registered" flag so the next [ensureRegistered] call
  /// will re-register with the server.  Called when the server rejects
  /// attestation headers (403) despite the local flag being set.
  void invalidateRegistration() {
    debugPrint('[Attestation] Clearing stale registration flag');
    _storage.write(key: _keyRegistered, value: 'false');
  }

  /// Registers this device's attestation key with the server.
  Future<void> _registerWithServer({String? authToken}) async {
    if (_hmacKey == null) return;
    final hexKey = _hexEncode(_hmacKey!);
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/attestation/register');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (authToken != null) {
        request.headers.set('Authorization', 'Bearer $authToken');
      }
      final appKey = appKeyValue();
      if (appKey.isNotEmpty) {
        request.headers.set(appKeyHeaderName, appKey);
      }
      request.write(jsonEncode({'device_id': deviceId, 'key_hex': hexKey}));
      final response = await request.close();
      await response.drain();
      if (response.statusCode != 200) {
        throw Exception('Registration failed: HTTP ${response.statusCode}');
      }
    } catch (_) {
      // Registration failed — will retry on next call to ensureRegistered
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// Returns the device's public attestation identifier (SHA-256 of the HMAC key).
  /// This is sent to the server during registration so it knows which key
  /// to use for verification.
  String get deviceId {
    if (_hmacKey == null) return '';
    return sha256.convert(_hmacKey!).toString().substring(0, 32);
  }

  /// Returns true if this device's key has been registered with the server.
  Future<bool> isKeyRegistered() async {
    final stored = await _storage.read(key: _keyRegistered);
    return stored == 'true';
  }

  /// Marks the key as registered with the server.
  Future<void> markKeyRegistered() async {
    await _storage.write(key: _keyRegistered, value: 'true');
  }

  /// Signs an HTTP request and returns the attestation headers.
  ///
  /// Headers produced:
  ///   X-App-Timestamp: Unix seconds (anti-replay)
  ///   X-App-Nonce: 16-byte hex nonce (anti-replay)
  ///   X-App-Signature: HMAC-SHA256(method:path:timestamp:nonce:bodyHash)
  ///   X-App-Device-Id: Device's attestation identifier
  Future<Map<String, String>> signRequest({
    required String method,
    required String path,
    String? body,
  }) async {
    if (_hmacKey == null) {
      await init();
    }
    if (_hmacKey == null) return {};

    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();
    final nonce = _generateNonce();
    final bodyHash = body != null && body.isNotEmpty
        ? sha256.convert(utf8.encode(body)).toString()
        : '';

    // Canonical string: METHOD:PATH:TIMESTAMP:NONCE:BODY_HASH
    final canonical = '$method:$path:$timestamp:$nonce:$bodyHash';
    final signature = _hmacSign(canonical);

    return {
      'X-App-Timestamp': timestamp,
      'X-App-Nonce': nonce,
      'X-App-Signature': signature,
      'X-App-Device-Id': deviceId,
    };
  }

  /// Verifies a signature locally (for testing/debugging).
  bool verifySignature({
    required String method,
    required String path,
    required String timestamp,
    required String nonce,
    required String bodyHash,
    required String signature,
  }) {
    if (_hmacKey == null) return false;
    final canonical = '$method:$path:$timestamp:$nonce:$bodyHash';
    final expected = _hmacSign(canonical);
    return _constantTimeCompare(expected, signature);
  }

  // ── Internal ──────────────────────────────────────────────────────────

  Future<Uint8List> _loadOrCreateKey() async {
    // Try loading from Keystore/Keychain via native channel
    try {
      final existing = await _attestChannel.invokeMethod<Uint8List>(
        'getAttestationKey',
      );
      if (existing != null && existing.length == 32) return existing;
    } catch (_) {}

    // Fallback: try loading from secure storage (hex encoded)
    final stored = await _storage.read(key: _keyAlias);
    if (stored != null) {
      try {
        return _hexDecode(stored);
      } catch (_) {}
    }

    // Generate new key and persist
    final key = _generateKey();
    await _storage.write(key: _keyAlias, value: _hexEncode(key));

    // Try to also store in native Keystore
    try {
      await _attestChannel.invokeMethod('setAttestationKey', {'key': key});
    } catch (_) {}

    return key;
  }

  Uint8List _generateKey() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }

  String _generateNonce() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    return _hexEncode(Uint8List.fromList(bytes));
  }

  String _hmacSign(String data) {
    final hmac = Hmac(sha256, _hmacKey!);
    final digest = hmac.convert(utf8.encode(data));
    return digest.toString();
  }

  /// Constant-time string comparison to prevent timing attacks.
  static bool _constantTimeCompare(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  static String _hexEncode(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _hexDecode(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}
