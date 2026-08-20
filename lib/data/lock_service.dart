import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as crypto_lib;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LockMethod { none, pin, biometric, both }

class LockService {
  LockService._();
  static final instance = LockService._();

  static const _keyPinHash = 'lock_pin_hash';
  static const _keyPinPepper = 'lock_pin_pepper';
  static const _keyLockMethod = 'lock_method';
  static const _keyLockEnabled = 'lock_enabled';
  static const _keyFailedAttempts = 'lock_failed_attempts';
  static const _keyLockoutUntil = 'lock_lockout_until';

  static const int _pbkdf2Iterations = 600000;
  static const int _saltLen = 16;
  static const int _pepperLen = 32;

  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();
  SharedPreferences? _prefs;

  bool _enabled = false;
  LockMethod _method = LockMethod.none;
  bool _hasPin = false;

  static int _failedAttempts = 0;
  static DateTime? _lockoutUntil;

  bool get isEnabled => _enabled;
  LockMethod get method => _method;
  bool get hasPin => _hasPin;
  bool get canUseBiometric => _method == LockMethod.biometric || _method == LockMethod.both;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _enabled = _prefs!.getBool(_keyLockEnabled) ?? false;
    final methodIndex = _prefs!.getInt(_keyLockMethod) ?? 0;
    _method = LockMethod.values[methodIndex];
    _hasPin = await _storage.read(key: _keyPinHash) != null;
    _failedAttempts = _prefs!.getInt(_keyFailedAttempts) ?? 0;
    final lockoutMillis = _prefs!.getInt(_keyLockoutUntil);
    _lockoutUntil = lockoutMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(lockoutMillis)
        : null;
    if (_lockoutUntil != null && DateTime.now().isAfter(_lockoutUntil!)) {
      _failedAttempts = 0;
      _lockoutUntil = null;
      await _persistFailureState();
    }
  }

  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  Future<bool> canCheckBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;
      final biometrics = await _auth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  /// Returns (or creates) a per-install random pepper used to blind the PIN
  /// before hashing. Stored in secure storage so an attacker who extracts the
  /// PIN hash alone cannot brute-force it without also reading the pepper.
  Future<Uint8List> _getOrCreatePepper() async {
    final stored = await _storage.read(key: _keyPinPepper);
    if (stored != null && stored.isNotEmpty) {
      try {
        final bytes = base64Decode(stored);
        if (bytes.length == _pepperLen) return Uint8List.fromList(bytes);
      } catch (_) {}
    }
    final pepper = _randomBytes(_pepperLen);
    await _storage.write(key: _keyPinPepper, value: base64Encode(pepper));
    return pepper;
  }

  /// PBKDF2-HMAC-SHA256 key derivation over `pin + pepper` with a random salt.
  /// High iteration count makes offline brute-force of the 4-8 digit PIN slow.
  Future<Uint8List> _deriveKey(String pin, Uint8List salt, Uint8List pepper) async {
    final pbkdf2 = crypto_lib.Pbkdf2(
      macAlgorithm: crypto_lib.Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKey(
      secretKey: crypto_lib.SecretKey([...utf8.encode(pin), ...pepper]),
      nonce: salt,
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }

  Future<String> _hashPin(String pin) async {
    final salt = _randomBytes(_saltLen);
    final pepper = await _getOrCreatePepper();
    final key = await _deriveKey(pin, salt, pepper);
    return 'v2:${base64Encode(salt)}:${base64Encode(key)}';
  }

  Future<bool> _verifyV2(String pin, String stored) async {
    final parts = stored.split(':');
    if (parts.length != 3 || parts[0] != 'v2') return false;
    final salt = base64Decode(parts[1]);
    final expected = base64Decode(parts[2]);
    final pepper = await _getOrCreatePepper();
    final key = await _deriveKey(pin, Uint8List.fromList(salt), pepper);
    return _constantTimeEquals(key, Uint8List.fromList(expected));
  }

  /// Verifies PINs stored with the legacy scheme (HMAC-SHA256 with a static
  /// pepper). Kept for backward compatibility so existing users can still log
  /// in after an app upgrade; the hash is transparently re-stored with the new
  /// scheme on the next successful verification.
  bool _verifyLegacy(String pin, String stored) {
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    final salt = base64Decode(parts[0]);
    final expectedHex = parts[1];
    final bytes = utf8.encode(pin) + salt;
    final hmacSha256 = Hmac(sha256, utf8.encode('najime_lock_key'));
    final digest = hmacSha256.convert(bytes);
    final computedHex = digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return _constantTimeEqualsString(computedHex, expectedHex);
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static bool _constantTimeEqualsString(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  bool _isRateLimited() {
    if (_lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      return true;
    }
    if (_lockoutUntil != null && DateTime.now().isAfter(_lockoutUntil!)) {
      _failedAttempts = 0;
      _lockoutUntil = null;
      _persistFailureState();
    }
    return false;
  }

  Future<void> _persistFailureState() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_keyFailedAttempts, _failedAttempts);
    if (_lockoutUntil != null) {
      await _prefs!.setInt(_keyLockoutUntil, _lockoutUntil!.millisecondsSinceEpoch);
    } else {
      await _prefs!.remove(_keyLockoutUntil);
    }
  }

  Future<void> _recordFailure() async {
    _failedAttempts++;
    if (_failedAttempts >= 10) {
      _lockoutUntil = DateTime.now().add(const Duration(minutes: 5));
    } else if (_failedAttempts >= 5) {
      _lockoutUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    await _persistFailureState();
  }

  Future<void> _resetFailureCounter() async {
    _failedAttempts = 0;
    _lockoutUntil = null;
    await _persistFailureState();
  }

  Future<bool> setPin(String pin) async {
    if (pin.length < 4 || pin.length > 8) return false;
    final hash = await _hashPin(pin);
    await _storage.write(key: _keyPinHash, value: hash);
    _hasPin = true;
    return true;
  }

  Future<bool> verifyPinSecure(String pin) async {
    if (_isRateLimited()) {
      return false;
    }
    final stored = await _storage.read(key: _keyPinHash);
    if (stored == null) {
      await _recordFailure();
      return false;
    }
    final bool verified;
    final bool isLegacy = !stored.startsWith('v2:');
    if (isLegacy) {
      verified = _verifyLegacy(pin, stored);
    } else {
      verified = await _verifyV2(pin, stored);
    }
    if (verified) {
      await _resetFailureCounter();
      // Transparently migrate legacy hashes to the stronger PBKDF2 scheme.
      if (isLegacy) {
        await setPin(pin);
      }
    } else {
      await _recordFailure();
    }
    return verified;
  }

  Future<bool> verifyPin(String pin) async {
    return verifyPinSecure(pin);
  }

  Future<bool> authenticateWithBiometric() async {
    debugPrint('[LockService] authenticateWithBiometric: starting');
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      final biometrics = await _auth.getAvailableBiometrics();
      debugPrint('[LockService] canCheck=$canCheck, isSupported=$isSupported, biometrics=$biometrics');

      if (!canCheck || !isSupported || biometrics.isEmpty) {
        debugPrint('[LockService] biometric not available on this device');
        return false;
      }

      final result = await _auth.authenticate(
        localizedReason: 'Unlock NajiMe',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[LockService] authenticate timed out after 10s');
          return false;
        },
      );
      debugPrint('[LockService] authenticateWithBiometric: result=$result');
      return result;
    } on PlatformException catch (e) {
      debugPrint('[LockService] biometric PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[LockService] biometric unexpected error: $e');
      return false;
    }
  }

  Future<void> enable({required LockMethod method}) async {
    _enabled = true;
    _method = method;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_keyLockEnabled, true);
    await _prefs!.setInt(_keyLockMethod, method.index);
  }

  Future<void> disable() async {
    _enabled = false;
    _method = LockMethod.none;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_keyLockEnabled, false);
    await _prefs!.setInt(_keyLockMethod, LockMethod.none.index);
    await _storage.delete(key: _keyPinHash);
    await _storage.delete(key: _keyPinPepper);
    _hasPin = false;
    await _resetFailureCounter();
  }

  Future<void> changeMethod(LockMethod method) async {
    _method = method;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_keyLockMethod, method.index);
  }
}
