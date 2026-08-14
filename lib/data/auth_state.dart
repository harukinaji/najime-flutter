import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'notification_service.dart';
import 'story_service.dart';
import 'token_cipher.dart';
import 'websocket_service.dart';
import '../config.dart';
import '../main.dart' show firebaseAvailable;

class AuthState {
  AuthState._();
  static final instance = AuthState._();

  static const _keyToken = 'auth_token';
  static const _keyUsername = 'auth_username';
  static const _keyDisplayName = 'auth_display_name';
  static const _keyEmail = 'auth_email';
  static const _keyBio = 'auth_bio';
  static const _keyAvatarUrl = 'auth_avatar_url';

  final _storage = const FlutterSecureStorage();
  SharedPreferences? _prefs;

  bool isAuthenticated = false;
  String? username;
  String? displayName;
  String? email;
  String? bio;
  String? avatarUrl;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _prefs!.setString('native_base_url', AppConfig.apiBaseUrl);
    final token = await _storage.read(key: _keyToken);
    if (token != null && token.isNotEmpty) {
      isAuthenticated = true;
      ApiService.setToken(token);
      WebSocketService.connect(token);
      await _storeEncryptedNativeToken(token);
      username = await _storage.read(key: _keyUsername);
      displayName = await _storage.read(key: _keyDisplayName);
      email = await _storage.read(key: _keyEmail);
      bio = _prefs!.getString(_keyBio);
      avatarUrl = _prefs!.getString(_keyAvatarUrl);
    }
  }

  /// Persists an AES-GCM-encrypted copy of the session token for the native
  /// notification quick-reply flow. Falls back to plaintext only when the
  /// Keystore-backed channel is unavailable (non-Android platforms).
  Future<void> _storeEncryptedNativeToken(String token) async {
    final encrypted = await TokenCipher.encrypt(token);
    if (encrypted != null) {
      await _prefs!.setString('native_auth_token', encrypted);
    }
  }

  Future<void> saveSession({
    required String token,
    required String username,
    String? displayName,
    String? email,
    String? bio,
    String? avatarUrl,
  }) async {
    if (token.isEmpty) return;

    isAuthenticated = true;
    this.username = username;
    this.displayName = displayName;
    this.email = email;
    this.bio = bio;
    this.avatarUrl = avatarUrl;
    ApiService.setToken(token);
    WebSocketService.connect(token);

    await _storage.write(key: _keyToken, value: token);
    _prefs ??= await SharedPreferences.getInstance();
    await _storeEncryptedNativeToken(token);
    await _storage.write(key: _keyUsername, value: username);
    if (displayName != null) {
      await _storage.write(key: _keyDisplayName, value: displayName);
    }
    if (email != null) {
      await _storage.write(key: _keyEmail, value: email);
    }

    _prefs ??= await SharedPreferences.getInstance();
    if (bio != null) {
      await _prefs!.setString(_keyBio, bio);
    }
    if (avatarUrl != null) {
      await _prefs!.setString(_keyAvatarUrl, avatarUrl);
    }

    StoryService.instance.setCurrentUser(
      id: username,
      name: displayName ?? username,
      avatarUrl: avatarUrl,
    );
    if (firebaseAvailable) {
      NotificationService().reRegisterToken();
    }
  }

  Future<void> logout() async {
    isAuthenticated = false;
    username = null;
    displayName = null;
    email = null;
    bio = null;
    avatarUrl = null;
    WebSocketService.disconnect();
    ApiService.logout();
    ApiService.setToken(null);

    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyDisplayName);
    await _storage.delete(key: _keyEmail);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_keyBio);
    await _prefs!.remove(_keyAvatarUrl);
    await _prefs!.remove('native_auth_token');
  }

  Future<ApiLoginResult> login(String username, String password) async {
    final result = await ApiService.login(username, password);
    if (result.success && result.token != null) {
      await saveSession(
        token: result.token!,
        username: result.username ?? username,
        displayName: result.displayName,
        email: result.email,
      );
    }
    return result;
  }
}
