import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'app_attestation.dart';
import 'notification_service.dart';
import 'story_service.dart';
import 'cache_service.dart';
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

  /// True when the local demo account is active. Demo sessions never contact
  /// the backend and are useful for previewing the UI without registration.
  bool isDemo = false;
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
      debugPrint(
        '[Auth] Restoring session for user: ${await _storage.read(key: _keyUsername)}',
      );
      isAuthenticated = true;
      isDemo = token == 'demo-local-session';
      ApiService.setToken(token);
      unawaited(_storeEncryptedNativeToken(token));
      final identity = await Future.wait<String?>([
        _storage.read(key: _keyUsername),
        _storage.read(key: _keyDisplayName),
        _storage.read(key: _keyEmail),
      ]);
      username = identity[0];
      displayName = identity[1];
      email = identity[2];
      bio = _prefs!.getString(_keyBio);
      avatarUrl = _prefs!.getString(_keyAvatarUrl);

      // Demo sessions are intentionally offline and must never open a socket.
      if (!isDemo) {
        // Registration is a background sync. Waiting here made offline startup
        // block on the server's TCP timeout before the first frame.
        unawaited(
          Future<void>.delayed(const Duration(seconds: 2), () async {
            await AppAttestation.instance.ensureRegistered(token);
            WebSocketService.connect(token);
          }),
        );
      }
      debugPrint('[Auth] Session restored, token set; realtime deferred');
    } else {
      debugPrint('[Auth] No stored session');
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
    isDemo = false;
    this.username = username;
    this.displayName = displayName;
    this.email = email;
    this.bio = bio;
    this.avatarUrl = avatarUrl;
    ApiService.setToken(token);

    // Register attestation key with the server BEFORE any API calls.
    // The server rejects requests with unregistered attestation keys (403),
    // so this must complete first.  Failures are non-fatal — the key may
    // already be registered from a previous session.
    await AppAttestation.instance.ensureRegistered(token);

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

  /// Starts an offline test account with deterministic profile data.
  /// The wallet is intentionally not created here: the user must create or
  /// import their own wallet from the Wallet tab.
  Future<void> startDemoSession() async {
    isAuthenticated = true;
    isDemo = true;
    username = 'demo_user';
    displayName = 'Demo User';
    email = 'demo@najime.local';
    bio = 'Локальный тестовый аккаунт';
    avatarUrl = null;
    ApiService.setToken('demo-local-session');
    _prefs ??= await SharedPreferences.getInstance();
    await _storage.write(key: _keyToken, value: 'demo-local-session');
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyDisplayName, value: displayName);
    await _storage.write(key: _keyEmail, value: email);
    await _prefs!.setString(_keyBio, bio!);
    StoryService.instance.setCurrentUser(id: username!, name: displayName!);
  }

  Future<void> logout() async {
    isAuthenticated = false;
    isDemo = false;
    username = null;
    displayName = null;
    email = null;
    bio = null;
    avatarUrl = null;
    WebSocketService.disconnect();
    ApiService.logout();
    ApiService.setToken('');

    // Chat/message history is encrypted on disk for offline startup. It is
    // session data, so remove it when the account signs out rather than
    // showing the previous account's chats to the next user.
    await CacheService.instance.clearAll();

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
