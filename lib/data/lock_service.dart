import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LockMethod { none, pin, biometric, both }

class LockService {
  LockService._();
  static final instance = LockService._();

  static const _keyPinHash = 'lock_pin_hash';
  static const _keyLockMethod = 'lock_method';
  static const _keyLockEnabled = 'lock_enabled';

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

  String _hashPin(String pin) {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final saltBase64 = base64Encode(salt);
    final bytes = utf8.encode(pin) + salt;
    final hmacSha256 = Hmac(sha256, utf8.encode('najime_lock_key'));
    final digest = hmacSha256.convert(bytes);
    final hexHash = digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$saltBase64:$hexHash';
  }

  bool _verifyPinHash(String pin, String stored) {
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    final saltBase64 = parts[0];
    final expectedHex = parts[1];
    final salt = base64Decode(saltBase64);
    final bytes = utf8.encode(pin) + salt;
    final hmacSha256 = Hmac(sha256, utf8.encode('najime_lock_key'));
    final digest = hmacSha256.convert(bytes);
    final computedHex = digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (computedHex.length != expectedHex.length) return false;
    int result = 0;
    for (int i = 0; i < computedHex.length; i++) {
      result |= computedHex.codeUnitAt(i) ^ expectedHex.codeUnitAt(i);
    }
    return result == 0;
  }

  bool _isRateLimited() {
    if (_lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      return true;
    }
    if (_lockoutUntil != null && DateTime.now().isAfter(_lockoutUntil!)) {
      _failedAttempts = 0;
      _lockoutUntil = null;
    }
    return false;
  }

  void _recordFailure() {
    _failedAttempts++;
    if (_failedAttempts >= 10) {
      _lockoutUntil = DateTime.now().add(const Duration(minutes: 5));
    } else if (_failedAttempts >= 5) {
      _lockoutUntil = DateTime.now().add(const Duration(seconds: 30));
    }
  }

  void _resetFailureCounter() {
    _failedAttempts = 0;
    _lockoutUntil = null;
  }

  Future<bool> setPin(String pin) async {
    if (pin.length < 4 || pin.length > 8) return false;
    final hash = _hashPin(pin);
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
      _recordFailure();
      return false;
    }
    final verified = _verifyPinHash(pin, stored);
    if (verified) {
      _resetFailureCounter();
    } else {
      _recordFailure();
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
    _hasPin = false;
  }

  Future<void> changeMethod(LockMethod method) async {
    _method = method;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_keyLockMethod, method.index);
  }
}
