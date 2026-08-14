import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../config.dart';
import 'secure_http_client.dart';

class ApiService {
  static const String _baseUrl = AppConfig.apiBaseUrl;

  /// WalletConnect project id from the frontend `.env` file. It's a public
  /// identifier used to construct the Reown AppKit relay/session engine; the
  /// WalletConnect metadata the wallets see comes from the backend instead.
  static String get walletConnectProjectId =>
      (dotenv.env['WALLETCONNECT_PROJECT_ID'] ?? '').trim();

  static String? _accessToken;
  static String? _username;

  static String? get accessToken => _accessToken;
  static String? get username => _username;

  static void setToken(String token) {
    _accessToken = token;
  }

  static Future<Map<String, String>?> fetchTurnCredentials() async {
    try {
      final headers = {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/turn/credentials'),
        headers: headers,
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final username = body['username'] as String?;
      final credential = body['credential'] as String?;
      if (username == null || credential == null) return null;
      return {'username': username, 'credential': credential};
    } catch (_) {
      return null;
    }
  }

  static http.Client? _cachedClient;
  static http.Client get client => _client;
  static http.Client get _client {
    if (_cachedClient != null) return _cachedClient!;
    _cachedClient = SignedHttpClient();
    return _cachedClient!;
  }

  /// WalletConnect v2 relay config (relay URL + project id), served from the
  /// backend so the app binary doesn't embed any cloud secret.
  static Future<WalletConnectConfig?> fetchWalletConnectConfig() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/walletconnect/config'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final relayUrl = body['relayUrl'] as String? ?? '';
      if (relayUrl.isEmpty) return null;
      final rawMetadata = body['metadata'];
      final metadata = rawMetadata is Map<String, dynamic>
          ? WalletConnectMetadata.fromJson(rawMetadata)
          : const WalletConnectMetadata(
              name: 'Najime',
              description: 'Najime Wallet',
              url: 'https://najime.app',
              icons: [],
              redirectNative: 'najime://',
              redirectUniversal: 'https://najime.app',
            );
      return WalletConnectConfig(
        relayUrl: relayUrl,
        metadata: metadata,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<ApiLoginResult> login(String username, String password) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        if (body['require_2fa'] == true) {
          return ApiLoginResult(
            success: false,
            require2fa: true,
            authMethod: body['auth_method'] as String?,
            emailHint: body['email_hint'] as String?,
            approvalId: body['approval_id'] as String?,
            pollSecret: body['poll_secret'] as String?,
            expiresIn: body['expires_in'] as int?,
            message: body['message'] as String?,
            username: body['username'] as String?,
            authTicket: body['auth_ticket'] as String?,
          );
        }

        _accessToken = body['token'] as String?;
        _username = body['username'] as String?;

        return ApiLoginResult(
          success: true,
          token: _accessToken,
          username: _username,
        );
      }

      return ApiLoginResult(
        success: false,
        message: body['message'] as String? ?? 'Login failed',
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<ApiLoginResult> verifyEmailCode(
    String username,
    String code, {
    String? authTicket,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/login/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'code': code,
          'auth_ticket': authTicket ?? '',
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        _accessToken = body['token'] as String?;
        _username = body['username'] as String?;

        return ApiLoginResult(
          success: true,
          token: _accessToken,
          username: _username,
          displayName: body['display_name'] as String?,
          email: body['email'] as String?,
          bio: body['bio'] as String?,
          avatarUrl: body['avatar_url'] as String?,
        );
      }

      return ApiLoginResult(
        success: false,
        message: body['message'] as String? ?? 'Verification failed',
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<ApiLoginResult> pollApproval(
    String approvalId,
    String pollSecret,
  ) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/login/approval/poll'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'approval_id': approvalId,
          'poll_secret': pollSecret,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        final status = body['status'] as String?;
        if (status == 'approved') {
          _accessToken = body['token'] as String?;
          _username = body['username'] as String?;

          return ApiLoginResult(
            success: true,
            token: _accessToken,
            username: _username,
            approvalStatus: status,
          );
        }

        return ApiLoginResult(
          success: false,
          require2fa: true,
          approvalStatus: status,
          message: body['message'] as String?,
        );
      }

      return ApiLoginResult(
        success: false,
        message: body['message'] as String? ?? 'Poll failed',
        approvalStatus: body['status'] as String?,
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<ApiLoginResult> fallbackToEmail(
    String approvalId,
    String pollSecret,
  ) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/login/approval/fallback_email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'approval_id': approvalId,
          'poll_secret': pollSecret,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        return ApiLoginResult(
          success: false,
          require2fa: true,
          authMethod: body['auth_method'] as String?,
          emailHint: body['email_hint'] as String?,
          message: body['message'] as String?,
          username: body['username'] as String?,
        );
      }

      return ApiLoginResult(
        success: false,
        message: body['message'] as String? ?? 'Fallback failed',
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<ApiLoginResult> loginWithGoogle(
    String idToken, {
    String? email,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/login/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id_token': idToken,
          if (email != null) 'email': email,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        _accessToken = body['token'] as String?;
        _username = body['username'] as String?;

        return ApiLoginResult(
          success: true,
          token: _accessToken,
          username: _username,
          displayName: body['display_name'] as String?,
          email: body['email'] as String?,
          bio: body['bio'] as String?,
          avatarUrl: body['avatar_url'] as String?,
        );
      }

      if (body['needs_registration'] == true) {
        return ApiLoginResult(
          success: false,
          needsRegistration: true,
          email: body['email'] as String?,
          message: body['message'] as String?,
        );
      }

      return ApiLoginResult(
        success: false,
        message: body['message'] as String? ?? 'Google sign-in failed',
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<bool> checkUsername(String username) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/check-username'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username}),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return body['available'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<ApiLoginResult> registerWithGoogle({
    required String idToken,
    required String username,
    required String displayName,
    String? email,
    String? avatarUrl,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/register/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id_token': idToken,
          'username': username,
          'display_name': displayName,
          if (email != null) 'email': email,
          if (avatarUrl != null) 'avatar_url': avatarUrl,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        _accessToken = body['token'] as String?;
        _username = body['username'] as String?;

        return ApiLoginResult(
          success: true,
          token: _accessToken,
          username: _username,
          displayName: body['display_name'] as String?,
          email: body['email'] as String?,
          bio: body['bio'] as String?,
          avatarUrl: body['avatar_url'] as String?,
          message: body['message'] as String?,
        );
      }

      return ApiLoginResult(
        success: false,
        message: body['message'] as String? ?? 'Registration failed',
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<ApiLoginResult> updateProfile({
    required String displayName,
    String? bio,
    String? avatarUrl,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/profile/update'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'display_name': displayName,
          if (bio != null) 'bio': bio,
          if (avatarUrl != null) 'avatar_url': avatarUrl,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        return ApiLoginResult(
          success: true,
          message: body['message'] as String?,
        );
      }

      return ApiLoginResult(
        success: false,
        message: body['message'] as String? ?? 'Failed to update profile',
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<ApiLoginResult> loginWithApple(String identityToken) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/login/apple'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'identity_token': identityToken}),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        _accessToken = body['token'] as String?;
        _username = body['username'] as String?;

        return ApiLoginResult(
          success: true,
          token: _accessToken,
          username: _username,
        );
      }

      return ApiLoginResult(
        success: false,
        message: body['message'] as String? ?? 'Apple sign-in failed',
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<bool> hasPassword() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/account/has-password'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['has_password'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<ApiLoginResult> setPassword(String password) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/account/set-password'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'password': password}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiLoginResult(
        success: response.statusCode == 200 && body['success'] == true,
        message: body['message'] as String?,
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<ApiLoginResult> verifyPassword(String password) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/account/verify-password'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'password': password}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiLoginResult(
        success: response.statusCode == 200 && body['success'] == true,
        message: body['message'] as String?,
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/users/search?q=${Uri.encodeComponent(query)}'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        final users = (body['users'] as List).cast<Map<String, dynamic>>();
        return users;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchGroups(String query) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/groups/search?q=${Uri.encodeComponent(query)}'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['groups'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> searchMessages(String query) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/messages/search?q=${Uri.encodeComponent(query)}'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['results'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static void logout() {
    _accessToken = null;
    _username = null;
  }

  static Future<List<Map<String, dynamic>>?> checkContacts(
    List<String> phoneNumbers,
  ) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/contacts/check'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'phone_numbers': phoneNumbers}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['contacts'] as List).cast<Map<String, dynamic>>();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/me'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['user'] as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getChats() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/chats'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['chats'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getMessages(String chatId) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/chats/$chatId/messages'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> sendMessage(
    String chatId,
    String content, {
    String type = 'text',
    String? fileName,
    String? fileSize,
    int? voiceDurationMs,
    String? voiceWaveform,
    String? replyToId,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/chats/$chatId/messages'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'content': content,
          'type': type,
          if (fileName != null) 'file_name': fileName,
          if (fileSize != null) 'file_size': fileSize,
          if (voiceDurationMs != null) 'voice_duration_ms': voiceDurationMs,
          if (voiceWaveform != null) 'voice_waveform': voiceWaveform,
          if (replyToId != null) 'reply_to': replyToId,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['message'] as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Marks an invoice message as paid (with the on-chain tx signature) so the
  /// sender and receiver both see the "Оплачено" state.
  static Future<bool> markInvoicePaid(String messageId, String txSignature) async {
    try {
      if (kDebugMode) debugPrint('[API] markInvoicePaid');
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/messages/$messageId/invoice-paid'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'tx_signature': txSignature}),
      );
      if (kDebugMode) debugPrint('[API] markInvoicePaid status=${response.statusCode}');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (e) {
      debugPrint('[API] markInvoicePaid error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> createCheck({
    required String chatId,
    required String pdaAddress,
    required int amountLamports,
    required String currency,
    required String txSignature,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/checks/create'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'chat_id': chatId,
          'pda_address': pdaAddress,
          'amount_lamports': amountLamports,
          'currency': currency,
          'tx_signature': txSignature,
        }),
      );
      return jsonDecode(response.body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> redeemCheck(String checkId, {String? txSignature}) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/checks/$checkId/redeem'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: txSignature != null ? jsonEncode({'tx_signature': txSignature}) : null,
      );
      return jsonDecode(response.body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getEscrowAddress() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/checks/escrow'),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['success'] == true) return body['escrow_address'] as String?;
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getProgramId() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/checks/program-id'),
      );
      return jsonDecode(response.body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> forwardMessage({
    required String sourceMessageId,
    required String targetChatId,
    required String content,
    required String type,
    String? fileName,
    String? fileSize,
    int? voiceDurationMs,
    String? voiceWaveform,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/messages/forward'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'source_message_id': sourceMessageId,
          'target_chat_id': targetChatId,
          'content': content,
          'type': type,
          if (fileName != null) 'file_name': fileName,
          if (fileSize != null) 'file_size': fileSize,
          if (voiceDurationMs != null) 'voice_duration_ms': voiceDurationMs,
          if (voiceWaveform != null) 'voice_waveform': voiceWaveform,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['message'] as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> markMessageDelivered(String messageId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/messages/$messageId/delivered'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> markChatRead(String chatId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/chats/$chatId/read'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> uploadFile(
    File file, {
    String scope = 'private',
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/upload'),
      );
      if (_accessToken != null) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
      }
      request.fields['scope'] = scope;
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      final streamed = await _client.send(request);
      final response = await http.Response.fromStream(streamed);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getFolders() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/folders'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['folders'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<String?> createFolder(String name, List<String> chatIds) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/folders'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'name': name, 'chat_ids': chatIds}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['folder_id'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> updateFolder(
    String folderId,
    String name,
    List<String> chatIds,
  ) async {
    try {
      final response = await _client.put(
        Uri.parse('$_baseUrl/api/folders/$folderId'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'name': name, 'chat_ids': chatIds}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> findOrCreateChat(String userId, {bool isProtected = false}) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/chats/find-or-create'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'user_id': userId, 'is_protected': isProtected}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getChatDetail(String chatId) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/chats/$chatId'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['chat'] as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> deleteFolder(String folderId) async {
    try {
      final response = await _client.delete(
        Uri.parse('$_baseUrl/api/folders/$folderId'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> addReaction(String messageId, String emoji) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/messages/$messageId/reactions'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'emoji': emoji}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> removeReaction(String messageId, String emoji) async {
    try {
      final response = await _client.delete(
        Uri.parse('$_baseUrl/api/messages/$messageId/reactions/$emoji'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> editMessage(
    String messageId,
    String content,
  ) async {
    try {
      final response = await _client.put(
        Uri.parse('$_baseUrl/api/messages/$messageId'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'content': content}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['message'] as Map<String, dynamic>?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> deleteMessage(String messageId) async {
    try {
      final response = await _client.delete(
        Uri.parse('$_baseUrl/api/messages/$messageId'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getCalls() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/calls'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['calls'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<bool> saveCall({
    required String contactId,
    required String type,
    required String status,
    int? durationSeconds,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/calls'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'contact_id': contactId,
          'type': type,
          'status': status,
          if (durationSeconds != null) 'duration_seconds': durationSeconds,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> pinMessage(String chatId, String messageId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/chats/$chatId/pin'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'message_id': messageId}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> unpinMessage(String chatId, String messageId) async {
    try {
      final response = await _client.delete(
        Uri.parse('$_baseUrl/api/chats/$chatId/pin/$messageId'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getPinnedMessages(String chatId) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/chats/$chatId/pinned'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['pinned'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> scheduleMessage(
    String chatId,
    String content, {
    String type = 'text',
    String? fileName,
    String? fileSize,
    int? voiceDurationMs,
    String? voiceWaveform,
    String? replyToId,
    required String scheduledAt,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/chats/$chatId/schedule'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'content': content,
          'type': type,
          if (fileName != null) 'file_name': fileName,
          if (fileSize != null) 'file_size': fileSize,
          if (voiceDurationMs != null) 'voice_duration_ms': voiceDurationMs,
          if (voiceWaveform != null) 'voice_waveform': voiceWaveform,
          if (replyToId != null) 'reply_to': replyToId,
          'scheduled_at': scheduledAt,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['scheduled_message'] as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getScheduledMessages(String chatId) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/chats/$chatId/scheduled'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['scheduled'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<bool> cancelScheduledMessage(String messageId) async {
    try {
      final response = await _client.delete(
        Uri.parse('$_baseUrl/api/scheduled/$messageId'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> muteChat(String chatId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/chats/$chatId/mute'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> unmuteChat(String chatId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/chats/$chatId/unmute'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> registerFcmToken(String token) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/fcm/register'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'fcm_token': token}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> createGroupChat({
    required String name,
    required List<String> participantIds,
    String? avatarUrl,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/chats/group/create'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'name': name,
          'participant_ids': participantIds,
          if (avatarUrl != null) 'avatar_url': avatarUrl,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getGroupMembers(String chatId) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/chats/group/$chatId/members'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['members'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<bool> addGroupMember({
    required String chatId,
    required String userId,
    required String displayName,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/chats/group/add-member'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'chat_id': chatId,
          'user_id': userId,
          'display_name': displayName,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> removeGroupMember({
    required String chatId,
    required String userId,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/chats/group/remove-member'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'chat_id': chatId,
          'user_id': userId,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<ConnectedAccountsResult> getConnectedAccounts() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/connected-accounts'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        final accounts = body['accounts'] as Map<String, dynamic>;
        return ConnectedAccountsResult(
          success: true,
          google: accounts['google'] as Map<String, dynamic>?,
          apple: accounts['apple'] as Map<String, dynamic>?,
          phone: accounts['phone'] as Map<String, dynamic>?,
          wallet: accounts['wallet'] as Map<String, dynamic>?,
        );
      }

      return ConnectedAccountsResult(
        success: false,
        message: body['message'] as String?,
      );
    } catch (e) {
      return ConnectedAccountsResult(
        success: false,
        message: 'Connection error: $e',
      );
    }
  }

  static Future<ApiLoginResult> linkGoogleAccount({
    required String googleId,
    required String email,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/connected-accounts/link/google'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'google_id': googleId, 'email': email}),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiLoginResult(
        success: response.statusCode == 200 && body['success'] == true,
        message: body['message'] as String?,
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<ApiLoginResult> unlinkGoogleAccount() async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/connected-accounts/unlink/google'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiLoginResult(
        success: response.statusCode == 200 && body['success'] == true,
        message: body['message'] as String?,
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<ApiLoginResult> linkPhoneAccount({
    required String phoneNumber,
    required bool isVerified,
    String? password,
    String? encryptedPhone,
    String? phoneNonce,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/connected-accounts/link/phone'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'phone_number': phoneNumber,
          'is_verified': isVerified,
          if (password != null) 'password': password,
          if (encryptedPhone != null) 'encrypted_phone': encryptedPhone,
          if (phoneNonce != null) 'phone_nonce': phoneNonce,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiLoginResult(
        success: response.statusCode == 200 && body['success'] == true,
        message: body['message'] as String?,
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<ApiLoginResult> unlinkPhoneAccount() async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/connected-accounts/unlink/phone'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiLoginResult(
        success: response.statusCode == 200 && body['success'] == true,
        message: body['message'] as String?,
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<ApiLoginResult> linkWalletAccount({
    required String walletAddress,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/connected-accounts/link/wallet'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'wallet_address': walletAddress}),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiLoginResult(
        success: response.statusCode == 200 && body['success'] == true,
        message: body['message'] as String?,
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  static Future<ApiLoginResult> unlinkWalletAccount() async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/connected-accounts/unlink/wallet'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiLoginResult(
        success: response.statusCode == 200 && body['success'] == true,
        message: body['message'] as String?,
      );
    } catch (e) {
      return ApiLoginResult(success: false, message: 'Connection error: $e');
    }
  }

  // ── Bot Creator API ──────────────────────────────────────────────

  static Future<Map<String, dynamic>?> createBot({
    required String username,
    required String displayName,
    String description = '',
    String avatarUrl = '',
    String startButtonText = 'Start',
    String startCommand = '/start',
    String miniAppUrl = '',
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/bots'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'username': username,
          'display_name': displayName,
          'description': description,
          'avatar_url': avatarUrl,
          'start_button_text': startButtonText,
          'start_command': startCommand,
          'mini_app_url': miniAppUrl,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['bot'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getMyBots() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/bots'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['bots'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getBotDetails(String botId) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/bots/$botId'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['bot'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> updateBot(String botId, {
    String? displayName,
    String? description,
    String? avatarUrl,
    bool? isActive,
    String? startButtonText,
    String? startCommand,
    String? miniAppUrl,
  }) async {
    try {
      final Map<String, dynamic> data = {};
      if (displayName != null) data['display_name'] = displayName;
      if (description != null) data['description'] = description;
      if (avatarUrl != null) data['avatar_url'] = avatarUrl;
      if (isActive != null) data['is_active'] = isActive;
      if (startButtonText != null) data['start_button_text'] = startButtonText;
      if (startCommand != null) data['start_command'] = startCommand;
      if (miniAppUrl != null) data['mini_app_url'] = miniAppUrl;
      final response = await _client.put(
        Uri.parse('$_baseUrl/api/bots/$botId'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode(data),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> deleteBot(String botId) async {
    try {
      final response = await _client.delete(
        Uri.parse('$_baseUrl/api/bots/$botId'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (e) {
      return false;
    }
  }

  static Future<String?> regenerateBotToken(String botId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/bots/$botId/regenerate-token'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['token'] as String;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> addBotToChat(String chatId, String botId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/chats/$chatId/add-bot'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'bot_id': botId}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> removeBotFromChat(String chatId, String botId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/chats/$chatId/remove-bot'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'bot_id': botId}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> searchBots(String query) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/bots/search?q=${Uri.encodeComponent(query)}'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['bots'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getBotInfo(String botId) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/bots/$botId/info'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['bot'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> sendCallback(String messageId, String callbackData) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/messages/$messageId/callback'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'callback_data': callbackData}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ── Mini App API ─────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getMiniAppWallet() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/miniapp/wallet'),
        headers: {if (_accessToken != null) 'Authorization': 'Bearer $_accessToken'},
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['wallet'] as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> transferSparks(int amount, String reason) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/miniapp/wallet/transfer'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'amount': amount, 'reason': reason}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['balance'] as int?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> createMultiplayerRoom({int maxPlayers = 8}) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/miniapp/multiplayer/room'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'max_players': maxPlayers}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['room'] as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> joinMultiplayerRoom(String roomId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/miniapp/multiplayer/join'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'room_id': roomId}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['room'] as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> leaveMultiplayerRoom(String roomId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/miniapp/multiplayer/leave'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'room_id': roomId}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getMultiplayerRooms() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/miniapp/multiplayer/rooms'),
        headers: {if (_accessToken != null) 'Authorization': 'Bearer $_accessToken'},
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['rooms'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> joinMatchmaking() async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/miniapp/multiplayer/matchmaking/join'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return {'room': body['room'], 'match_found': body['match_found']};
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> leaveMatchmaking() async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/miniapp/multiplayer/matchmaking/leave'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> updateMultiplayerState(String roomId, Map<String, dynamic> state) async {
    try {
      final response = await _client.put(
        Uri.parse('$_baseUrl/api/miniapp/multiplayer/state'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'room_id': roomId, 'state': state}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getVoiceChannels() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/miniapp/voice/channels'),
        headers: {if (_accessToken != null) 'Authorization': 'Bearer $_accessToken'},
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['channels'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>?> joinVoiceChannel(String channelId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/miniapp/voice/join'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'channel_id': channelId}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['participants'] as List).cast<String>();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>?> leaveVoiceChannel(String channelId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/miniapp/voice/leave'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'channel_id': channelId}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['participants'] as List).cast<String>();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Sticker API ──────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getInstalledStickerPacks() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/stickers/packs'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['packs'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getMyStickerPacks() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/stickers/my-packs'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['packs'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getStickerPack(String packId) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/stickers/packs/$packId'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['pack'] as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> createStickerPack({
    required String name,
    String? description,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/stickers/packs'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'name': name,
          if (description != null) 'description': description,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['pack'] as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> deleteStickerPack(String packId) async {
    try {
      final response = await _client.delete(
        Uri.parse('$_baseUrl/api/stickers/packs/$packId'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> addSticker({
    required String packId,
    required String imageUrl,
    String? emoji,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/stickers/packs/$packId/stickers'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'image_url': imageUrl,
          if (emoji != null) 'emoji': emoji,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['sticker'] as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> deleteSticker(String stickerId) async {
    try {
      final response = await _client.delete(
        Uri.parse('$_baseUrl/api/stickers/$stickerId'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> installStickerPack(String packId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/stickers/packs/$packId/install'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> uninstallStickerPack(String packId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/stickers/packs/$packId/uninstall'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> searchStickerPacks(String query) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/stickers/search?q=${Uri.encodeComponent(query)}'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['packs'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> importTelegramPack(String url) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/stickers/import-telegram'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({'url': url}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> sendSticker(String chatId, String stickerId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/chats/$chatId/messages'),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'content': stickerId,
          'type': 'sticker',
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return body['message'] as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─── Stories ────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> getStories() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/stories'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return (body['users'] as List).cast<Map<String, dynamic>>();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> createStory({
    required String mediaPath,
    required String mediaType,
    String? caption,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/stories'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'media_path': mediaPath,
          'media_type': mediaType,
          'caption': caption,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> viewStory(String storyId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/stories/$storyId/view'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }
}

class ApiLoginResult {
  final bool success;
  final String? token;
  final String? username;
  final String? message;
  final bool require2fa;
  final String? authMethod;
  final String? emailHint;
  final String? approvalId;
  final String? pollSecret;
  final int? expiresIn;
  final String? approvalStatus;
  final bool needsRegistration;
  final String? email;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final String? authTicket;

  ApiLoginResult({
    required this.success,
    this.token,
    this.username,
    this.message,
    this.require2fa = false,
    this.authMethod,
    this.emailHint,
    this.approvalId,
    this.pollSecret,
    this.expiresIn,
    this.approvalStatus,
    this.needsRegistration = false,
    this.email,
    this.displayName,
    this.bio,
    this.avatarUrl,
    this.authTicket,
  });
}

/// WalletConnect v2 relay + AppKit metadata config fetched from the backend.
/// The project id is not part of this: it lives in the frontend `.env`.
class WalletConnectConfig {
  final String relayUrl;
  final WalletConnectMetadata metadata;

  const WalletConnectConfig({
    required this.relayUrl,
    required this.metadata,
  });
}

/// Reown AppKit metadata used to build WalletConnect pairings and the
/// deep-link flow (native custom scheme + universal link for wallet returns).
class WalletConnectMetadata {
  final String name;
  final String description;
  final String url;
  final List<String> icons;
  final String redirectNative;
  final String redirectUniversal;

  const WalletConnectMetadata({
    required this.name,
    required this.description,
    required this.url,
    required this.icons,
    required this.redirectNative,
    required this.redirectUniversal,
  });

  factory WalletConnectMetadata.fromJson(Map<String, dynamic> json) {
    final redirect = json['redirect'];
    final redirectMap = redirect is Map<String, dynamic> ? redirect : const {};
    final icons = json['icons'];
    return WalletConnectMetadata(
      name: json['name'] as String? ?? 'Najime',
      description: json['description'] as String? ?? 'Najime Wallet',
      url: json['url'] as String? ?? 'https://najime.app',
      icons: icons is List
          ? icons.whereType<String>().where((i) => i.isNotEmpty).toList()
          : const [],
      redirectNative:
          redirectMap['native'] as String? ?? 'najime://',
      redirectUniversal:
          redirectMap['universal'] as String? ?? 'https://najime.app',
    );
  }
}

class ConnectedAccountsResult {
  final bool success;
  final String? message;
  final Map<String, dynamic>? google;
  final Map<String, dynamic>? apple;
  final Map<String, dynamic>? phone;
  final Map<String, dynamic>? wallet;

  ConnectedAccountsResult({
    required this.success,
    this.message,
    this.google,
    this.apple,
    this.phone,
    this.wallet,
  });
}
