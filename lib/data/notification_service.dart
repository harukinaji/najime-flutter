import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'api_service.dart';
import 'secure_http_client.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static const _channel = MethodChannel('com.naji.najimessenger/notifications');

  static void Function(RemoteMessage)? onMessageOpenedApp;
  static void Function(String chatId, String reply)? onReply;

  Future<void> init() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    _setupBackgroundHandler();
    _setupForegroundHandler();
    _setupTokenRefresh();
    _setupNativeReplyListener();
    _checkInitialReply();
    await _registerToken();
  }

  void _setupNativeReplyListener() {
    _channel.setMethodCallHandler((call) async {
      debugPrint('[FCM] Native call: ${call.method}');
      if (call.method == 'onReply') {
        final args = call.arguments as Map;
        final chatId = args['chat_id'] as String?;
        final replyText = args['reply_text'] as String?;
        debugPrint('[FCM] Reply from native: chatId=$chatId text=$replyText');
        if (chatId != null && replyText != null && onReply != null) {
          onReply!(chatId, replyText);
        }
      }
      return null;
    });
  }

  void _checkInitialReply() async {
    try {
      final result = await _channel.invokeMethod('getInitialReply');
      if (result != null && result is Map) {
        final chatId = result['chat_id'] as String?;
        final replyText = result['reply_text'] as String?;
        debugPrint('[FCM] Initial reply: chatId=$chatId text=$replyText');
        if (chatId != null && replyText != null && onReply != null) {
          onReply!(chatId, replyText);
        }
      }
    } catch (e) {
      debugPrint('[FCM] getInitialReply error: $e');
    }
  }

  void _setupBackgroundHandler() {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleMessageData(message.data);
    });
  }

  void _setupForegroundHandler() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final data = message.data;
      final type = data['type'] as String?;

      if (type == 'new_message') {
        final messageId = data['message_id'] as String?;
        if (messageId != null) {
          _sendDeliveryReceiptForeground(messageId);
        }

        // Check if notifications are enabled
        final prefs = await SharedPreferences.getInstance();
        final messagesEnabled = prefs.getBool('notif_messages') ?? true;
        final groupMessagesEnabled =
            prefs.getBool('notif_group_messages') ?? true;
        final isGroup = data['is_group'] == true || data['is_group'] == 'true';

        if (!messagesEnabled || (isGroup && !groupMessagesEnabled)) {
          debugPrint('[FCM] Notification suppressed by user settings');
          return;
        }

        // Check if this specific chat is muted
        final chatId = data['chat_id'] as String?;
        if (chatId != null) {
          final mutedChats = prefs.getStringList('muted_chats') ?? [];
          if (mutedChats.contains(chatId)) {
            debugPrint('[FCM] Chat $chatId is muted, skipping notification');
            return;
          }
        }
      }
    });
  }

  Future<void> _sendDeliveryReceiptForeground(String messageId) async {
    try {
      final success = await ApiService.markMessageDelivered(messageId);
      debugPrint(
        '[FCM] Foreground delivery receipt sent for $messageId: $success',
      );
    } catch (e) {
      debugPrint('[FCM] Failed to send foreground delivery receipt: $e');
    }
  }

  void _setupTokenRefresh() {
    _messaging.onTokenRefresh.listen((token) {
      debugPrint('[FCM] Token refreshed');
      _sendTokenToServer(token);
    });
  }

  Future<void> _registerToken() async {
    final token = await _messaging.getToken();
    if (token != null) {
      if (kDebugMode) debugPrint('[FCM] Token registered');
      await _sendTokenToServer(token);
    }
  }

  Future<void> _sendTokenToServer(String token) async {
    try {
      await ApiService.registerFcmToken(token);
      debugPrint('[FCM] Token registered on server');
    } catch (e) {
      debugPrint('[FCM] Failed to register token: $e');
    }
  }

  Future<void> reRegisterToken() async {
    final token = await _messaging.getToken();
    if (token != null) {
      debugPrint('[FCM] Re-registering token after login');
      await _sendTokenToServer(token);
    }
  }

  void _handleMessageData(Map<String, dynamic> data) {
    final chatId = data['chat_id'] as String?;
    final type = data['type'] as String?;

    if (type == 'new_message' && chatId != null && onMessageOpenedApp != null) {
      onMessageOpenedApp!(RemoteMessage(data: data));
    }
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background handler START: ${message.messageId}');

  final data = message.data;
  debugPrint('[FCM] Background data: $data');

  final type = data['type'] as String?;
  debugPrint('[FCM] Background type: $type');

  if (type == 'new_message') {
    final messageId = data['message_id'] as String?;
    debugPrint('[FCM] Background messageId=$messageId');

    // Only send delivery receipt for this specific message
    // Read receipt is sent when user OPENS the chat
    if (messageId != null) {
      debugPrint('[FCM] Sending delivery receipt for $messageId');
      await _sendDeliveryReceiptBackground(messageId);
    }
  }
  debugPrint('[FCM] Background handler END');
}

Future<void> _sendDeliveryReceiptBackground(String messageId) async {
  try {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'auth_token');
    if (token == null) return;

    // Read attestation key from secure storage (same key used by AppAttestation)
    const keyAlias = 'najime_app_hmac_key';
    final keyHex = await storage.read(key: keyAlias);
    if (keyHex == null || keyHex.isEmpty) return;

    final hmacKey = _hexDecode(keyHex);
    if (hmacKey.length != 32) return;

    final deviceId = sha256.convert(hmacKey).toString().substring(0, 32);
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();
    final nonce = _generateNonce();
    final canonical =
        'POST:/api/messages/$messageId/delivered:$timestamp:$nonce:';
    final signature = _hmacSign(hmacKey, canonical);

    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}/api/messages/$messageId/delivered',
    );
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    if (SignedHttpClient.shouldOverrideCertificateVerification) {
      httpClient.badCertificateCallback = (cert, host, port) =>
          SignedHttpClient.verifyServerCertificate(cert, host, port);
    }
    final client = http_io.IOClient(httpClient);
    try {
      await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          if (appKeyValue().isNotEmpty) appKeyHeaderName: appKeyValue(),
          'X-App-Timestamp': timestamp,
          'X-App-Nonce': nonce,
          'X-App-Signature': signature,
          'X-App-Device-Id': deviceId,
        },
      );
      debugPrint('[FCM] Delivery receipt sent for $messageId');
    } finally {
      client.close();
    }
  } catch (e) {
    debugPrint('[FCM] Failed to send delivery receipt: $e');
  }
}

String _generateNonce() {
  final rng = Random.secure();
  final bytes = List.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String _hmacSign(List<int> key, String data) {
  final hmac = Hmac(sha256, key);
  final digest = hmac.convert(utf8.encode(data));
  return digest.toString();
}

Uint8List _hexDecode(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return result;
}

void setupBackgroundMessaging() {
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
}
